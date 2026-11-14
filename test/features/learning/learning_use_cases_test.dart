import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

void main() {
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

  for (final activity in ['weakness', 'source']) {
    Future<QuizSession> targeted(
      QuizPromptKind kind,
      List<String> ids, {
      int limit = 20,
      String? owner,
    }) => activity == 'weakness'
        ? useCases.startWeaknessPractice(
            wordIds: ids,
            kind: kind,
            limit: limit,
            expectedOwnerId: owner,
          )
        : useCases.startSourcePracticeForWords(
            wordIds: ids,
            kind: kind,
            limit: limit,
            expectedOwnerId: owner,
          );

    test(
      '$activity retains reverse kind and target while drawing real options',
      () async {
        final session = await targeted(QuizPromptKind.spellingChoice, [
          'word-3',
        ]);
        final q = session.questions.single;
        expect(q.word.id, 'word-3');
        expect(q.kind, QuizPromptKind.spellingChoice);
        expect(q.promptText, 'ชานชาลา');
        expect(q.correctAnswer, 'platform');
        expect(q.optionWords!['ticket']!.id, 'word-2');
      },
    );

    test(
      '$activity retains definition kind for the requested target only',
      () async {
        final session = await targeted(QuizPromptKind.definitionChoice, [
          'word-3',
        ]);
        final q = session.questions.single;
        expect(q.word.id, 'word-3');
        expect(q.kind, QuizPromptKind.definitionChoice);
        expect(q.optionWords!['ticket']!.id, 'word-2');
        expect(q.correctAnswer, 'platform');
      },
    );

    test(
      '$activity rejects unsupported target without creating a session',
      () async {
        final session = await targeted(QuizPromptKind.definitionChoice, [
          'word-2',
        ]);
        expect(session.isEmpty, isTrue);
        expect(await database.select(database.learningSessions).get(), isEmpty);
      },
    );

    test(
      '$activity definition never substitutes a different category target',
      () async {
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: 'category-2',
                ownerId: 'local:guest',
                name: 'Other',
                normalizedName: 'other',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final row in const [
          ('other-p', 'platform', 'ชานชาลา'),
          ('other-t', 'ticket', 'ตั๋ว'),
        ]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: row.$1,
                  ownerId: 'local:guest',
                  categoryId: 'category-2',
                  spelling: row.$2,
                  normalizedSpelling: row.$2,
                  meaning: row.$3,
                  normalizedMeaning: row.$3,
                  partOfSpeech: 'noun',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
        final session = await targeted(QuizPromptKind.definitionChoice, [
          'word-3',
        ], limit: 1);
        expect(session.questions.single.word.id, 'word-3');
        expect(session.questions.single.optionWords!['ticket']!.id, 'word-2');
      },
    );

    test(
      '$activity considers requested eligible target beyond first 100 before limiting',
      () async {
        for (var i = 0; i < 101; i++) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: 'a-$i',
                  ownerId: 'local:guest',
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
        final ids = [for (var i = 0; i < 101; i++) 'a-$i', 'word-3'];
        final session = await targeted(
          QuizPromptKind.definitionChoice,
          ids,
          limit: 1,
        );
        expect(session.questions.single.word.id, 'word-3');
        expect(session.questions.single.kind, QuizPromptKind.definitionChoice);
      },
    );
  }

  test(
    'reverse quiz rejects a same-meaning collision beyond its first 100 rows',
    () async {
      for (var i = 0; i < 96; i++) {
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'zz-$i',
                ownerId: 'local:guest',
                categoryId: 'category-1',
                spelling: 'extra$i',
                normalizedSpelling: 'extra$i',
                meaning: 'คำ $i',
                normalizedMeaning: 'คำ $i',
                partOfSpeech: 'noun',
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
      }
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'zzz-conflict',
              ownerId: 'local:guest',
              categoryId: 'category-1',
              spelling: 'depot',
              normalizedSpelling: 'depot',
              meaning: 'สถานี',
              normalizedMeaning: 'สถานี',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      final quiz = await useCases.startQuiz(
        categoryId: 'category-1',
        kind: QuizPromptKind.spellingChoice,
        limit: 1,
      );
      expect(quiz.questions.single.word.id, 'word-2');
    },
  );

  test(
    'definition without category never hides a late same-category sense collision',
    () async {
      for (var i = 0; i < 50; i++) {
        final category = 'synthetic-cat-$i';
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: category,
                ownerId: 'local:guest',
                name: category,
                normalizedName: category,
                createdAtUtcMs: 1,
                updatedAtUtcMs: 1,
              ),
            );
        for (final pair in [('platform', 'ชานชาลา'), ('ticket', 'ตั๋ว')]) {
          await database
              .into(database.vocabularyWords)
              .insert(
                VocabularyWordsCompanion.insert(
                  id: 'a-$i-${pair.$1}',
                  ownerId: 'local:guest',
                  categoryId: category,
                  spelling: pair.$1,
                  normalizedSpelling: pair.$1,
                  meaning: pair.$2,
                  normalizedMeaning: pair.$2,
                  partOfSpeech: 'noun',
                  createdAtUtcMs: 1,
                  updatedAtUtcMs: 1,
                ),
              );
        }
      }
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'z-conflict',
              ownerId: 'local:guest',
              categoryId: 'synthetic-cat-0',
              spelling: 'platform',
              normalizedSpelling: 'platform',
              meaning: 'เวที',
              normalizedMeaning: 'เวที',
              partOfSpeech: 'noun',
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
      final quiz = await useCases.startQuiz(
        kind: QuizPromptKind.definitionChoice,
        limit: 1,
      );
      expect(quiz.questions.single.word.categoryId, isNot('synthetic-cat-0'));
    },
  );

  test(
    'reverse quiz keeps real word IDs and asks for English from Thai',
    () async {
      final session = await useCases.startQuiz(
        categoryId: 'category-1',
        kind: QuizPromptKind.spellingChoice,
        limit: 4,
      );
      expect(session.questions, hasLength(4));
      for (final question in session.questions) {
        expect(question.kind, QuizPromptKind.spellingChoice);
        expect(question.promptText, question.word.meaning);
        expect(question.correctAnswer, question.word.spelling);
        expect(question.options, contains(question.word.spelling));
        expect(
          question.optionWords?[question.correctAnswer]?.id,
          question.word.id,
        );
      }
    },
  );

  test(
    'definition quiz binds the approved travel sense to the actual word',
    () async {
      final session = await useCases.startQuiz(
        categoryId: 'category-1',
        kind: QuizPromptKind.definitionChoice,
        limit: 1,
      );
      final question = session.questions.single;
      expect(question.kind, QuizPromptKind.definitionChoice);
      expect(question.word.id, 'word-3');
      expect(
        question.promptText,
        'The place at a train station where you wait to get on a train.',
      );
      expect(question.correctAnswer, 'platform');
      expect(question.options.toSet(), {'platform', 'ticket'});
      expect(question.optionWords?['ticket']?.id, 'word-2');
    },
  );

  test(
    'unsupported definition sense creates no dangling learning session',
    () async {
      await (database.update(
        database.vocabularyWords,
      )..where((w) => w.id.equals('word-3'))).write(
        const VocabularyWordsCompanion(
          meaning: Value('เวที'),
          normalizedMeaning: Value('เวที'),
        ),
      );
      final session = await useCases.startQuiz(
        categoryId: 'category-1',
        kind: QuizPromptKind.definitionChoice,
      );
      expect(session.isEmpty, isTrue);
      expect(await database.select(database.learningSessions).get(), isEmpty);
    },
  );

  test(
    'definition pair beyond 100 unrelated rows remains eligible before target limit',
    () async {
      for (var i = 0; i < 101; i++) {
        await database
            .into(database.vocabularyWords)
            .insert(
              VocabularyWordsCompanion.insert(
                id: 'a-$i',
                ownerId: 'local:guest',
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
      final session = await useCases.startQuiz(
        categoryId: 'category-1',
        kind: QuizPromptKind.definitionChoice,
        limit: 1,
      );
      expect(session.questions.single.word.id, 'word-3');
      expect(session.questions.single.options.toSet(), {'platform', 'ticket'});
    },
  );

  Future<void> mergeGuestIntoOtherOwner() async {
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'local:target',
            firebaseUid: const Value('synthetic-target-uid'),
            accountState: const Value('firebaseBound'),
            isActive: const Value(false),
            createdAtUtcMs: 1,
          ),
        );
    final result =
        await DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => now,
          generateConflictId: () => 'synthetic-conflict-${++nextId}',
          generateOwnerId: () => 'synthetic-owner-${++nextId}',
        ).upgrade(
          activeOwnerId: 'local:guest',
          firebaseUid: 'synthetic-target-uid',
        );
    expect(result.targetOwnerId, 'local:target');
    expect(
      (await database.select(database.vocabularyWords).get()).every(
        (w) => w.ownerId == 'local:target',
      ),
      isTrue,
    );
  }

  test('weakness original owner is fenced after target IDs rehome', () async {
    await mergeGuestIntoOtherOwner();
    await expectLater(
      useCases.startWeaknessPractice(
        wordIds: ['word-3'],
        kind: QuizPromptKind.spellingChoice,
        expectedOwnerId: 'local:guest',
      ),
      throwsStateError,
    );
    expect(await database.select(database.learningSessions).get(), isEmpty);
  });

  for (final activity in ['quiz', 'due', 'source']) {
    test(
      '$activity rejects its original owner after IDs rehome during upgrade',
      () async {
        await mergeGuestIntoOtherOwner();
        final load = switch (activity) {
          'quiz' => useCases.startQuiz(expectedOwnerId: 'local:guest'),
          'due' => useCases.startDueReview(expectedOwnerId: 'local:guest'),
          _ => useCases.startSourcePracticeForWords(
            wordIds: ['word-1'],
            expectedOwnerId: 'local:guest',
          ),
        };
        await expectLater(load, throwsStateError);
        expect(await database.select(database.learningSessions).get(), isEmpty);
      },
    );
  }

  test(
    'a stale answer cannot become the new owners answer after rehome',
    () async {
      final session = await useCases.startQuiz(limit: 1);
      await mergeGuestIntoOtherOwner();
      await expectLater(
        useCases.recordAnswer(
          sessionId: session.id,
          wordId: session.questions.single.word.id,
          promptMode: 'srsRecall',
          isCorrect: true,
          responseTimeMs: 10,
          attemptNumber: 1,
          expectedOwnerId: 'local:guest',
        ),
        throwsStateError,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.srsStates).get(), isEmpty);
    },
  );

  test(
    'a stale finish cannot complete the new owners rehomed session',
    () async {
      final session = await useCases.startQuiz(limit: 1);
      await mergeGuestIntoOtherOwner();
      await expectLater(
        useCases.finishSession(session.id, expectedOwnerId: 'local:guest'),
        throwsStateError,
      );
      expect(
        (await database.select(database.learningSessions).getSingle()).state,
        'active',
      );
      expect(await database.select(database.achievementUnlocks).get(), isEmpty);
    },
  );

  test(
    'quiz option formula counts distinct meanings rather than word rows',
    () async {
      final single = await useCases.startQuiz(
        categoryId: 'category-1',
        limit: 1,
      );
      expect(single.questions.single.options, hasLength(1));
      await database
          .update(database.vocabularyWords)
          .write(const VocabularyWordsCompanion(meaning: Value('สถานี')));
      final duplicateMeanings = await useCases.startQuiz(
        categoryId: 'category-1',
        limit: 4,
      );
      expect(duplicateMeanings.questions, hasLength(4));
      expect(
        duplicateMeanings.questions.every(
          (question) => question.options.toSet().length == 1,
        ),
        isTrue,
      );
      await (database.update(database.vocabularyWords)
            ..where((word) => word.id.equals('word-2')))
          .write(const VocabularyWordsCompanion(meaning: Value('ตั๋ว')));
      final contrast = await useCases.startQuiz(
        categoryId: 'category-1',
        limit: 4,
      );
      expect(
        contrast.questions.every(
          (question) => question.options.toSet().length == 2,
        ),
        isTrue,
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.srsStates).get(), isEmpty);
      expect(
        (await database.select(database.learningSessions).get()).every(
          (session) => session.state == 'active',
        ),
        isTrue,
      );
    },
  );

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
      final quiz = await useCases.startQuiz(categoryId: 'category-1', limit: 2);
      now = now.add(const Duration(seconds: 2));
      await useCases.recordAnswer(
        sessionId: quiz.id,
        wordId: quiz.questions.first.word.id,
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 2000,
        attemptNumber: 1,
      );
      now = now.add(const Duration(seconds: 1));
      final summary = await useCases.finishSession(quiz.id);

      expect(summary.correctCount, 1);
      expect(summary.wrongCount, 0);
      expect(summary.score, 100);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
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
      Future<void> submit() async {
        await useCases.recordAnswer(
          sessionId: session.id,
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 42,
          attemptNumber: 1,
          attemptId: 'attempt:synthetic-retry',
          occurredAtUtc: submittedAt,
        );
      }

      await submit();
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

  test('committed-answer signal retains original identity on replay', () async {
    final observed = <(String, String, int)>[];
    final original = now.add(const Duration(microseconds: 123));
    final learning = LearningUseCases(
      owners: useCases.owners,
      repository: useCases.repository,
      generateId: useCases.generateId,
      nowUtc: () => now,
      buildInfo: useCases.buildInfo,
      onAnswerCommitted:
          ({
            required ownerId,
            required attemptId,
            required occurredAtUtcMs,
          }) async {
            final row = await (database.select(
              database.answerAttempts,
            )..where((row) => row.id.equals(attemptId))).getSingle();
            expect(
              (row.ownerId, row.occurredAtUtcMs),
              (ownerId, occurredAtUtcMs),
            );
            observed.add((ownerId, attemptId, occurredAtUtcMs));
          },
    );
    final session = await learning.startQuiz(limit: 1);
    Future<void> submit() => learning.recordAnswer(
      sessionId: session.id,
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: false,
      responseTimeMs: 42,
      attemptNumber: 1,
      attemptId: 'attempt:original-signal',
      occurredAtUtc: original,
    );
    await submit();
    now = now.add(const Duration(days: 2));
    await submit();
    expect(observed, [
      (
        'local:guest',
        'attempt:original-signal',
        original.millisecondsSinceEpoch,
      ),
      (
        'local:guest',
        'attempt:original-signal',
        original.millisecondsSinceEpoch,
      ),
    ]);
    expect(await database.select(database.answerAttempts).get(), hasLength(1));
    expect(await database.select(database.srsStates).get(), hasLength(1));
    expect(await database.select(database.eventsV2).get(), isEmpty);
  });

  test(
    'failed committed-answer signal preserves learning and permits repair',
    () async {
      var signals = 0;
      final original = now;
      final learning = LearningUseCases(
        owners: useCases.owners,
        repository: useCases.repository,
        generateId: useCases.generateId,
        nowUtc: () => now,
        buildInfo: useCases.buildInfo,
        onAnswerCommitted:
            ({
              required ownerId,
              required attemptId,
              required occurredAtUtcMs,
            }) async {
              signals++;
              if (signals == 1) {
                throw StateError('synthetic settlement failure');
              }
            },
      );
      final session = await learning.startQuiz(limit: 1);
      Future<void> submit() => learning.recordAnswer(
        sessionId: session.id,
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 42,
        attemptNumber: 1,
        attemptId: 'attempt:repair-signal',
        occurredAtUtc: original,
      );
      await submit();
      expect(signals, 1);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        (await database.select(database.pointsLedgerEntries).getSingle())
            .amount,
        1,
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      await submit();
      expect(signals, 2);
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
      expect(await database.select(database.researchConsents).get(), isEmpty);
      expect(await database.select(database.eventsV2).get(), isEmpty);
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
