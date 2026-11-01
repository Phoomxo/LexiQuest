import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/presentation/native_exercise_checkpoint_binding.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test(
    'failed ordinary preparation keeps the original submission time and input without minting an ID',
    () async {
      final f = await _Fixture.open();
      try {
        final binding = NativeExerciseCheckpointBinding(
          learning: f.learning,
          display: f.state.exercise,
          resumeState: f.state,
          stillCurrent: () => true,
        );
        await binding.initialize();
        final submittedAt = f.h.now;
        final original = NativeExerciseDraft(
          text: 'synthetic original response',
          responseTimeMs: 321,
        );
        final before = await f.h.snapshot();
        final idsBefore = f.ids;
        f.beforeHook = () async {
          if (f.hookCalls == 1) {
            f.h.now = f.h.now.add(const Duration(seconds: 4));
            throw StateError(
              'Synthetic preparation failure before answer identity',
            );
          }
        };
        await expectLater(binding.saveAnswer(original), throwsStateError);
        expect(
          f.ids,
          idsBefore,
          reason: 'Rejected preparation must not mint an answer ID',
        );
        expect(await f.h.snapshot(), before);
        await binding.saveAnswer(
          NativeExerciseDraft(
            text: 'synthetic later response',
            responseTimeMs: 999,
          ),
        );
        final command = binding.state!.checkpoint.answer!;
        expect(f.hookCalls, 2, reason: 'An unsuccessful hook must be retried');
        expect(command.occurredAtUtc, submittedAt);
        expect(command.nativeDraft!.text, original.text);
        expect(command.responseTimeMs, 321);
        expect(f.ids, idsBefore + 1);
        expect(await f.h.count('answer_attempts'), 1);
      } finally {
        await f.h.close();
      }
    },
  );

  test(
    'stage captures occurrence before its actual stored-state read and durable receipt wins on retry',
    () async {
      final f = await _Fixture.open();
      final read = _HeldSessionRead();
      try {
        final input = WordScrambleAnswerInput(
          exercise: f.state.exercise as WordScrambleSession,
          response: 'synthetic original response',
          responseTime: const Duration(milliseconds: 432),
        );
        final submittedAt = f.h.now;
        final staging = f.h.database.runWithInterceptor(
          () => f.learning.stageNativeAnswer(
            state: f.state,
            input: input,
            stillCurrent: () => true,
          ),
          interceptor: read,
        );
        await read.entered.future.timeout(const Duration(seconds: 2));
        final idsBefore = f.ids;
        f.h.now = f.h.now.add(const Duration(seconds: 4));
        expect(
          f.ids,
          idsBefore,
          reason: 'The authoritative stored lookup precedes ID minting',
        );
        read.release.complete();
        final pending = await staging;
        final command = pending.checkpoint.answer!;
        expect(command.occurredAtUtc, submittedAt);
        expect(command.responseTimeMs, 432);
        final persisted = await f.h.snapshot();
        f.h.now = f.h.now.add(const Duration(seconds: 30));
        final replay = await f.learning.stageNativeAnswer(
          state: f.state,
          input: input,
          stillCurrent: () => true,
        );
        expect(
          replay.checkpoint.stableSerialization,
          pending.checkpoint.stableSerialization,
        );
        expect(f.ids, idsBefore + 1);
        expect(await f.h.snapshot(), persisted);
      } finally {
        if (!read.release.isCompleted) read.release.complete();
        await f.h.close();
      }
    },
  );
}

final class _Fixture {
  _Fixture(this.h);
  final ConfiguredQuizHarness h;
  late final LearningUseCases learning;
  late final NativeExerciseState state;
  int ids = 0, hookCalls = 0;
  Future<void> Function()? beforeHook;
  static Future<_Fixture> open() async {
    final f = _Fixture(await ConfiguredQuizHarness.open());
    f.learning = LearningUseCases(
      owners: f.h.owners,
      repository: DriftLearningRepository(
        f.h.database,
        ownerWrites: f.h.ownerWrites,
      ),
      generateId: () => 'synthetic-capture-${++f.ids}',
      nowUtc: () => f.h.now,
      buildInfo: const AppBuildInfo(
        version: '1.0.0+1',
        buildId: 'synthetic-native-capture',
      ),
      beforeOrdinaryAnswer:
          ({
            required expectedOwnerId,
            required sessionId,
            required stillCurrent,
          }) async {
            f.hookCalls++;
            await f.beforeHook?.call();
          },
    );
    final prepared = (await f.learning.prepareWordScramble(
      categoryId: configuredCategoryId,
      stillCurrent: () => true,
    ))!;
    await f.learning.startNativeExercise(prepared, stillCurrent: () => true);
    f.state = await f.learning.readNativeExerciseState(
      prepared,
      stillCurrent: () => true,
    );
    return f;
  }
}

final class _HeldSessionRead extends QueryInterceptor {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (!entered.isCompleted && statement.contains('learning_sessions')) {
      entered.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}
