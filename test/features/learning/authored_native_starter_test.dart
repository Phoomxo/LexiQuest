import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'dart:convert';
import 'dart:async';
import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart'
    show LocalOwnersCompanion;
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/native_sentence_source.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/data/bundled_starter_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';

void main() {
  test(
    'installed starter supplies all native sentence modes without a provider',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final reader = DriftLearningPackRepository(
        database: h.database,
        ownerWrites: h.ownerWrites,
      );
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: reader,
        nowUtc: () => h.now,
        generateId: () => 'starter-pack-${++sequence}',
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final installed = await packs.importPack(
        packs.prepareImport(scope: owner, pack: bundledStarterPack),
      );
      final learning = LearningUseCases(
        owners: h.owners,
        repository: DriftLearningRepository(
          h.database,
          ownerWrites: h.ownerWrites,
          lexicalContent: reader,
        ),
        generateId: () => 'starter-native-${++sequence}',
        nowUtc: () => h.now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      for (final variant in ClozeVariant.values) {
        expect(
          await learning.prepareCloze(
            categoryId: installed.categoryId,
            variant: variant,
            stillCurrent: () => true,
          ),
          isNotNull,
        );
      }
      expect(
        await learning.prepareSentenceScramble(
          categoryId: installed.categoryId,
          stillCurrent: () => true,
        ),
        isNotNull,
      );
      expect(await h.count('learning_sessions'), 0);
      expect((await h.researchCounts()).values, everyElement(0));
    },
  );

  for (final mode in ['typed', 'choice', 'scramble']) {
    test(
      '$mode authored pending answer survives reopen and commits idempotently',
      () async {
        final dir = await Directory.systemTemp.createTemp('authored-native-');
        var h = await ConfiguredQuizHarness.open(
          file: File('${dir.path}/native.sqlite'),
        );
        var sequence = 0;
        late LearningPackUseCases packs;
        late LearningUseCases learning;
        void wire() {
          final reader = DriftLearningPackRepository(
            database: h.database,
            ownerWrites: h.ownerWrites,
          );
          packs = LearningPackUseCases(
            repository: reader,
            nowUtc: () => h.now,
            generateId: () => 'starter-pack-${++sequence}',
          );
          learning = LearningUseCases(
            owners: h.owners,
            repository: DriftLearningRepository(
              h.database,
              ownerWrites: h.ownerWrites,
              lexicalContent: reader,
            ),
            generateId: () => 'starter-native-${++sequence}',
            nowUtc: () => h.now,
            buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
          );
        }

        wire();
        addTearDown(() async {
          await packs.dispose();
          await h.close();
          await dir.delete(recursive: true);
        });
        final owner = (await packs.captureOwner(stillCurrent: () => true))!;
        final pack = await packs.importPack(
          packs.prepareImport(scope: owner, pack: bundledStarterPack),
        );
        final exercise = mode == 'scramble'
            ? (await learning.prepareSentenceScramble(
                categoryId: pack.categoryId,
                stillCurrent: () => true,
              ))!
            : (await learning.prepareCloze(
                categoryId: pack.categoryId,
                variant: mode == 'typed'
                    ? ClozeVariant.typed
                    : ClozeVariant.choice,
                stillCurrent: () => true,
              ))!;
        expect(switch (exercise) {
          ClozeSession(:final content) => content.source,
          SentenceScrambleSession(:final content) => content.source,
          _ => null,
        }, isA<AuthoredSentenceSource>());
        await learning.startNativeExercise(exercise, stillCurrent: () => true);
        var state = await learning.readNativeExerciseState(
          exercise,
          stillCurrent: () => true,
        );
        expect(jsonDecode(state.plan.stableSerialization)['schemaVersion'], 2);
        state = await learning.stageNativeAnswer(
          state: state,
          input: switch (exercise) {
            TypedClozeSession() => TypedClozeAnswerInput(
              exercise: exercise,
              response: exercise.word.spelling,
              responseTime: const Duration(seconds: 1),
            ),
            ChoiceClozeSession() => ChoiceClozeAnswerInput(
              exercise: exercise,
              optionId: exercise.word.id,
              responseTime: const Duration(seconds: 1),
            ),
            SentenceScrambleSession() => SentenceScrambleAnswerInput(
              exercise: exercise,
              response: exercise.content.sentence,
              responseTime: const Duration(seconds: 1),
            ),
            _ => throw StateError('Unexpected mode'),
          },
          stillCurrent: () => true,
        );
        final pending = state.checkpoint.stableSerialization;
        await packs.dispose();
        h = await h.reopen();
        wire();
        state = await learning.resumeNativeExercise(
          sessionId: exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(state.checkpoint.stableSerialization, pending);
        expect(
          (await learning.commitNativeAnswer(
            state.exercise,
            state.checkpoint.answer!,
            stillCurrent: () => true,
          )).inserted,
          isTrue,
        );
        state = await learning.resumeNativeExercise(
          sessionId: exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(
          (await learning.commitNativeAnswer(
            state.exercise,
            state.checkpoint.answer!,
            stillCurrent: () => true,
          )).inserted,
          isFalse,
        );
        expect(await h.count('answer_attempts'), 1);
        expect((await h.researchCounts()).values, everyElement(0));
        h.now = h.now.add(const Duration(seconds: 2));
        state = await learning.stageNativeFinish(
          state: state,
          stillCurrent: () => true,
        );
        final endedAt = state.checkpoint.endedAtUtc!;
        await packs.dispose();
        h = await h.reopen();
        wire();
        state = await learning.resumeNativeExercise(
          sessionId: exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        final intent = NativeFinishIntent(
          exercise: state.exercise,
          answer: state.checkpoint.answer!,
          endedAtUtc: endedAt,
        );
        expect(
          (await learning.finishNativeExercise(
            intent,
            stillCurrent: () => true,
          )).state,
          'completed',
        );
        final snapshot = await h.snapshot();
        await learning.finishNativeExercise(intent, stillCurrent: () => true);
        expect(await h.snapshot(), snapshot);
      },
    );
  }

  test(
    'stale target and owner ABA reject prepared authored starts without writes',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final reader = DriftLearningPackRepository(
        database: h.database,
        ownerWrites: h.ownerWrites,
      );
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: reader,
        nowUtc: () => h.now,
        generateId: () => 'starter-pack-${++sequence}',
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final pack = await packs.importPack(
        packs.prepareImport(scope: owner, pack: bundledStarterPack),
      );
      final learning = LearningUseCases(
        owners: h.owners,
        repository: DriftLearningRepository(
          h.database,
          ownerWrites: h.ownerWrites,
          lexicalContent: reader,
        ),
        generateId: () => 'starter-native-${++sequence}',
        nowUtc: () => h.now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      Future<ClozeSession> prepare() async => (await learning.prepareCloze(
        categoryId: pack.categoryId,
        variant: ClozeVariant.typed,
        stillCurrent: () => true,
      ))!;
      final stale = await prepare();
      await h.database.customStatement(
        'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
        [stale.word.id],
      );
      await expectLater(
        learning.startNativeExercise(stale, stillCurrent: () => true),
        throwsA(anything),
      );
      final aba = (await learning.prepareSentenceScramble(
        categoryId: pack.categoryId,
        stillCurrent: () => true,
      ))!;
      await (h.database.update(h.database.localOwners)
            ..where((row) => row.id.equals(configuredOwnerId)))
          .write(const LocalOwnersCompanion(isActive: drift.Value(false)));
      await (h.database.update(h.database.localOwners)
            ..where((row) => row.id.equals(configuredOtherOwnerId)))
          .write(const LocalOwnersCompanion(isActive: drift.Value(true)));
      await Future<void>.delayed(Duration.zero);
      await (h.database.update(h.database.localOwners)
            ..where((row) => row.id.equals(configuredOtherOwnerId)))
          .write(const LocalOwnersCompanion(isActive: drift.Value(false)));
      await (h.database.update(h.database.localOwners)
            ..where((row) => row.id.equals(configuredOwnerId)))
          .write(const LocalOwnersCompanion(isActive: drift.Value(true)));
      await Future<void>.delayed(Duration.zero);
      await expectLater(
        learning.startNativeExercise(aba, stillCurrent: () => true),
        throwsA(anything),
      );
      expect(await h.count('learning_sessions'), 0);
      expect(await h.count('answer_attempts'), 0);
      expect((await h.researchCounts()).values, everyElement(0));
      final current = await prepare() as TypedClozeSession;
      await learning.startNativeExercise(current, stillCurrent: () => true);
      var state = await learning.readNativeExerciseState(
        current,
        stillCurrent: () => true,
      );
      state = await learning.stageNativeAnswer(
        state: state,
        input: TypedClozeAnswerInput(
          exercise: current,
          response: current.word.spelling,
          responseTime: const Duration(seconds: 1),
        ),
        stillCurrent: () => true,
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1, local_revision = local_revision + 1 WHERE id = ?',
        [current.word.id],
      );
      await expectLater(
        learning.commitNativeAnswer(
          current,
          state.checkpoint.answer!,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: current.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      expect(await h.count('answer_attempts'), 0);
      final choice =
          (await learning.prepareCloze(
                categoryId: pack.categoryId,
                variant: ClozeVariant.choice,
                stillCurrent: () => true,
              ))!
              as ChoiceClozeSession;
      await learning.startNativeExercise(choice, stillCurrent: () => true);
      var choiceState = await learning.readNativeExerciseState(
        choice,
        stillCurrent: () => true,
      );
      choiceState = await learning.stageNativeAnswer(
        state: choiceState,
        input: ChoiceClozeAnswerInput(
          exercise: choice,
          optionId: choice.word.id,
          responseTime: const Duration(seconds: 1),
        ),
        stillCurrent: () => true,
      );
      final peer = choice.choices.firstWhere(
        (word) => word.id != choice.word.id,
      );
      await h.database.customStatement(
        'UPDATE vocabulary_words SET is_deleted = 1, local_revision = local_revision + 1 WHERE id = ?',
        [peer.id],
      );
      final before = await h.snapshot();
      await expectLater(
        learning.commitNativeAnswer(
          choice,
          choiceState.checkpoint.answer!,
          stillCurrent: () => true,
        ),
        throwsA(anything),
      );
      expect(await h.snapshot(), before);
    },
  );

  test(
    'owner ABA during the ambient probe rejects prepare and resume',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final reader = DriftLearningPackRepository(
        database: h.database,
        ownerWrites: h.ownerWrites,
      );
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: reader,
        nowUtc: () => h.now,
        generateId: () => 'starter-pack-${++sequence}',
      );
      final repo = DriftLearningRepository(
        h.database,
        ownerWrites: h.ownerWrites,
        lexicalContent: reader,
      );
      final learning = LearningUseCases(
        owners: h.owners,
        repository: repo,
        generateId: () => 'starter-native-${++sequence}',
        nowUtc: () => h.now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final pack = await packs.importPack(
        packs.prepareImport(scope: owner, pack: bundledStarterPack),
      );
      final original = (await learning.prepareCloze(
        categoryId: pack.categoryId,
        variant: ClozeVariant.typed,
        stillCurrent: () => true,
      ))!;
      await learning.startNativeExercise(original, stillCurrent: () => true);
      Future<void> aba() async {
        await (h.database.update(h.database.localOwners)
              ..where((row) => row.id.equals(configuredOwnerId)))
            .write(const LocalOwnersCompanion(isActive: drift.Value(false)));
        await (h.database.update(h.database.localOwners)
              ..where((row) => row.id.equals(configuredOtherOwnerId)))
            .write(const LocalOwnersCompanion(isActive: drift.Value(true)));
        await Future<void>.delayed(Duration.zero);
        await (h.database.update(h.database.localOwners)
              ..where((row) => row.id.equals(configuredOtherOwnerId)))
            .write(const LocalOwnersCompanion(isActive: drift.Value(false)));
        await (h.database.update(h.database.localOwners)
              ..where((row) => row.id.equals(configuredOwnerId)))
            .write(const LocalOwnersCompanion(isActive: drift.Value(true)));
        await Future<void>.delayed(Duration.zero);
      }

      for (final resume in [false, true]) {
        final probe = _DelayProbe();
        final future = h.database.runWithInterceptor(
          () => resume
              ? repo.resumeNativeExercise(
                  sessionId: original.id,
                  expectedOwnerId: configuredOwnerId,
                  stillCurrent: () => true,
                )
              : repo.prepareAuthoredCloze(
                  session: original.session,
                  categoryId: pack.categoryId,
                  variant: ClozeVariant.typed,
                  stillCurrent: () => true,
                ),
          interceptor: probe,
        );
        try {
          await probe.entered.future.timeout(const Duration(seconds: 10));
          await aba();
        } finally {
          probe.release.complete();
        }
        await expectLater(future, throwsA(isA<StateError>()));
      }
      expect(await h.count('learning_sessions'), 1);
      expect(await h.count('answer_attempts'), 0);
    },
  );

  test('corrupt retained snapshot aborts preparation without writes', () async {
    final h = await ConfiguredQuizHarness.open();
    final reader = DriftLearningPackRepository(
      database: h.database,
      ownerWrites: h.ownerWrites,
    );
    var sequence = 0;
    final packs = LearningPackUseCases(
      repository: reader,
      nowUtc: () => h.now,
      generateId: () => 'starter-pack-${++sequence}',
    );
    addTearDown(() async {
      await packs.dispose();
      await h.close();
    });
    final owner = (await packs.captureOwner(stillCurrent: () => true))!;
    final pack = await packs.importPack(
      packs.prepareImport(scope: owner, pack: bundledStarterPack),
    );
    final learning = LearningUseCases(
      owners: h.owners,
      repository: DriftLearningRepository(
        h.database,
        ownerWrites: h.ownerWrites,
        lexicalContent: reader,
      ),
      generateId: () => 'starter-native-${++sequence}',
      nowUtc: () => h.now,
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    );
    await h.database.customStatement(
      "UPDATE lexical_content_snapshots SET lexical_sha256 = ? WHERE pack_version_id = ?",
      ['0' * 64, pack.id],
    );
    final before = await h.snapshot();
    await expectLater(
      learning.prepareCloze(
        categoryId: pack.categoryId,
        variant: ClozeVariant.typed,
        stillCurrent: () => true,
      ),
      throwsA(
        isA<PackStorageException>().having(
          (e) => e.code,
          'code',
          PackStorageFailureCode.corrupt,
        ),
      ),
    );
    expect(await h.snapshot(), before);
  });

  test(
    'categoryless scan crosses a page of words without examples and keeps distinct choices',
    () async {
      final h = await ConfiguredQuizHarness.open();
      final reader = DriftLearningPackRepository(
        database: h.database,
        ownerWrites: h.ownerWrites,
      );
      var sequence = 0;
      final packs = LearningPackUseCases(
        repository: reader,
        nowUtc: () => h.now,
        generateId: () => 'starter-pack-${++sequence}',
      );
      addTearDown(() async {
        await packs.dispose();
        await h.close();
      });
      final owner = (await packs.captureOwner(stillCurrent: () => true))!;
      final pack = await packs.importPack(
        packs.prepareImport(scope: owner, pack: bundledStarterPack),
      );
      for (var i = 0; i < 105; i++) {
        final spelling =
            'term${String.fromCharCode(97 + i ~/ 26)}${String.fromCharCode(97 + i % 26)}';
        await h.addWord(
          id: 'a-page-${i.toString().padLeft(3, '0')}',
          categoryId: pack.categoryId!,
          spelling: spelling,
          meaning: 'synthetic $i',
        );
      }
      await h.addWord(
        id: 'a-duplicate',
        categoryId: pack.categoryId!,
        spelling: 'termaa',
        meaning: 'another synthetic meaning',
      );
      final learning = LearningUseCases(
        owners: h.owners,
        repository: DriftLearningRepository(
          h.database,
          ownerWrites: h.ownerWrites,
          lexicalContent: reader,
        ),
        generateId: () => 'starter-native-${++sequence}',
        nowUtc: () => h.now,
        buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
      );
      final typed = (await learning.prepareCloze(
        variant: ClozeVariant.typed,
        stillCurrent: () => true,
      ))!;
      final choice =
          (await learning.prepareCloze(
                variant: ClozeVariant.choice,
                stillCurrent: () => true,
              ))!
              as ChoiceClozeSession;
      expect(typed.content.source, isA<AuthoredSentenceSource>());
      expect(choice.word.id, typed.word.id);
      expect(
        choice.choices.map((e) => e.spelling.toLowerCase()).toSet(),
        hasLength(3),
      );
      expect(await h.count('learning_sessions'), 0);
    },
  );
}

final class _DelayProbe extends drift.QueryInterceptor {
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.contains('owner_transaction_probe') && !entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return executor.runSelect(statement, args);
  }
}
