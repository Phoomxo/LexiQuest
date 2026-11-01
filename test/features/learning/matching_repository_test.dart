import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/matching_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/matching_exercise.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late ConfiguredQuizHarness h;
  late DriftLearningRepository canonical;
  late DriftMatchingRepository repository;
  late MatchingUseCases matching;
  var ids = 0;

  void configure() {
    canonical = DriftLearningRepository(h.database, ownerWrites: h.ownerWrites);
    repository = DriftMatchingRepository(canonical);
    matching = MatchingUseCases(
      repository: repository,
      generateId: () => 'synthetic-matching-${++ids}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(
        version: 'synthetic',
        buildId: 'synthetic-matching',
      ),
    );
  }

  setUp(() async {
    h = await ConfiguredQuizHarness.open();
    ids = 0;
    configure();
  });
  tearDown(() => h.close());

  Future<MatchingState> start({bool Function()? current}) async {
    final plan = await matching.prepare(
      expectedOwnerId: configuredOwnerId,
      categoryId: configuredCategoryId,
      stillCurrent: current ?? () => true,
    );
    return matching.start(plan!, stillCurrent: current ?? () => true);
  }

  Future<MatchingState> pair(MatchingState state, int word, int meaning) async {
    final selected = await matching.saveSelection(
      state,
      wordIndex: word,
      meaningIndex: meaning,
      stillCurrent: () => true,
    );
    final pending = await matching.save(
      selected,
      matching.preparePair(
        selected,
        responseTime: const Duration(milliseconds: 350),
      ),
      stillCurrent: () => true,
    );
    return matching.commit(pending, stillCurrent: () => true);
  }

  test(
    'prepare and resume are pure reads; copied preparation and state are denied',
    () async {
      final before = await h.snapshot();
      final plan = (await matching.prepare(
        expectedOwnerId: configuredOwnerId,
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!;
      expect(await h.snapshot(), before);
      final copied = MatchingPlan.parse(
        id: plan.id,
        json: plan.stableSerialization,
      );
      await expectLater(
        matching.start(copied, stillCurrent: () => true),
        throwsStateError,
      );
      final state = await matching.start(plan, stillCurrent: () => true);
      final savedRows = await h.snapshot();
      final resumed = await matching.resume(
        sessionId: plan.session.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(await h.snapshot(), savedRows);
      expect(resumed.plan.id, state.plan.id);
      await expectLater(
        matching.saveSelection(
          _CopiedState(state),
          wordIndex: 0,
          meaningIndex: 0,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.snapshot(), savedRows);
    },
  );

  test(
    'wrong and correct pairs acknowledge once and finish from canonical counts',
    () async {
      var state = await start();
      final original = state;
      state = await pair(state, 0, 1);
      expect(state.checkpoint.answer!.isCorrect, isFalse);
      expect(state.checkpoint.matched, isEmpty);
      expect(await h.count('answer_attempts'), 1);
      state = await matching.next(state, stillCurrent: () => true);
      for (var index = 0; index < state.plan.words.length; index++) {
        state = await pair(state, index, index);
        if (index < state.plan.words.length - 1) {
          state = await matching.next(state, stillCurrent: () => true);
        }
      }
      expect(state.checkpoint.matched, [0, 1, 2, 3]);
      final closing = await matching.save(
        state,
        matching.prepareFinish(state),
        stillCurrent: () => true,
      );
      final completed = await matching.finish(
        closing,
        stillCurrent: () => true,
      );
      final beforeReplay = await h.snapshot();
      final replay = await matching.finish(closing, stillCurrent: () => true);
      expect(
        (
          completed.completedSummary!.correctCount,
          completed.completedSummary!.wrongCount,
          completed.completedSummary!.score,
        ),
        (4, 1, 80),
      );
      expect(replay.completedSummary!.id, original.plan.session.id);
      expect(await h.snapshot(), beforeReplay);
      expect(await h.count('srs_states'), 0);
      expect(await h.count('points_ledger_entries'), 0);
      expect(await h.count('achievement_unlocks'), 0);
      expect(await h.count('learning_day_log'), 0);
      expect((await h.researchCounts()).values, everyElement(0));
      final attempts = await h.database.select(h.database.answerAttempts).get();
      expect(
        attempts.map((attempt) => attempt.evidenceClass),
        everyElement('recognition'),
      );
      expect(
        attempts.map((attempt) => attempt.promptMode),
        everyElement(MatchingPlan.promptMode),
      );
    },
  );

  test(
    'pending write and answer lost acknowledgements replay their original identity',
    () async {
      final initial = await start();
      final selected = await matching.saveSelection(
        initial,
        wordIndex: 1,
        meaningIndex: 1,
        stillCurrent: () => true,
      );
      final immutable = matching.preparePair(
        selected,
        responseTime: const Duration(milliseconds: 500),
      );
      final pending = await matching.save(
        selected,
        immutable,
        stillCurrent: () => true,
      );
      final beforeSaveReplay = await h.snapshot();
      final replayedPending = await matching.save(
        selected,
        immutable,
        stillCurrent: () => true,
      );
      expect(replayedPending.revision, pending.revision);
      expect(await h.snapshot(), beforeSaveReplay);
      final answered = await matching.commit(pending, stillCurrent: () => true);
      final beforeAnswerReplay = await h.snapshot();
      h.now = h.now.add(const Duration(hours: 3));
      final replay = await matching.commit(pending, stillCurrent: () => true);
      expect(replay.revision, answered.revision);
      expect(await h.snapshot(), beforeAnswerReplay);
      expect(await h.count('answer_attempts'), 1);
      final attempt = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      expect(attempt.id, immutable.answer!.id);
      expect(attempt.occurredAtUtcMs, immutable.answer!.occurredAtUtcMs);
      await expectLater(
        matching.saveSelection(
          initial,
          wordIndex: 2,
          meaningIndex: 2,
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.snapshot(), beforeAnswerReplay);
    },
  );

  test('real owner ABA permanently retires an issued board', () async {
    final state = await start();
    final upgrades = DriftOwnerUpgradeRepository(
      h.database,
      nowUtc: () => h.now,
      generateOwnerId: () => 'synthetic-matching-new-guest',
      generateConflictId: () => 'synthetic-matching-conflict',
    );
    final guest = await upgrades.createLocalGuestAfterLogout();
    await upgrades.rollbackLocalGuestLogout(
      previousOwnerId: configuredOwnerId,
      guestOwnerId: guest.targetOwnerId,
    );
    await Future<void>.delayed(Duration.zero);
    final before = await h.snapshot();
    await expectLater(
      matching.saveSelection(
        state,
        wordIndex: 0,
        meaningIndex: 0,
        stillCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(await h.snapshot(), before);
  });

  test(
    'deletion fence and changed vocabulary reject pending pair without effects',
    () async {
      final state = await start();
      final selected = await matching.saveSelection(
        state,
        wordIndex: 0,
        meaningIndex: 0,
        stillCurrent: () => true,
      );
      final pending = await matching.save(
        selected,
        matching.preparePair(selected, responseTime: Duration.zero),
        stillCurrent: () => true,
      );
      await h.database.customUpdate(
        'UPDATE vocabulary_words SET meaning = ?, local_revision = local_revision + 1 WHERE id = ?',
        variables: [
          const Variable<String>('changed synthetic meaning'),
          Variable<String>(state.plan.words.first.id),
        ],
        updates: {h.database.vocabularyWords},
      );
      final before = await h.snapshot();
      await expectLater(
        matching.commit(pending, stillCurrent: () => true),
        throwsStateError,
      );
      expect(await h.snapshot(), before);
      await h.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-matching-deletion',
      );
      final fenced = await h.snapshot();
      await expectLater(
        matching.resume(
          sessionId: state.plan.session.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      expect(await h.snapshot(), fenced);
    },
  );

  test(
    'generic start, answer, and finish cannot bypass matching authority',
    () async {
      final state = await start();
      final before = await h.snapshot();
      await expectLater(
        canonical.startSession(state.plan.session),
        throwsStateError,
      );
      final intent = MatchingPairIntent(
        id: 'attempt:matching:${state.plan.session.id}:1',
        ordinal: 1,
        wordIndex: 0,
        meaningIndex: 0,
        occurredAtUtcMs: h.now.millisecondsSinceEpoch,
        responseTimeMs: 10,
      );
      await expectLater(
        canonical.recordAnswer(state.plan.command(intent)),
        throwsStateError,
      );
      await expectLater(
        canonical.finishSession(
          ownerId: configuredOwnerId,
          sessionId: state.plan.session.id,
          endedAtUtc: h.now,
        ),
        throwsStateError,
      );
      expect(await h.snapshot(), before);
    },
  );

  test('corrupt stored result cannot become a claimed matching score', () async {
    final state = await pair(await start(), 0, 0);
    await h.database.customUpdate(
      'UPDATE learning_sessions SET correct_count = 999, score = 100 WHERE id = ?',
      variables: [Variable<String>(state.plan.session.id)],
      updates: {h.database.learningSessions},
    );
    final before = await h.snapshot();
    await expectLater(
      matching.resume(
        sessionId: state.plan.session.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(await h.snapshot(), before);
  });

  test(
    'file restart preserves selection, original pending pair, answer and completion',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-synthetic-matching-',
      );
      addTearDown(() async {
        await h.close();
        await directory.delete(recursive: true);
      });
      await h.close();
      h = await ConfiguredQuizHarness.open(
        file: File('${directory.path}/matching.sqlite'),
      );
      configure();
      var state = await start();
      final id = state.plan.session.id;
      state = await matching.saveSelection(
        state,
        wordIndex: 0,
        meaningIndex: 0,
        stillCurrent: () => true,
      );
      h = await h.reopen();
      configure();
      var before = await h.snapshot();
      state = await matching.resume(
        sessionId: id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(
        (state.checkpoint.selectedWord, state.checkpoint.selectedMeaning),
        (0, 0),
      );
      expect(await h.snapshot(), before);
      state = await matching.save(
        state,
        matching.preparePair(
          state,
          responseTime: const Duration(milliseconds: 200),
        ),
        stillCurrent: () => true,
      );
      final originalIntent = state.checkpoint.answer!.toJson();
      h = await h.reopen();
      configure();
      state = await matching.resume(
        sessionId: id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(state.checkpoint.answer!.toJson(), originalIntent);
      state = await matching.commit(state, stillCurrent: () => true);
      h = await h.reopen();
      configure();
      state = await matching.resume(
        sessionId: id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(state.checkpoint.phase, MatchingPhase.answered);
      expect(state.checkpoint.matched, [0]);
      for (var index = 1; index < 4; index++) {
        state = await matching.next(state, stillCurrent: () => true);
        state = await pair(state, index, index);
      }
      state = await matching.save(
        state,
        matching.prepareFinish(state),
        stillCurrent: () => true,
      );
      h = await h.reopen();
      configure();
      state = await matching.resume(
        sessionId: id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(state.checkpoint.phase, MatchingPhase.closing);
      state = await matching.finish(state, stillCurrent: () => true);
      h = await h.reopen();
      configure();
      before = await h.snapshot();
      state = await matching.resume(
        sessionId: id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      expect(state.completedSummary!.score, 100);
      expect(await h.snapshot(), before);
    },
  );
}

final class _CopiedState implements MatchingState {
  _CopiedState(this.source);
  final MatchingState source;
  @override
  MatchingPlan get plan => source.plan;
  @override
  MatchingCheckpoint get checkpoint => source.checkpoint;
  @override
  int get revision => source.revision;
  @override
  LearningSessionSummary? get completedSummary => source.completedSummary;
}
