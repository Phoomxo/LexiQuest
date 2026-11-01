import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test(
    'completed native summary is read from canonical file facts without changing any table',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-native-completed-read-',
      );
      var storage = await ConfiguredQuizHarness.open(
        file: File('${directory.path}/native.sqlite'),
      );
      addTearDown(() async {
        await storage.close();
        final resolved = await directory.resolveSymbolicLinks();
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$temp${Platform.pathSeparator}lexiquest-native-completed-read-',
          ),
        );
        await directory.delete(recursive: true);
      });
      var nextId = 0;
      LearningUseCases create() => LearningUseCases(
        owners: storage.owners,
        repository: DriftLearningRepository(
          storage.database,
          ownerWrites: storage.ownerWrites,
        ),
        generateId: () => 'synthetic-completed-summary-${++nextId}',
        nowUtc: () => storage.now,
        buildInfo: const AppBuildInfo(
          version: '1.0.0+1',
          buildId: 'synthetic-completed-summary',
        ),
      );
      var learning = create();
      final prepared = (await learning.prepareWordScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!;
      final exercise = await learning.startNativeExercise(
        prepared,
        stillCurrent: () => true,
      );
      var state = await learning.readNativeExerciseState(
        exercise,
        stillCurrent: () => true,
      );
      expect(state.completedSummary, isNull);
      state = await learning.stageNativeAnswer(
        state: state,
        input: WordScrambleAnswerInput(
          exercise: exercise,
          response: exercise.word.spelling,
          responseTime: const Duration(milliseconds: 321),
        ),
        stillCurrent: () => true,
      );
      expect(state.phase, NativeCheckpointPhase.pendingAnswer);
      expect(state.completedSummary, isNull);
      await learning.commitNativeAnswer(
        exercise,
        state.checkpoint.answer!,
        stillCurrent: () => true,
      );
      state = await learning.readNativeExerciseState(
        exercise,
        stillCurrent: () => true,
      );
      expect(state.phase, NativeCheckpointPhase.answered);
      expect(state.completedSummary, isNull);
      storage.now = storage.now.add(const Duration(seconds: 2));
      state = await learning.stageNativeFinish(
        state: state,
        stillCurrent: () => true,
      );
      expect(state.completedSummary, isNull);
      final endedAt = state.checkpoint.endedAtUtc!;
      final expected = await learning.finishNativeExercise(
        NativeFinishIntent(
          exercise: exercise,
          answer: state.checkpoint.answer!,
          endedAtUtc: endedAt,
        ),
        stillCurrent: () => true,
      );
      final originalRow = await storage.session(exercise.id);

      storage = await storage.reopen();
      storage.now = storage.now.add(const Duration(hours: 17));
      learning = create();
      expect(storage.database.allTables, hasLength(45));
      final before = await storage.snapshot();
      state = await learning.resumeNativeExercise(
        sessionId: exercise.id,
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      final actual = state.completedSummary;
      expect(actual, isNotNull);
      expect(
        (
          actual!.id,
          actual.state,
          actual.correctCount,
          actual.wrongCount,
          actual.score,
        ),
        (expected.id, 'completed', 1, 0, 100),
      );
      expect(state.exercise.ownerId, configuredOwnerId);
      expect(state.exercise.startedAtUtc, configuredStart);
      expect(state.checkpoint.endedAtUtc, endedAt);
      expect(
        (await storage.session(exercise.id))['ended_at_utc_ms'],
        endedAt.millisecondsSinceEpoch,
      );
      expect(await storage.session(exercise.id), originalRow);
      expect(await storage.snapshot(), before);
      final again = await learning.readNativeExerciseState(
        state.exercise,
        stillCurrent: () => true,
      );
      expect(
        (again.completedSummary!.id, again.completedSummary!.score),
        (actual.id, actual.score),
      );
      expect(await storage.snapshot(), before);
    },
  );
}
