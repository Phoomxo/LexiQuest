import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/evidence_context.dart';
import '../../recommendation/domain/recommendation_models.dart';
import '../../recommendation/domain/recommendation_policy.dart';
import '../../rewards/domain/avatar_progression_policy.dart';
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
    final attempts = await _loadValidatedPracticeAttempts(ownerId);
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
    final avatarProgression = const AvatarProgressionPolicy().evaluate(
      lifetimeXp: totalXp,
    );
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
    final achievementRows =
        await (database.select(database.achievementUnlocks)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.unlockedAtUtcMs),
                (row) => OrderingTerm.asc(row.achievementId),
                (row) => OrderingTerm.asc(row.definitionVersion),
                (row) => OrderingTerm.asc(row.sourceEventId),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final durableAchievementRows = <String, AchievementUnlock>{};
    for (final row in achievementRows) {
      durableAchievementRows.putIfAbsent(row.achievementId, () => row);
    }

    final weaknesses = await _loadWeaknesses(ownerId);
    return ProgressSnapshot(
      sampleSize: attempts.length,
      correctCount: correctCount,
      wrongCount: wrongCount,
      accuracy: attempts.isEmpty ? null : correctCount / attempts.length,
      totalXp: totalXp,
      completedSessions: completedSessions,
      streakDays:
          (await (database.select(
                database.streakStates,
              )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull())
              ?.currentStreakDays ??
          0,
      dueReviewCount: dueRow.read(dueCountExpression) ?? 0,
      masteredWordCount: masteredRow.read(masteredCountExpression) ?? 0,
      achievementCount: durableAchievementRows.length,
      gameLevel: avatarProgression.level,
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
      achievements: durableAchievementRows.values
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

  /// Latest canonical practice evidence used only for freshness decisions.
  /// Assessment and recreational attempts remain excluded by the shared
  /// validated-practice boundary.
  Future<DateTime?> loadLatestPracticeEvidenceAtUtc({
    required String ownerId,
  }) async {
    if (ownerId.isEmpty || ownerId.trim() != ownerId) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    final attempts = await _loadValidatedPracticeAttempts(ownerId);
    return attempts.isEmpty
        ? null
        : DateTime.fromMillisecondsSinceEpoch(
            attempts.last.occurredAtUtcMs,
            isUtc: true,
          );
  }

  /// Returns f14's typed advisory decisions without changing the legacy
  /// [ProgressSnapshot] contract or persisting a recommendation record.
  Future<List<RecommendationDecision>> loadFlashcardFirstDecisions({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    if (!nowUtc.isUtc) {
      throw ArgumentError.value(nowUtc, 'nowUtc', 'must be UTC');
    }
    final candidates = await _loadFlashcardRecommendationCandidates(ownerId);
    final srsByWordId = await _loadSrsForWords(
      ownerId: ownerId,
      wordIds: candidates.map((candidate) => candidate.wordId).toSet(),
    );
    const policy = FlashcardFirstRecommendationPolicy();
    return candidates
        .map(
          (candidate) => policy.recommend(
            _recommendationEvidenceForCandidate(
              ownerId: ownerId,
              candidate: candidate,
              srs: srsByWordId[candidate.wordId],
              nowUtc: nowUtc,
            ),
          ),
        )
        .toList(growable: false);
  }

  RecommendationEvidence _recommendationEvidenceForCandidate({
    required String ownerId,
    required _FlashcardRecommendationCandidate candidate,
    required SrsState? srs,
    required DateTime nowUtc,
  }) {
    final references = <RecommendationEvidenceReference>[
      RecommendationEvidenceReference(
        source: RecommendationEvidenceSource.progressReadModel,
        ownerId: ownerId,
        contentId: candidate.wordId,
        referenceId: 'progress:${candidate.wordId}',
        version: 'progress-v1',
        capturedAtUtc: candidate.latestAttemptAtUtc,
      ),
    ];
    final lastReviewAtUtcMs = srs?.lastReviewAtUtcMs;
    if (srs != null && lastReviewAtUtcMs != null) {
      references.add(
        RecommendationEvidenceReference(
          source: RecommendationEvidenceSource.srsReadModel,
          ownerId: srs.ownerId,
          contentId: srs.wordId,
          referenceId: 'srs:${srs.id}',
          version: 'srs-v${srs.algorithmVersion}',
          capturedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            lastReviewAtUtcMs,
            isUtc: true,
          ),
        ),
      );
    }
    return RecommendationEvidence(
      policyVersion: FlashcardFirstRecommendationPolicy.policyVersion,
      ownerId: ownerId,
      contentOwnerId: ownerId,
      contentId: candidate.wordId,
      confidence: candidate.confidence,
      isUnseen: false,
      isMastered: srs != null && srs.repetitions >= 4 && srs.intervalDays >= 14,
      observedAtUtc: candidate.latestAttemptAtUtc,
      evaluatedAtUtc: nowUtc,
      evidenceReferences: references,
    );
  }

  Future<List<_FlashcardRecommendationCandidate>>
  _loadFlashcardRecommendationCandidates(String ownerId) async {
    final weaknesses = await _loadWeaknesses(ownerId, limit: 5);
    final weaknessByWordId = {
      for (final weakness in weaknesses) weakness.wordId: weakness,
    };
    final attempts = await _loadValidatedPracticeAttempts(
      ownerId,
      wordIds: weaknessByWordId.keys.toSet(),
    );
    final attemptsByWordId = <String, List<AnswerAttempt>>{};
    for (final attempt in attempts) {
      (attemptsByWordId[attempt.wordId] ??= <AnswerAttempt>[]).add(attempt);
    }
    final candidates = <_FlashcardRecommendationCandidate>[];
    for (final entry in attemptsByWordId.entries) {
      final wordAttempts = entry.value;
      final incorrectCount = wordAttempts
          .where((attempt) => !attempt.isCorrect)
          .length;
      if (incorrectCount == 0) continue;
      candidates.add(
        _FlashcardRecommendationCandidate(
          wordId: entry.key,
          spelling: weaknessByWordId[entry.key]!.spelling,
          confidence: 1 - (incorrectCount / wordAttempts.length),
          incorrectCount: incorrectCount,
          latestAttemptAtUtc: DateTime.fromMillisecondsSinceEpoch(
            wordAttempts.last.occurredAtUtcMs,
            isUtc: true,
          ),
        ),
      );
    }
    candidates.sort((left, right) {
      final errorRate = (1 - right.confidence).compareTo(1 - left.confidence);
      if (errorRate != 0) return errorRate;
      final incorrectCount = right.incorrectCount.compareTo(
        left.incorrectCount,
      );
      if (incorrectCount != 0) return incorrectCount;
      final spelling = left.spelling.compareTo(right.spelling);
      if (spelling != 0) return spelling;
      return left.wordId.compareTo(right.wordId);
    });
    return candidates;
  }

  Future<List<AnswerAttempt>> _loadValidatedPracticeAttempts(
    String ownerId, {
    Set<String>? wordIds,
  }) async {
    if (wordIds != null && wordIds.isEmpty) return const <AnswerAttempt>[];
    final query = database.select(database.answerAttempts)
      ..where((row) => row.ownerId.equals(ownerId))
      ..orderBy([(row) => OrderingTerm.asc(row.occurredAtUtcMs)]);
    if (wordIds != null) {
      query.where((row) => row.wordId.isIn(wordIds.toList()));
    }
    final storedAttempts = await query.get();
    if (storedAttempts.isEmpty) return const <AnswerAttempt>[];
    final sessionIds = storedAttempts
        .map((attempt) => attempt.sessionId)
        .toSet();
    final referencedWordIds = storedAttempts
        .map((attempt) => attempt.wordId)
        .toSet();
    final sessions = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.isIn(sessionIds.toList(growable: false)))).get();
    final words =
        await (database.select(database.vocabularyWords)..where(
              (row) => row.id.isIn(referencedWordIds.toList(growable: false)),
            ))
            .get();
    final sessionOwners = <String, String>{
      for (final session in sessions) session.id: session.ownerId,
    };
    final wordOwners = <String, String>{
      for (final word in words) word.id: word.ownerId,
    };
    for (final attempt in storedAttempts) {
      if (sessionOwners[attempt.sessionId] != ownerId ||
          wordOwners[attempt.wordId] != ownerId) {
        throw const FormatException(
          'attempt session and word references must match the attempt owner',
        );
      }
    }
    return storedAttempts.where(_isPracticeAttempt).toList(growable: false);
  }

  Future<Map<String, SrsState>> _loadSrsForWords({
    required String ownerId,
    required Set<String> wordIds,
  }) async {
    if (wordIds.isEmpty) return const <String, SrsState>{};
    final rows =
        await (database.select(database.srsStates)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.wordId.isIn(wordIds.toList()),
            ))
            .get();
    return Map<String, SrsState>.unmodifiable({
      for (final row in rows) row.wordId: row,
    });
  }

  Future<List<WeaknessEvidence>> _loadWeaknesses(
    String ownerId, {
    int? limit,
  }) async {
    if (limit != null && limit <= 0) return const <WeaknessEvidence>[];
    final limitSql = limit == null ? '' : 'LIMIT ?';
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
        w.spelling ASC,
        w.id ASC
      $limitSql
      ''',
          variables: [
            Variable<String>(ownerId),
            if (limit != null) Variable<int>(limit),
          ],
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
}

final class _FlashcardRecommendationCandidate {
  const _FlashcardRecommendationCandidate({
    required this.wordId,
    required this.spelling,
    required this.confidence,
    required this.incorrectCount,
    required this.latestAttemptAtUtc,
  });

  final String wordId;
  final String spelling;
  final double confidence;
  final int incorrectCount;
  final DateTime latestAttemptAtUtc;
}
