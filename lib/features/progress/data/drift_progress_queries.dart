import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/domain/learning_evidence_contract.dart';
import '../../learning/domain/evidence_eligibility_policy.dart';
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
    final stored =
        await (database.select(database.answerAttempts)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([(row) => OrderingTerm.asc(row.occurredAtUtcMs)]))
            .get();
    final assessmentSessions =
        await (database.select(database.learningSessions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.activityType.equals('assessment'),
            ))
            .get();
    final excludedSessions = assessmentSessions.map((row) => row.id).toSet();
    final excludedSources = {...excludedSessions};
    final nativeXpIneligibleSessions = <String>{};
    final xpEligibleSessions = <String>{};
    final attempts = <AnswerAttempt>[];
    final streakAttempts = <AnswerAttempt>[];
    for (final row in stored) {
      if (excludedSessions.contains(row.sessionId) ||
          !LearningEvidenceContract.validEvidenceMetadata(
            evidenceClass: row.evidenceClass,
            evidenceContextJson: row.evidenceContextJson,
          )) {
        excludedSources.add(row.id);
        if (LearningEvidenceContract.nativeProjectionPromptModes.contains(
          row.promptMode,
        )) {
          nativeXpIneligibleSessions.add(row.sessionId);
        }
      } else {
        if (_eligible(row, LearningProjection.masterySrs)) {
          attempts.add(row);
        }
        if (_eligible(row, LearningProjection.streak)) {
          streakAttempts.add(row);
        }
        if (_eligible(row, LearningProjection.xp)) {
          xpEligibleSessions.add(row.sessionId);
        } else {
          excludedSources.add(row.id);
          nativeXpIneligibleSessions.add(row.sessionId);
        }
      }
    }
    excludedSources.addAll(
      nativeXpIneligibleSessions.difference(xpEligibleSessions),
    );
    final correctCount = attempts.where((row) => row.isCorrect).length;
    final wrongCount = attempts.length - correctCount;
    final responseTimes = attempts
        .map((row) => row.responseTimeMs)
        .whereType<int>()
        .toList(growable: false);
    // Legacy purchase debits still fund the shop, but never spend learning XP.
    final pointsRows =
        await (database.select(database.pointsLedgerEntries)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.entryType.equals('rewardPurchase').not(),
            ))
            .get();
    final totalXp = pointsRows
        .where((row) => !excludedSources.contains(row.sourceEventId))
        .fold<int>(0, (sum, row) => sum + row.amount);
    final completedCount = database.learningSessions.id.count();
    final completedRow =
        await (database.selectOnly(database.learningSessions)
              ..addColumns([completedCount])
              ..where(
                database.learningSessions.ownerId.equals(ownerId) &
                    database.learningSessions.activityType
                        .equals('assessment')
                        .not() &
                    database.learningSessions.state.equals('completed'),
              ))
            .getSingle();
    final dueCountExpression = database.srsStates.id.count();
    final dueRow =
        await (database.selectOnly(database.srsStates)
              ..addColumns([dueCountExpression])
              ..join([
                innerJoin(
                  database.vocabularyWords,
                  database.vocabularyWords.id.equalsExp(
                        database.srsStates.wordId,
                      ) &
                      database.vocabularyWords.ownerId.equalsExp(
                        database.srsStates.ownerId,
                      ) &
                      database.vocabularyWords.isDeleted.equals(false),
                  useColumns: false,
                ),
                innerJoin(
                  database.vocabularyCategories,
                  database.vocabularyCategories.id.equalsExp(
                        database.vocabularyWords.categoryId,
                      ) &
                      database.vocabularyCategories.ownerId.equalsExp(
                        database.srsStates.ownerId,
                      ) &
                      database.vocabularyCategories.isDeleted.equals(false),
                  useColumns: false,
                ),
              ])
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
              ..join([
                innerJoin(
                  database.vocabularyWords,
                  database.vocabularyWords.id.equalsExp(
                        database.srsStates.wordId,
                      ) &
                      database.vocabularyWords.ownerId.equalsExp(
                        database.srsStates.ownerId,
                      ) &
                      database.vocabularyWords.isDeleted.equals(false),
                  useColumns: false,
                ),
              ])
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

    final weaknesses = await _loadWeaknesses(ownerId, attempts);
    return ProgressSnapshot(
      sampleSize: attempts.length,
      correctCount: correctCount,
      wrongCount: wrongCount,
      accuracy: attempts.isEmpty ? null : correctCount / attempts.length,
      totalXp: totalXp,
      completedSessions: completedRow.read(completedCount) ?? 0,
      streakDays: _streakDays(
        streakAttempts.map((row) => row.occurredAtUtcMs),
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

  Future<List<WeaknessEvidence>> _loadWeaknesses(
    String ownerId,
    List<AnswerAttempt> attempts,
  ) async {
    final rows = await database
        .customSelect(
          '''
      SELECT
        w.id AS word_id,
        w.spelling AS spelling,
        w.meaning AS meaning,
        s.due_at_utc_ms AS due_at_utc_ms
      FROM vocabulary_words w
      JOIN vocabulary_categories c
        ON c.id = w.category_id AND c.owner_id = w.owner_id AND c.is_deleted = 0
      LEFT JOIN srs_states s
        ON s.word_id = w.id AND s.owner_id = w.owner_id
      WHERE w.owner_id = ? AND w.is_deleted = 0
      ORDER BY w.id ASC
      ''',
          variables: [Variable<String>(ownerId)],
          readsFrom: {
            database.answerAttempts,
            database.vocabularyWords,
            database.vocabularyCategories,
            database.srsStates,
          },
        )
        .get();
    final byWord = <String, List<AnswerAttempt>>{};
    for (final attempt in attempts) {
      byWord.putIfAbsent(attempt.wordId, () => []).add(attempt);
    }
    final result = rows
        .where(
          (row) =>
              byWord[row.read<String>('word_id')]?.any((a) => !a.isCorrect) ??
              false,
        )
        .map((row) {
          final evidence = byWord[row.read<String>('word_id')]!;
          final sampleSize = evidence.length;
          final incorrectCount = evidence.where((a) => !a.isCorrect).length;
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
        .toList();
    result.sort((a, b) {
      final rate = b.errorRate.compareTo(a.errorRate);
      if (rate != 0) return rate;
      final wrong = b.incorrectCount.compareTo(a.incorrectCount);
      return wrong != 0 ? wrong : a.spelling.compareTo(b.spelling);
    });
    return result;
  }

  static bool _eligible(AnswerAttempt attempt, LearningProjection projection) =>
      LearningEvidenceContract.allowsOrdinaryProjection(
        promptMode: attempt.promptMode,
        evidenceClass: attempt.evidenceClass,
        evidenceContextJson: attempt.evidenceContextJson,
        projection: projection,
      );

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
