import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/cloze_session_harness.dart';
import '../../support/dictation_session_harness.dart'
    show DictationWriteInterference;

void main() {
  late ClozeSessionHarness h;
  setUp(() async => h = await ClozeSessionHarness.open());
  tearDown(() => h.close());

  Future<void> save(ClozeSession exercise, RecordAnswerCommand command) => h
      .learning
      .commitNativeAnswer(exercise, command, stillCurrent: () => h.current);

  for (final variant in ClozeVariant.values) {
    test(
      '$variant keeps sole canonical outcome and exact attempt outbox while all other tables remain byte-identical',
      () async {
        final before = await h.storage.snapshot();
        final prepared = (await h.prepare(variant))!;
        final exercise = await h.learning.startNativeExercise(
          prepared,
          stillCurrent: () => h.current,
        );
        expect(exercise, same(prepared));
        final command = h.answer(exercise);
        final first = await h.learning.commitNativeAnswer(
          exercise,
          command,
          stillCurrent: () => h.current,
        );
        expect(first.inserted, isTrue);
        expect(first.srs, isNull);
        final close = h.learning.prepareNativeFinish(exercise, command);
        final summary = await h.learning.finishNativeExercise(
          close,
          stillCurrent: () => h.current,
        );
        expect(
          (
            summary.state,
            summary.correctCount,
            summary.wrongCount,
            summary.score,
          ),
          ('completed', 1, 0, 100),
        );
        final after = await h.storage.snapshot();
        for (final table in before.keys.where(
          (table) => !{
            'learning_sessions',
            'answer_attempts',
            'outbox_operations',
          }.contains(table),
        )) {
          expect(after[table], before[table], reason: table);
        }
        expect(await h.storage.count('learning_sessions'), 1);
        final attempt = await h.database
            .select(h.database.answerAttempts)
            .getSingle();
        expect(attempt.id, command.id);
        expect(
          attempt.evidenceContextJson,
          jsonEncode(command.evidenceContext.toJson()),
        );
        expect(attempt.providerProvenance, exercise.providerProvenance);
        final outbox = await h.database
            .select(h.database.outboxOperations)
            .get();
        expect(
          outbox.map(
            (row) => (
              row.ownerId,
              row.entityType,
              row.entityId,
              row.payloadVersion,
              row.operationKind,
            ),
          ),
          [(exercise.ownerId, 'attempt', command.id, 2, 'upsert')],
        );
        final history = await DriftLearningHistoryQueries(
          h.database,
        ).load(ownerId: configuredOwnerId, nowUtc: h.now);
        expect(history.entries.single.answerCount, 1);
        expect(history.entries.single.correctCount, 1);
        expect(history.entries.single.hasAcceptedQuiz, isFalse);
        expect(h.questEvents, 0);
        expect(h.streakEvents, 0);
      },
    );

    test(
      '$variant retries all original ACKs without regenerating or retiming content answer or close',
      () async {
        final exercise = await h.ready(variant);
        final answer = h.answer(exercise);
        final first = await h.learning.commitNativeAnswer(
          exercise,
          answer,
          stillCurrent: () => true,
        );
        final close = h.learning.prepareNativeFinish(exercise, answer);
        final summary = await h.learning.finishNativeExercise(
          close,
          stillCurrent: () => true,
        );
        final original = await h.storage.snapshot();
        await h.database.customStatement(
          'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
          [exercise.word.id],
        );
        h.now = h.now.add(const Duration(hours: 1));
        expect(
          await h.learning.startNativeExercise(
            exercise,
            stillCurrent: () => true,
          ),
          same(exercise),
        );
        final replay = await h.learning.commitNativeAnswer(
          exercise,
          answer,
          stillCurrent: () => true,
        );
        expect(first.inserted, isTrue);
        expect(replay.inserted, isFalse);
        final repeated = await h.learning.finishNativeExercise(
          close,
          stillCurrent: () => true,
        );
        expect((repeated.id, repeated.score), (summary.id, summary.score));
        final after = await h.storage.snapshot();
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'outbox_operations',
        ]) {
          expect(after[table], original[table], reason: table);
        }
        expect(h.provider.requests, hasLength(1));
        final stored = await h.database
            .select(h.database.answerAttempts)
            .getSingle();
        expect(
          (stored.id, stored.occurredAtUtcMs, stored.responseTimeMs),
          (answer.id, answer.occurredAtUtc.millisecondsSinceEpoch, 1234),
        );
        expect(
          (await h.storage.session(exercise.id))['ended_at_utc_ms'],
          close.endedAtUtc.millisecondsSinceEpoch,
        );
      },
    );

    for (final mutation in ['revision', 'spelling', 'delete', 'category']) {
      for (final stage in ['start', 'save', 'finish']) {
        test(
          '$variant $mutation before $stage refuses changed original target',
          () async {
            final exercise = (await h.prepare(variant))!;
            if (stage != 'start') {
              await h.learning.startNativeExercise(
                exercise,
                stillCurrent: () => true,
              );
            }
            final answer = h.answer(exercise);
            if (stage == 'finish') await save(exercise, answer);
            final before = await h.storage.snapshot();
            final set = switch (mutation) {
              'revision' => 'local_revision = local_revision + 1',
              'spelling' => "spelling = 'changed-same-revision'",
              'delete' => 'is_deleted = 1',
              _ => 'category_id = ?',
            };
            if (mutation == 'category') {
              await h.database.customStatement(
                'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
                [exercise.word.categoryId],
              );
            } else {
              await h.database.customStatement(
                'UPDATE vocabulary_words SET $set WHERE id = ?',
                [exercise.word.id],
              );
            }
            final write = switch (stage) {
              'start' => h.learning.startNativeExercise(
                exercise,
                stillCurrent: () => true,
              ),
              'save' => h.learning.commitNativeAnswer(
                exercise,
                answer,
                stillCurrent: () => true,
              ),
              _ => h.learning.finishNativeExercise(
                h.learning.prepareNativeFinish(exercise, answer),
                stillCurrent: () => true,
              ),
            };
            await expectLater(write, throwsStateError);
            final after = await h.storage.snapshot();
            for (final table in [
              'learning_sessions',
              'answer_attempts',
              'outbox_operations',
            ]) {
              expect(after[table], before[table], reason: table);
            }
          },
        );
      }
    }

    test(
      '$variant rejects foreign owner and original-process ABA invalidation',
      () async {
        final exercise = await h.ready(variant);
        final answer = h.answer(exercise);
        await h.storage.switchOwner(configuredOtherOwnerId);
        await expectLater(
          save(exercise, answer),
          throwsA(
            isA<AccountDeletionException>().having(
              (error) => error.code,
              'code',
              AccountDeletionFailureCode.ownerChanged,
            ),
          ),
        );
        await h.storage.switchOwner(configuredOwnerId);
        h.current = false;
        await expectLater(save(exercise, answer), throwsStateError);
        expect(await h.storage.count('answer_attempts'), 0);
      },
    );

    test('$variant actual deletion fence denies saving any new fact', () async {
      final exercise = await h.ready(variant);
      final answer = h.answer(exercise);
      await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-cloze-deletion',
      );
      await expectLater(
        save(exercise, answer),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.unavailable,
          ),
        ),
      );
      expect(await h.storage.count('answer_attempts'), 0);
      expect(await h.storage.count('outbox_operations'), 0);
    });

    test(
      '$variant copied and restarted handles cannot adopt stored session',
      () async {
        final exercise = await h.ready(variant);
        final copied = switch (exercise) {
          TypedClozeSession() => TypedClozeSession(
            session: exercise.session,
            word: exercise.word,
            content: exercise.content,
          ),
          ChoiceClozeSession() => ChoiceClozeSession(
            session: exercise.session,
            word: exercise.word,
            content: exercise.content,
            choices: exercise.choices,
          ),
        };
        final restarted = DriftLearningRepository(
          h.database,
          ownerWrites: h.storage.ownerWrites,
        );
        for (final repository in [h.repository, restarted]) {
          await expectLater(
            repository.startNativeExercise(copied, stillCurrent: () => true),
            throwsStateError,
          );
          await expectLater(
            repository.commitNativeAnswer(
              exercise,
              h.answer(exercise),
              stillCurrent: () => true,
            ),
            repository == restarted ? throwsStateError : completes,
          );
        }
        expect(await h.storage.count('answer_attempts'), 1);
      },
    );

    test(
      '$variant all three public generic gateways reject native prefix across restart',
      () async {
        final prepared = (await h.prepare(variant))!;
        final restarted = DriftLearningRepository(
          h.database,
          ownerWrites: h.storage.ownerWrites,
        );
        await expectLater(
          restarted.startSession(prepared.session),
          throwsStateError,
        );
        expect(await h.storage.count('learning_sessions'), 0);
        final exercise = await h.learning.startNativeExercise(
          prepared,
          stillCurrent: () => true,
        );
        final answer = h.answer(exercise);
        await expectLater(restarted.recordAnswer(answer), throwsStateError);
        await expectLater(
          h.learning.recordAnswer(
            sessionId: answer.sessionId,
            wordId: answer.wordId,
            promptMode: answer.promptMode,
            isCorrect: answer.isCorrect,
            attemptNumber: answer.attemptNumber,
            responseTimeMs: answer.responseTimeMs,
            attemptId: answer.id,
            occurredAtUtc: answer.occurredAtUtc,
            evidenceContext: answer.evidenceContext,
          ),
          throwsStateError,
        );
        await expectLater(
          restarted.finishSession(
            ownerId: exercise.ownerId,
            sessionId: exercise.id,
            endedAtUtc: h.now,
          ),
          throwsStateError,
        );
        await expectLater(
          h.learning.finishSession(exercise.id),
          throwsStateError,
        );
        expect(await h.storage.count('answer_attempts'), 0);
        expect((await h.storage.session(exercise.id))['state'], 'active');
      },
    );

    test(
      '$variant cannot close a bare session or replace the first pending response',
      () async {
        final exercise = await h.ready(variant);
        final answer = h.answer(exercise);
        final close = h.learning.prepareNativeFinish(exercise, answer);
        await expectLater(
          h.learning.finishNativeExercise(close, stillCurrent: () => true),
          throwsStateError,
        );
        await save(exercise, answer);
        await expectLater(
          save(exercise, h.answer(exercise, correct: false)),
          throwsStateError,
        );
        await h.learning.finishNativeExercise(close, stillCurrent: () => true);
        h.now = h.now.add(const Duration(minutes: 1));
        await expectLater(
          h.learning.finishNativeExercise(
            h.learning.prepareNativeFinish(exercise, answer),
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        expect(await h.storage.count('answer_attempts'), 1);
      },
    );

    test(
      '$variant all mutation ACKs require a real top-level commit',
      () async {
        final exercise = (await h.prepare(variant))!;
        await expectLater(
          h.database.transaction(
            () => h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            ),
          ),
          throwsStateError,
        );
        expect(await h.storage.count('learning_sessions'), 0);
        await h.learning.startNativeExercise(
          exercise,
          stillCurrent: () => true,
        );
        final answer = h.answer(exercise);
        await expectLater(
          h.database.transaction(() => save(exercise, answer)),
          throwsStateError,
        );
        expect(await h.storage.count('answer_attempts'), 0);
        await save(exercise, answer);
        final close = h.learning.prepareNativeFinish(exercise, answer);
        await expectLater(
          h.database.transaction(
            () => h.learning.finishNativeExercise(
              close,
              stillCurrent: () => true,
            ),
          ),
          throwsStateError,
        );
        expect((await h.storage.session(exercise.id))['state'], 'active');
      },
    );

    for (final stage in ['start', 'save', 'finish']) {
      test(
        '$variant final SQL target guard rolls back inserted $stage then original intent can retry',
        () async {
          final exercise = (await h.prepare(variant))!;
          if (stage != 'start') {
            await h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            );
          }
          final answer = h.answer(exercise);
          if (stage == 'finish') await save(exercise, answer);
          final close = h.learning.prepareNativeFinish(exercise, answer);
          final before = await h.storage.snapshot();
          final interference = DictationWriteInterference(
            stage == 'save' ? 'answer_attempts' : 'learning_sessions',
            (executor) async {
              final changed = exercise is ChoiceClozeSession
                  ? exercise.choices.last
                  : exercise.word;
              await executor.runCustom(
                'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
                [changed.id],
              );
            },
            onUpdate: stage == 'finish',
          );
          Future<Object> write() => switch (stage) {
            'start' => h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            ),
            'save' => h.learning.commitNativeAnswer(
              exercise,
              answer,
              stillCurrent: () => true,
            ),
            _ => h.learning.finishNativeExercise(
              close,
              stillCurrent: () => true,
            ),
          };
          await expectLater(
            h.database.runWithInterceptor(write, interceptor: interference),
            throwsStateError,
          );
          expect(interference.fired, isTrue);
          expect(await h.storage.snapshot(), before);
          await write();
          expect(h.provider.requests, hasLength(1));
        },
      );
    }

    test(
      '$variant current guard is last and rolls back an actually inserted answer',
      () async {
        final exercise = await h.ready(variant);
        final answer = h.answer(exercise);
        final before = await h.storage.snapshot();
        final interference = DictationWriteInterference('answer_attempts', (
          _,
        ) async {
          h.current = false;
        });
        await expectLater(
          h.database.runWithInterceptor(
            () => save(exercise, answer),
            interceptor: interference,
          ),
          throwsStateError,
        );
        expect(interference.fired, isTrue);
        expect(await h.storage.snapshot(), before);
        expect(h.notifications, 0);
      },
    );

    test(
      '$variant preserves newer genuine remote SRS over older ordinary evidence',
      () async {
        final exercise = (await h.prepare(variant))!;
        final oldAt = h.now.subtract(const Duration(days: 5));
        const ordinaryId = 'synthetic-old-ordinary-cloze-control';
        await h.repository.startSession(
          LearningSessionDraft(
            id: ordinaryId,
            ownerId: configuredOwnerId,
            activityType: 'quiz',
            startedAtUtc: oldAt,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
        await h.repository.recordAnswer(
          RecordAnswerCommand(
            id: 'synthetic-old-ordinary-cloze-answer',
            ownerId: configuredOwnerId,
            sessionId: ordinaryId,
            wordId: exercise.word.id,
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: 100,
            attemptNumber: 1,
            occurredAtUtc: oldAt,
          ),
        );
        final entity = SyncEntity(
          collection: SyncCollection.srsStates,
          entityId: exercise.word.id,
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: h.now,
          serverUpdatedAtUtc: h.now,
          payload: {
            'wordId': exercise.word.id,
            'stability': 12.5,
            'difficulty': 4.5,
            'intervalDays': 14,
            'repetitions': 8,
            'lapses': 2,
            'lastReviewAtUtcMs': h.now
                .subtract(const Duration(days: 1))
                .millisecondsSinceEpoch,
            'dueAtUtcMs': h.now
                .add(const Duration(days: 13))
                .millisecondsSinceEpoch,
            'algorithmVersion': 1,
          },
        );
        await DriftSyncStore(h.database).applyPullPage(
          ownerId: configuredOwnerId,
          collection: entity.collection,
          page: PullPage(
            changes: [entity],
            hasMore: false,
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: h.now,
              documentId: entity.entityId,
            ),
          ),
        );
        Future<List<Map<String, Object?>>> rows() async => [
          for (final row
              in await h.database
                  .customSelect(
                    'SELECT * FROM srs_states WHERE owner_id = ? AND word_id = ?',
                    variables: [
                      Variable(configuredOwnerId),
                      Variable(exercise.word.id),
                    ],
                  )
                  .get())
            row.data,
        ];
        final remote = await rows();
        expect(remote.single['repetitions'], 8);
        expect(remote.single['stability'], 12.5);
        final before = await h.storage.snapshot();
        await h.learning.startNativeExercise(
          exercise,
          stillCurrent: () => true,
        );
        final answer = h.answer(exercise);
        await save(exercise, answer);
        await save(exercise, answer);
        await h.learning.finishNativeExercise(
          h.learning.prepareNativeFinish(exercise, answer),
          stillCurrent: () => true,
        );
        expect(await rows(), remote);
        final after = await h.storage.snapshot();
        for (final table in [
          'points_ledger_entries',
          'reward_transactions',
          'achievement_unlocks',
        ]) {
          expect(after[table], before[table], reason: table);
        }
      },
    );
  }

  for (final mutation in ['revision', 'spelling', 'delete', 'category']) {
    test(
      'choice validates every distractor original $mutation before saving',
      () async {
        final exercise =
            await h.ready(ClozeVariant.choice) as ChoiceClozeSession;
        final distractor = exercise.choices.firstWhere(
          (word) => word.id != exercise.word.id,
        );
        final answer = h.answer(exercise);
        final sql = switch (mutation) {
          'revision' => 'local_revision = local_revision + 1',
          'spelling' => "spelling = 'changed-distractor'",
          'delete' => 'is_deleted = 1',
          _ => "category_id = '$configuredOtherCategoryId'",
        };
        await h.database.customStatement(
          'UPDATE vocabulary_words SET $sql WHERE id = ?',
          [distractor.id],
        );
        await expectLater(save(exercise, answer), throwsStateError);
        expect(await h.storage.count('answer_attempts'), 0);
        expect(await h.storage.count('outbox_operations'), 0);
      },
    );
  }

  test(
    'unreserved inferred legacy Cloze retains ordinary generic behavior',
    () async {
      final word = (await h.repository.listQuizWords(
        ownerId: configuredOwnerId,
        limit: 1,
      )).single;
      const id = 'legacy-inferred-cloze-session';
      await h.repository.startSession(
        LearningSessionDraft(
          id: id,
          ownerId: configuredOwnerId,
          activityType: 'cloze',
          startedAtUtc: h.now,
          appVersion: 'legacy',
          buildId: 'legacy',
        ),
      );
      final result = await h.repository.recordAnswer(
        RecordAnswerCommand(
          id: 'legacy-inferred-cloze-answer',
          ownerId: configuredOwnerId,
          sessionId: id,
          wordId: word.id,
          promptMode: 'clozeTyped',
          isCorrect: true,
          responseTimeMs: 100,
          attemptNumber: 1,
          occurredAtUtc: h.now,
        ),
      );
      expect(result.srs, isNotNull);
      final summary = await h.repository.finishSession(
        ownerId: configuredOwnerId,
        sessionId: id,
        endedAtUtc: h.now,
      );
      expect((summary.state, summary.score), ('completed', 100));
      expect(await h.storage.count('points_ledger_entries'), 1);
    },
  );
}
