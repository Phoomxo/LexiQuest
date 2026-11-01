import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../export/domain/export_contracts.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../motivation/data/drift_motivation_scope.dart';
import '../../progress/domain/progress_models.dart';

final class DriftAchievementShareReader {
  DriftAchievementShareReader(this.database, this.ownerWrites) {
    if (!identical(database, ownerWrites.database)) {
      throw ArgumentError(
        'Achievement cards require the canonical owner database',
      );
    }
  }
  final db.AppDatabase database;
  final DriftOwnerWriteCoordinator ownerWrites;

  Future<void> requireEvidence({
    required String ownerId,
    required AchievementEvidence achievement,
    required bool Function() stillCurrent,
  }) => withMotivationOwner(
    database,
    ownerWrites,
    ownerId,
    stillCurrent,
    (current) => database.transaction(() async {
      final stored =
          await (database.select(database.achievementUnlocks)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.achievementId.equals(achievement.id) &
                    row.definitionVersion.equals(achievement.definitionVersion),
              ))
              .getSingleOrNull();
      void require(bool allowed) {
        if (!allowed || !current()) {
          throw const ExportException(ExportFailureCode.noData);
        }
      }

      require(
        stored != null &&
            achievement.definitionVersion == 1 &&
            achievement.unlockedAtUtc.isUtc &&
            stored.sourceEventId == achievement.sourceEventId &&
            stored.unlockedAtUtcMs ==
                achievement.unlockedAtUtc.millisecondsSinceEpoch,
      );
      final sessions = await (database.select(
        database.learningSessions,
      )..where((row) => row.ownerId.equals(ownerId))).get();
      final controlled = await database
          .customSelect(
            'SELECT learning_session_id AS session_id FROM assessment_runs '
            'UNION SELECT learning_session_id AS session_id FROM measurement_opportunities',
          )
          .get();
      final controlledIds = controlled
          .map((row) => row.readNullable<String>('session_id'))
          .whereType<String>()
          .toSet();
      final ordinarySessions = {
        for (final session in sessions)
          if (session.activityType != 'assessment' &&
              !controlledIds.contains(session.id))
            session.id: session,
      };
      final attempts =
          await (database.select(database.answerAttempts)
                ..where((row) => row.ownerId.equals(ownerId))
                ..orderBy([
                  (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      bool eligible(db.AnswerAttempt row) =>
          ordinarySessions.containsKey(row.sessionId) &&
          LearningEvidenceContract.allowsOrdinaryProjection(
            promptMode: row.promptMode,
            evidenceClass: row.evidenceClass,
            evidenceContextJson: row.evidenceContextJson,
            projection: LearningProjection.achievement,
          );
      final source = achievement.sourceEventId;
      switch (achievement.id) {
        case 'first_answer':
        case 'first_correct':
        case 'ten_correct':
          final answer = attempts.where((row) => row.id == source).firstOrNull;
          require(
            answer != null &&
                eligible(answer) &&
                answer.occurredAtUtcMs == stored!.unlockedAtUtcMs &&
                (achievement.id == 'first_answer' || answer.isCorrect),
          );
          if (achievement.id == 'ten_correct') {
            require(
              attempts
                      .takeWhile((row) => row.id != source)
                      .where((row) => eligible(row) && row.isCorrect)
                      .length >=
                  9,
            );
          }
          break;
        case 'first_session':
        case 'perfect_session':
          final session = ordinarySessions[source];
          require(
            session != null &&
                session.state == 'completed' &&
                session.endedAtUtcMs == stored!.unlockedAtUtcMs,
          );
          final answers = attempts
              .where((row) => row.sessionId == source)
              .toList();
          require(
            answers.every(
              (row) => LearningEvidenceContract.validEvidenceMetadata(
                evidenceClass: row.evidenceClass,
                evidenceContextJson: row.evidenceContextJson,
              ),
            ),
          );
          require(
            answers.isEmpty
                ? session!.activityType != 'dictation'
                : answers.any(eligible),
          );
          if (achievement.id == 'perfect_session') {
            require(
              answers.isNotEmpty &&
                  answers.every((row) => row.isCorrect) &&
                  session!.wrongCount == 0 &&
                  session.correctCount > 0,
            );
          }
          break;
        default:
          require(false);
      }
    }),
  );
}
