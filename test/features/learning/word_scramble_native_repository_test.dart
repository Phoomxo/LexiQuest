import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_learning_history_queries.dart';

import '../../support/word_scramble_session_harness.dart';
import '../../support/dictation_session_harness.dart'
    show DictationWriteInterference;

void main() {
  late WordScrambleSessionHarness h;
  setUp(() async => h = await WordScrambleSessionHarness.open());
  tearDown(() => h.close());

  Future<AnswerRecordResult> save(
    WordScrambleSession exercise,
    RecordAnswerCommand answer,
  ) => h.learning.commitNativeAnswer(
    exercise,
    answer,
    stillCurrent: () => h.current,
  );

  for (final correct in [false, true]) {
    test(
      'sole $correct canonical answer has actual history but no ordinary or Research effects',
      () async {
        final before = await h.storage.snapshot();
        final prepared = (await h.prepare())!;
        final exercise = await h.learning.startNativeExercise(
          prepared,
          stillCurrent: () => true,
        );
        expect(exercise, same(prepared));
        final answer = h.answer(exercise, correct: correct);
        final result = await save(exercise, answer);
        expect(result.inserted, isTrue);
        expect(result.srs, isNull);
        final close = h.learning.prepareNativeFinish(exercise, answer);
        final summary = await h.learning.finishNativeExercise(
          close,
          stillCurrent: () => true,
        );
        expect(
          (
            summary.state,
            summary.correctCount,
            summary.wrongCount,
            summary.score,
          ),
          ('completed', correct ? 1 : 0, correct ? 0 : 1, correct ? 100 : 0),
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
        expect(attempt.id, answer.id);
        expect(
          attempt.evidenceContextJson,
          jsonEncode(answer.evidenceContext.toJson()),
        );
        expect(attempt.providerProvenance, isNull);
        final outbox = await h.database
            .select(h.database.outboxOperations)
            .get();
        expect(
          outbox.map(
            (row) =>
                (row.ownerId, row.entityType, row.entityId, row.payloadVersion),
          ),
          [(exercise.ownerId, 'attempt', answer.id, 2)],
        );
        final history = await DriftLearningHistoryQueries(
          h.database,
        ).load(ownerId: configuredOwnerId, nowUtc: h.now);
        expect(history.entries.single.answerCount, 1);
        expect(history.entries.single.correctCount, correct ? 1 : 0);
        expect(history.entries.single.activityType, 'wordScramble');
        expect((h.questEvents, h.streakEvents), (0, 0));
      },
    );
  }

  test(
    'original launch answer and close ACKs replay exactly after target edits',
    () async {
      final exercise = await h.ready();
      final answer = h.answer(exercise);
      await save(exercise, answer);
      final close = h.learning.prepareNativeFinish(exercise, answer);
      final summary = await h.learning.finishNativeExercise(
        close,
        stillCurrent: () => true,
      );
      final before = await h.storage.snapshot();
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
      expect((await save(exercise, answer)).inserted, isFalse);
      final replay = await h.learning.finishNativeExercise(
        close,
        stillCurrent: () => true,
      );
      expect((replay.id, replay.score), (summary.id, summary.score));
      final after = await h.storage.snapshot();
      for (final table in [
        'learning_sessions',
        'answer_attempts',
        'outbox_operations',
      ]) {
        expect(after[table], before[table], reason: table);
      }
      final stored = await h.database
          .select(h.database.answerAttempts)
          .getSingle();
      expect(
        (stored.id, stored.responseTimeMs, stored.occurredAtUtcMs),
        (answer.id, 1234, answer.occurredAtUtc.millisecondsSinceEpoch),
      );
      expect(
        (await h.storage.session(exercise.id))['ended_at_utc_ms'],
        close.endedAtUtc.millisecondsSinceEpoch,
      );
    },
  );

  for (final mutation in [
    'revision',
    'spelling',
    'meaning',
    'partOfSpeech',
    'delete',
    'category',
  ]) {
    for (final stage in ['start', 'save', 'finish']) {
      test(
        '$mutation before $stage rejects original target without partial facts',
        () async {
          final exercise = (await h.prepare())!;
          if (stage != 'start') {
            await h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            );
          }
          final answer = h.answer(exercise);
          if (stage == 'finish') await save(exercise, answer);
          await _changeTarget(h, exercise, mutation);
          final before = await h.storage.snapshot();
          await expectLater(switch (stage) {
            'start' => h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            ),
            'save' => save(exercise, answer),
            _ => h.learning.finishNativeExercise(
              h.learning.prepareNativeFinish(exercise, answer),
              stillCurrent: () => true,
            ),
          }, throwsStateError);
          expect(await h.storage.snapshot(), before);
        },
      );
    }
  }

  for (final stage in ['start', 'save', 'finish']) {
    test(
      'target change after actual $stage SQL rolls back the whole boundary',
      () async {
        final exercise = (await h.prepare())!;
        if (stage != 'start') {
          await h.learning.startNativeExercise(
            exercise,
            stillCurrent: () => true,
          );
        }
        final answer = h.answer(exercise);
        if (stage == 'finish') await save(exercise, answer);
        final before = await h.storage.snapshot();
        final probe = DictationWriteInterference(
          stage == 'save' ? 'answer_attempts' : 'learning_sessions',
          (executor) async {
            await executor.runUpdate(
              'UPDATE vocabulary_words SET meaning = ? WHERE id = ?',
              ['changed after SQL', exercise.word.id],
            );
          },
          onUpdate: stage == 'finish',
        );
        await expectLater(
          h.database.runWithInterceptor(
            () => switch (stage) {
              'start' => h.learning.startNativeExercise(
                exercise,
                stillCurrent: () => true,
              ),
              'save' => save(exercise, answer),
              _ => h.learning.finishNativeExercise(
                h.learning.prepareNativeFinish(exercise, answer),
                stillCurrent: () => true,
              ),
            },
            interceptor: probe,
          ),
          throwsStateError,
        );
        expect(probe.fired, isTrue);
        expect(await h.storage.snapshot(), before);
      },
    );

    test(
      'inherited transaction cannot return an uncommitted $stage ACK',
      () async {
        final exercise = (await h.prepare())!;
        if (stage != 'start') {
          await h.learning.startNativeExercise(
            exercise,
            stillCurrent: () => true,
          );
        }
        final answer = h.answer(exercise);
        if (stage == 'finish') await save(exercise, answer);
        final before = await h.storage.snapshot();
        await h.database.transaction(() async {
          await expectLater(switch (stage) {
            'start' => h.learning.startNativeExercise(
              exercise,
              stillCurrent: () => true,
            ),
            'save' => save(exercise, answer),
            _ => h.learning.finishNativeExercise(
              h.learning.prepareNativeFinish(exercise, answer),
              stillCurrent: () => true,
            ),
          }, throwsStateError);
        });
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'owner switch and route ABA invalidation deny any new saved fact',
    () async {
      final exercise = await h.ready();
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

  test(
    'actual owner deletion fence denies answer and outbox together',
    () async {
      final exercise = await h.ready();
      final answer = h.answer(exercise);
      await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-scramble-delete',
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
    },
  );

  test(
    'copied handles and fresh repository cannot adopt a persisted launch',
    () async {
      final exercise = await h.ready();
      final copied = WordScrambleSession(
        session: exercise.session,
        word: exercise.word,
      );
      final restarted = DriftLearningRepository(
        h.database,
        ownerWrites: h.storage.ownerWrites,
      );
      for (final repository in [h.repository, restarted]) {
        await expectLater(
          repository.startNativeExercise(copied, stillCurrent: () => true),
          throwsStateError,
        );
      }
      await expectLater(
        restarted.commitNativeAnswer(
          exercise,
          h.answer(exercise),
          stillCurrent: () => true,
        ),
        throwsStateError,
      );
      expect(await h.storage.count('answer_attempts'), 0);
    },
  );

  test('all generic gateways reject the reserved native prefix', () async {
    final exercise = (await h.prepare())!;
    await expectLater(
      h.repository.startSession(exercise.session),
      throwsStateError,
    );
    await h.learning.startNativeExercise(exercise, stillCurrent: () => true);
    final answer = h.answer(exercise);
    await expectLater(h.repository.recordAnswer(answer), throwsStateError);
    await expectLater(
      h.learning.recordAnswer(
        sessionId: exercise.id,
        wordId: exercise.word.id,
        promptMode: answer.promptMode,
        isCorrect: true,
        responseTimeMs: answer.responseTimeMs,
        attemptNumber: 1,
        attemptId: answer.id,
        occurredAtUtc: answer.occurredAtUtc,
        evidenceContext: answer.evidenceContext,
      ),
      throwsStateError,
    );
    await expectLater(
      h.repository.finishSession(
        ownerId: exercise.ownerId,
        sessionId: exercise.id,
        endedAtUtc: h.now,
      ),
      throwsStateError,
    );
    await expectLater(h.learning.finishSession(exercise.id), throwsStateError);
    expect(await h.storage.count('answer_attempts'), 0);
    expect((await h.storage.session(exercise.id))['state'], 'active');
  });

  for (final mutation in [
    'SQL pin',
    'provider',
    'prompt',
    'word',
    'skill',
    'class',
    'hint',
  ]) {
    test(
      'forged $mutation is denied without poisoning original answer',
      () async {
        final exercise = await h.ready();
        final answer = h.answer(exercise);
        final json = Map<String, Object?>.from(answer.evidenceContext.toJson());
        if (mutation == 'SQL pin') {
          json['contentRevision'] = exercise.wordContentRevision;
        }
        if (mutation == 'skill') json['skillId'] = 'foreign-skill';
        if (mutation == 'class') {
          json['evidenceClass'] = EvidenceClass.recognition.name;
        }
        if (mutation == 'hint') json['hintLevel'] = 1;
        final forged = RecordAnswerCommand(
          id: answer.id,
          ownerId: answer.ownerId,
          sessionId: answer.sessionId,
          wordId: mutation == 'word' ? configuredWordIds.last : answer.wordId,
          promptMode: mutation == 'prompt' ? 'dictation' : answer.promptMode,
          isCorrect: answer.isCorrect,
          responseTimeMs: answer.responseTimeMs,
          attemptNumber: answer.attemptNumber,
          occurredAtUtc: answer.occurredAtUtc,
          providerProvenance: mutation == 'provider'
              ? 'invented-provider'
              : null,
          evidenceContext: EvidenceContext.fromJson(json),
        );
        final before = await h.storage.snapshot();
        await expectLater(save(exercise, forged), throwsArgumentError);
        expect(await h.storage.snapshot(), before);
        expect((await save(exercise, answer)).inserted, isTrue);
      },
    );
  }

  test(
    'cannot close bare launch replace pending answer or retime original close',
    () async {
      final exercise = await h.ready();
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
      h.now = h.now.add(const Duration(seconds: 1));
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
    'raw typed response remains transient through save finish and outbox',
    () async {
      final exercise = await h.ready();
      const response = 'synthetic private raw response 4582';
      final answer = h.answer(exercise, response: response);
      await save(exercise, answer);
      await h.learning.finishNativeExercise(
        h.learning.prepareNativeFinish(exercise, answer),
        stillCurrent: () => true,
      );
      expect(answer.isCorrect, isFalse);
      expect(jsonEncode(await h.storage.snapshot()), isNot(contains(response)));
      expect(
        answer.evidenceContext.contentRevision,
        exercise.evidenceContentRevision,
      );
    },
  );
}

Future<void> _changeTarget(
  WordScrambleSessionHarness h,
  WordScrambleSession exercise,
  String mutation,
) async {
  if (mutation == 'category') {
    await h.database.customStatement(
      'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
      [exercise.word.categoryId],
    );
    return;
  }
  final set = switch (mutation) {
    'revision' => 'local_revision = local_revision + 1',
    'spelling' => "spelling = 'changed'",
    'meaning' => "meaning = 'changed meaning'",
    'partOfSpeech' => "part_of_speech = 'verb'",
    _ => 'is_deleted = 1',
  };
  await h.database.customStatement(
    'UPDATE vocabulary_words SET $set WHERE id = ?',
    [exercise.word.id],
  );
}
