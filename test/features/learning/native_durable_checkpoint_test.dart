import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_time_admission.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/configured_quiz_harness.dart';
import '../../support/sentence_scramble_native_harness.dart'
    show SyntheticSentenceScrambleProvider;

void main() {
  late Directory directory;
  late ConfiguredQuizHarness storage;
  late LearningUseCases learning;
  var nextId = 0;
  var current = true;

  LearningUseCases create({bool generation = false}) => LearningUseCases(
    owners: storage.owners,
    repository: DriftLearningRepository(
      storage.database,
      ownerWrites: storage.ownerWrites,
    ),
    generateId: () => 'synthetic-durable-${++nextId}',
    nowUtc: () => storage.now,
    buildInfo: const AppBuildInfo(
      version: '1.0.0+1',
      buildId: 'synthetic-durable',
    ),
    contentProvider: generation
        ? SyntheticSentenceScrambleProvider(storage.database)
        : null,
  );

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'lexiquest-native-checkpoint-',
    );
    storage = await ConfiguredQuizHarness.open(
      file: File('${directory.path}/native.sqlite'),
    );
    nextId = 0;
    current = true;
    learning = create(generation: true);
  });
  tearDown(() async {
    await storage.close();
    await directory.delete(recursive: true);
  });

  Future<NativeExerciseState> start(String mode) async {
    final prepared = switch (mode) {
      'dictation' => await learning.prepareDictation(
        categoryId: configuredCategoryId,
        stillCurrent: () => current,
      ),
      'wordScramble' => await learning.prepareWordScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => current,
      ),
      'sentenceScramble' => await learning.prepareSentenceScramble(
        categoryId: configuredCategoryId,
        stillCurrent: () => current,
      ),
      _ => await learning.prepareCloze(
        categoryId: configuredCategoryId,
        variant: mode == 'clozeTyped'
            ? ClozeVariant.typed
            : ClozeVariant.choice,
        stillCurrent: () => current,
      ),
    };
    final exercise = await learning.startNativeExercise(
      prepared!,
      stillCurrent: () => current,
    );
    return learning.readNativeExerciseState(
      exercise,
      stillCurrent: () => current,
    );
  }

  Future<NativeExerciseState> reopen(String sessionId) async {
    storage = await storage.reopen();
    storage.now = storage.now.add(const Duration(hours: 17));
    learning = create();
    final before = await storage.snapshot();
    final state = await learning.resumeNativeExercise(
      sessionId: sessionId,
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => current,
    );
    expect(
      await storage.snapshot(),
      before,
      reason: 'resume is a SELECT-only capability',
    );
    return state;
  }

  for (final mode in [
    'dictation',
    'wordScramble',
    'sentenceScramble',
    'clozeTyped',
    'clozeChoice',
  ]) {
    test(
      '$mode retains every durable phase and original answer and close after file restarts',
      () async {
        var state = await start(mode);
        final originalPlan = state.plan.stableSerialization;
        final originalStart = state.exercise.startedAtUtc;
        final draft = _draft(state.exercise);
        state = await learning.saveNativeDraft(
          state: state,
          draft: draft,
          stillCurrent: () => current,
        );
        final firstRevision = state.checkpointRevision;
        state = await reopen(state.exercise.id);
        expect(state.phase, NativeCheckpointPhase.awaitingAnswer);
        expect(state.checkpointRevision, firstRevision);
        expect(state.checkpoint.draft.toJson(), draft.toJson());
        expect(state.plan.stableSerialization, originalPlan);
        expect(state.exercise.startedAtUtc, originalStart);

        state = await learning.stageNativeAnswer(
          state: state,
          input: _input(state.exercise, assisted: draft.assisted),
          stillCurrent: () => current,
        );
        final pending = state.checkpoint.stableSerialization;
        final answerId = state.checkpoint.answer!.id;
        final answerTime = state.checkpoint.answer!.occurredAtUtc;
        state = await reopen(state.exercise.id);
        expect(state.phase, NativeCheckpointPhase.pendingAnswer);
        expect(state.checkpoint.stableSerialization, pending);
        final answer = state.checkpoint.answer!;
        expect(
          (await learning.commitNativeAnswer(
            state.exercise,
            answer,
            stillCurrent: () => current,
          )).inserted,
          isTrue,
        );
        state = await reopen(state.exercise.id);
        expect(state.phase, NativeCheckpointPhase.answered);
        final saved = await storage.snapshot();
        expect(
          (await learning.commitNativeAnswer(
            state.exercise,
            state.checkpoint.answer!,
            stillCurrent: () => current,
          )).inserted,
          isFalse,
        );
        expect(await storage.snapshot(), saved);

        storage.now = storage.now.add(const Duration(seconds: 2));
        state = await learning.stageNativeFinish(
          state: state,
          stillCurrent: () => current,
        );
        final endedAt = state.checkpoint.endedAtUtc!;
        state = await reopen(state.exercise.id);
        expect(state.phase, NativeCheckpointPhase.closing);
        final wrongClose = learning.prepareNativeFinish(
          state.exercise,
          state.checkpoint.answer!,
        );
        final beforeWrong = await storage.snapshot();
        await expectLater(
          learning.finishNativeExercise(
            wrongClose,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), beforeWrong);
        final summary = await learning.finishNativeExercise(
          NativeFinishIntent(
            exercise: state.exercise,
            answer: state.checkpoint.answer!,
            endedAtUtc: endedAt,
          ),
          stillCurrent: () => current,
        );
        expect(
          (summary.state, summary.correctCount, summary.wrongCount),
          ('completed', 1, 0),
        );
        state = await reopen(state.exercise.id);
        expect(state.phase, NativeCheckpointPhase.completed);
        expect(state.plan.stableSerialization, originalPlan);
        final complete = await storage.snapshot();
        await learning.finishNativeExercise(
          NativeFinishIntent(
            exercise: state.exercise,
            answer: state.checkpoint.answer!,
            endedAtUtc: endedAt,
          ),
          stillCurrent: () => current,
        );
        expect(await storage.snapshot(), complete);
        final attempt = await storage.database
            .select(storage.database.answerAttempts)
            .getSingle();
        expect(
          (attempt.id, attempt.occurredAtUtcMs, attempt.responseTimeMs),
          (answerId, answerTime.millisecondsSinceEpoch, 1234),
        );
        expect(await storage.count('answer_attempts'), 1);
        expect(await storage.count('learning_time_segments'), 0);
        expect(
          (await storage.researchCounts()).values.every((count) => count == 0),
          isTrue,
        );
        final snapshot = await DriftAccountSnapshotBuilder(
          storage.database,
          nowUtc: () => storage.now,
        ).build(ownerId: configuredOwnerId);
        final data =
            (jsonDecode(utf8.decode(snapshot.bytes))
                    as Map<String, dynamic>)['data']
                as Map<String, dynamic>;
        final row =
            (data['learning_sessions'] as List).single as Map<String, dynamic>;
        expect(row['accepted_plan_json'], originalPlan);
        expect(row['checkpoint_json'], state.checkpoint.stableSerialization);
      },
    );
  }

  test(
    'draft CAS reconciles a lost ACK and cannot reset sticky assistance or latency',
    () async {
      final first = await start('dictation');
      final draft = NativeExerciseDraft(
        text: 'private acknowledged draft',
        responseTimeMs: 250,
        assisted: true,
      );
      final saved = await learning.saveNativeDraft(
        state: first,
        draft: draft,
        stillCurrent: () => current,
      );
      final before = await storage.snapshot();
      final replay = await learning.saveNativeDraft(
        state: first,
        draft: draft,
        stillCurrent: () => current,
      );
      expect(replay.checkpointRevision, saved.checkpointRevision);
      expect(await storage.snapshot(), before);
      await expectLater(
        learning.saveNativeDraft(
          state: first,
          draft: NativeExerciseDraft(
            text: 'competing draft',
            responseTimeMs: 260,
            assisted: true,
          ),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      for (final reset in [
        NativeExerciseDraft(responseTimeMs: 250),
        NativeExerciseDraft(assisted: true),
      ]) {
        await expectLater(
          learning.saveNativeDraft(
            state: saved,
            draft: reset,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
      }
      await expectLater(
        learning.stageNativeAnswer(
          state: saved,
          input: _input(saved.exercise),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'an abandoned draft reopens without manufacturing an answer or completion reward',
    () async {
      var state = await start('sentenceScramble');
      state = await learning.abandonNativeExercise(
        state: state,
        stillCurrent: () => current,
      );
      final before = await storage.snapshot();
      state = await reopen(state.exercise.id);
      expect(state.phase, NativeCheckpointPhase.abandoned);
      await expectLater(
        learning.commitNativeAnswer(
          state.exercise,
          learning.prepareNativeAnswer(_input(state.exercise)),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
      expect(await storage.count('answer_attempts'), 0);
      expect(await storage.count('achievement_unlocks'), 0);
      expect(await storage.count('outbox_operations'), 0);
    },
  );

  test(
    'ordinary native clocks are normalized to milliseconds without changing the original retry time',
    () async {
      storage.now = storage.now.add(const Duration(microseconds: 731));
      final state = await start('dictation');
      expect(state.exercise.startedAtUtc.microsecondsSinceEpoch % 1000, 0);
      final answer = learning.prepareNativeAnswer(_input(state.exercise));
      expect(answer.occurredAtUtc.microsecondsSinceEpoch % 1000, 0);
      await learning.commitNativeAnswer(
        state.exercise,
        answer,
        stillCurrent: () => current,
      );
      final intent = learning.prepareNativeFinish(state.exercise, answer);
      expect(intent.endedAtUtc.microsecondsSinceEpoch % 1000, 0);
      await learning.finishNativeExercise(intent, stillCurrent: () => current);
    },
  );

  for (final mode in ['wordScramble', 'sentenceScramble']) {
    test(
      'native exact slots retain holes and bank identity for $mode after restart',
      () async {
        if (mode == 'wordScramble') {
          await storage.database.customStatement(
            "UPDATE vocabulary_words SET spelling = 'letter', normalized_spelling = 'letter', local_revision = local_revision + 1 WHERE id = ?",
            [configuredWordIds.first],
          );
        }
        final first = await start(mode);
        final exercise = first.exercise;
        final bank = switch (exercise) {
          WordScrambleSession(:final letters) => letters,
          SentenceScrambleSession(:final content, :final tokenOrder) =>
            tokenOrder.map((index) => content.tokens[index]).toList(),
          _ => throw StateError('Synthetic tile bank missing'),
        };
        final indices = mode == 'wordScramble'
            ? [
                for (var index = 0; index < bank.length; index++)
                  if (bank[index] == 't') index,
              ]
            : [0, bank.length - 1];
        final slots = List<int?>.filled(bank.length, null)
          ..[1] = indices.first
          ..[bank.length - 2] = indices.last;
        final text = slots
            .whereType<int>()
            .map((index) => bank[index])
            .join(mode == 'wordScramble' ? '' : ' ');
        await learning.saveNativeDraft(
          state: first,
          draft: NativeExerciseDraft(
            tileSlots: slots,
            text: text,
            responseTimeMs: 321,
          ),
          stillCurrent: () => current,
        );
        final resumed = await reopen(first.exercise.id);
        expect(resumed.checkpoint.draft.tileSlots, slots);
        expect(resumed.checkpoint.draft.text, text);
        expect(resumed.checkpoint.draft.tileSlots!.whereType<int>(), indices);
        final canonical = exercise is SentenceScrambleSession
            ? indices.map((index) => exercise.tokenOrder[index]).toList()
            : indices;
        expect(
          resumed.checkpoint.draft.canonicalTokenIndices(resumed.exercise),
          canonical,
        );
        final before = await storage.snapshot();
        await expectLater(
          learning.saveNativeDraft(
            state: resumed,
            draft: NativeExerciseDraft(
              tileSlots: slots.take(slots.length - 1),
              text: text,
              responseTimeMs: 322,
            ),
            stillCurrent: () => current,
          ),
          throwsFormatException,
        );
        await expectLater(
          learning.saveNativeDraft(
            state: resumed,
            draft: NativeExerciseDraft(
              tileSlots: slots,
              text: 'contradictory typed response',
              responseTimeMs: 322,
            ),
            stillCurrent: () => current,
          ),
          throwsFormatException,
        );
        final outsideBank = List<int?>.of(slots)..[0] = bank.length;
        await expectLater(
          learning.saveNativeDraft(
            state: resumed,
            draft: NativeExerciseDraft(
              tileSlots: outsideBank,
              text: text,
              responseTimeMs: 322,
            ),
            stillCurrent: () => current,
          ),
          throwsFormatException,
        );
        expect(
          () => NativeExerciseDraft(tileSlots: [indices.first, indices.first]),
          throwsFormatException,
        );
        expect(await storage.snapshot(), before);
        await learning.saveNativeDraft(
          state: resumed,
          draft: NativeExerciseDraft(
            text: 'explicit typed replacement',
            responseTimeMs: 400,
          ),
          stillCurrent: () => current,
        );
        var typed = await reopen(first.exercise.id);
        expect(typed.checkpoint.draft.tileSlots, isNull);
        expect(typed.checkpoint.draft.text, 'explicit typed replacement');
        typed = await learning.saveNativeDraft(
          state: typed,
          draft: NativeExerciseDraft(
            tileSlots: slots,
            text: text,
            responseTimeMs: 500,
          ),
          stillCurrent: () => current,
        );
        final input = switch (typed.exercise) {
          WordScrambleSession exercise => WordScrambleAnswerInput(
            exercise: exercise,
            response: text,
            tileSlots: slots,
            responseTime: const Duration(milliseconds: 1234),
          ),
          SentenceScrambleSession exercise => SentenceScrambleAnswerInput(
            exercise: exercise,
            response: text,
            tileSlots: slots,
            responseTime: const Duration(milliseconds: 1234),
          ),
          _ => throw StateError('Synthetic tile input missing'),
        };
        await learning.stageNativeAnswer(
          state: typed,
          input: input,
          stillCurrent: () => current,
        );
        final pending = await reopen(first.exercise.id);
        expect(pending.phase, NativeCheckpointPhase.pendingAnswer);
        expect(pending.checkpoint.draft.tileSlots, slots);
        expect(pending.checkpoint.answer!.nativeDraft!.tileSlots, slots);
        expect(
          pending.checkpoint.draft.canonicalTokenIndices(pending.exercise),
          canonical,
        );
        expect(pending.checkpoint.answer!.isCorrect, isFalse);
        await learning.commitNativeAnswer(
          pending.exercise,
          pending.checkpoint.answer!,
          stillCurrent: () => current,
        );
      },
    );
  }

  for (final longTarget in [false, true]) {
    test(
      'native tile draft retains exact Word Scramble indices after restart long=$longTarget',
      () async {
        final spelling = longTarget
            ? '${List.filled(69, 'a').join()}b'
            : 'letter';
        await storage.database.customStatement(
          'UPDATE vocabulary_words SET spelling = ?, normalized_spelling = ?, local_revision = local_revision + 1 WHERE id = ?',
          [spelling, spelling, configuredWordIds.first],
        );
        final first = await start('wordScramble');
        final exercise = first.exercise as WordScrambleSession;
        final indices = longTarget
            ? [0, 65, 69]
            : [
                for (var index = 0; index < exercise.letters.length; index++)
                  if (exercise.letters[index] == 't') index,
              ];
        expect(indices, hasLength(longTarget ? 3 : 2));
        final slots = List<int?>.filled(exercise.letters.length, null);
        for (var index = 0; index < indices.length; index++) {
          slots[index] = indices[index];
        }
        final draft = NativeExerciseDraft(
          tileSlots: slots,
          text: indices.map((index) => exercise.letters[index]).join(),
          responseTimeMs: 321,
        );
        await learning.saveNativeDraft(
          state: first,
          draft: draft,
          stillCurrent: () => current,
        );
        final resumed = await reopen(first.exercise.id);
        expect(
          resumed.checkpoint.draft.canonicalTokenIndices(resumed.exercise),
          indices,
        );
        expect(resumed.checkpoint.draft.tileSlots, slots);
        expect(resumed.checkpoint.draft.text, draft.text);
        expect(
          (resumed.exercise as WordScrambleSession).letters,
          exercise.letters,
        );
        final before = await storage.snapshot();
        await expectLater(
          learning.saveNativeDraft(
            state: resumed,
            draft: NativeExerciseDraft(
              tileSlots: slots,
              text: 'mismatched tiles',
              responseTimeMs: 322,
            ),
            stillCurrent: () => current,
          ),
          throwsFormatException,
        );
        expect(await storage.snapshot(), before);
      },
    );
  }

  test(
    'native identity guard rejects a whole valid plan copied into another session',
    () async {
      final original = await start('dictation');
      final other = await start('dictation');
      await storage.database.customStatement(
        'UPDATE learning_sessions SET accepted_plan_id = ?, accepted_plan_json = ?, '
        'checkpoint_json = ? WHERE id = ?',
        [
          original.plan.id,
          original.plan.stableSerialization,
          original.checkpoint.stableSerialization,
          other.exercise.id,
        ],
      );
      final before = await storage.snapshot();
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: other.exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => current,
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

  for (final collision in [false, true]) {
    test(
      'native identity guard preserves captured owner after actual merge collision=$collision',
      () async {
        await storage.database.customStatement(
          "UPDATE local_owners SET firebase_uid = NULL, account_state = 'localGuest' WHERE id = ?",
          [configuredOwnerId],
        );
        final state = await start('dictation');
        if (collision) {
          await storage.database.customStatement(
            "UPDATE vocabulary_categories SET name = 'Synthetic travel', normalized_name = 'synthetic travel' WHERE id = ?",
            [configuredOtherCategoryId],
          );
          await storage.database.customStatement(
            'UPDATE vocabulary_words SET spelling = ?, normalized_spelling = ?, meaning = ?, normalized_meaning = ?, part_of_speech = ? WHERE owner_id = ?',
            [
              state.exercise.word.spelling,
              state.exercise.word.spelling.toLowerCase(),
              state.exercise.word.meaning,
              state.exercise.word.meaning.toLowerCase(),
              state.exercise.word.partOfSpeech,
              configuredOtherOwnerId,
            ],
          );
        }
        await DriftOwnerUpgradeRepository(
          storage.database,
          nowUtc: () => storage.now,
          generateConflictId: () =>
              'synthetic-native-merge-conflict-${++nextId}',
          generateOwnerId: () => 'synthetic-native-unused-owner',
        ).upgrade(
          activeOwnerId: configuredOwnerId,
          firebaseUid: 'synthetic-configured-uid-b',
        );
        final row = await storage.session(state.exercise.id);
        expect(row['owner_id'], configuredOtherOwnerId);
        expect(row['accepted_plan_json'], state.plan.stableSerialization);
        final before = await storage.snapshot();
        learning = create();
        await expectLater(
          learning.resumeNativeExercise(
            sessionId: state.exercise.id,
            expectedOwnerId: configuredOtherOwnerId,
            stillCurrent: () => current,
          ),
          throwsA(
            isA<NativeExerciseUnavailable>().having(
              (error) => error.reason,
              'reason',
              NativeExerciseUnavailableReason.ownerChanged,
            ),
          ),
        );
        expect(await storage.snapshot(), before);
      },
    );
  }

  test(
    'native identity guard rejects an abandoned score without an answer',
    () async {
      var state = await start('dictation');
      state = await learning.abandonNativeExercise(
        state: state,
        stillCurrent: () => current,
      );
      await storage.database.customStatement(
        'UPDATE learning_sessions SET score = 100 WHERE id = ?',
        [state.exercise.id],
      );
      final before = await storage.snapshot();
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: state.exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
    },
  );

  for (final column in [
    'accepted_plan_json',
    'checkpoint_json',
    'accepted_plan_id',
  ]) {
    test(
      'corrupt $column is unavailable and read does not repair it',
      () async {
        final state = await start('sentenceScramble');
        await storage.database.customStatement(
          'UPDATE learning_sessions SET $column = ? WHERE id = ?',
          ['{"schemaVersion":99}', state.exercise.id],
        );
        final before = await storage.snapshot();
        await expectLater(
          learning.resumeNativeExercise(
            sessionId: state.exercise.id,
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), before);
      },
    );
  }

  for (final mutation in ['revision', 'meaning', 'category', 'owner']) {
    test(
      '$mutation drift prevents mutable resume without changing stored teaching content',
      () async {
        final state = await start('dictation');
        if (mutation == 'owner') {
          await storage.switchOwner(configuredOtherOwnerId);
        } else if (mutation == 'category') {
          await storage.database.customStatement(
            'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
            [state.exercise.word.categoryId],
          );
        } else {
          await storage.database.customStatement(
            'UPDATE vocabulary_words SET ${mutation == 'revision' ? 'local_revision = local_revision + 1' : "meaning = 'changed without a revision'"} WHERE id = ?',
            [state.exercise.word.id],
          );
        }
        final before = await storage.snapshot();
        await expectLater(
          learning.resumeNativeExercise(
            sessionId: state.exercise.id,
            expectedOwnerId: configuredOwnerId,
            stillCurrent: () => current,
          ),
          throwsStateError,
        );
        expect(await storage.snapshot(), before);
        expect(
          (await storage.session(state.exercise.id))['accepted_plan_json'],
          state.plan.stableSerialization,
        );
      },
    );
  }

  test(
    'deletion fence and a retired caller cannot reopen or write a draft',
    () async {
      final state = await start('dictation');
      current = false;
      await expectLater(
        learning.saveNativeDraft(
          state: state,
          draft: NativeExerciseDraft(),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      current = true;
      await expectLater(
        learning.saveNativeDraft(
          state: state,
          draft: NativeExerciseDraft(),
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      await storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-native-checkpoint-delete',
      );
      final before = await storage.snapshot();
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: state.exercise.id,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'actual inbound attempt path rejects local plans drafts and submitted responses',
    () async {
      final state = await start('dictation');
      final command = learning.prepareNativeAnswer(_input(state.exercise));
      final payload = <String, Object?>{
        'sessionId': '${DictationSession.idPrefix}synthetic-remote',
        'wordId': command.wordId,
        'promptMode': command.promptMode,
        'isCorrect': command.isCorrect,
        'responseTimeMs': command.responseTimeMs,
        'attemptNumber': 1,
        'occurredAtUtcMs': command.occurredAtUtc.millisecondsSinceEpoch,
        'providerProvenance': null,
        'evidenceClass': command.evidenceContext.evidenceClass.name,
        'evidenceContext': command.evidenceContext.toJson(),
      };
      Future<void> pull(Map<String, Object?> body) =>
          DriftSyncStore(storage.database).applyPullPage(
            ownerId: configuredOwnerId,
            collection: SyncCollection.attempts,
            page: PullPage(
              changes: [
                SyncEntity(
                  collection: SyncCollection.attempts,
                  entityId: 'synthetic-native-remote-answer',
                  revision: 1,
                  isDeleted: false,
                  payloadVersion: 2,
                  clientUpdatedAtUtc: storage.now,
                  serverUpdatedAtUtc: storage.now,
                  payload: body,
                ),
              ],
              hasMore: false,
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: storage.now,
                documentId: 'synthetic-native-remote-answer',
              ),
            ),
          );
      for (final field in [
        'acceptedPlanJson',
        'checkpoint',
        'response',
        'draft',
        'nativeDraft',
      ]) {
        final before = await storage.snapshot();
        await expectLater(
          pull({...payload, field: 'synthetic private injection'}),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
        expect(await storage.snapshot(), before, reason: field);
      }
      await pull(payload);
      final placeholder = await storage.session(
        payload['sessionId']! as String,
      );
      expect(placeholder['state'], 'syncedEvidence');
      expect(placeholder['accepted_plan_json'], isNull);
      final before = await storage.snapshot();
      await expectLater(
        learning.resumeNativeExercise(
          sessionId: payload['sessionId']! as String,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      expect(await storage.snapshot(), before);
    },
  );

  test(
    'a checkpoint advance retires live time admission but preserves its already closed proof',
    () async {
      final state = await start('dictation');
      final repository = learning.repository as DriftLearningRepository;
      final admission = await repository.admitCanonicalLearningTime(
        NativeLearningTimeAdmission(
          state.exercise,
          hintLevel: 0,
          callerContext: LearningTimeCallerContext.ordinary,
        ),
        expectedOwnerId: configuredOwnerId,
        stillCurrent: () => current,
      );
      final assisted = await learning.saveNativeDraft(
        state: state,
        draft: NativeExerciseDraft(assisted: true, responseTimeMs: 100),
        stillCurrent: () => current,
      );
      await expectLater(
        repository.requireLiveCanonicalLearningTimeAdmission(
          admission,
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => current,
        ),
        throwsStateError,
      );
      await repository.requireCanonicalLearningTimeAdmission(
        admission,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => current,
      );
      final pending = await learning.stageNativeAnswer(
        state: assisted,
        input: _input(assisted.exercise, assisted: true),
        stillCurrent: () => current,
      );
      await learning.commitNativeAnswer(
        pending.exercise,
        pending.checkpoint.answer!,
        stillCurrent: () => current,
      );
      await repository.requireCanonicalLearningTimeAdmission(
        admission,
        expectedOwnerId: configuredOwnerId,
        ownerStillCurrent: () => current,
      );
      expect(await storage.count('learning_time_segments'), 0);
    },
  );
}

NativeExerciseDraft _draft(AcceptedNativeExercise exercise) =>
    switch (exercise) {
      ChoiceClozeSession() => NativeExerciseDraft(
        optionId: exercise.choices.first.id,
        responseTimeMs: 321,
      ),
      SentenceScrambleSession() => NativeExerciseDraft(
        tileSlots: [
          0,
          1,
          for (var index = 2; index < exercise.tokenOrder.length; index++) null,
        ],
        text: exercise.tokenOrder
            .take(2)
            .map((index) => exercise.content.tokens[index])
            .join(' '),
        responseTimeMs: 321,
      ),
      _ => NativeExerciseDraft(
        text: 'synthetic private partial text',
        responseTimeMs: 321,
        assisted: exercise is DictationSession,
      ),
    };

NativeAnswerInput _input(
  AcceptedNativeExercise exercise, {
  bool assisted = false,
}) => switch (exercise) {
  DictationSession() => DictationAnswerInput(
    exercise: exercise,
    response: exercise.word.spelling,
    assisted: assisted,
    responseTime: const Duration(milliseconds: 1234),
  ),
  WordScrambleSession() => WordScrambleAnswerInput(
    exercise: exercise,
    response: exercise.word.spelling,
    responseTime: const Duration(milliseconds: 1234),
  ),
  SentenceScrambleSession() => SentenceScrambleAnswerInput(
    exercise: exercise,
    response: exercise.content.sentence,
    responseTime: const Duration(milliseconds: 1234),
  ),
  TypedClozeSession() => TypedClozeAnswerInput(
    exercise: exercise,
    response: exercise.word.spelling,
    responseTime: const Duration(milliseconds: 1234),
  ),
  ChoiceClozeSession() => ChoiceClozeAnswerInput(
    exercise: exercise,
    optionId: exercise.word.id,
    responseTime: const Duration(milliseconds: 1234),
  ),
};
