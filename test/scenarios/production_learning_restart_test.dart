import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide QuestDefinition, VocabularyWord;
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
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
}
