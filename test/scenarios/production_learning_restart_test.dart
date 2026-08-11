import 'dart:async';
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
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

const _ownerSeed = 'learning-restart-owner';
const _ownerId = 'local:$_ownerSeed';
const _buildInfo = AppBuildInfo(version: '1.0.0', buildId: 'restart-test');

AppDatabase _openDatabase(String path) =>
    AppDatabase(NativeDatabase(File(path)));

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
}) => database
    .into(database.eventsV2)
    .insert(
      EventsV2Companion.insert(
        eventId: 'learning-event:real-$number',
        eventType: 'QuizCompleted',
        eventVersion: 1,
        occurredAtUtc: occurredAt,
        recordedAtUtc: occurredAt,
        actorIdentity: ownerId,
        ownerId: ownerId,
        aggregateType: 'LearningSession',
        aggregateId: 'session-real',
        idempotencyKey: 'learning-attempt:real-$number:v1',
        consentContextJson: '{}',
        appVersion: '1.0.0',
        buildId: 'restart-test',
        privacyClassification: 'anonymized',
        payloadJson: '{"correct":true}',
      ),
    );

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
                rewardItemId,
              }) => rewardRepository.grantQuestXp(
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                xpAmount: xpAmount,
              ),
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
          questEventSink: (event) =>
              quest.processEvent(event, [questDefinition]).then((_) {}),
          streakEventSink: () => streak.recordLearningDay().then((_) {}),
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
          questEventSink: (_) async => throw StateError('quest unavailable'),
          streakEventSink: () async => throw StateError('streak unavailable'),
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
        await first.close();
        first = null;

        reopened = _openDatabase(path);
        final attempts = await reopened.select(reopened.answerAttempts).get();
        final srs = await reopened.select(reopened.srsStates).get();
        final attemptOutbox = await (reopened.select(
          reopened.outboxOperations,
        )..where((row) => row.entityType.equals('attempt'))).get();
        final replayEvents = await (reopened.select(
          reopened.eventsV2,
        )..where((row) => row.ownerId.equals(_ownerId))).get();

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
          questEventSink: (event) async {
            deliveredEventIds.add(event.eventId);
            await quest.processEvent(event, [questDefinition]);
            throw StateError('quest failed after applying');
          },
          streakEventSink: () async {
            await streak.recordLearningDay();
            throw StateError('streak failed after applying');
          },
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
          questEventSink: (event) async {
            deliveredEventIds.add(event.eventId);
            await reopenedQuest.processEvent(event, [questDefinition]);
          },
          streakEventSink: () =>
              reopenedStreak.recordLearningDay().then((_) {}),
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
                rewardItemId,
              }) => rewardRepository.grantQuestXp(
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                xpAmount: xpAmount,
              ),
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
                rewardItemId,
              }) => restartedRewards.grantQuestXp(
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                xpAmount: xpAmount,
              ),
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
