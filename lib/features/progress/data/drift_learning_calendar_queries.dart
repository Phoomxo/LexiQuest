import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import 'drift_review_center_queries.dart';
import '../domain/learning_calendar.dart';

final class DriftLearningCalendarQueries {
  const DriftLearningCalendarQueries(this.database);
  final AppDatabase database;

  Future<LearningCalendarSnapshot> load({
    required String ownerId,
    required LearningCalendarPeriod period,
    required DateTime nowUtc,
  }) async {
    if (!nowUtc.isUtc || nowUtc.microsecondsSinceEpoch < 0) {
      throw ArgumentError('Calendar clock must be nonnegative UTC');
    }
    final ownerWrites = DriftOwnerWriteCoordinator(
      database,
      nowUtc: () => nowUtc,
    );
    await requireReviewReadOwner(
      database,
      expectedOwnerId: ownerId,
      stillCurrent: () => true,
    );
    await ownerWrites.requireOwnerUnfenced(ownerId);
    final result = await database.transaction(() async {
      final variables = <Variable>[
        Variable<String>(ownerId),
        Variable<int>(period.firstDay.toUtc().millisecondsSinceEpoch),
        Variable<int>(period.endExclusive.toUtc().millisecondsSinceEpoch),
        Variable<int>(nowUtc.millisecondsSinceEpoch),
      ];
      const ordinarySession =
          "s.activity_type <> 'assessment' "
          'AND NOT EXISTS (SELECT 1 FROM assessment_runs r WHERE r.learning_session_id = s.id) '
          'AND NOT EXISTS (SELECT 1 FROM measurement_opportunities o WHERE o.learning_session_id = s.id)';
      final answers = await database
          .customSelect(
            'SELECT a.occurred_at_utc_ms,a.is_correct,a.evidence_class,a.evidence_context_json '
            'FROM answer_attempts a '
            'JOIN learning_sessions s ON s.id=a.session_id AND s.owner_id=a.owner_id '
            'JOIN vocabulary_words w ON w.id=a.word_id AND w.owner_id=a.owner_id '
            'WHERE a.owner_id=? AND a.occurred_at_utc_ms>=? AND a.occurred_at_utc_ms<? '
            'AND a.occurred_at_utc_ms<=? AND $ordinarySession',
            variables: variables,
          )
          .get();
      final sessions = await database
          .customSelect(
            'SELECT s.ended_at_utc_ms FROM learning_sessions s '
            "WHERE s.owner_id=? AND s.state='completed' AND s.ended_at_utc_ms>=? "
            'AND s.ended_at_utc_ms<? AND s.ended_at_utc_ms<=? '
            'AND s.started_at_utc_ms>=0 AND s.ended_at_utc_ms>=s.started_at_utc_ms '
            'AND $ordinarySession',
            variables: variables,
          )
          .get();
      final counts = <DateTime, (int, int)>{};
      final completed = <DateTime, int>{};
      for (final answer in answers) {
        if (!LearningEvidenceContract.validEvidenceMetadata(
          evidenceClass: answer.read<String>('evidence_class'),
          evidenceContextJson: answer.read<String>('evidence_context_json'),
        )) {
          continue;
        }
        final date = _date(answer.read<int>('occurred_at_utc_ms'));
        final previous = counts[date] ?? (0, 0);
        counts[date] = (
          previous.$1 + 1,
          previous.$2 + (answer.read<bool>('is_correct') ? 1 : 0),
        );
      }
      for (final session in sessions) {
        final date = _date(session.read<int>('ended_at_utc_ms'));
        completed.update(date, (count) => count + 1, ifAbsent: () => 1);
      }
      return LearningCalendarSnapshot(
        ownerId: ownerId,
        period: period,
        days: [
          for (var index = 0; index < period.dayCount; index++)
            LearningCalendarDay(
              date: period.dayAt(index),
              answerCount: counts[period.dayAt(index)]?.$1 ?? 0,
              correctCount: counts[period.dayAt(index)]?.$2 ?? 0,
              completedSessionCount: completed[period.dayAt(index)] ?? 0,
            ),
        ],
      );
    });
    await ownerWrites.requireOwnerUnfenced(ownerId);
    await requireReviewReadOwner(
      database,
      expectedOwnerId: ownerId,
      stillCurrent: () => true,
    );
    return result;
  }

  DateTime _date(int milliseconds) {
    final local = DateTime.fromMillisecondsSinceEpoch(
      milliseconds,
      isUtc: true,
    ).toLocal();
    return DateTime(local.year, local.month, local.day);
  }
}
