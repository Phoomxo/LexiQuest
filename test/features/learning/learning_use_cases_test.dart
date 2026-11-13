import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
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
