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
}
