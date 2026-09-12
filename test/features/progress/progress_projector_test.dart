import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/native_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/typed_recall_mode_adapter.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/review/data/drift_review_center_reader.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/avatar_progression_policy.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/vocabulary/data/packaged_starter_catalog.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository learning;
  late DriftProgressQueries progress;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    learning = DriftLearningRepository(database);
    progress = DriftProgressQueries(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  test(
    'empty evidence returns sample size zero without invented scores',
    () async {
      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.sampleSize, 0);
      expect(result.accuracy, isNull);
      expect(result.streakDays, 0);
      expect(result.weaknesses, isEmpty);
      expect(result.recommendations, isEmpty);
    },
  );

  test(
    'canonical prompt modes contribute to their maintained skills',
    () async {
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session-canonical-skills',
              ownerId: 'owner-1',
              activityType: 'mixedPractice',
              state: 'completed',
              startedAtUtcMs: 1,
              appVersion: 'test',
              buildId: 'test',
            ),
          );
      final modes = <String>[
        'pronunciation',
        'shadowing',
        'pronunciationTranscript',
        'meaningChoice',
        'srsRecall',
        'activeRecall',
        'typedRecall',
        'associativeRecall',
      ];
      for (var index = 0; index < modes.length; index++) {
        await database
            .into(database.answerAttempts)
            .insert(
              AnswerAttemptsCompanion.insert(
                id: 'attempt-canonical-skill-$index',
                ownerId: 'owner-1',
                sessionId: 'session-canonical-skills',
                wordId: index.isEven ? 'word-1' : 'word-2',
                promptMode: modes[index],
                isCorrect: true,
                attemptNumber: index + 1,
                occurredAtUtcMs: index + 2,
              ),
            );
      }

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 9, 9),
      );

      final pronunciation = result.skills.singleWhere(
        (skill) => skill.key == 'pronunciation',
      );
      final retention = result.skills.singleWhere(
        (skill) => skill.key == 'retention',
      );
      expect(pronunciation.sampleSize, 3);
      expect(pronunciation.accuracy, 1);
      expect(retention.sampleSize, 5);
      expect(retention.accuracy, 1);
    },
  );

  test(
    'canonical speaking and recall adapters commit into progress skills',
    () async {
      await _insertAvailableWord(database, id: 'word-adapter-progress');
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'unused-progress-owner',
        nowUtc: () => DateTime.utc(2026, 9, 9),
      );
      var nextId = 0;
      final useCases = LearningUseCases(
        owners: owners,
        repository: learning,
        generateId: () => 'progress-adapter-${++nextId}',
        nowUtc: () => DateTime.utc(2026, 9, 9, 0, 0, nextId),
        buildInfo: const AppBuildInfo(
          version: 'test',
          buildId: 'progress-adapters',
        ),
      );
      final session = await useCases.startQuiz(
        categoryId: 'category-1',
        limit: 1,
      );
      final word = session.questions.single.word;
      final evidence = CurrentActivityEvidenceAdapter(learning: useCases);
      await const SpeakingModeAdapter()
          .capture(
            evidence: evidence,
            ownerId: 'owner-1',
            sessionId: session.id,
            wordId: word.id,
            assessment: TranscriptPronunciationAssessment(
              target: word.spelling,
              transcript: word.spelling,
              similarityPercent: 100,
              isExactMatch: true,
              method: 'exact',
              engine: 'synthetic',
              locale: 'en-US',
              occurredAtUtc: DateTime.utc(2026, 9, 9),
            ),
            responseTimeMs: 10,
            attemptNumber: 1,
          )
          .pending
          .record();
      for (final entry in const <(TypedRecallPromptKind, int)>[
        (TypedRecallPromptKind.meaning, 2),
        (TypedRecallPromptKind.context, 3),
      ]) {
        await const TypedRecallModeAdapter()
            .capture(
              evidence: evidence,
              ownerId: 'owner-1',
              sessionId: session.id,
              prompt: TypedRecallPrompt(
                wordId: word.id,
                canonicalAnswer: word.spelling,
                promptKind: entry.$1,
                normalizationRevision: typedRecallNormalizationRevisionV1,
                contentRevision: word.contentRevision!,
                contentChecksumSha256: word.contentChecksumSha256!,
              ),
              response: word.spelling,
              responseTimeMs: 10,
              attemptNumber: entry.$2,
              support: const TypedRecallSupport.unassisted(),
            )
            .pending
            .record();
      }

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 9, 9, 1),
      );

      expect(result.sampleSize, 3);
      expect(
        result.skills
            .singleWhere((skill) => skill.key == 'pronunciation')
            .sampleSize,
        1,
      );
      expect(
        result.skills
            .singleWhere((skill) => skill.key == 'retention')
            .sampleSize,
        2,
      );
    },
  );

  test(
    'due count matches the actionable Review Center queue without deleting history',
    () async {
      final nowUtc = DateTime.utc(2026, 9, 9);
      await _insertAvailableWord(database, id: 'word-due-active');
      await _insertAvailableWord(
        database,
        id: 'word-due-deleted',
        deleted: true,
      );
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'category-deleted',
              ownerId: 'owner-1',
              name: 'Deleted',
              normalizedName: 'deleted',
              isDeleted: const Value(true),
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await _insertAvailableWord(
        database,
        id: 'word-deleted-category',
        categoryId: 'category-deleted',
      );
      await _insertAvailableWord(
        database,
        id: 'word-unpublished',
        publicationState: ContentPublicationState.published.name,
      );
      await _insertAvailableWord(
        database,
        id: 'word-invalid-core',
        checksumSha256:
            '0000000000000000000000000000000000000000000000000000000000000000',
      );
      await _insertAvailableWord(database, id: 'word-negative-due');
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner-2',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      await database
          .into(database.vocabularyCategories)
          .insert(
            VocabularyCategoriesCompanion.insert(
              id: 'category-owner-2',
              ownerId: 'owner-2',
              name: 'Private',
              normalizedName: 'private',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      await _insertAvailableWord(
        database,
        id: 'word-owner-2',
        ownerId: 'owner-2',
        categoryId: 'category-owner-2',
      );
      final packagedWordId = await _insertExactPackagedStarterWord(database);
      for (final entry in <(String, int)>[
        ('word-due-active', nowUtc.millisecondsSinceEpoch),
        ('word-due-deleted', nowUtc.millisecondsSinceEpoch),
        ('word-deleted-category', nowUtc.millisecondsSinceEpoch),
        ('word-unpublished', nowUtc.millisecondsSinceEpoch),
        ('word-invalid-core', nowUtc.millisecondsSinceEpoch),
        ('word-owner-2', nowUtc.millisecondsSinceEpoch),
        ('word-negative-due', -1),
        (packagedWordId, nowUtc.millisecondsSinceEpoch),
      ]) {
        await _insertDueState(database, wordId: entry.$1, dueAtUtcMs: entry.$2);
      }

      final queue = await DriftReviewCenterReader(database).compose(
        ReviewQueueFilter(
          ownerId: 'owner-1',
          evaluatedAtUtc: nowUtc,
          timezoneId: 'Asia/Bangkok',
          includeReasons: const {ReviewQueueReason.dueSrs},
        ),
      );
      final snapshot = await progress.load(ownerId: 'owner-1', nowUtc: nowUtc);

      expect(queue.map((item) => item.identity.id).toSet(), {
        'word-due-active',
        packagedWordId,
      });
      expect(snapshot.dueReviewCount, queue.length);
      expect(await database.select(database.srsStates).get(), hasLength(8));
    },
  );

  test('progress reads the dedicated streak authority', () async {
    await _insertSevenDatedAttempts(database);
    await _insertStreakState(database, currentStreakDays: 3);

    final result = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );

    expect(result.sampleSize, 7);
    expect(result.streakDays, 3);
  });

  test(
    'progress reports zero when dedicated streak authority is missing',
    () async {
      await _insertSevenDatedAttempts(database);

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.sampleSize, 7);
      expect(result.streakDays, 0);
    },
  );

  test(
    'mixed attempts derive accuracy points and weakness while reading streak',
    () async {
      await learning.startSession(
        LearningSessionDraft(
          id: 'session-1',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 29, 10),
          appVersion: 'test',
          buildId: 'test',
        ),
      );
      await learning.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-1',
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 500,
          attemptNumber: 1,
          occurredAtUtc: DateTime.utc(2026, 7, 29, 10),
          evidenceContext: _frozenV13LegacyEvidence(),
        ),
      );
      await learning.recordAnswer(
        RecordAnswerCommand.frozenV13LegacyIngress(
          id: 'attempt-2',
          ownerId: 'owner-1',
          sessionId: 'session-1',
          wordId: 'word-2',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 400,
          attemptNumber: 2,
          occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
          evidenceContext: _frozenV13LegacyEvidence(),
        ),
      );
      await learning.finishSession(
        ownerId: 'owner-1',
        sessionId: 'session-1',
        endedAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      );
      await _insertStreakState(database, currentStreakDays: 2);

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.sampleSize, 2);
      expect(result.accuracy, 0.5);
      expect(result.totalXp, 1);
      expect(result.completedSessions, 1);
      expect(result.streakDays, 2);
      expect(result.weaknesses.single.wordId, 'word-1');
      expect(result.weaknesses.single.incorrectCount, 1);
      expect(result.recommendations.single.sampleSize, 1);
    },
  );

  test('cosmetic purchase never changes lifetime xp or level', () async {
    await database
        .into(database.pointsLedgerEntries)
        .insert(
          PointsLedgerEntriesCompanion.insert(
            id: 'xp:learning-award',
            ownerId: 'owner-1',
            idempotencyKey: 'xp:learning-award',
            entryType: 'quizCorrect',
            amount: 200,
            sourceEventId: const Value('event:learning-award'),
            occurredAtUtcMs: DateTime.utc(
              2026,
              7,
              30,
              10,
            ).millisecondsSinceEpoch,
          ),
        );
    final rewards = DriftRewardRepository(database);
    final item = RewardCatalog.byId('theme_ocean')!;
    final beforeProgress = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );
    final beforeRewards = await rewards.load('owner-1');

    final purchase = await rewards.purchase(
      ownerId: 'owner-1',
      item: item,
      idempotencyKey: 'purchase:theme-ocean',
      transactionId: 'reward:theme-ocean',
      occurredAtUtc: DateTime.utc(2026, 7, 30, 11),
    );
    final afterProgress = await progress.load(
      ownerId: 'owner-1',
      nowUtc: DateTime.utc(2026, 7, 30, 12),
    );

    expect(afterProgress.totalXp, beforeProgress.totalXp);
    expect(afterProgress.gameLevel, beforeProgress.gameLevel);
    expect(
      purchase.account.coinBalance,
      beforeRewards.coinBalance - item.price,
    );
  });

  test(
    'definition-version audit rows project one durable achievement',
    () async {
      for (final row in const [
        ('achievement-v2', 2, 'source-later', 20),
        ('achievement-v1', 1, 'source-first', 10),
      ]) {
        await database
            .into(database.achievementUnlocks)
            .insert(
              AchievementUnlocksCompanion.insert(
                id: row.$1,
                ownerId: 'owner-1',
                achievementId: 'first_answer',
                definitionVersion: row.$2,
                sourceEventId: row.$3,
                unlockedAtUtcMs: row.$4,
              ),
            );
      }

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.achievementCount, 1);
      expect(result.achievements, hasLength(1));
      expect(result.achievements.single.definitionVersion, 1);
      expect(result.achievements.single.sourceEventId, 'source-first');
    },
  );

  test(
    'lifetime xp excludes purchases negative and unknown point types',
    () async {
      for (final row in const [
        ('quiz-positive', 'quizCorrect', 5),
        ('quest-positive', 'questCompletion', 20),
        ('purchase-audit', 'rewardPurchase', -10),
        ('unknown-positive', 'futureUnknown', 999),
        ('quiz-negative', 'quizCorrect', -3),
      ]) {
        await database
            .into(database.pointsLedgerEntries)
            .insert(
              PointsLedgerEntriesCompanion.insert(
                id: row.$1,
                ownerId: 'owner-1',
                idempotencyKey: 'idem:${row.$1}',
                entryType: row.$2,
                amount: row.$3,
                occurredAtUtcMs: 1,
              ),
            );
      }

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.totalXp, 25);
      expect(result.gameLevel, 2);
      expect(
        result.gameLevel,
        const AvatarProgressionPolicy().evaluate(lifetimeXp: 25).level,
      );
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(5),
      );
    },
  );

  test(
    'assessment and recreational history are absent from every practice field',
    () async {
      final assessment = _assessmentEvidence();
      final recreational = _recreationalEvidence();
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session-assessment',
              ownerId: 'owner-1',
              activityType: 'assessment',
              state: 'completed',
              startedAtUtcMs: DateTime.utc(
                2026,
                7,
                30,
                9,
              ).millisecondsSinceEpoch,
              endedAtUtcMs: Value(
                DateTime.utc(2026, 7, 30, 10).millisecondsSinceEpoch,
              ),
              correctCount: const Value(1),
              score: const Value(100),
              appVersion: 'test',
              buildId: 'test',
            ),
          );
      await database
          .into(database.learningSessions)
          .insert(
            LearningSessionsCompanion.insert(
              id: 'session-recreational',
              ownerId: 'owner-1',
              activityType: 'game',
              state: 'completed',
              startedAtUtcMs: DateTime.utc(
                2026,
                7,
                29,
                9,
              ).millisecondsSinceEpoch,
              endedAtUtcMs: Value(
                DateTime.utc(2026, 7, 29, 10).millisecondsSinceEpoch,
              ),
              correctCount: const Value(0),
              score: const Value(0),
              appVersion: 'test',
              buildId: 'test',
            ),
          );
      await database
          .into(database.answerAttempts)
          .insert(
            AnswerAttemptsCompanion.insert(
              id: 'attempt-assessment',
              ownerId: 'owner-1',
              sessionId: 'session-assessment',
              wordId: 'word-1',
              promptMode: 'assessmentResponse',
              isCorrect: true,
              responseTimeMs: const Value(300),
              attemptNumber: 1,
              occurredAtUtcMs: DateTime.utc(
                2026,
                7,
                30,
                9,
                30,
              ).millisecondsSinceEpoch,
              evidenceClass: Value(assessment.evidenceClass.name),
              evidenceContextJson: Value(jsonEncode(assessment.toJson())),
            ),
          );
      await database
          .into(database.answerAttempts)
          .insert(
            AnswerAttemptsCompanion.insert(
              id: 'attempt-recreational',
              ownerId: 'owner-1',
              sessionId: 'session-recreational',
              wordId: 'word-1',
              promptMode: 'meaningChoice',
              isCorrect: false,
              responseTimeMs: const Value(900),
              attemptNumber: 1,
              occurredAtUtcMs: DateTime.utc(
                2026,
                7,
                29,
                9,
                30,
              ).millisecondsSinceEpoch,
              evidenceClass: Value(recreational.evidenceClass.name),
              evidenceContextJson: Value(jsonEncode(recreational.toJson())),
            ),
          );

      final result = await progress.load(
        ownerId: 'owner-1',
        nowUtc: DateTime.utc(2026, 7, 30, 12),
      );

      expect(result.sampleSize, 0);
      expect(result.correctCount, 0);
      expect(result.wrongCount, 0);
      expect(result.accuracy, isNull);
      expect(result.completedSessions, 0);
      expect(result.streakDays, 0);
      expect(result.skills.every((skill) => skill.sampleSize == 0), isTrue);
      expect(result.weaknesses, isEmpty);
      expect(result.recommendations, isEmpty);
      expect(result.averageResponseTimeMs, isNull);
      expect(result.latestEvidenceAtUtc, isNull);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(2),
      );
      expect(
        await database.select(database.learningSessions).get(),
        hasLength(2),
      );
    },
  );
}

Future<void> _insertSevenDatedAttempts(AppDatabase database) async {
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'session-streak-authority',
          ownerId: 'owner-1',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: DateTime.utc(2026, 7, 24, 10).millisecondsSinceEpoch,
          endedAtUtcMs: Value(
            DateTime.utc(2026, 7, 30, 10, 1).millisecondsSinceEpoch,
          ),
          correctCount: const Value(7),
          score: const Value(100),
          appVersion: 'test',
          buildId: 'test',
        ),
      );

  for (var offset = 0; offset < 7; offset++) {
    final occurredAtUtc = DateTime.utc(2026, 7, 24 + offset, 10);
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'attempt-streak-$offset',
            ownerId: 'owner-1',
            sessionId: 'session-streak-authority',
            wordId: offset.isEven ? 'word-1' : 'word-2',
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: const Value(100),
            attemptNumber: offset + 1,
            occurredAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
          ),
        );
  }
}

Future<void> _insertStreakState(
  AppDatabase database, {
  required int currentStreakDays,
}) async {
  await database
      .into(database.streakStates)
      .insert(
        StreakStatesCompanion.insert(
          ownerId: 'owner-1',
          currentStreakDays: Value(currentStreakDays),
          longestStreakDays: Value(currentStreakDays),
          lastLearnedAtUtcMs: Value(
            DateTime.utc(2026, 7, 30, 10).millisecondsSinceEpoch,
          ),
          updatedAtUtcMs: DateTime.utc(2026, 7, 30, 10).millisecondsSinceEpoch,
        ),
      );
}

EvidenceContext _frozenV13LegacyEvidence() =>
    LearningEvidenceContract.frozenV13LegacyEvidenceContext();

EvidenceContext _assessmentEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.assessment,
  skillId: 'assessment-skill',
  hintLevel: 0,
  contentRevision: 'assessment-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.enforced,
  protocolId: 'protocol-a',
  protocolVersion: 'protocol-v1',
  experimentId: 'experiment-a',
  experimentVersion: 1,
  assignmentId: 'assignment-a',
  cohort: 'assessment',
  researchConsentVersion: 1,
  instrumentId: 'instrument-a',
  instrumentVersion: 'instrument-v1',
  formId: 'form-a',
  formVersion: 'form-v1',
  assessmentItemId: 'item-a',
  assessmentResponseCode: 'correct',
  scoringRuleVersion: 'score-v1',
  engagementAllowed: false,
);

EvidenceContext _recreationalEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.recreational,
  skillId: 'game-history',
  hintLevel: 0,
  contentRevision: 'game-content-v1',
  rolloutMode: EvidencePolicyRolloutMode.legacy,
  engagementAllowed: true,
);

Future<void> _insertAvailableWord(
  AppDatabase database, {
  required String id,
  String ownerId = 'owner-1',
  String categoryId = 'category-1',
  bool deleted = false,
  String publicationState = 'private',
  String? checksumSha256,
}) async {
  final spelling = id.replaceFirst('word-', '');
  final meaning = 'meaning-$spelling';
  const source = 'manual';
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: 'noun',
          source: const Value(source),
          contentChecksumSha256: Value(
            checksumSha256 ??
                ContentQualityPolicy.vocabularyChecksumSha256(
                  categoryId: categoryId,
                  spelling: spelling,
                  normalizedSpelling: spelling,
                  meaning: meaning,
                  normalizedMeaning: meaning,
                  partOfSpeech: 'noun',
                  cefrLevel: null,
                  source: source,
                  isGlobal: false,
                ),
          ),
          contentPublicationState: Value(publicationState),
          isDeleted: Value(deleted),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<String> _insertExactPackagedStarterWord(AppDatabase database) async {
  final word = PackagedStarterCatalog.words.first;
  final manifest = word.manifest;
  await database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: PackagedStarterCatalog.ownerId,
          accountState: const Value('localGuest'),
          createdAtUtcMs:
              PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
          isActive: const Value(false),
        ),
      );
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: PackagedStarterCatalog.categoryId,
          ownerId: PackagedStarterCatalog.ownerId,
          name: PackagedStarterCatalog.categoryName,
          normalizedName: PackagedStarterCatalog.categoryName,
          createdAtUtcMs:
              PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
          updatedAtUtcMs:
              PackagedStarterCatalog.timestamp.millisecondsSinceEpoch,
        ),
      );
  await database.into(database.vocabularyWords).insert(word.insert);
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: manifest.storageId,
          contentType: manifest.identity.type.name,
          contentId: manifest.identity.id,
          revision: manifest.identity.revision,
          checksumSha256: manifest.checksumSha256,
          byteLength: manifest.byteLength,
          provenance: manifest.provenance.name,
          sourceUri: manifest.sourceUri,
          reviewState: manifest.reviewState.name,
          publicationState: manifest.publicationState.name,
          createdAtUtcMs: manifest.createdAtUtc.millisecondsSinceEpoch,
          reviewedAtUtcMs: Value(
            manifest.reviewedAtUtc?.millisecondsSinceEpoch,
          ),
          publishedAtUtcMs: Value(
            manifest.publishedAtUtc?.millisecondsSinceEpoch,
          ),
        ),
      );
  return word.id;
}

Future<void> _insertDueState(
  AppDatabase database, {
  required String wordId,
  required int dueAtUtcMs,
}) => database
    .into(database.srsStates)
    .insert(
      SrsStatesCompanion.insert(
        id: 'srs:owner-1:$wordId',
        ownerId: 'owner-1',
        wordId: wordId,
        dueAtUtcMs: dueAtUtcMs,
        algorithmVersion: 1,
      ),
    );
