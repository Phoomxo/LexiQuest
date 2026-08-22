import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/evidence_context.dart';
import '../domain/progress_models.dart';

final class DriftProgressQueries {
  const DriftProgressQueries(this.database);

  final AppDatabase database;

  Future<ProgressSnapshot> load({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final storedAttempts =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.occurredAtUtcMs)]))
            .get();
    final attempts = storedAttempts
        .where(_isPracticeAttempt)
        .toList(growable: false);
    final correctCount = attempts.where((row) => row.isCorrect).length;
    final wrongCount = attempts.length - correctCount;
    final responseTimes = attempts
        .map((row) => row.responseTimeMs)
        .whereType<int>()
        .toList(growable: false);
    final pointsExpression = database.pointsLedgerEntries.amount.sum();
    final pointsRow =
        await (database.selectOnly(database.pointsLedgerEntries)
              ..addColumns([pointsExpression])
              ..where(
                database.pointsLedgerEntries.ownerId.equals(ownerId) &
                    database.pointsLedgerEntries.amount.isBiggerThanValue(0) &
                    database.pointsLedgerEntries.entryType.isIn(const [
                      'quizCorrect',
                      'questCompletion',
                    ]),
              ))
            .getSingle();
    final totalXp = pointsRow.read(pointsExpression) ?? 0;
    final practiceSessionIds = attempts
        .map((attempt) => attempt.sessionId)
        .toSet();
    final completedRows =
        await (database.select(database.learningSessions)..where(
              (session) =>
                  session.ownerId.equals(ownerId) &
                  session.state.equals('completed'),
            ))
            .get();
    final completedSessions = completedRows
        .where((session) => practiceSessionIds.contains(session.id))
        .length;
    final dueCountExpression = database.srsStates.id.count();
    final dueRow =
        await (database.selectOnly(database.srsStates)
              ..addColumns([dueCountExpression])
              ..where(
                database.srsStates.ownerId.equals(ownerId) &
                    database.srsStates.dueAtUtcMs.isSmallerOrEqualValue(
                      nowUtc.millisecondsSinceEpoch,
                    ),
              ))
            .getSingle();
    final masteredCountExpression = database.srsStates.id.count();
    final masteredRow =
        await (database.selectOnly(database.srsStates)
              ..addColumns([masteredCountExpression])
              ..where(
                database.srsStates.ownerId.equals(ownerId) &
                    database.srsStates.repetitions.isBiggerOrEqualValue(4) &
                    database.srsStates.intervalDays.isBiggerOrEqualValue(14),
              ))
            .getSingle();
    final achievementCountExpression = database.achievementUnlocks.id.count();
    final achievementRow =
        await (database.selectOnly(database.achievementUnlocks)
              ..addColumns([achievementCountExpression])
              ..where(database.achievementUnlocks.ownerId.equals(ownerId)))
            .getSingle();
    final achievementRows =
        await (database.select(database.achievementUnlocks)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.unlockedAtUtcMs)]))
            .get();

    final weaknesses = await _loadWeaknesses(ownerId);
    return ProgressSnapshot(
      sampleSize: attempts.length,
      correctCount: correctCount,
      wrongCount: wrongCount,
      accuracy: attempts.isEmpty ? null : correctCount / attempts.length,
      totalXp: totalXp,
      completedSessions: completedSessions,
      streakDays: _streakDays(
        attempts.map((row) => row.occurredAtUtcMs),
        nowUtc,
      ),
      dueReviewCount: dueRow.read(dueCountExpression) ?? 0,
      masteredWordCount: masteredRow.read(masteredCountExpression) ?? 0,
      achievementCount: achievementRow.read(achievementCountExpression) ?? 0,
      gameLevel: (totalXp ~/ 20) + 1,
      skills: _skills(attempts),
      weaknesses: weaknesses,
      recommendations: weaknesses
          .take(5)
          .map(
            (item) => LearningRecommendation(
              wordId: item.wordId,
              title: 'ทบทวนคำว่า ${item.spelling}',
              reason:
                  'ตอบผิด ${item.incorrectCount} จาก ${item.sampleSize} ครั้ง',
              sampleSize: item.sampleSize,
            ),
          )
          .toList(growable: false),
      achievements: achievementRows
          .map(
            (row) => AchievementEvidence(
              id: row.achievementId,
              definitionVersion: row.definitionVersion,
              sourceEventId: row.sourceEventId,
              unlockedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                row.unlockedAtUtcMs,
                isUtc: true,
              ),
            ),
          )
          .toList(growable: false),
      algorithmVersion: 1,
      averageResponseTimeMs: responseTimes.isEmpty
          ? null
          : responseTimes.reduce((a, b) => a + b) / responseTimes.length,
      latestEvidenceAtUtc: attempts.isEmpty
          ? null
          : DateTime.fromMillisecondsSinceEpoch(
              attempts.last.occurredAtUtcMs,
              isUtc: true,
            ),
    );
  }

  Future<List<WeaknessEvidence>> _loadWeaknesses(String ownerId) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        a.word_id AS word_id,
        w.spelling AS spelling,
        w.meaning AS meaning,
        COUNT(*) AS sample_size,
        SUM(CASE WHEN a.is_correct = 0 THEN 1 ELSE 0 END) AS incorrect_count,
        s.due_at_utc_ms AS due_at_utc_ms
      FROM answer_attempts a
      INNER JOIN vocabulary_words w
        ON w.id = a.word_id AND w.owner_id = a.owner_id
      LEFT JOIN srs_states s
        ON s.word_id = a.word_id AND s.owner_id = a.owner_id
      WHERE a.owner_id = ? AND w.is_deleted = 0
        AND a.evidence_class NOT IN ('assessment', 'recreational')
        AND json_extract(a.evidence_context_json, '\$.evidenceClass') =
            a.evidence_class
      GROUP BY a.word_id, w.spelling, w.meaning, s.due_at_utc_ms
      HAVING SUM(CASE WHEN a.is_correct = 0 THEN 1 ELSE 0 END) > 0
      ORDER BY
        (1.0 * SUM(CASE WHEN a.is_correct = 0 THEN 1 ELSE 0 END) / COUNT(*)) DESC,
        incorrect_count DESC,
        w.spelling ASC
      ''',
          variables: [Variable<String>(ownerId)],
          readsFrom: {
            database.answerAttempts,
            database.vocabularyWords,
            database.srsStates,
          },
        )
        .get();
    return rows
        .map((row) {
          final sampleSize = row.read<int>('sample_size');
          final incorrectCount = row.read<int>('incorrect_count');
          final dueAt = row.readNullable<int>('due_at_utc_ms');
          return WeaknessEvidence(
            wordId: row.read<String>('word_id'),
            spelling: row.read<String>('spelling'),
            meaning: row.read<String>('meaning'),
            sampleSize: sampleSize,
            incorrectCount: incorrectCount,
            errorRate: incorrectCount / sampleSize,
            dueAtUtc: dueAt == null
                ? null
                : DateTime.fromMillisecondsSinceEpoch(dueAt, isUtc: true),
          );
        })
        .toList(growable: false);
  }

  List<SkillEvidence> _skills(List<AnswerAttempt> attempts) {
    const definitions = <(String, String, Set<String>)>[
      ('listening', 'Listening', {'listening', 'dictation'}),
      ('pronunciation', 'Pronunciation', {'pronunciation', 'shadowing'}),
      ('spelling', 'Spelling', {'spelling', 'dictation'}),
      (
        'retention',
        'Retention',
        {'meaningChoice', 'srsRecall', 'activeRecall'},
      ),
    ];
    return definitions
        .map((definition) {
          final relevant = attempts
              .where((attempt) => definition.$3.contains(attempt.promptMode))
              .toList(growable: false);
          final correct = relevant.where((attempt) => attempt.isCorrect).length;
          return SkillEvidence(
            key: definition.$1,
            label: definition.$2,
            sampleSize: relevant.length,
            accuracy: relevant.isEmpty ? null : correct / relevant.length,
          );
        })
        .toList(growable: false);
  }

  bool _isPracticeAttempt(AnswerAttempt attempt) {
    final decoded = jsonDecode(attempt.evidenceContextJson);
    if (decoded is! Map) {
      throw const FormatException('attempt evidence context must be an object');
    }
    final context = EvidenceContext.fromJson(decoded.cast<String, Object?>());
    if (attempt.evidenceClass != context.evidenceClass.name ||
        attempt.evidenceContextJson != jsonEncode(context.toJson())) {
      throw const FormatException('attempt evidence metadata mismatch');
    }
    return context.evidenceClass != EvidenceClass.assessment &&
        context.evidenceClass != EvidenceClass.recreational;
  }

  int _streakDays(Iterable<int> timestamps, DateTime nowUtc) {
    final days = timestamps
        .map((value) => DateTime.fromMillisecondsSinceEpoch(value, isUtc: true))
        .map((value) => DateTime.utc(value.year, value.month, value.day))
        .toSet();
    if (days.isEmpty) return 0;
    final today = DateTime.utc(nowUtc.year, nowUtc.month, nowUtc.day);
    var cursor = days.contains(today)
        ? today
        : today.subtract(const Duration(days: 1));
    if (!days.contains(cursor)) return 0;
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }
}
