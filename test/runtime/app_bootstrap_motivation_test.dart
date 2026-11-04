import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/native_exercise_checkpoint_binding.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  test(
    'real bootstrap counts every committed quiz answer before another answer or refresh',
    () async {
      final h = await _BootstrapMotivation.open(wordCount: 20);
      var state = await h.startQuiz(limit: 20);
      expect(state.plan.questions, hasLength(20));

      for (var index = 0; index < 20; index++) {
        final pending = await h.prepareCorrectQuizAnswer(state);
        final result = await h.commitQuizAnswer(pending);
        state = result.state;
        expect(result.record.inserted, isTrue);
        await h.expectQuests(index + 1);
        expect(await h.count('answer_attempts'), index + 1);

        if ({4, 9, 19}.contains(index)) {
          final beforeReplay = await h.snapshot();
          final replay = await h.commitQuizAnswer(pending);
          expect(replay.record.inserted, isFalse);
          await h.expectQuests(index + 1);
          expect(await h.snapshot(), beforeReplay);
        }
        if (index < 19) {
          state = await h.learning.advanceQuiz(
            sessionId: state.sessionId,
            expectedOwnerId: h.ownerId,
            expectedRevision: state.checkpointRevision,
          );
        }
      }

      final closing = await h.learning.prepareQuizFinish(
        sessionId: state.sessionId,
        expectedOwnerId: h.ownerId,
        expectedRevision: state.checkpointRevision,
      );
      final finished = await h.learning.finishConfiguredQuiz(
        sessionId: state.sessionId,
        expectedOwnerId: h.ownerId,
        expectedRevision: closing.checkpointRevision,
      );
      expect(finished.summary.correctCount, 20);
      expect(finished.summary.wrongCount, 0);
      await h.expectQuests(20);
      final completed = await h.snapshot();
      await h.learning.finishConfiguredQuiz(
        sessionId: state.sessionId,
        expectedOwnerId: h.ownerId,
        expectedRevision: closing.checkpointRevision,
      );
      await h.activate();
      await h.expectQuests(20);
      expect(await h.snapshot(), completed);
      await h.expectNoResearch();
    },
  );

  test(
    'real bootstrap includes the final SRS rating immediately and replays it once',
    () async {
      final h = await _BootstrapMotivation.open(wordCount: 5);
      final prepared = await h.learning.prepareSrsReview(
        expectedOwnerId: h.ownerId,
        sourceWordIds: h.wordIds,
        limit: 5,
        stillCurrent: () => true,
      );
      final review = await h.learning.startSrsReview(
        prepared!,
        stillCurrent: () => true,
      );
      expect(review.words, hasLength(5));
      late SrsReviewAnswerIntent lastRating;
      for (var index = 0; index < 5; index++) {
        await h.learning.prepareOrdinaryAnswer(
          expectedOwnerId: h.ownerId,
          sessionId: review.id,
          stillCurrent: () => true,
        );
        lastRating = h.learning.prepareSrsRating(
          review: review,
          cardIndex: index,
          recalled: true,
          responseTimeMs: 500,
        );
        await h.learning.commitSrsRating(lastRating, stillCurrent: () => true);
        await h.expectQuests(index + 1);
      }
      final answered = await h.snapshot();
      final replay = await h.learning.commitSrsRating(
        lastRating,
        stillCurrent: () => true,
      );
      expect(replay.inserted, isFalse);
      await h.expectQuests(5);
      expect(await h.snapshot(), answered);

      final closing = h.learning.prepareSrsFinish(review);
      final summary = await h.learning.finishSrsReview(
        closing,
        stillCurrent: () => true,
      );
      expect(summary.correctCount, 5);
      final completed = await h.snapshot();
      await h.learning.finishSrsReview(closing, stillCurrent: () => true);
      await h.activate();
      await h.expectQuests(5);
      expect(await h.snapshot(), completed);
      expect(await h.count('answer_attempts'), 5);
      await h.expectNoResearch();
    },
  );

  test(
    'real bootstrap preserves native and matching reward exclusions after reconciliation',
    () async {
      final h = await _BootstrapMotivation.open(wordCount: 4);
      final exercise = (await h.learning.prepareDictation(
        categoryId: h.categoryId,
        stillCurrent: () => true,
      ))!;
      final binding = NativeExerciseCheckpointBinding(
        learning: h.learning,
        display: exercise,
        stillCurrent: () => true,
      );
      await binding.initialize();
      await binding.saveAnswer(
        NativeExerciseDraft(text: exercise.word.spelling, responseTimeMs: 500),
      );
      final nativeSummary = await binding.finish();
      expect(nativeSummary.correctCount, 1);
      await h.expectQuests(0);
      await h.activate();
      await h.expectQuests(0);

      final matching = h.dependencies.matching!;
      final plan = (await matching.prepare(
        expectedOwnerId: h.ownerId,
        categoryId: h.categoryId,
        limit: 4,
        stillCurrent: () => true,
      ))!;
      var state = await matching.start(plan, stillCurrent: () => true);
      expect(plan.words, hasLength(4));
      for (var index = 0; index < 4; index++) {
        final selected = await matching.saveSelection(
          state,
          wordIndex: index,
          meaningIndex: index,
          stillCurrent: () => true,
        );
        final pending = await matching.save(
          selected,
          matching.preparePair(
            selected,
            responseTime: const Duration(milliseconds: 500),
          ),
          stillCurrent: () => true,
        );
        state = await matching.commit(pending, stillCurrent: () => true);
        await h.expectQuests(0);
        if (index < 3) {
          state = await matching.next(state, stillCurrent: () => true);
        }
      }
      final closing = await matching.save(
        state,
        matching.prepareFinish(state),
        stillCurrent: () => true,
      );
      final finished = await matching.finish(closing, stillCurrent: () => true);
      expect(finished.completedSummary!.correctCount, 4);
      expect(await h.count('answer_attempts'), 5);
      await h.activate();
      await h.expectQuests(0);
      final reconciled = await h.snapshot();
      await matching.finish(closing, stillCurrent: () => true);
      await binding.finish();
      await h.activate();
      expect(await h.snapshot(), reconciled);
      await h.expectNoResearch();
    },
  );

  test(
    'real bootstrap rejects an old owner pending answer and credits only the current owner',
    () async {
      final h = await _BootstrapMotivation.open(wordCount: 2);
      final originalOwner = h.ownerId;
      final pending = await h.prepareCorrectQuizAnswer(
        await h.startQuiz(limit: 1),
      );
      h.runtime.setForeground(false);
      const otherOwner = 'synthetic-bootstrap-motivation-other-owner';
      final observed = h.runtime.watchChanges().firstWhere(
        (_) => h.runtime.currentOwnerId == otherOwner,
      );
      await h.database.transaction(() async {
        await h.database
            .update(h.database.localOwners)
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await h.database
            .into(h.database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: otherOwner,
                createdAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      });
      await observed.timeout(const Duration(seconds: 2));
      await expectLater(
        h.learning.commitQuizAnswer(
          sessionId: pending.sessionId,
          expectedOwnerId: originalOwner,
          expectedRevision: pending.checkpointRevision,
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.ownerChanged,
          ),
        ),
      );
      expect(await h.count('answer_attempts'), 0);

      h.ownerId = otherOwner;
      await h.seedWords(2);
      h.runtime.setForeground(true);
      await h.activate();
      final currentPending = await h.prepareCorrectQuizAnswer(
        await h.startQuiz(limit: 1),
      );
      await h.commitQuizAnswer(currentPending);
      await h.expectQuests(1);
      final attempts = await h.database.select(h.database.answerAttempts).get();
      expect(attempts.map((row) => row.ownerId), [otherOwner]);
      final originalInstances = await h.dependencies.quest!.repository
          .getAllInstances(originalOwner);
      expect(originalInstances, hasLength(2));
      expect(
        originalInstances
            .expand((row) => row.progress)
            .map((row) => row.currentCount),
        everyElement(0),
      );
      await h.expectNoResearch();
    },
  );
}

final class _BootstrapMotivation {
  _BootstrapMotivation(this.dependencies, this.ownerId);

  final AppDependencies dependencies;
  String ownerId;
  late String categoryId;
  final wordIds = <String>[];

  AppDatabase get database => dependencies.database!;
  LearningUseCases get learning => dependencies.learning!;
  MotivationRuntime get runtime => dependencies.motivation!;

  static Future<_BootstrapMotivation> open({required int wordCount}) async {
    final database = AppDatabase(NativeDatabase.memory());
    final dependencies = await AppBootstrap(
      createDatabase: () => database,
      initializeFirebase: () async => throw StateError('synthetic offline'),
      initializeSupabase: () async => throw StateError('synthetic offline'),
      loadConfig: () => throw const AppConfigException('synthetic offline'),
      guestSessionService: _OfflineGuest(),
      cloudSyncEnabled: false,
    ).initialize();
    addTearDown(dependencies.dispose);
    final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
    final h = _BootstrapMotivation(dependencies, owner.id);
    await h.seedWords(wordCount);
    h.runtime.setForeground(true);
    await h.activate();
    await h.expectQuests(0);
    return h;
  }

  Future<void> seedWords(int count) async {
    final category = await dependencies.vocabulary!.createCategory('Synthetic');
    categoryId = category.id;
    wordIds.clear();
    const spellings = [
      'apple',
      'book',
      'cloud',
      'door',
      'earth',
      'flower',
      'garden',
      'house',
      'island',
      'jacket',
      'key',
      'leaf',
      'mountain',
      'night',
      'ocean',
      'paper',
      'queen',
      'river',
      'stone',
      'tree',
    ];
    for (var index = 0; index < count; index++) {
      final word = await dependencies.vocabulary!.createWord(
        CreateWordCommand(
          categoryId: categoryId,
          spelling: spellings[index],
          meaning: 'Synthetic meaning ${index + 1}',
          partOfSpeech: 'noun',
        ),
      );
      wordIds.add(word.id);
    }
  }

  Future<void> activate() =>
      runtime.activate(ownerId: ownerId, stillCurrent: () => true);

  Future<ConfiguredQuizState> startQuiz({required int limit}) async {
    final launch = await learning.prepareConfiguredQuiz(
      expectedOwnerId: ownerId,
      configuration: QuizConfiguration.category(
        categoryId: categoryId,
        limit: limit,
        direction: MeaningQuizDirection.reverse,
        hints: QuizHintPolicy.disabled,
      ),
    );
    return learning.startConfiguredQuiz(launch);
  }

  Future<ConfiguredQuizState> prepareCorrectQuizAnswer(
    ConfiguredQuizState state,
  ) {
    final question = state.plan.questions[state.checkpoint.questionOrdinal];
    return learning.prepareQuizAnswer(
      sessionId: state.sessionId,
      expectedOwnerId: ownerId,
      expectedRevision: state.checkpointRevision,
      selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
    );
  }

  Future<ConfiguredQuizAnswerResult> commitQuizAnswer(
    ConfiguredQuizState pending,
  ) => learning.commitQuizAnswer(
    sessionId: pending.sessionId,
    expectedOwnerId: ownerId,
    expectedRevision: pending.checkpointRevision,
  );

  Future<void> expectQuests(int answers) async {
    final view = await runtime.load(
      expectedOwnerId: ownerId,
      stillCurrent: () => true,
    );
    expect(view.history, hasLength(2));
    expect(view.history.map((row) => row.ownerId), everyElement(ownerId));
    final daily = view.history.singleWhere(
      (row) => row.questId == 'daily-correct-5-v1',
    );
    final weekly = view.history.singleWhere(
      (row) => row.questId == 'weekly-correct-20-v1',
    );
    expect(weekly.progress.single.currentCount, answers);
    expect(daily.progress.single.currentCount, answers < 5 ? answers : 5);
    expect(daily.state.name, answers >= 5 ? 'completed' : 'active');
    expect(weekly.state.name, answers >= 20 ? 'completed' : 'active');
    expect(
      view.motivation.questXp,
      answers >= 20
          ? 250
          : answers >= 5
          ? 50
          : 0,
    );
    expect(view.motivation.state.freezeCount, answers >= 20 ? 1 : 0);
  }

  Future<int> count(String table) async =>
      (await database
              .customSelect('SELECT COUNT(*) AS n FROM "$table"')
              .getSingle())
          .read<int>('n');

  Future<Map<String, List<String>>> snapshot() async => {
    for (final table in database.allTables)
      table.actualTableName: [
        for (final row
            in await database
                .customSelect(
                  'SELECT * FROM "${table.actualTableName}" ORDER BY rowid',
                )
                .get())
          jsonEncode(row.data),
      ],
  };

  Future<void> expectNoResearch() async {
    expect(dependencies.researchAvailability.isEnabled, isFalse);
    expect(dependencies.studyRuntime, isNull);
    for (final table in [
      'research_consents',
      'experiment_assignments',
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'measurement_opportunities',
      'assessment_runs',
      'events_v2',
    ]) {
      expect(await count(table), 0, reason: table);
    }
    final outbox = await database.select(database.outboxOperations).get();
    expect(outbox, isNotEmpty);
    expect(
      outbox.map((row) => row.entityType),
      everyElement(
        isIn(const {
          'category',
          'word',
          'attempt',
          'readingEvent',
          'rewardTransaction',
          'srsState',
          'achievementUnlock',
        }),
      ),
    );
  }
}

final class _OfflineGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}
