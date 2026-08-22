import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide QuestDefinition, QuestInstance, VocabularyWord;
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/learning_side_effect_reconciler.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/economy_transaction_policy.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

const _ownerSeed = 'learning-restart-owner';
const _ownerId = 'local:$_ownerSeed';
const _buildInfo = AppBuildInfo(version: '1.0.0', buildId: 'restart-test');

AppDatabase _openDatabase(String path) =>
    AppDatabase(NativeDatabase(File(path)));

LearningEvidenceProjectionSink _coinsSink(DriftRewardRepository rewards) =>
    (_, evidence) async {
      final isCorrect = evidence.attempt.isCorrect;
      final eligibleClass =
          evidence.context.evidenceClass != EvidenceClass.assessment &&
          evidence.context.evidenceClass != EvidenceClass.recreational;
      final award = const EconomyAwardPolicyV1().evaluate(
        sourceEventId: evidence.attempt.id,
        amount: 1,
        eligible: isCorrect && eligibleClass,
      );
      if (award.coinAmount == 0) {
        return LearningProjectionResult.notApplicable(
          payload: <String, dynamic>{
            'reasonCode': isCorrect ? 'evidenceIneligible' : 'incorrectAnswer',
          },
        );
      }
      final result = await rewards.grantCoins(
        ownerId: evidence.attempt.ownerId,
        idempotencyKey: award.coinIdempotencyKey,
        amount: award.coinAmount,
        sourceEventId: award.sourceEventId,
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
          evidence.attempt.occurredAtUtcMs,
          isUtc: true,
        ),
      );
      return switch (result) {
        CoinGrantResult.inserted => const LearningProjectionResult.applied(
          payload: <String, dynamic>{'status': 'inserted'},
        ),
        CoinGrantResult.replayed => const LearningProjectionResult.applied(
          payload: <String, dynamic>{'status': 'replayed'},
        ),
        CoinGrantResult.capturedByLegacyBackfill =>
          const LearningProjectionResult.notApplicable(
            payload: <String, dynamic>{
              'reasonCode': 'capturedByLegacyBackfill',
            },
          ),
      };
    };

final class _CrashAfterProgressRepository implements QuestRepository {
  _CrashAfterProgressRepository(this.delegate);
  final QuestRepository delegate;
  bool armed = true;

  @override
  Future<void> saveProgress(String id, List<ObjectiveProgress> progress) async {
    await delegate.saveProgress(id, progress);
    if (armed) {
      armed = false;
      throw StateError('injected crash after progress before completion');
    }
  }

  @override
  Future<QuestDefinition?> getDefinition(String id) =>
      delegate.getDefinition(id);
  @override
  Future<List<QuestInstance>> getActiveInstances(String owner) =>
      delegate.getActiveInstances(owner);
  @override
  Future<List<QuestInstance>> getAllInstances(String owner, {int limit = 50}) =>
      delegate.getAllInstances(owner, limit: limit);
  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) => delegate.getCompletedInstancesForSourceEvent(
    ownerId: ownerId,
    sourceEventId: sourceEventId,
    questIds: questIds,
    limit: limit,
  );
  @override
  Future<void> markAbandoned(String id) => delegate.markAbandoned(id);
  @override
  Future<void> markCompleted(String id, DateTime at) =>
      delegate.markCompleted(id, at);
  @override
  Future<void> markExpired(String id, DateTime at) =>
      delegate.markExpired(id, at);
  @override
  Future<void> startInstance(QuestInstance instance) =>
      delegate.startInstance(instance);
  @override
  Future<void> upsertDefinition(QuestDefinition definition) =>
      delegate.upsertDefinition(definition);
}

Future<void> _insertLearningEvent(
  AppDatabase database, {
  required String ownerId,
  required int number,
  required DateTime occurredAt,
}) async {
  final attemptId = 'real-$number';
  final categoryId = 'category-real-$ownerId';
  final wordId = 'word-real-$ownerId';
  const sessionId = 'session-real';
  final context = LearningEvidenceContract.frozenV13LegacyEvidenceContext();
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Legacy replay',
          normalizedName: 'legacy replay',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: wordId,
          ownerId: ownerId,
          categoryId: categoryId,
          spelling: 'legacy',
          normalizedSpelling: 'legacy',
          meaning: 'replay',
          normalizedMeaning: 'replay',
          partOfSpeech: 'noun',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
          updatedAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: ownerId,
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: '1.0.0',
          buildId: 'restart-test',
        ),
        mode: InsertMode.insertOrIgnore,
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: attemptId,
          ownerId: ownerId,
          sessionId: sessionId,
          wordId: wordId,
          promptMode: 'meaningChoice',
          isCorrect: true,
          attemptNumber: number,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(context.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(context.toJson())),
        ),
      );
  await database
      .into(database.eventsV2)
      .insert(
        EventsV2Companion.insert(
          eventId: 'learning-event:$attemptId',
          eventType: 'QuizCompleted',
          eventVersion: 1,
          occurredAtUtc: occurredAt,
          recordedAtUtc: occurredAt,
          actorIdentity: ownerId,
          ownerId: ownerId,
          aggregateType: 'LearningSession',
          aggregateId: sessionId,
          idempotencyKey: 'learning-attempt:$attemptId:v1',
          consentContextJson: '{}',
          appVersion: '1.0.0',
          buildId: 'restart-test',
          privacyClassification: 'anonymized',
          payloadJson: jsonEncode(<String, dynamic>{'attemptId': attemptId}),
        ),
      );
}

Future<int> _appliedReceiptCount(
  AppDatabase database,
  String projection,
) async {
  final row = await database
      .customSelect(
        "SELECT COUNT(*) AS total FROM events_v2 WHERE event_type = "
        "'LearningProjectionApplied' AND json_extract(payload_json, "
        "'\$.projection') = ?",
        variables: [Variable<String>(projection)],
        readsFrom: {database.eventsV2},
      )
      .getSingle();
  return row.read<int>('total');
}

DriftLocalOwnerRepository _owners(
  AppDatabase database,
  DateTime Function() now,
) {
  return DriftLocalOwnerRepository(
    database,
    generateId: () => _ownerSeed,
    nowUtc: now,
  );
}

String Function() _ids(List<String> values) {
  var index = 0;
  return () {
    if (index >= values.length) {
      throw StateError('test id sequence exhausted');
    }
    return values[index++];
  };
}

Future<VocabularyWord> _createVocabulary({
  required AppDatabase database,
  required DriftLocalOwnerRepository owners,
  required DateTime Function() now,
  required String suffix,
}) async {
  final vocabulary = VocabularyUseCases(
    owners: owners,
    vocabulary: DriftVocabularyRepository(database),
    generateId: _ids(['category-$suffix', 'word-$suffix']),
    nowUtc: now,
  );
  final category = await vocabulary.createCategory('Restart Travel');
  return vocabulary.createWord(
    CreateWordCommand(
      categoryId: category.id,
      spelling: 'station',
      meaning: 'station meaning',
      partOfSpeech: 'noun',
    ),
  );
}

QuestDefinition _correctAnswerQuest({
  required String id,
  required int targetCount,
  required int xp,
}) {
  return QuestDefinition(
    questId: id,
    catalogVersion: 1,
    title: 'Durable correct answers',
    description: 'Prove correct answers replay once.',
    type: QuestType.daily,
    objectives: [
      QuestObjective(
        objectiveId: 'correct-answers',
        description: 'Correct answers',
        targetCount: targetCount,
        criteria: const ObjectiveCriteria(
          eventType: 'QuizCompleted',
          filters: {'correct': true},
        ),
      ),
    ],
    reward: RewardSpec(xpAmount: xp),
  );
}

void main() {
  setUpAll(tz.initializeTimeZones);

  test(
    'production learning projections survive a file-backed restart',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-restart-',
      );
      final path = '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDatabase? first;
      AppDatabase? reopened;
      LearningReconciliationScheduler? firstReconciliation;
      var now = DateTime.utc(2026, 8, 9, 3);

      try {
        first = _openDatabase(path);
        final owners = _owners(first, () => now);
        final owner = await owners.getOrCreateActiveOwner();
        final word = await _createVocabulary(
          database: first,
          owners: owners,
          now: () => now,
          suffix: 'journey',
        );
        final rewardRepository = DriftRewardRepository(first);
        final quest = QuestUseCases(
          repository: DriftQuestRepository(first),
          owners: owners,
          generateId: () => 'journey-quest-instance',
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
          rewardSink:
              ({
                required ownerId,
                required idempotencyKey,
                required xpAmount,
                required sourceEventId,
                required occurredAtUtc,
                rewardItemId,
              }) async {
                await rewardRepository.grantQuestXpAndCoins(
                  ownerId: ownerId,
                  sourceEventId: sourceEventId,
                  xpAmount: xpAmount,
                  occurredAtUtc: occurredAtUtc,
                );
              },
        );
        final questDefinition = _correctAnswerQuest(
          id: 'restart-correct-once',
          targetCount: 1,
          xp: 50,
        );
        await quest.startQuest(questDefinition);
        final streak = StreakUseCases(
          repository: DriftStreakRepository(first),
          owners: owners,
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        );
        firstReconciliation = LearningReconciliationScheduler(
          LearningSideEffectReconciler(
            first,
            coinsSink: _coinsSink(rewardRepository),
            questSink: (event) async {
              final projection = await quest.projectEvent(event, [
                questDefinition,
              ]);
              final payload = quest.projectionPayload(projection, [
                questDefinition,
              ]);
              return projection.eligible
                  ? LearningProjectionResult.applied(payload: payload)
                  : LearningProjectionResult.notApplicable(payload: payload);
            },
            streakSink: (event) async {
              await streak.recordLearningDayForOwner(
                ownerId: event.ownerIdentity,
                occurredAtUtc: event.occurredAtUtc,
              );
              return const LearningProjectionResult.applied();
            },
            rewardSink: (event, questResult) async {
              final applied = await quest.reconcileReward(event, questResult);
              return applied
                  ? const LearningProjectionResult.applied()
                  : const LearningProjectionResult.notApplicable();
            },
          ),
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(first),
          generateId: _ids([
            'journey-session',
            'journey-correct',
            'journey-wrong',
          ]),
          nowUtc: () => now,
          buildInfo: _buildInfo,
          eventAdapter: const EventV1ToV2Adapter(
            appVersion: '1.0.0',
            buildId: 'restart-test',
          ),
          onSideEffectsPending: firstReconciliation.request,
        );

        final quiz = await learning.startQuiz(limit: 10);
        await learning.recordAnswer(
          sessionId: quiz.id,
          wordId: word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 350,
          attemptNumber: 1,
        );
        now = now.add(const Duration(minutes: 1));
        final incorrectAt = now;
        await learning.recordAnswer(
          sessionId: quiz.id,
          wordId: word.id,
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 700,
          attemptNumber: 2,
        );
        await firstReconciliation.drain();
        await firstReconciliation.dispose();
        firstReconciliation = null;

        await first.close();
        first = null;

        reopened = _openDatabase(path);
        final reopenedOwners = _owners(reopened, () => now);
        final reopenedOwner = await reopenedOwners.getOrCreateActiveOwner();
        final attempts = await (reopened.select(
          reopened.answerAttempts,
        )..where((row) => row.ownerId.equals(_ownerId))).get();
        final srs = await (reopened.select(
          reopened.srsStates,
        )..where((row) => row.ownerId.equals(_ownerId))).getSingle();
        final progress = await ProgressUseCases(
          owners: reopenedOwners,
          queries: DriftProgressQueries(reopened),
          nowUtc: () => now,
        ).load();
        final rewards = await RewardUseCases(
          owners: reopenedOwners,
          repository: DriftRewardRepository(reopened),
          generateId: () => 'unused-reward-id',
          nowUtc: () => now,
        ).load();
        final questInstances = await DriftQuestRepository(
          reopened,
        ).getAllInstances(_ownerId);
        final streakState = await StreakUseCases(
          repository: DriftStreakRepository(reopened),
          owners: reopenedOwners,
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        ).getCurrentStreak();
        final attemptOutbox =
            await (reopened.select(reopened.outboxOperations)..where(
                  (row) =>
                      row.ownerId.equals(_ownerId) &
                      row.entityType.equals('attempt'),
                ))
                .get();

        expect(reopenedOwner.id, owner.id);
        expect(attempts, hasLength(2));
        expect(srs.repetitions, 0);
        expect(srs.lapses, 1);
        expect(
          srs.dueAtUtcMs,
          incorrectAt.add(const Duration(days: 1)).millisecondsSinceEpoch,
        );
        expect(progress.sampleSize, 2);
        expect(progress.correctCount, 1);
        expect(progress.wrongCount, 1);
        expect(progress.masteredWordCount, 0);
        expect(progress.weaknesses.single.wordId, word.id);
        expect(progress.weaknesses.single.incorrectCount, 1);
        expect(progress.totalXp, 51);
        expect(rewards.balance, 51);
        expect(streakState.currentStreakDays, 1);
        expect(questInstances, hasLength(1));
        expect(questInstances.single.state, QuestInstanceState.completed);
        expect(questInstances.single.progress.single.currentCount, 1);
        expect(
          questInstances.single.progress.single.sourceEventIds,
          hasLength(1),
        );
        expect(attemptOutbox.map((row) => row.entityId).toSet(), {
          'attempt:journey-correct',
          'attempt:journey-wrong',
        });
        expect(attemptOutbox.map((row) => row.operationId).toSet(), {
          'attempt:attempt:journey-correct:1',
          'attempt:attempt:journey-wrong:1',
        });
      } finally {
        await firstReconciliation?.dispose();
        await reopened?.close();
        await first?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'post-commit sink failure leaves a durable event envelope for replay',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-envelope-',
      );
      final path = '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDatabase? first;
      AppDatabase? reopened;
      LearningReconciliationScheduler? firstReconciliation;
      final now = DateTime.utc(2026, 8, 9, 4);

      try {
        first = _openDatabase(path);
        final owners = _owners(first, () => now);
        final word = await _createVocabulary(
          database: first,
          owners: owners,
          now: () => now,
          suffix: 'failure',
        );
        firstReconciliation = LearningReconciliationScheduler(
          LearningSideEffectReconciler(
            first,
            questSink: (_) async => throw StateError('quest unavailable'),
            streakSink: (_) async => throw StateError('streak unavailable'),
          ),
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(first),
          generateId: _ids(['failure-session', 'failure-answer']),
          nowUtc: () => now,
          buildInfo: _buildInfo,
          eventAdapter: const EventV1ToV2Adapter(
            appVersion: '1.0.0',
            buildId: 'restart-test',
          ),
          onSideEffectsPending: firstReconciliation.request,
        );
        final quiz = await learning.startQuiz(limit: 10);

        await learning.recordAnswer(
          sessionId: quiz.id,
          wordId: word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 400,
          attemptNumber: 1,
        );
        await firstReconciliation.drain();
        await firstReconciliation.dispose();
        firstReconciliation = null;
        await first.close();
        first = null;

        reopened = _openDatabase(path);
        final attempts = await reopened.select(reopened.answerAttempts).get();
        final srs = await reopened.select(reopened.srsStates).get();
        final attemptOutbox = await (reopened.select(
          reopened.outboxOperations,
        )..where((row) => row.entityType.equals('attempt'))).get();
        final replayEvents =
            await (reopened.select(reopened.eventsV2)..where(
                  (row) =>
                      row.ownerId.equals(_ownerId) &
                      row.eventId.equals(
                        'learning-event:attempt:failure-answer',
                      ),
                ))
                .get();

        expect(attempts, hasLength(1));
        expect(attempts.single.id, 'attempt:failure-answer');
        expect(srs, hasLength(1));
        expect(srs.single.repetitions, 1);
        expect(attemptOutbox, hasLength(1));
        expect(attemptOutbox.single.state, 'pending');
        expect(attemptOutbox.single.entityId, attempts.single.id);
        expect(
          replayEvents,
          hasLength(1),
          reason:
              'a swallowed post-commit projection failure needs a durable '
              'EventEnvelopeV2 replay source',
        );
      } finally {
        await firstReconciliation?.dispose();
        await reopened?.close();
        await first?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'retrying the same durable answer keeps XP quest and streak idempotent',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-learning-replay-',
      );
      final path = '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDatabase? first;
      AppDatabase? reopened;
      LearningReconciliationScheduler? firstReconciliation;
      LearningReconciliationScheduler? reopenedReconciliation;
      final now = DateTime.utc(2026, 8, 9, 5);
      final deliveredEventIds = <String>[];
      final questDefinition = _correctAnswerQuest(
        id: 'replay-correct-five',
        targetCount: 5,
        xp: 0,
      );

      try {
        first = _openDatabase(path);
        final owners = _owners(first, () => now);
        final word = await _createVocabulary(
          database: first,
          owners: owners,
          now: () => now,
          suffix: 'replay',
        );
        final quest = QuestUseCases(
          repository: DriftQuestRepository(first),
          owners: owners,
          generateId: () => 'replay-quest-instance',
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        );
        await quest.startQuest(questDefinition);
        final streak = StreakUseCases(
          repository: DriftStreakRepository(first),
          owners: owners,
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        );
        firstReconciliation = LearningReconciliationScheduler(
          LearningSideEffectReconciler(
            first,
            questSink: (event) async {
              deliveredEventIds.add(event.eventId);
              await quest.projectEvent(event, [questDefinition]);
              throw StateError('quest failed after applying');
            },
            streakSink: (event) async {
              await streak.recordLearningDayForOwner(
                ownerId: event.ownerIdentity,
                occurredAtUtc: event.occurredAtUtc,
              );
              throw StateError('streak failed after applying');
            },
          ),
        );
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(first),
          generateId: _ids(['replay-session', 'replay-answer']),
          nowUtc: () => now,
          buildInfo: _buildInfo,
          eventAdapter: const EventV1ToV2Adapter(
            appVersion: '1.0.0',
            buildId: 'restart-test',
          ),
          onSideEffectsPending: firstReconciliation.request,
        );
        final quiz = await learning.startQuiz(limit: 10);
        await learning.recordAnswer(
          sessionId: quiz.id,
          wordId: word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 300,
          attemptNumber: 1,
        );
        await firstReconciliation.drain();
        await firstReconciliation.dispose();
        firstReconciliation = null;
        await first.close();
        first = null;

        reopened = _openDatabase(path);
        final reopenedOwners = _owners(reopened, () => now);
        final reopenedQuest = QuestUseCases(
          repository: DriftQuestRepository(reopened),
          owners: reopenedOwners,
          generateId: () => 'unused-quest-id',
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        );
        final reopenedStreak = StreakUseCases(
          repository: DriftStreakRepository(reopened),
          owners: reopenedOwners,
          nowUtc: () => now,
          timezoneId: 'Asia/Bangkok',
        );
        reopenedReconciliation = LearningReconciliationScheduler(
          LearningSideEffectReconciler(
            reopened,
            questSink: (event) async {
              deliveredEventIds.add(event.eventId);
              final projection = await reopenedQuest.projectEvent(event, [
                questDefinition,
              ]);
              final payload = reopenedQuest.projectionPayload(projection, [
                questDefinition,
              ]);
              return projection.eligible
                  ? LearningProjectionResult.applied(payload: payload)
                  : LearningProjectionResult.notApplicable(payload: payload);
            },
            streakSink: (event) async {
              await reopenedStreak.recordLearningDayForOwner(
                ownerId: event.ownerIdentity,
                occurredAtUtc: event.occurredAtUtc,
              );
              return const LearningProjectionResult.applied();
            },
            rewardSink: (event, questResult) async {
              final applied = await reopenedQuest.reconcileReward(
                event,
                questResult,
              );
              return applied
                  ? const LearningProjectionResult.applied()
                  : const LearningProjectionResult.notApplicable();
            },
          ),
        );
        final replayLearning = LearningUseCases(
          owners: reopenedOwners,
          repository: DriftLearningRepository(reopened),
          generateId: () => 'replay-answer',
          nowUtc: () => now,
          buildInfo: _buildInfo,
          eventAdapter: const EventV1ToV2Adapter(
            appVersion: '1.0.0',
            buildId: 'restart-test',
          ),
          onSideEffectsPending: reopenedReconciliation.request,
        );

        for (var replay = 0; replay < 2; replay++) {
          final result = await replayLearning.recordAnswer(
            sessionId: quiz.id,
            wordId: word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 300,
            attemptNumber: 1,
          );
          expect(result.inserted, isFalse);
        }
        await reopenedReconciliation.drain();

        final attempts = await reopened.select(reopened.answerAttempts).get();
        final answerXp = await (reopened.select(
          reopened.pointsLedgerEntries,
        )..where((row) => row.entryType.equals('quizCorrect'))).get();
        final attemptOutbox = await (reopened.select(
          reopened.outboxOperations,
        )..where((row) => row.entityType.equals('attempt'))).get();
        final instances = await DriftQuestRepository(
          reopened,
        ).getAllInstances(_ownerId);
        final learningDays = await DriftStreakRepository(
          reopened,
        ).getLearningDays(_ownerId);
        final streakState = await reopenedStreak.getCurrentStreak();

        expect(attempts, hasLength(1));
        expect(answerXp, hasLength(1));
        expect(attemptOutbox, hasLength(1));
        expect(learningDays, hasLength(1));
        expect(streakState.currentStreakDays, 1);
        expect(
          {
            'distinctEventIds': deliveredEventIds.toSet().length,
            'questProgress': instances.single.progress.single.currentCount,
          },
          {'distinctEventIds': 1, 'questProgress': 1},
          reason:
              'replay must reuse the durable answer event identity so quest '
              'source-event de-duplication can prevent duplicate progress',
        );
      } finally {
        await reopenedReconciliation?.dispose();
        await firstReconciliation?.dispose();
        await reopened?.close();
        await first?.close();
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'real reconciler recovers quest boundary and reward receipt crashes',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-real-reconcile-',
      );
      final path = '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDatabase? database;
      final at = DateTime.utc(2026, 8, 9, 8);
      final definition = _correctAnswerQuest(
        id: 'real-crash-quest',
        targetCount: 1,
        xp: 40,
      );
      try {
        database = _openDatabase(path);
        var owners = _owners(database, () => at);
        final owner = await owners.getOrCreateActiveOwner();
        final realQuestRepository = DriftQuestRepository(database);
        var quest = QuestUseCases(
          repository: realQuestRepository,
          owners: owners,
          generateId: () => 'real-crash-instance',
          nowUtc: () => at,
          timezoneId: 'Asia/Bangkok',
        );
        await quest.startQuest(definition);
        await _insertLearningEvent(
          database,
          ownerId: owner.id,
          number: 1,
          occurredAt: at,
        );
        quest = QuestUseCases(
          repository: _CrashAfterProgressRepository(realQuestRepository),
          owners: owners,
          generateId: () => 'unused',
          nowUtc: () => at,
          timezoneId: 'Asia/Bangkok',
        );
        final firstReconciler = LearningSideEffectReconciler(
          database,
          questSink: (event) async {
            final projection = await quest.projectEvent(event, [definition]);
            return LearningProjectionResult.applied(
              payload: quest.projectionPayload(projection, [definition]),
            );
          },
          streakSink: (_) async => const LearningProjectionResult.applied(),
          rewardSink: (_, _) async => const LearningProjectionResult.applied(),
        );
        await firstReconciler.reconcileOwner(owner.id);

        final active = await realQuestRepository.getActiveInstances(owner.id);
        expect(active.single.progress.single.currentCount, 1);
        expect(await _appliedReceiptCount(database, 'quest'), 0);
        expect(await _appliedReceiptCount(database, 'reward'), 0);
        await database.close();
        database = null;

        database = _openDatabase(path);
        owners = _owners(database, () => at);
        final rewardRepository = DriftRewardRepository(database);
        quest = QuestUseCases(
          repository: DriftQuestRepository(database),
          owners: owners,
          generateId: () => 'unused-after-restart',
          nowUtc: () => at,
          timezoneId: 'Asia/Bangkok',
          rewardSink:
              ({
                required ownerId,
                required idempotencyKey,
                required xpAmount,
                required sourceEventId,
                required occurredAtUtc,
                rewardItemId,
              }) async {
                await rewardRepository.grantQuestXpAndCoins(
                  ownerId: ownerId,
                  sourceEventId: sourceEventId,
                  xpAmount: xpAmount,
                  occurredAtUtc: occurredAtUtc,
                );
              },
        );
        await database.customStatement('''
          CREATE TRIGGER fail_reward_receipt
          BEFORE INSERT ON events_v2
          WHEN NEW.event_type = 'LearningProjectionApplied'
            AND json_extract(NEW.payload_json, '\$.projection') = 'reward'
          BEGIN SELECT RAISE(ABORT, 'injected reward receipt crash'); END
        ''');
        LearningSideEffectReconciler realReconciler() =>
            LearningSideEffectReconciler(
              database!,
              questSink: (event) async {
                final projection = await quest.projectEvent(event, [
                  definition,
                ]);
                return LearningProjectionResult.applied(
                  payload: quest.projectionPayload(projection, [definition]),
                );
              },
              streakSink: (_) async => const LearningProjectionResult.applied(),
              rewardSink: (event, questResult) async =>
                  await quest.reconcileReward(event, questResult)
                  ? const LearningProjectionResult.applied()
                  : const LearningProjectionResult.notApplicable(),
            );
        await realReconciler().reconcileOwner(owner.id);
        expect(await _appliedReceiptCount(database, 'quest'), 1);
        expect(await _appliedReceiptCount(database, 'reward'), 0);
        expect(
          await (database.select(
            database.pointsLedgerEntries,
          )..where((row) => row.entryType.equals('questCompletion'))).get(),
          hasLength(1),
        );
        await database.close();
        database = null;

        database = _openDatabase(path);
        await database.customStatement('DROP TRIGGER fail_reward_receipt');
        owners = _owners(database, () => at);
        final restartedRewards = DriftRewardRepository(database);
        quest = QuestUseCases(
          repository: DriftQuestRepository(database),
          owners: owners,
          generateId: () => 'unused-final',
          nowUtc: () => at,
          timezoneId: 'Asia/Bangkok',
          rewardSink:
              ({
                required ownerId,
                required idempotencyKey,
                required xpAmount,
                required sourceEventId,
                required occurredAtUtc,
                rewardItemId,
              }) async {
                await restartedRewards.grantQuestXpAndCoins(
                  ownerId: ownerId,
                  sourceEventId: sourceEventId,
                  xpAmount: xpAmount,
                  occurredAtUtc: occurredAtUtc,
                );
              },
        );
        await realReconciler().reconcileOwner(owner.id);
        expect(await _appliedReceiptCount(database, 'reward'), 1);
        expect(
          await (database.select(
            database.pointsLedgerEntries,
          )..where((row) => row.entryType.equals('questCompletion'))).get(),
          hasLength(1),
        );
      } finally {
        await database?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'real streak replay is ordered and applies the durable event owner',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-real-streak-',
      );
      final path = '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      AppDatabase? database;
      final firstDay = DateTime.utc(2026, 8, 8, 5);
      try {
        database = _openDatabase(path);
        final owners = _owners(database, () => firstDay);
        final ownerA = await owners.getOrCreateActiveOwner();
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(ownerA.id)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'owner-b',
                createdAtUtcMs: firstDay.millisecondsSinceEpoch,
                isActive: const Value(true),
              ),
            );
        await _insertLearningEvent(
          database,
          ownerId: ownerA.id,
          number: 1,
          occurredAt: firstDay,
        );
        await _insertLearningEvent(
          database,
          ownerId: ownerA.id,
          number: 2,
          occurredAt: firstDay.add(const Duration(days: 1)),
        );
        var oldestFailed = false;
        final streak = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: owners,
          nowUtc: () => firstDay,
          timezoneId: 'UTC',
        );
        final failing = LearningSideEffectReconciler(
          database,
          streakSink: (event) async {
            if (!oldestFailed) {
              oldestFailed = true;
              throw StateError('oldest unavailable');
            }
            await streak.recordLearningDayForOwner(
              ownerId: event.ownerIdentity,
              occurredAtUtc: event.occurredAtUtc,
            );
            return const LearningProjectionResult.applied();
          },
        );
        await failing.reconcileOwner(ownerA.id);
        expect(await _appliedReceiptCount(database, 'streak'), 0);
        expect(
          await DriftStreakRepository(database).getLearningDays('owner-b'),
          isEmpty,
        );
        await database.close();
        database = null;

        database = _openDatabase(path);
        final restartedOwners = _owners(database, () => firstDay);
        final restartedStreak = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: restartedOwners,
          nowUtc: () => firstDay,
          timezoneId: 'UTC',
        );
        final real = LearningSideEffectReconciler(
          database,
          streakSink: (event) async {
            await restartedStreak.recordLearningDayForOwner(
              ownerId: event.ownerIdentity,
              occurredAtUtc: event.occurredAtUtc,
            );
            return const LearningProjectionResult.applied();
          },
        );
        await real.reconcileOwner(ownerA.id);
        expect(
          await DriftStreakRepository(database).getLearningDays(ownerA.id),
          ['2026-08-09', '2026-08-08'],
        );
        expect(
          await DriftStreakRepository(database).getLearningDays('owner-b'),
          isEmpty,
        );
        expect(await _appliedReceiptCount(database, 'streak'), 2);
      } finally {
        await database?.close();
        if (await directory.exists()) await directory.delete(recursive: true);
      }
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );

  test(
    'answer completion does not await an offline projection batch',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final now = DateTime.utc(2026, 8, 9, 9);
      final owners = _owners(database, () => now);
      final word = await _createVocabulary(
        database: database,
        owners: owners,
        now: () => now,
        suffix: 'latency',
      );
      final entered = Completer<void>();
      final release = Completer<void>();
      final scheduler = LearningReconciliationScheduler(
        LearningSideEffectReconciler(
          database,
          streakSink: (_) async {
            entered.complete();
            await release.future;
            return const LearningProjectionResult.applied();
          },
        ),
      );
      try {
        final learning = LearningUseCases(
          owners: owners,
          repository: DriftLearningRepository(database),
          generateId: _ids(['latency-session', 'latency-answer']),
          nowUtc: () => now,
          buildInfo: _buildInfo,
          eventAdapter: const EventV1ToV2Adapter(
            appVersion: '1.0.0',
            buildId: 'restart-test',
          ),
          onSideEffectsPending: scheduler.request,
        );
        final quiz = await learning.startQuiz();
        final result = await learning.recordAnswer(
          sessionId: quiz.id,
          wordId: word.id,
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: 1,
        );
        expect(result.inserted, isTrue);
        await entered.future;
        release.complete();
        await scheduler.drain();
      } finally {
        if (!release.isCompleted) release.complete();
        await scheduler.dispose();
        await database.close();
      }
    },
  );
}
