import 'dart:convert';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/dictation_session_harness.dart';

void main() {
  group('owned Dictation', () {
    late DictationSessionHarness h;
    setUp(() async => h = await DictationSessionHarness.open());
    tearDown(() => h.close());

    test(
      'prepares one actual category word without creating a session',
      () async {
        final session = await h.learning.prepareDictation(
          categoryId: configuredCategoryId,
          stillCurrent: () => h.current,
        );
        expect(session, isNotNull);
        expect(session!.ownerId, configuredOwnerId);
        expect(session.word.categoryId, configuredCategoryId);
        expect(session.evidenceContentRevision, 'local-vocabulary-v1:1');
        expect(session.session.activityType, 'dictation');
        expect(
          await h.database.select(h.database.learningSessions).get(),
          isEmpty,
        );
      },
    );

    test(
      'empty category and invalidated preparation create no session',
      () async {
        expect(
          await h.learning.prepareDictation(
            categoryId: 'missing-category',
            stillCurrent: () => true,
          ),
          isNull,
        );
        await expectLater(
          h.learning.prepareDictation(
            categoryId: configuredCategoryId,
            stillCurrent: () => false,
          ),
          throwsStateError,
        );
        expect(
          await h.database.select(h.database.learningSessions).get(),
          isEmpty,
        );
      },
    );

    test(
      'pending answer freezes normalized correctness, pins, ID and time',
      () async {
        final session = await h.ready();
        final capturedAt = h.now;
        final command = h.answer(session, assisted: true);
        h.now = h.now.add(const Duration(hours: 1));
        expect(command.ownerId, session.ownerId);
        expect(command.sessionId, session.id);
        expect(command.wordId, session.word.id);
        expect(command.isCorrect, isTrue);
        expect(command.occurredAtUtc, capturedAt);
        expect(command.responseTimeMs, 1234);
        expect(command.attemptNumber, 1);
        expect(
          command.evidenceContext.contentRevision,
          session.evidenceContentRevision,
        );
        expect(command.evidenceContext.hintLevel, 1);
        expect(command.providerProvenance, isNull);
      },
    );

    test(
      'normal Dictation gets SRS but no motivation hooks or session awards',
      () async {
        final session = await h.ready();
        final command = h.answer(session);
        final saved = await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => h.current,
        );
        expect(saved.inserted, isTrue);
        expect(saved.srs, isNotNull);
        final finish = h.learning.prepareNativeFinish(session, command);
        final summary = await h.learning.finishNativeExercise(
          finish,
          stillCurrent: () => h.current,
        );
        expect(summary.correctCount, 1);
        expect(summary.score, 100);
        expect(h.questEvents, 0);
        expect(h.streakEvents, 0);
        expect(
          await h.database.select(h.database.pointsLedgerEntries).get(),
          isEmpty,
        );
        expect(
          await h.database.select(h.database.achievementUnlocks).get(),
          isEmpty,
        );
        final operations = await h.database
            .select(h.database.outboxOperations)
            .get();
        expect(
          operations.map((op) => (op.entityType, op.payloadVersion)),
          unorderedEquals([('attempt', 2), ('srsState', 1)]),
        );
      },
    );

    for (final correct in [true, false]) {
      test(
        'assisted $correct retains one outcome without SRS or rewards',
        () async {
          final session = await h.ready();
          final command = h.answer(session, assisted: true, correct: correct);
          final saved = await h.learning.commitNativeAnswer(
            session,
            command,
            stillCurrent: () => h.current,
          );
          expect(saved.inserted, isTrue);
          expect(saved.srs, isNull);
          final finish = h.learning.prepareNativeFinish(session, command);
          final summary = await h.learning.finishNativeExercise(
            finish,
            stillCurrent: () => h.current,
          );
          expect(summary.correctCount, correct ? 1 : 0);
          expect(summary.wrongCount, correct ? 0 : 1);
          expect(
            await h.database.select(h.database.answerAttempts).get(),
            hasLength(1),
          );
          expect(await h.database.select(h.database.srsStates).get(), isEmpty);
          expect(
            await h.database.select(h.database.pointsLedgerEntries).get(),
            isEmpty,
          );
          expect(
            await h.database.select(h.database.achievementUnlocks).get(),
            isEmpty,
          );
          expect(h.questEvents, 0);
          expect(h.streakEvents, 0);
          final operations = await h.database
              .select(h.database.outboxOperations)
              .get();
          expect(
            operations.map(
              (op) => (op.entityType, op.entityId, op.payloadVersion),
            ),
            [('attempt', command.id, 2)],
          );
        },
      );
    }

    test(
      'same start, answer and close intents replay original immutable facts',
      () async {
        final session = await h.ready();
        final command = h.answer(session, assisted: true);
        await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        );
        final closing = h.learning.prepareNativeFinish(session, command);
        await h.learning.finishNativeExercise(
          closing,
          stillCurrent: () => true,
        );
        final before = await h.database
            .customSelect(
              'SELECT started_at_utc_ms,ended_at_utc_ms,correct_count,wrong_count,score '
              'FROM learning_sessions WHERE id = ?',
              variables: [Variable(session.id)],
            )
            .getSingle();
        final hooks = (h.notifications, h.questEvents, h.streakEvents);
        h.now = h.now.add(const Duration(days: 1));
        expect(
          await h.learning.startNativeExercise(
            session,
            stillCurrent: () => true,
          ),
          same(session),
        );
        final replay = await h.learning.commitNativeAnswer(
          session,
          command,
          stillCurrent: () => true,
        );
        expect(replay.inserted, isFalse);
        await h.learning.finishNativeExercise(
          closing,
          stillCurrent: () => true,
        );
        final after = await h.database
            .customSelect(
              'SELECT started_at_utc_ms,ended_at_utc_ms,correct_count,wrong_count,score '
              'FROM learning_sessions WHERE id = ?',
              variables: [Variable(session.id)],
            )
            .getSingle();
        expect(after.data, before.data);
        expect((h.notifications, h.questEvents, h.streakEvents), hooks);
        expect(
          await h.database.select(h.database.answerAttempts).get(),
          hasLength(1),
        );
        expect(
          await h.database.select(h.database.outboxOperations).get(),
          hasLength(1),
        );
      },
    );
  });

  late AppDatabase database;
  late LearningUseCases useCases;
  late DateTime now;
  late int nextId;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    now = DateTime.utc(2026, 7, 30, 9);
    nextId = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: owner.id,
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final word in const [
      ('word-1', 'station', 'สถานี'),
      ('word-2', 'ticket', 'ตั๋ว'),
      ('word-3', 'platform', 'ชานชาลา'),
      ('word-4', 'journey', 'การเดินทาง'),
    ]) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: word.$1,
              ownerId: owner.id,
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
    useCases = LearningUseCases(
      owners: owners,
      repository: DriftLearningRepository(database),
      generateId: () => '${++nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.2.3', buildId: 'test-build'),
    );
  });

  tearDown(() => database.close());

  test(
    'starts quiz from local words with deterministic unique options',
    () async {
      final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 4);

      expect(quiz.id, 'session:1');
      expect(quiz.questions, hasLength(4));
      expect(quiz.questions.first.options.toSet(), hasLength(4));
      expect(
        quiz.questions.first.options,
        contains(quiz.questions.first.correctAnswer),
      );
      final stored = await database
          .select(database.learningSessions)
          .getSingle();
      expect(stored.appVersion, '1.2.3');
      expect(stored.buildId, 'test-build');
    },
  );

  test('starts associative reading with durable vocabulary evidence', () async {
    final session = await useCases.startReading(limit: 2);

    expect(session.questions, hasLength(2));
    final stored = await database.select(database.learningSessions).getSingle();
    expect(stored.activityType, 'associativeReading');
  });

  test(
    'records answers and finishes a session from durable evidence',
    () async {
      final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 1);
      now = now.add(const Duration(seconds: 2));
      final configured = quiz.configured!;
      final question = quiz.questions.single;
      final pending = await useCases.prepareQuizAnswer(
        sessionId: quiz.id,
        expectedOwnerId: configured.ownerId,
        expectedRevision: configured.checkpointRevision,
        selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
        responseTimeMs: 2000,
      );
      final answer = await useCases.commitQuizAnswer(
        sessionId: quiz.id,
        expectedOwnerId: configured.ownerId,
        expectedRevision: pending.checkpointRevision,
      );
      now = now.add(const Duration(seconds: 1));
      final closing = await useCases.prepareQuizFinish(
        sessionId: quiz.id,
        expectedOwnerId: configured.ownerId,
        expectedRevision: answer.state.checkpointRevision,
      );
      final summary = (await useCases.finishConfiguredQuiz(
        sessionId: quiz.id,
        expectedOwnerId: configured.ownerId,
        expectedRevision: closing.checkpointRevision,
      )).summary;

      expect(summary.correctCount, 1);
      expect(summary.wrongCount, 0);
      expect(summary.score, 100);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  test(
    'legacy answer capture keeps the revision shown before a vocabulary edit',
    () async {
      final word = (await useCases.prepareReading(limit: 1)).single;
      final owner = await useCases.owners.getOrCreateActiveOwner();
      await useCases.repository.startSession(
        LearningSessionDraft(
          id: 'legacy-quiz',
          ownerId: owner.id,
          activityType: 'quiz',
          startedAtUtc: now,
          appVersion: 'legacy-test',
          buildId: 'legacy-test',
        ),
      );
      final context = captureCurrentActivityEvidence(
        promptMode: 'meaningChoice',
        contentRevision: word.contentRevision,
      );
      await database.customStatement(
        "UPDATE vocabulary_words SET local_revision = 2 WHERE id = '${word.id}'",
      );
      await useCases.recordAnswer(
        sessionId: 'legacy-quiz',
        wordId: word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 400,
        attemptNumber: 1,
        evidenceContext: context,
      );

      final answer = await database.select(database.answerAttempts).getSingle();
      expect(word.contentRevision, 'local-vocabulary-v1:1');
      expect(jsonDecode(answer.evidenceContextJson), context.toJson());
      expect(
        (await useCases.prepareReading()).first.contentRevision,
        'local-vocabulary-v1:2',
      );
    },
  );

  test('empty local vocabulary returns an explicit empty quiz', () async {
    final quiz = await useCases.startQuiz(categoryId: 'missing', limit: 10);

    expect(quiz.questions, isEmpty);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test(
    'weakness practice selects only requested local evidence words',
    () async {
      final session = await useCases.startWeaknessPractice(
        wordIds: const ['word-3', 'word-1', 'missing'],
      );

      expect(session.questions.map((question) => question.word.id).toSet(), {
        'word-1',
        'word-3',
      });
      final stored = await database
          .select(database.learningSessions)
          .getSingle();
      expect(stored.activityType, 'weaknessPractice');
    },
  );

  test('weakness practice finds targets beyond the first 100 words', () async {
    final owner = await database.select(database.localOwners).getSingle();
    for (var i = 0; i < 101; i++) {
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'a-$i',
              ownerId: owner.id,
              categoryId: 'category-1',
              spelling: 'synthetic$i',
              normalizedSpelling: 'synthetic$i',
              meaning: 'คำสังเคราะห์ $i',
              normalizedMeaning: 'คำสังเคราะห์ $i',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    final session = await useCases.startWeaknessPractice(
      wordIds: ['word-3', 'word-3'],
      limit: 1,
    );
    expect(session.questions.map((q) => q.word.id), ['word-3']);
  });

  test('empty targeted practice creates no session', () async {
    final session = await useCases.startWeaknessPractice(wordIds: []);
    expect(session.isEmpty, isTrue);
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  test('ghost duel retains its own activity semantics', () async {
    await useCases.startGhostDuel(wordIds: ['word-1']);
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.activityType, 'ghostDuel');
  });

  test('source practice retains source activity semantics', () async {
    final result = await useCases.startSourcePracticeForWords(
      wordIds: ['word-2'],
    );

    expect(result.questions.map((question) => question.word.id), ['word-2']);
    final session = await database
        .select(database.learningSessions)
        .getSingle();
    expect(session.activityType, 'sourcePractice');
  });

  test(
    'single target still has distractors from the owner vocabulary',
    () async {
      final session = await useCases.startWeaknessPractice(wordIds: ['word-1']);
      expect(session.questions, hasLength(1));
      expect(session.questions.single.options, hasLength(4));
    },
  );

  test(
    'retry with the same submission does not duplicate evidence or points',
    () async {
      final session = await useCases.startQuiz(limit: 1);
      final submittedAt = now;
      final state = session.configured!;
      final question = session.questions.single;
      final pending = await useCases.prepareQuizAnswer(
        sessionId: session.id,
        expectedOwnerId: state.ownerId,
        expectedRevision: state.checkpointRevision,
        selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
        responseTimeMs: 42,
      );
      Future<void> submit() async {
        await useCases.commitQuizAnswer(
          sessionId: session.id,
          expectedOwnerId: state.ownerId,
          expectedRevision: pending.checkpointRevision,
        );
      }

      await submit();
      final recorded = await database
          .select(database.answerAttempts)
          .getSingle();
      expect(recorded.id, pending.checkpoint.answer!.attemptId);
      expect(recorded.occurredAtUtcMs, submittedAt.millisecondsSinceEpoch);
      now = now.add(const Duration(minutes: 1));
      await submit();
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
    },
  );

  test('reading use cases save and restore owner-scoped progress', () async {
    final empty = await useCases.loadReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
    );
    expect(empty, isNull);

    final saved = await useCases.saveReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
      position: 4,
      isCompleted: false,
    );
    final restored = await useCases.loadReadingProgress(
      documentId: 'article-1',
      documentRevision: 1,
    );

    expect(saved.lastPosition, 4);
    expect(restored, saved);
  });

  test('reading progress rejects a changed expected owner', () async {
    await database.customUpdate(
      'UPDATE local_owners SET is_active = 0 WHERE is_active = 1',
      updates: {database.localOwners},
    );
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'local:replacement',
            createdAtUtcMs: 2,
          ),
        );

    await expectLater(
      useCases.saveReadingProgress(
        documentId: 'article-1',
        documentRevision: 1,
        position: 2,
        isCompleted: false,
        expectedOwnerId: 'local:guest',
      ),
      throwsStateError,
    );
    expect(await database.select(database.readingEvents).get(), isEmpty);
  });
}
