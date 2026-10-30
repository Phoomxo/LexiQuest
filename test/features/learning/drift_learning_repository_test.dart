import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';

import '../../support/dictation_session_harness.dart';

void main() {
  group('Dictation capability boundaries', () {
    late DictationSessionHarness h;
    setUp(() async => h = await DictationSessionHarness.open());
    tearDown(() => h.close());

    test(
      'a bare session cannot be finished without its exact saved response',
      () async {
        final session = await h.ready();
        final command = h.answer(session);
        final intent = h.learning.prepareNativeFinish(session, command);
        await expectLater(
          h.learning.finishNativeExercise(intent, stillCurrent: () => true),
          throwsStateError,
        );
        final stored = await h.database
            .select(h.database.learningSessions)
            .getSingle();
        expect(stored.state, 'active');
        expect(stored.endedAtUtcMs, isNull);
        expect(
          await h.database.select(h.database.achievementUnlocks).get(),
          isEmpty,
        );
      },
    );

    test('target edits before start create no session', () async {
      final session = (await h.learning.prepareDictation(
        categoryId: configuredCategoryId,
        stillCurrent: () => true,
      ))!;
      await h.database.customStatement(
        'UPDATE vocabulary_words SET spelling = ?,local_revision = local_revision + 1 WHERE id = ?',
        ['changed', session.word.id],
      );
      await expectLater(
        h.learning.startNativeExercise(session, stillCurrent: () => true),
        throwsStateError,
      );
      expect(
        await h.database.select(h.database.learningSessions).get(),
        isEmpty,
      );
    });

    for (final mutation in ['revision', 'spelling', 'delete']) {
      test(
        '$mutation after start rejects save without any attempt/outbox',
        () async {
          final session = await h.ready();
          final command = h.answer(session);
          final sql = switch (mutation) {
            'revision' => 'local_revision = local_revision + 1',
            'spelling' => "spelling = 'changed-with-same-revision'",
            _ => 'is_deleted = 1',
          };
          await h.database.customStatement(
            'UPDATE vocabulary_words SET $sql WHERE id = ?',
            [session.word.id],
          );
          await expectLater(
            h.learning.commitNativeAnswer(
              session,
              command,
              stillCurrent: () => true,
            ),
            throwsStateError,
          );
          expect(
            await h.database.select(h.database.answerAttempts).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.outboxOperations).get(),
            isEmpty,
          );
        },
      );
    }

    test(
      'owner change and epoch ABA invalidation cannot save old owner data',
      () async {
        final session = await h.ready();
        final command = h.answer(session);
        await h.storage.switchOwner(configuredOtherOwnerId);
        await expectLater(
          h.learning.commitNativeAnswer(
            session,
            command,
            stillCurrent: () => true,
          ),
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
        await expectLater(
          h.learning.commitNativeAnswer(
            session,
            command,
            stillCurrent: () => h.current,
          ),
          throwsStateError,
        );
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          isEmpty,
        );
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          isEmpty,
        );
      },
    );

    test('actual deletion fence denies original save', () async {
      final session = await h.ready();
      final command = h.answer(session);
      await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: 'synthetic-configured-uid-a',
        idempotencyKey: 'synthetic-dictation-deletion',
      );
      await expectLater(
        h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.unavailable,
          ),
        ),
      );
      expect(await h.database.select(h.database.answerAttempts).get(), isEmpty);
      expect(
        await h.database.select(h.database.outboxOperations).get(),
        isEmpty,
      );
    });

    test(
      'a restarted repository cannot adopt the original bare session',
      () async {
        final session = await h.ready();
        final restarted = DriftLearningRepository(
          h.database,
          ownerWrites: h.storage.ownerWrites,
        );
        final command = h.answer(session);
        await expectLater(
          restarted.startNativeExercise(session, stillCurrent: () => true),
          throwsStateError,
        );
        await expectLater(
          restarted.commitNativeAnswer(
            session,
            command,
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        await expectLater(
          restarted.finishNativeExercise(
            h.learning.prepareNativeFinish(session, command),
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          isEmpty,
        );
      },
    );

    for (final stage in ['learning_sessions', 'answer_attempts']) {
      test(
        'final target reread rolls back $stage after actual SQL write',
        () async {
          final session = (await h.learning.prepareDictation(
            categoryId: configuredCategoryId,
            stillCurrent: () => true,
          ))!;
          if (stage == 'answer_attempts') {
            await h.learning.startNativeExercise(
              session,
              stillCurrent: () => true,
            );
          }
          final command = h.answer(session);
          final interference = DictationWriteInterference(stage, (
            executor,
          ) async {
            await executor.runCustom(
              'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
              [session.word.id],
            );
          });
          await expectLater(
            h.database.runWithInterceptor(
              () => stage == 'learning_sessions'
                  ? h.learning.startNativeExercise(
                      session,
                      stillCurrent: () => true,
                    )
                  : h.learning.commitNativeAnswer(
                      session,
                      command,
                      stillCurrent: () => true,
                    ),
              interceptor: interference,
            ),
            throwsStateError,
          );
          expect(interference.fired, isTrue);
          expect(
            await h.database.select(h.database.answerAttempts).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.outboxOperations).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.learningSessions).get(),
            stage == 'learning_sessions' ? isEmpty : hasLength(1),
          );
        },
      );
    }

    test(
      'final synchronous current guard rolls back an inserted answer',
      () async {
        final session = await h.ready();
        final command = h.answer(session);
        final interference = DictationWriteInterference('answer_attempts', (
          _,
        ) async {
          h.current = false;
        });
        await expectLater(
          h.database.runWithInterceptor(
            () => h.learning.commitNativeAnswer(
              session,
              command,
              stillCurrent: () => h.current,
            ),
            interceptor: interference,
          ),
          throwsStateError,
        );
        expect(interference.fired, isTrue);
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          isEmpty,
        );
        expect(await h.database.select(h.database.srsStates).get(), isEmpty);
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          isEmpty,
        );
        expect(h.notifications, 0);
      },
    );

    test(
      'final target check rolls back close and retries its original end time',
      () async {
        final session = await h.ready();
        final command = h.answer(session, assisted: true);
        await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        );
        final close = h.learning.prepareNativeFinish(session, command);
        final interference = DictationWriteInterference('learning_sessions', (
          executor,
        ) async {
          await executor.runCustom(
            'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
            [session.word.id],
          );
        }, onUpdate: true);
        await expectLater(
          h.database.runWithInterceptor(
            () => h.learning.finishNativeExercise(
              close,
              stillCurrent: () => true,
            ),
            interceptor: interference,
          ),
          throwsStateError,
        );
        expect(interference.fired, isTrue);
        final unfinished = await h.database
            .select(h.database.learningSessions)
            .getSingle();
        expect(unfinished.state, 'active');
        expect(unfinished.endedAtUtcMs, isNull);
        h.now = h.now.add(const Duration(hours: 1));
        final summary = await h.learning.finishNativeExercise(
          close,
          stillCurrent: () => true,
        );
        expect(summary.correctCount, 1);
        final completed = await h.database
            .select(h.database.learningSessions)
            .getSingle();
        expect(completed.endedAtUtcMs, close.endedAtUtc.millisecondsSinceEpoch);
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.achievementUnlocks).get(),
          isEmpty,
        );
      },
    );

    test(
      'first immutable answer and close identities cannot be replaced',
      () async {
        final session = await h.ready();
        final original = h.answer(session);
        await h.learning.commitNativeAnswer(
          session,
          original,
          stillCurrent: () => true,
        );
        final different = h.answer(session, correct: false);
        await expectLater(
          h.learning.commitNativeAnswer(
            session,
            different,
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        final close = h.learning.prepareNativeFinish(session, original);
        await h.learning.finishNativeExercise(close, stillCurrent: () => true);
        h.now = h.now.add(const Duration(seconds: 5));
        await expectLater(
          h.learning.finishNativeExercise(
            h.learning.prepareNativeFinish(session, original),
            stillCurrent: () => true,
          ),
          throwsStateError,
        );
        final attempt = await h.database
            .select(h.database.answerAttempts)
            .getSingle();
        expect(attempt.id, original.id);
        expect(
          attempt.occurredAtUtcMs,
          original.occurredAtUtc.millisecondsSinceEpoch,
        );
        final stored = await h.database
            .select(h.database.learningSessions)
            .getSingle();
        expect(stored.endedAtUtcMs, close.endedAtUtc.millisecondsSinceEpoch);
      },
    );

    test(
      'all three capability ACKs require their own committed transaction',
      () async {
        final prepared = (await h.learning.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => true,
        ))!;
        await expectLater(
          h.database.transaction(
            () => h.learning.startNativeExercise(
              prepared,
              stillCurrent: () => true,
            ),
          ),
          throwsStateError,
        );
        expect(
          await h.database.select(h.database.learningSessions).get(),
          isEmpty,
        );
        final session = await h.learning.startNativeExercise(
          prepared,
          stillCurrent: () => true,
        );
        final command = h.answer(session);
        await expectLater(
          h.database.transaction(
            () => h.learning.commitNativeAnswer(
              session,
              command,
              stillCurrent: () => true,
            ),
          ),
          throwsStateError,
        );
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          isEmpty,
        );
        await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        );
        final close = h.learning.prepareNativeFinish(session, command);
        await expectLater(
          h.database.transaction(
            () => h.learning.finishNativeExercise(
              close,
              stillCurrent: () => true,
            ),
          ),
          throwsStateError,
        );
        final stored = await h.database
            .select(h.database.learningSessions)
            .getSingle();
        expect(stored.state, 'active');
      },
    );
  });

  late AppDatabase database;
  late DriftLearningRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningRepository(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: 'owner-1',
              categoryId: 'category-1',
              spelling: word.$2,
              normalizedSpelling: word.$2,
              meaning: word.$3,
              normalizedMeaning: word.$3,
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
  });

  tearDown(() => database.close());

  test('quiz words come from active local vocabulary for the owner', () async {
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      categoryId: 'category-1',
      limit: 10,
    );

    expect(words.map((word) => word.id), ['word-1', 'word-2']);
    expect(words.first.meaning, 'สถานี');
    expect(words.first.contentRevision, 'local-vocabulary-v1:1');
  });

  test('target filters exclude deleted words and other owners', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1));
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-2',
            ownerId: 'owner-2',
            name: 'Other',
            normalizedName: 'other',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'other-word',
            ownerId: 'owner-2',
            categoryId: 'category-2',
            spelling: 'synthetic',
            normalizedSpelling: 'synthetic',
            meaning: 'อื่น',
            normalizedMeaning: 'อื่น',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database.customStatement(
      "UPDATE vocabulary_words SET is_deleted = 1 WHERE id = 'word-2'",
    );
    final words = await repository.listQuizWords(
      ownerId: 'owner-1',
      limit: 10,
      wordIds: ['word-1', 'word-2', 'other-word'],
    );
    expect(words.map((word) => word.id), ['word-1']);
    expect(
      await repository.listQuizWords(
        ownerId: 'owner-1',
        limit: 10,
        wordIds: [],
      ),
      isEmpty,
    );
  });

  test('answer transaction is idempotent and updates SRS and points', () async {
    const session = LearningSessionDraft(
      id: 'session-1',
      ownerId: 'owner-1',
      activityType: 'quiz',
      startedAtUtc: null,
      appVersion: '1.0.0',
      buildId: 'test',
    );
    await repository.startSession(
      session.copyWith(startedAtUtc: DateTime.utc(2026, 7, 30, 10)),
    );
    final command = RecordAnswerCommand(
      id: 'attempt-1',
      ownerId: 'owner-1',
      sessionId: 'session-1',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 420,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
    );

    final first = await repository.recordAnswer(command);
    final replay = await repository.recordAnswer(command);

    expect(first.inserted, isTrue);
    expect(replay.inserted, isFalse);
    expect(replay.srs!.intervalDays, 1);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    final achievements = await database
        .select(database.achievementUnlocks)
        .get();
    expect(achievements.map((row) => row.achievementId).toSet(), {
      'first_answer',
      'first_correct',
    });
    final outbox = await database.select(database.outboxOperations).get();
    expect(outbox.map((row) => row.entityType), contains('attempt'));
    final storedSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('session-1'))).getSingle();
    expect(storedSession.correctCount, 1);
    expect(storedSession.wrongCount, 0);
  });

  test('finishing session stores auditable score and counts', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    await repository.recordAnswer(
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: false,
        responseTimeMs: 800,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );

    final result = await repository.finishSession(
      ownerId: 'owner-1',
      sessionId: 'session-1',
      endedAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
    );

    expect(result.state, 'completed');
    expect(result.correctCount, 0);
    expect(result.wrongCount, 1);
    expect(result.score, 0);
  });

  test(
    'out-of-order local attempts rebuild SRS in canonical event order',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-order',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 9),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final later = DateTime.utc(2026, 7, 30, 10);
      final earlier = DateTime.utc(2026, 7, 30, 9, 30);
      await repository.recordAnswer(
        RecordAnswerCommand(
          id: 'attempt-later',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 200,
          attemptNumber: 2,
          occurredAtUtc: later,
        ),
      );

      final result = await repository.recordAnswer(
        RecordAnswerCommand(
          id: 'attempt-earlier',
          ownerId: 'owner-1',
          sessionId: 'session-order',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: false,
          responseTimeMs: 300,
          attemptNumber: 1,
          occurredAtUtc: earlier,
        ),
      );

      expect(result.srs!.lastReviewAtUtc, later);
      expect(result.srs!.repetitions, 1);
      expect(result.srs!.lapses, 1);
      final firstAnswer = await (database.select(
        database.achievementUnlocks,
      )..where((row) => row.achievementId.equals('first_answer'))).getSingle();
      expect(firstAnswer.sourceEventId, 'attempt-earlier');
      expect(firstAnswer.unlockedAtUtcMs, earlier.millisecondsSinceEpoch);
    },
  );

  test('attempt replay compares provider provenance', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-provenance',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    final command = RecordAnswerCommand(
      id: 'attempt-provenance',
      ownerId: 'owner-1',
      sessionId: 'session-provenance',
      wordId: 'word-1',
      promptMode: 'pronunciation',
      isCorrect: true,
      responseTimeMs: 400,
      attemptNumber: 1,
      occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      providerProvenance: 'device-stt',
    );
    await repository.recordAnswer(command);

    await expectLater(
      repository.recordAnswer(
        RecordAnswerCommand(
          id: command.id,
          ownerId: command.ownerId,
          sessionId: command.sessionId,
          wordId: command.wordId,
          promptMode: command.promptMode,
          isCorrect: command.isCorrect,
          responseTimeMs: command.responseTimeMs,
          attemptNumber: command.attemptNumber,
          occurredAtUtc: command.occurredAtUtc,
          providerProvenance: 'cloud-stt',
        ),
      ),
      throwsStateError,
    );
  });

  test('typed ordinary evidence persists unchanged through replay', () async {
    await repository.startSession(
      LearningSessionDraft(
        id: 'session-context',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: DateTime.utc(2026, 7, 30, 10),
        appVersion: '1.0.0',
        buildId: 'test',
      ),
    );
    final context = captureCurrentActivityEvidence(
      promptMode: 'meaningChoice',
      contentRevision: 'local-vocabulary-v1:1',
    );
    RecordAnswerCommand command(EvidenceContext evidence) =>
        RecordAnswerCommand(
          id: 'attempt-context',
          ownerId: 'owner-1',
          sessionId: 'session-context',
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 400,
          attemptNumber: 1,
          occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
          evidenceContext: evidence,
        );

    final first = await repository.recordAnswer(command(context));
    final replay = await repository.recordAnswer(command(context));
    expect(first.inserted, isTrue);
    expect(replay.inserted, isFalse);
    await database.customStatement(
      'UPDATE answer_attempts SET evidence_context_json = ? WHERE id = ?',
      [
        jsonEncode(Map.fromEntries(context.toJson().entries.toList().reversed)),
        'attempt-context',
      ],
    );
    expect(
      (await repository.recordAnswer(command(context))).inserted,
      isFalse,
      reason: 'JSON object key order does not change an immutable fact.',
    );
    final stored = await database.select(database.answerAttempts).getSingle();
    expect(stored.evidenceClass, 'recognition');
    expect(jsonDecode(stored.evidenceContextJson), context.toJson());
    final outbox = await database.select(database.outboxOperations).get();
    expect(
      outbox
          .singleWhere((operation) => operation.entityType == 'attempt')
          .payloadVersion,
      2,
    );
    expect(
      outbox
          .singleWhere((operation) => operation.entityType == 'srsState')
          .payloadVersion,
      1,
    );
    expect(
      replay.srs!.intervalDays,
      1,
      reason:
          'This migration records metadata without activating projection policy.',
    );

    for (final changed in [
      captureCurrentActivityEvidence(
        promptMode: 'meaningChoice',
        contentRevision: 'local-vocabulary-v1:2',
      ),
      captureCurrentActivityEvidence(
        promptMode: 'meaningChoice',
        contentRevision: 'local-vocabulary-v1:1',
        hintLevel: 1,
      ),
    ]) {
      await expectLater(
        repository.recordAnswer(command(changed)),
        throwsStateError,
      );
    }
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(
      await database.select(database.pointsLedgerEntries).get(),
      hasLength(1),
    );
    expect(
      await database.select(database.rewardTransactions).get(),
      hasLength(1),
    );
    expect(
      (await database.select(database.answerAttempts).getSingle()).toJson(),
      stored.toJson(),
    );
  });

  test(
    'ordinary record boundary rejects research pins without collecting rows',
    () async {
      final context = EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.recognition,
        skillId: 'meaning-recall',
        hintLevel: 0,
        contentRevision: 'local-vocabulary-v1:1',
        rolloutMode: EvidencePolicyRolloutMode.legacy,
        protocolId: 'synthetic-protocol',
      );
      final command = RecordAnswerCommand(
        id: 'attempt-forbidden-research',
        ownerId: 'owner-1',
        sessionId: 'absent-session',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
        evidenceContext: context,
      );
      expect(() => repository.recordAnswer(command), throwsArgumentError);
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test(
    'invalid cloud-contract evidence is rejected before local commit',
    () async {
      await repository.startSession(
        LearningSessionDraft(
          id: 'session-limits',
          ownerId: 'owner-1',
          activityType: 'quiz',
          startedAtUtc: DateTime.utc(2026, 7, 30, 10),
          appVersion: '1.0.0',
          buildId: 'test',
        ),
      );
      final base = RecordAnswerCommand(
        id: 'attempt-limits',
        ownerId: 'owner-1',
        sessionId: 'session-limits',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      );

      for (final invalid in [
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: 'x' * 61,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: 2147483648,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: 1000001,
          occurredAtUtc: base.occurredAtUtc,
        ),
        RecordAnswerCommand(
          id: base.id,
          ownerId: base.ownerId,
          sessionId: base.sessionId,
          wordId: base.wordId,
          promptMode: base.promptMode,
          isCorrect: base.isCorrect,
          responseTimeMs: base.responseTimeMs,
          attemptNumber: base.attemptNumber,
          occurredAtUtc: base.occurredAtUtc,
          providerProvenance: 'p' * 121,
        ),
      ]) {
        expect(() => repository.recordAnswer(invalid), throwsArgumentError);
      }

      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('reading progress is monotonic and completion is idempotent', () async {
    final first = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-1',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 80,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10),
      ),
    );
    final rewound = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-2',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 30,
        isCompleted: false,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 1),
      ),
    );
    final completed = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );
    final replay = await repository.saveReadingProgress(
      ReadingProgressCommand(
        eventId: 'reading-3',
        ownerId: 'owner-1',
        documentId: 'doc-1',
        documentRevision: 1,
        position: 100,
        isCompleted: true,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 10, 2),
      ),
    );

    expect(first.lastPosition, 80);
    expect(rewound.lastPosition, 80);
    expect(completed.isCompleted, isTrue);
    expect(replay, completed);
    expect(await database.select(database.readingEvents).get(), hasLength(3));
    final readingOutbox = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('readingEvent'))).get();
    expect(readingOutbox, hasLength(3));
  });

  test('reading progress rejects an owner that is no longer active', () async {
    await database.customUpdate(
      "UPDATE local_owners SET is_active = 0 WHERE id = 'owner-1'",
      updates: {database.localOwners},
    );
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2));

    await expectLater(
      repository.saveReadingProgress(
        ReadingProgressCommand(
          eventId: 'reading-stale-owner',
          ownerId: 'owner-1',
          documentId: 'doc-1',
          documentRevision: 1,
          position: 2,
          isCompleted: false,
          occurredAtUtc: DateTime.utc(2026, 10, 21),
        ),
      ),
      throwsStateError,
    );
    expect(await database.select(database.readingEvents).get(), isEmpty);
    expect(
      await database.select(database.readingProgressEntries).get(),
      isEmpty,
    );
    expect(await database.select(database.outboxOperations).get(), isEmpty);
  });
}
