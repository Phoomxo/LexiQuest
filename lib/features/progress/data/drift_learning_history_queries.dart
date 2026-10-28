import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
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
WITH page AS (
  SELECT id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms
  FROM learning_sessions
  WHERE owner_id = ?
  ${before == null ? '' : 'AND (started_at_utc_ms < ? OR (started_at_utc_ms = ? AND id < ?))'}
  ORDER BY started_at_utc_ms DESC, id DESC
  LIMIT ?
), answer_counts AS (
  SELECT a.owner_id, a.session_id, COUNT(*) AS answer_count,
         SUM(CASE WHEN a.is_correct = 1 THEN 1 ELSE 0 END) AS correct_count
  FROM answer_attempts a
  WHERE a.owner_id = ?
    AND a.session_id IN (SELECT id FROM page)
  GROUP BY a.owner_id, a.session_id
)
SELECT s.id, s.activity_type, s.state, s.started_at_utc_ms, s.ended_at_utc_ms,
       COALESCE(a.answer_count, 0) AS answer_count,
       COALESCE(a.correct_count, 0) AS correct_count
FROM page s
LEFT JOIN answer_counts a ON a.session_id = s.id AND a.owner_id = s.owner_id
ORDER BY s.started_at_utc_ms DESC, s.id DESC
''',
            variables: [
              Variable.withString(ownerId),
              if (before != null) ...[
                Variable.withInt(before.startedAtUtc.millisecondsSinceEpoch),
                Variable.withInt(before.startedAtUtc.millisecondsSinceEpoch),
                Variable.withString(before.sessionId),
              ],
              Variable.withInt(pageSize + 1),
              Variable.withString(ownerId),
            ],
            readsFrom: {database.learningSessions, database.answerAttempts},
          )
          .get();
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
              answerCount: row.read<int>('answer_count'),
              correctCount: row.read<int>('correct_count'),
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
SELECT a.occurred_at_utc_ms, COUNT(*) AS answer_count
FROM answer_attempts a
INNER JOIN learning_sessions s ON s.id = a.session_id AND s.owner_id = a.owner_id
WHERE a.owner_id = ? AND a.occurred_at_utc_ms >= ? AND a.occurred_at_utc_ms < ?
GROUP BY a.occurred_at_utc_ms
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
        final local = DateTime.fromMillisecondsSinceEpoch(
          answer.read<int>('occurred_at_utc_ms'),
          isUtc: true,
        ).toLocal();
        final day = DateTime(local.year, local.month, local.day);
        counts.update(
          day,
          (count) => count + answer.read<int>('answer_count'),
          ifAbsent: () => answer.read<int>('answer_count'),
        );
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
