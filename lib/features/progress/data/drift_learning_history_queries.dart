import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/learning_history_models.dart';

final class DriftLearningHistoryQueries {
  const DriftLearningHistoryQueries(this.database);

  final AppDatabase database;
  static const pageSize = 50;

  Future<LearningHistorySnapshot> load({
    required String ownerId,
    required DateTime nowUtc,
    LearningHistoryCursor? before,
  }) {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    if (before != null && before.ownerId != ownerId) {
      throw LearningHistoryOwnerChanged();
    }
    if (before != null && !before.startedAtUtc.isUtc) {
      throw ArgumentError.value(before.startedAtUtc, 'before', 'must be UTC');
    }
    return database.transaction(() async {
      final rows = await database
          .customSelect(
            '''
  SELECT id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms,
         (accepted_plan_id IS NOT NULL AND accepted_plan_json IS NOT NULL
          AND checkpoint_revision >= 1 AND checkpoint_json IS NOT NULL) AS has_accepted_quiz
  FROM learning_sessions
  WHERE owner_id = ? AND activity_type <> 'assessment'
  ${before == null ? '' : 'AND (started_at_utc_ms < ? OR (started_at_utc_ms = ? AND id < ?))'}
  ORDER BY started_at_utc_ms DESC, id DESC
  LIMIT ?
''',
            variables: [
              Variable.withString(ownerId),
              if (before != null) ...[
                Variable.withInt(before.startedAtUtc.millisecondsSinceEpoch),
                Variable.withInt(before.startedAtUtc.millisecondsSinceEpoch),
                Variable.withString(before.sessionId),
              ],
              Variable.withInt(pageSize + 1),
            ],
            readsFrom: {database.learningSessions, database.answerAttempts},
          )
          .get();
      final pageAttempts =
          await (database.select(database.answerAttempts)..where(
                (row) =>
                    row.ownerId.equals(ownerId) &
                    row.sessionId.isIn(
                      rows.map((row) => row.read<String>('id')),
                    ),
              ))
              .get();
      final answerCounts = <String, (int, int)>{};
      for (final attempt in pageAttempts) {
        if (!LearningEvidenceContract.validEvidenceMetadata(
          evidenceClass: attempt.evidenceClass,
          evidenceContextJson: attempt.evidenceContextJson,
        )) {
          continue;
        }
        final previous = answerCounts[attempt.sessionId] ?? (0, 0);
        answerCounts[attempt.sessionId] = (
          previous.$1 + 1,
          previous.$2 + (attempt.isCorrect ? 1 : 0),
        );
      }
      final entries = rows
          .take(pageSize)
          .map(
            (row) => LearningHistoryEntry(
              sessionId: row.read<String>('id'),
              activityType: row.read<String>('activity_type'),
              state: row.read<String>('state'),
              startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.read<int>('started_at_utc_ms'),
                isUtc: true,
              ),
              endedAtUtc: row.readNullable<int>('ended_at_utc_ms') == null
                  ? null
                  : DateTime.fromMillisecondsSinceEpoch(
                      row.read<int>('ended_at_utc_ms'),
                      isUtc: true,
                    ),
              answerCount: answerCounts[row.read<String>('id')]?.$1 ?? 0,
              correctCount: answerCounts[row.read<String>('id')]?.$2 ?? 0,
              hasAcceptedQuiz: row.read<int>('has_accepted_quiz') == 1,
            ),
          )
          .toList(growable: false);
      final localNow = nowUtc.toLocal();
      final firstDay = DateTime(
        localNow.year,
        localNow.month,
        localNow.day - 6,
      );
      final tomorrow = DateTime(
        localNow.year,
        localNow.month,
        localNow.day + 1,
      );
      final answers = await database
          .customSelect(
            '''
SELECT a.occurred_at_utc_ms, a.evidence_class, a.evidence_context_json
FROM answer_attempts a
INNER JOIN learning_sessions s ON s.id = a.session_id AND s.owner_id = a.owner_id
WHERE a.owner_id = ? AND a.occurred_at_utc_ms >= ? AND a.occurred_at_utc_ms < ?
  AND s.activity_type <> 'assessment'
''',
            variables: [
              Variable.withString(ownerId),
              Variable.withInt(firstDay.toUtc().millisecondsSinceEpoch),
              Variable.withInt(tomorrow.toUtc().millisecondsSinceEpoch),
            ],
            readsFrom: {database.learningSessions, database.answerAttempts},
          )
          .get();
      final counts = <DateTime, int>{};
      for (final answer in answers) {
        if (!LearningEvidenceContract.validEvidenceMetadata(
          evidenceClass: answer.read<String>('evidence_class'),
          evidenceContextJson: answer.read<String>('evidence_context_json'),
        )) {
          continue;
        }
        final local = DateTime.fromMillisecondsSinceEpoch(
          answer.read<int>('occurred_at_utc_ms'),
          isUtc: true,
        ).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        counts.update(day, (count) => count + 1, ifAbsent: () => 1);
      }
      return LearningHistorySnapshot(
        ownerId: ownerId,
        entries: entries,
        days: List.generate(7, (index) {
          final day = DateTime(
            firstDay.year,
            firstDay.month,
            firstDay.day + index,
          );
          return LearningHistoryDay(day: day, answerCount: counts[day] ?? 0);
        }),
        nextCursor: rows.length > pageSize
            ? LearningHistoryCursor(
                ownerId: ownerId,
                startedAtUtc: entries.last.startedAtUtc,
                sessionId: entries.last.sessionId,
              )
            : null,
      );
    });
  }
}
