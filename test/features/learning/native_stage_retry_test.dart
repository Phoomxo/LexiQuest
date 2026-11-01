import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  late Directory directory;
  late ConfiguredQuizHarness storage;
  late LearningUseCases learning;
  var nextId = 0;
  var current = true;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'lexiquest-native-stage-retry-',
    );
    storage = await ConfiguredQuizHarness.open(
      file: File('${directory.path}/native.sqlite'),
    );
    nextId = 0;
    current = true;
    learning = LearningUseCases(
      owners: storage.owners,
      repository: DriftLearningRepository(
        storage.database,
        ownerWrites: storage.ownerWrites,
      ),
      generateId: () => 'synthetic-stage-${++nextId}',
      nowUtc: () => storage.now,
      buildInfo: const AppBuildInfo(
        version: '1.0.0+1',
        buildId: 'synthetic-stage-retry',
      ),
    );
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  Future<NativeExerciseState> start({bool dictation = false}) async {
    final prepared = dictation
        ? await learning.prepareDictation(
            categoryId: configuredCategoryId,
            stillCurrent: () => current,
          )
        : await learning.prepareWordScramble(
            categoryId: configuredCategoryId,
            stillCurrent: () => current,
          );
    final exercise = await learning.startNativeExercise(
      prepared!,
      stillCurrent: () => current,
    );
    return learning.readNativeExerciseState(
      exercise,
      stillCurrent: () => current,
    );
  }

  test(
    'stage retries reject changed submission latency assistance and input mode',
    () async {
      final original = await start(dictation: true);
      await learning.stageNativeAnswer(
        state: original,
        input: _input(original),
        stillCurrent: () => current,
      );
      final before = await storage.snapshot();
      final exercise = original.exercise as DictationSession;
      for (final changed in [
        DictationAnswerInput(
          exercise: exercise,
          response: 'different submission',
          assisted: false,
          responseTime: const Duration(milliseconds: 321),
        ),
        DictationAnswerInput(
          exercise: exercise,
          response: exercise.word.spelling,
          assisted: false,
          responseTime: const Duration(milliseconds: 322),
        ),
        DictationAnswerInput(
          exercise: exercise,
          response: exercise.word.spelling,
          assisted: true,
          responseTime: const Duration(milliseconds: 321),
        ),
      ]) {
        await expectLater(
          learning.stageNativeAnswer(
            state: original,
            input: changed,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), before);
      }
      final word = await start();
      final wordExercise = word.exercise as WordScrambleSession;
      await learning.stageNativeAnswer(
        state: word,
        input: _input(word),
        stillCurrent: () => current,
      );
      final used = <int>{};
      final slots = <int?>[];
      for (final letter in wordExercise.word.spelling.split('')) {
        final index = wordExercise.letters
            .asMap()
            .entries
            .firstWhere(
              (entry) => entry.value == letter && !used.contains(entry.key),
            )
            .key;
        used.add(index);
        slots.add(index);
      }
      final typedBefore = await storage.snapshot();
      await expectLater(
        learning.stageNativeAnswer(
          state: word,
          input: WordScrambleAnswerInput(
            exercise: wordExercise,
            response: wordExercise.word.spelling,
            responseTime: const Duration(milliseconds: 321),
            tileSlots: slots,
          ),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), typedBefore);
    },
  );

  test(
    'stage retries reconcile canonical answer and completion ACK loss without writes',
    () async {
      final original = await start();
      final input = _input(original);
      final pending = await learning.stageNativeAnswer(
        state: original,
        input: input,
        stillCurrent: () => current,
      );
      await learning.commitNativeAnswer(
        pending.exercise,
        pending.checkpoint.answer!,
        stillCurrent: () => current,
      );
      final answered = await learning.readNativeExerciseState(
        original.exercise,
        stillCurrent: () => current,
      );
      storage.now = storage.now.add(const Duration(seconds: 5));
      final answerBefore = await storage.snapshot();
      final answerReplay = await learning.stageNativeAnswer(
        state: original,
        input: input,
        stillCurrent: () => current,
      );
      expect(answerReplay.phase, NativeCheckpointPhase.answered);
      expect(
        answerReplay.checkpoint.stableSerialization,
        answered.checkpoint.stableSerialization,
      );
      expect(answerReplay.checkpointRevision, answered.checkpointRevision);
      expect(await storage.snapshot(), answerBefore);
      final closing = await learning.stageNativeFinish(
        state: answered,
        stillCurrent: () => current,
      );
      final close = NativeFinishIntent(
        exercise: closing.exercise,
        answer: closing.checkpoint.answer!,
        endedAtUtc: closing.checkpoint.endedAtUtc!,
      );
      await learning.finishNativeExercise(close, stillCurrent: () => current);
      storage.now = storage.now.add(const Duration(seconds: 5));
      final completedBefore = await storage.snapshot();
      final finalAnswerReplay = await learning.stageNativeAnswer(
        state: original,
        input: input,
        stillCurrent: () => current,
      );
      final finalCloseReplay = await learning.stageNativeFinish(
        state: answered,
        stillCurrent: () => current,
      );
      expect(finalAnswerReplay.phase, NativeCheckpointPhase.completed);
      expect(finalCloseReplay.phase, NativeCheckpointPhase.completed);
      expect(
        finalAnswerReplay.checkpoint.stableSerialization,
        finalCloseReplay.checkpoint.stableSerialization,
      );
      expect(finalCloseReplay.checkpoint.endedAtUtc, close.endedAtUtc);
      expect(
        finalCloseReplay.checkpoint.answer!.id,
        pending.checkpoint.answer!.id,
      );
      expect(await storage.snapshot(), completedBefore);
      expect(await storage.count('answer_attempts'), 1);
    },
  );

  test(
    'stage retries cannot jump an intervening acknowledged draft revision',
    () async {
      final original = await start(dictation: true);
      final newer = await learning.saveNativeDraft(
        state: original,
        draft: NativeExerciseDraft(
          text: 'acknowledged intervening typing',
          responseTimeMs: 100,
        ),
        stillCurrent: () => current,
      );
      await learning.stageNativeAnswer(
        state: newer,
        input: _input(newer),
        stillCurrent: () => current,
      );
      final before = await storage.snapshot();
      await expectLater(
        learning.stageNativeAnswer(
          state: original,
          input: _input(original),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'stage retries deny copied states and forged old drafts before reconciliation',
    () async {
      final original = await start();
      final input = _input(original);
      final pending = await learning.stageNativeAnswer(
        state: original,
        input: input,
        stillCurrent: () => current,
      );
      final pendingBefore = await storage.snapshot();
      for (final copy in [
        _CopiedNativeState(original),
        _CopiedNativeState(
          original,
          checkpoint: AwaitingNativeAnswer(
            NativeExerciseDraft(text: 'invented previous draft'),
          ),
        ),
        _CopiedNativeState(pending, revision: original.checkpointRevision),
      ]) {
        await expectLater(
          learning.stageNativeAnswer(
            state: copy,
            input: input,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), pendingBefore);
      }
      await learning.commitNativeAnswer(
        pending.exercise,
        pending.checkpoint.answer!,
        stillCurrent: () => current,
      );
      final answered = await learning.readNativeExerciseState(
        original.exercise,
        stillCurrent: () => current,
      );
      await learning.stageNativeFinish(
        state: answered,
        stillCurrent: () => current,
      );
      final closingBefore = await storage.snapshot();
      await expectLater(
        learning.stageNativeFinish(
          state: _CopiedNativeState(answered),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), closingBefore);
      final abandonOriginal = await start();
      await learning.abandonNativeExercise(
        state: abandonOriginal,
        stillCurrent: () => current,
      );
      final abandonedBefore = await storage.snapshot();
      await expectLater(
        learning.abandonNativeExercise(
          state: _CopiedNativeState(abandonOriginal),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), abandonedBefore);
    },
  );

  for (final loss in ['caller', 'owner', 'fence']) {
    test(
      'stage retry rejects $loss loss before returning an existing ACK',
      () async {
        final original = await start();
        final input = _input(original);
        await learning.stageNativeAnswer(
          state: original,
          input: input,
          stillCurrent: () => current,
        );
        switch (loss) {
          case 'caller':
            current = false;
          case 'owner':
            await storage.switchOwner(configuredOtherOwnerId);
          case 'fence':
            await storage.ownerWrites.beginDeletion(
              ownerId: configuredOwnerId,
              firebaseUid: configuredFirebaseUid,
              idempotencyKey: 'synthetic-stage-retry-fence',
            );
        }
        final before = await storage.snapshot();
        await expectLater(
          learning.stageNativeAnswer(
            state: original,
            input: input,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), before);
      },
    );
  }

  test(
    'concurrent identical stage actions converge on one original command',
    () async {
      final original = await start();
      final input = _input(original);
      final results = await Future.wait([
        learning.stageNativeAnswer(
          state: original,
          input: input,
          stillCurrent: () => current,
        ),
        learning.stageNativeAnswer(
          state: original,
          input: input,
          stillCurrent: () => current,
        ),
      ]);
      expect(
        results.first.checkpoint.stableSerialization,
        results.last.checkpoint.stableSerialization,
      );
      expect(results.first.checkpointRevision, results.last.checkpointRevision);
      expect(await storage.count('answer_attempts'), 0);
      expect(await storage.count('outbox_operations'), 0);
    },
  );
}

NativeAnswerInput _input(NativeExerciseState state) => switch (state.exercise) {
  DictationSession exercise => DictationAnswerInput(
    exercise: exercise,
    response: exercise.word.spelling,
    assisted: false,
    responseTime: const Duration(milliseconds: 321),
  ),
  WordScrambleSession exercise => WordScrambleAnswerInput(
    exercise: exercise,
    response: exercise.word.spelling,
    responseTime: const Duration(milliseconds: 321),
  ),
  _ => throw StateError('Synthetic stage input unavailable'),
};

final class _CopiedNativeState implements NativeExerciseState {
  _CopiedNativeState(
    this.original, {
    NativeCheckpoint? checkpoint,
    int? revision,
  }) : checkpoint = checkpoint ?? original.checkpoint,
       checkpointRevision = revision ?? original.checkpointRevision;
  final NativeExerciseState original;
  @override
  AcceptedNativeExercise get exercise => original.exercise;
  @override
  AcceptedNativePlan get plan => original.plan;
  @override
  LearningSessionSummary? get completedSummary => original.completedSummary;
  @override
  final NativeCheckpoint checkpoint;
  @override
  final int checkpointRevision;
  @override
  NativeCheckpointPhase get phase => checkpoint.phase;
}
