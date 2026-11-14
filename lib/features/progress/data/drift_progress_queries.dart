import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/learning_models.dart';
import '../../learning/domain/quiz_round.dart';
import '../../motivation/data/drift_streak_repository.dart';
import '../../motivation/domain/streak_policy.dart' as motivation;
import '../../quest/data/drift_quest_progress_reader.dart';
import '../../quest/domain/quest_progress_models.dart';
import '../domain/progress_models.dart';

final class DriftProgressQueries {
  const DriftProgressQueries(
    this.database, {
    this.questReader,
    this.questVisible,
    this.streakRepository,
  });

  final AppDatabase database;
  final DriftStreakRepository? streakRepository;
  final DriftQuestProgressReader? questReader;
  final bool Function()? questVisible;

  Future<ProgressSnapshot> load({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    return database.transaction(() async {
      final attempts =
          (await database
                  .customSelect(
                    '''
        SELECT a.* FROM answer_attempts a
        JOIN learning_sessions s ON s.id = a.session_id AND s.owner_id = a.owner_id
        WHERE a.owner_id = ? AND $_eligibleAttempt AND $_nonAssessment
        ORDER BY a.occurred_at_utc_ms, a.id
        ''',
                    variables: [Variable<String>(ownerId)],
                    readsFrom: {
                      database.answerAttempts,
                      database.learningSessions,
                      database.archivedV25Records,
                    },
                  )
                  .get())
              .map((row) => database.answerAttempts.map(row.data))
              .toList();
      final correctCount = attempts.where((row) => row.isCorrect).length;
      final wrongCount = attempts.length - correctCount;
      final responseTimes = attempts
          .map((row) => row.responseTimeMs)
          .whereType<int>()
          .toList(growable: false);
      // Legacy purchase debits still fund the shop, but never spend learning XP.
      final pointsRow = await database
          .customSelect(
            r'''
        SELECT COALESCE(SUM(p.amount),0) AS xp FROM points_ledger_entries p
        WHERE p.owner_id=? AND p.entry_type <> 'rewardPurchase'
          AND NOT EXISTS (
            SELECT 1 FROM archived_v25_records ar
            WHERE ar.owner_id=p.owner_id AND ar.source_table='points_ledger_entries'
              AND ar.source_row_key=p.id AND json_extract(ar.payload_json,'$._v25_reward_excluded')=1
          )
        ''',
            variables: [Variable<String>(ownerId)],
            readsFrom: {
              database.pointsLedgerEntries,
              database.archivedV25Records,
            },
          )
          .getSingle();
      final totalXp = pointsRow.read<int>('xp');
      final completedRow = await database
          .customSelect(
            '''
        SELECT COUNT(*) AS n FROM learning_sessions s
        WHERE s.owner_id = ? AND s.state = 'completed' AND $_nonAssessment
        ''',
            variables: [Variable<String>(ownerId)],
            readsFrom: {database.learningSessions, database.archivedV25Records},
          )
          .getSingle();
      final wordCount = database.vocabularyWords.id.count();
      final wordRow =
          await (database.selectOnly(database.vocabularyWords)
                ..addColumns([wordCount])
                ..where(
                  database.vocabularyWords.ownerId.equals(ownerId) &
                      database.vocabularyWords.isDeleted.equals(false),
                ))
              .getSingle();
      final dueWords = await database
          .customSelect(
            '''
      SELECT w.spelling, c.name AS category_name FROM srs_states s
      INNER JOIN vocabulary_words w ON w.id = s.word_id AND w.owner_id = s.owner_id
      LEFT JOIN vocabulary_categories c ON c.id = w.category_id AND c.owner_id = w.owner_id
      WHERE s.owner_id = ? AND w.is_deleted = 0 AND s.due_at_utc_ms <= ?
      ORDER BY s.due_at_utc_ms ASC, w.id ASC
      ''',
            variables: [
              Variable<String>(ownerId),
              Variable<int>(nowUtc.millisecondsSinceEpoch),
            ],
            readsFrom: {
              database.srsStates,
              database.vocabularyWords,
              database.vocabularyCategories,
            },
          )
          .get();
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
      QuestSummary? quests;
      try {
        if (questVisible?.call() ?? questReader != null) {
          quests =
              await questReader?.load(ownerId: ownerId, asOfUtc: nowUtc) ??
              QuestSummary(
                current: const [],
                history: const [],
                issues: const [QuestProgressIssue.unavailableCatalog],
              );
        }
      } on Object {
        quests = QuestSummary(
          current: const [],
          history: const [],
          issues: const [QuestProgressIssue.unavailableEvidence],
        );
      }
      late final motivation.StreakFoldResult learningDays;
      try {
        learningDays =
            await (streakRepository ?? DriftStreakRepository(database))
                .loadLearningDays(ownerId: ownerId, asOfUtc: nowUtc);
      } on Object {
        learningDays = motivation.StreakFoldResult(
          state: motivation.StreakState.initial(
            ownerId: ownerId,
            nowMs: nowUtc.millisecondsSinceEpoch,
          ),
          currentStreakDays: 0,
          days: const [],
          status: motivation.StreakFoldStatus.unavailable,
          uncertainHistory: true,
        );
      }
      return ProgressSnapshot(
        ownerId: ownerId,
        asOfUtc: nowUtc,
        quests: quests,
        sampleSize: attempts.length,
        correctCount: correctCount,
        wrongCount: wrongCount,
        accuracy: attempts.isEmpty ? null : correctCount / attempts.length,
        totalXp: totalXp,
        completedSessions: completedRow.read<int>('n'),
        learningDays: learningDays,
        dueReviewCount: dueWords.length,
        vocabularyWordCount: wordRow.read(wordCount) ?? 0,
        nextDueSpelling: dueWords.firstOrNull?.read<String>('spelling'),
        nextDueCategoryName: dueWords.firstOrNull?.readNullable<String>(
          'category_name',
        ),
        recentSessions: await _loadRecentSessions(ownerId),
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
    });
  }

  Future<List<SessionHistoryEntry>> _loadRecentSessions(String ownerId) async {
    final rows = await database
        .customSelect(
          '''
      $_historyProjection
      WHERE s.owner_id = ? AND s.state = 'completed' AND s.ended_at_utc_ms IS NOT NULL AND $_nonAssessment
      GROUP BY s.id
      ORDER BY s.ended_at_utc_ms DESC, s.id DESC
      LIMIT 20
      ''',
          variables: [Variable<String>(ownerId)],
          readsFrom: {
            database.learningSessions,
            database.answerAttempts,
            database.vocabularyWords,
            database.vocabularyCategories,
            database.archivedV25Records,
          },
        )
        .get();
    return rows.map(_historyEntry).toList(growable: false);
  }

  Future<SessionHistoryEntry?> loadSession({
    required String ownerId,
    required String sessionId,
  }) async {
    final row = await database
        .customSelect(
          '''
      $_historyProjection
      WHERE s.owner_id = ? AND s.id = ? AND s.state = 'completed' AND s.ended_at_utc_ms IS NOT NULL AND $_nonAssessment
      GROUP BY s.id
      ''',
          variables: [Variable<String>(ownerId), Variable<String>(sessionId)],
          readsFrom: {
            database.learningSessions,
            database.answerAttempts,
            database.vocabularyWords,
            database.vocabularyCategories,
            database.archivedV25Records,
          },
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _loadHistoryDetails(ownerId, row);
  }

  Future<SessionHistoryEntry?> loadLatestSessionForCategory({
    required String ownerId,
    required String categoryId,
  }) async {
    final row = await database
        .customSelect(
          '''
      $_historyProjection
      WHERE s.owner_id = ? AND s.state = 'completed' AND s.ended_at_utc_ms IS NOT NULL AND $_nonAssessment
      GROUP BY s.id
      HAVING COUNT(DISTINCT c.id) = 1 AND COUNT(c.id) = COUNT(a.id) AND MIN(c.id) = ?
      ORDER BY s.ended_at_utc_ms DESC, s.id DESC
      LIMIT 1
      ''',
          variables: [Variable<String>(ownerId), Variable<String>(categoryId)],
          readsFrom: {
            database.learningSessions,
            database.answerAttempts,
            database.vocabularyWords,
            database.vocabularyCategories,
            database.archivedV25Records,
          },
        )
        .getSingleOrNull();
    if (row == null) return null;
    return _loadHistoryDetails(ownerId, row);
  }

  Future<SessionHistoryEntry> _loadHistoryDetails(
    String ownerId,
    QueryRow row,
  ) async {
    final sessionId = row.read<String>('id');
    if (row.readNullable<String>('legacy_evidence_disposition') ==
        'history-v25') {
      return _historyEntry(row);
    }
    final mistakes = await _loadSessionMistakes(ownerId, sessionId);
    final raw = row.readNullable<String>('question_plan_json');
    QuizPlan? plan;
    List<OriginalQuizAnswer>? original;
    if (raw != null) {
      try {
        final pinned = decodeQuizPlan(raw);
        final attempts =
            await (database.select(database.answerAttempts)
                  ..where(
                    (attempt) =>
                        attempt.ownerId.equals(ownerId) &
                        attempt.sessionId.equals(sessionId),
                  )
                  ..orderBy([
                    (attempt) => OrderingTerm.asc(attempt.attemptNumber),
                    (attempt) => OrderingTerm.asc(attempt.id),
                  ]))
                .get();
        final answers = <OriginalQuizAnswer>[];
        for (final attempt in attempts) {
          final evidence = decodeQuizResponse(
            attempt.answerEvidenceJson ?? '',
            plan: pinned,
          );
          final question = pinned.questions[evidence.slot];
          final choice = evidence.selectedOption;
          final selected = choice == null ? null : question.options[choice];
          if (attempt.promptMode != question.kind.name ||
              attempt.isCorrect != (selected == question.correctAnswer)) {
            throw const FormatException(
              'Original quiz response does not match the plan',
            );
          }
          answers.add((
            question: question,
            chosenAnswer: selected,
            isCorrect: attempt.isCorrect,
          ));
        }
        if (answers.isNotEmpty) {
          plan = pinned;
          original = List.unmodifiable(answers);
        }
      } on FormatException {
        // Aggregate results remain readable when the original wording is unavailable.
      }
    }
    return _historyEntry(
      row,
      mistakes: mistakes,
      plan: plan,
      originalAnswers: original,
    );
  }

  Future<List<QuizWord>> _loadSessionMistakes(
    String ownerId,
    String sessionId,
  ) async {
    final rows = await database
        .customSelect(
          '''
      SELECT DISTINCT w.id, w.category_id, w.spelling, w.meaning, w.part_of_speech
      FROM answer_attempts a
      INNER JOIN vocabulary_words w ON w.id = a.word_id AND w.owner_id = a.owner_id
      WHERE a.owner_id = ? AND a.session_id = ? AND a.is_correct = 0 AND w.is_deleted = 0
      ORDER BY w.spelling ASC, w.id ASC
      ''',
          variables: [Variable<String>(ownerId), Variable<String>(sessionId)],
          readsFrom: {database.answerAttempts, database.vocabularyWords},
        )
        .get();
    return rows
        .map(
          (word) => QuizWord(
            id: word.read<String>('id'),
            categoryId: word.read<String>('category_id'),
            spelling: word.read<String>('spelling'),
            meaning: word.read<String>('meaning'),
            partOfSpeech: word.read<String>('part_of_speech'),
          ),
        )
        .toList(growable: false);
  }

  SessionHistoryEntry _historyEntry(
    QueryRow projected, {
    List<QuizWord> mistakes = const [],
    QuizPlan? plan,
    List<OriginalQuizAnswer>? originalAnswers,
  }) {
    final row = database.learningSessions.map(projected.data);
    final total = row.correctCount + row.wrongCount;
    return SessionHistoryEntry(
      ownerId: row.ownerId,
      summary: LearningSessionSummary(
        id: row.id,
        state: row.state,
        correctCount: row.correctCount,
        wrongCount: row.wrongCount,
        score:
            row.score ??
            (total == 0 ? 0 : (row.correctCount * 100 / total).round()),
      ),
      activityType: row.activityType,
      startedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.startedAtUtcMs,
        isUtc: true,
      ),
      completedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        row.endedAtUtcMs!,
        isUtc: true,
      ),
      mistakes: mistakes,
      categoryId: projected.readNullable<String>('linked_category_id'),
      categoryName:
          plan?.categoryName ??
          projected.readNullable<String>('linked_category_name'),
      originalAnswers: originalAnswers,
    );
  }

  static const _historyProjection = '''
      SELECT s.*,
        CASE WHEN COUNT(DISTINCT c.id) = 1 AND COUNT(c.id) = COUNT(a.id)
          THEN MIN(c.id) END AS linked_category_id,
        CASE WHEN COUNT(DISTINCT c.id) = 1 AND COUNT(c.id) = COUNT(a.id)
          THEN MIN(c.name) END AS linked_category_name
      FROM learning_sessions s
      LEFT JOIN answer_attempts a ON a.session_id = s.id
      LEFT JOIN vocabulary_words w
        ON w.id = a.word_id AND w.owner_id = a.owner_id AND a.owner_id = s.owner_id
      LEFT JOIN vocabulary_categories c
        ON c.id = w.category_id AND c.owner_id = w.owner_id
      ''';

  static const _nonAssessment =
      '''s.activity_type <> 'assessment' AND NOT EXISTS (
        SELECT 1 FROM archived_v25_records ar
        WHERE ar.owner_id = s.owner_id AND ar.source_table = 'assessment_runs'
          AND json_extract(ar.payload_json, '\$.learning_session_id') = s.id
      )''';

  static const _eligibleAttempt = '''
      (a.legacy_evidence_disposition IS NULL OR a.legacy_evidence_disposition = 'base-v25')
      AND (s.legacy_evidence_disposition IS NULL OR s.legacy_evidence_disposition = 'base-v25')''';

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
      JOIN learning_sessions session ON session.id = a.session_id AND session.owner_id = a.owner_id
      INNER JOIN vocabulary_words w
        ON w.id = a.word_id AND w.owner_id = a.owner_id
      LEFT JOIN srs_states s
        ON s.word_id = a.word_id AND s.owner_id = a.owner_id
      WHERE a.owner_id = ? AND w.is_deleted = 0
        AND session.activity_type <> 'assessment'
        AND (a.legacy_evidence_disposition IS NULL OR a.legacy_evidence_disposition = 'base-v25')
        AND (session.legacy_evidence_disposition IS NULL OR session.legacy_evidence_disposition = 'base-v25')
        AND NOT EXISTS (SELECT 1 FROM archived_v25_records ar
          WHERE ar.owner_id = session.owner_id AND ar.source_table = 'assessment_runs'
            AND json_extract(ar.payload_json, '\$.learning_session_id') = session.id)
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
            database.learningSessions,
            database.archivedV25Records,
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
      ('listening', 'การฟัง', {'listening', 'dictation'}),
      (
        'pronunciation',
        'การพูด (ความตรงของข้อความ)',
        {'pronunciation', 'shadowing', 'pronunciationTranscript'},
      ),
      ('spelling', 'การสะกดคำ', {'spelling', 'dictation', 'ghostSpelling'}),
      (
        'retention',
        'การจำและเรียกคืน',
        {'meaningChoice', 'srsRecall', 'activeRecall', 'associativeRecall'},
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
}
