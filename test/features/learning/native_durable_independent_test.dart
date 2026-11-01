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

  LearningUseCases create() => LearningUseCases(
    owners: storage.owners,
    repository: DriftLearningRepository(
      storage.database,
      ownerWrites: storage.ownerWrites,
    ),
    generateId: () => 'synthetic-independent-native-${++nextId}',
    nowUtc: () => storage.now,
    buildInfo: const AppBuildInfo(
      version: '1.0.0+1',
      buildId: 'synthetic-independent-native',
    ),
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'lexiquest-native-independent-',
    );
    storage = await ConfiguredQuizHarness.open(
      file: File('${directory.path}/native.sqlite'),
    );
    nextId = 0;
    learning = create();
  });
  tearDown(() async {
    await storage.close();
    final resolved = await directory.resolveSymbolicLinks();
    final temp = await Directory.systemTemp.resolveSymbolicLinks();
    expect(
      resolved,
      startsWith(
        '$temp${Platform.pathSeparator}lexiquest-native-independent-',
      ),
    );
    await directory.delete(recursive: true);
  });

  Future<NativeExerciseState> start() async {
    final prepared = await learning.prepareWordScramble(
      categoryId: configuredCategoryId,
      stillCurrent: () => true,
    );
    final exercise = await learning.startNativeExercise(
      prepared!,
      stillCurrent: () => true,
    );
    return learning.readNativeExerciseState(exercise, stillCurrent: () => true);
  }

  WordScrambleAnswerInput input(NativeExerciseState state) =>
      WordScrambleAnswerInput(
        exercise: state.exercise as WordScrambleSession,
        response: state.exercise.word.spelling,
        responseTime: const Duration(milliseconds: 321),
      );

  test(
    'independent native resume rejects replacement canonical attempt identity',
    () async {
      final state = await start();
      final answer = learning.prepareNativeAnswer(input(state));
      await learning.commitNativeAnswer(
        state.exercise,
        answer,
        stillCurrent: () => true,
      );
      await storage.database.customStatement(
        'UPDATE answer_attempts SET id = ? WHERE id = ?',
        ['synthetic-independent-replaced-attempt', answer.id],
      );
      storage = await storage.reopen();
      learning = create();
      final before = await storage.snapshot();
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: state.exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsA(
          isA<NativeExerciseUnavailable>().having(
            (error) => error.reason,
            'reason',
            NativeExerciseUnavailableReason.corrupt,
          ),
        ),
      );
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'independent uncertain answer stage retry retains the original command',
    () async {
      final originalState = await start();
      final originalInput = input(originalState);
      final first = await learning.stageNativeAnswer(
        state: originalState,
        input: originalInput,
        stillCurrent: () => true,
      );
      final before = await storage.snapshot();
      storage.now = storage.now.add(const Duration(seconds: 5));
      final replay = await learning.stageNativeAnswer(
        state: originalState,
        input: originalInput,
        stillCurrent: () => true,
      );
      expect(replay.checkpointRevision, first.checkpointRevision);
      expect(
        replay.checkpoint.stableSerialization,
        first.checkpoint.stableSerialization,
      );
      expect(replay.checkpoint.answer!.id, first.checkpoint.answer!.id);
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'independent uncertain abandon retry retains the original close',
    () async {
      final original = await start();
      final first = await learning.abandonNativeExercise(
        state: original,
        stillCurrent: () => true,
      );
      final before = await storage.snapshot();
      storage.now = storage.now.add(const Duration(seconds: 5));
      final replay = await learning.abandonNativeExercise(
        state: original,
        stillCurrent: () => true,
      );
      expect(replay.checkpointRevision, first.checkpointRevision);
      expect(
        replay.checkpoint.stableSerialization,
        first.checkpoint.stableSerialization,
      );
      expect(replay.checkpoint.endedAtUtc, first.checkpoint.endedAtUtc);
      expect(await storage.snapshot(), before);
      expect(await storage.count('answer_attempts'), 0);
    },
  );

  test(
    'independent uncertain close stage retry retains the original close',
    () async {
      var state = await start();
      final answer = learning.prepareNativeAnswer(input(state));
      await learning.commitNativeAnswer(
        state.exercise,
        answer,
        stillCurrent: () => true,
      );
      state = await learning.readNativeExerciseState(
        state.exercise,
        stillCurrent: () => true,
      );
      final first = await learning.stageNativeFinish(
        state: state,
        stillCurrent: () => true,
      );
      final before = await storage.snapshot();
      storage.now = storage.now.add(const Duration(seconds: 5));
      final replay = await learning.stageNativeFinish(
        state: state,
        stillCurrent: () => true,
      );
      expect(replay.checkpointRevision, first.checkpointRevision);
      expect(
        replay.checkpoint.stableSerialization,
        first.checkpoint.stableSerialization,
      );
      expect(replay.checkpoint.endedAtUtc, first.checkpoint.endedAtUtc);
      expect(await storage.snapshot(), before);
    },
  );
}
