import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  late AppDatabase database;
  late DriftLearningRepository learning;
  late DriftProgressQueries progress;
  final firstReview = DateTime.utc(2026, 7, 30);
  final now = DateTime.utc(2026, 10, 28);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    learning = DriftLearningRepository(database);
    progress = DriftProgressQueries(database);
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(id: 'synthetic-owner', createdAtUtcMs: 1),
        );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'synthetic-category',
            ownerId: 'synthetic-owner',
            name: 'Audit',
            normalizedName: 'audit',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'synthetic-word',
            ownerId: 'synthetic-owner',
            categoryId: 'synthetic-category',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'synthetic meaning',
            normalizedMeaning: 'synthetic meaning',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await learning.startSession(
      LearningSessionDraft(
        id: 'synthetic-session',
        ownerId: 'synthetic-owner',
        activityType: 'quiz',
        startedAtUtc: firstReview,
        appVersion: 'audit',
        buildId: '6500cbf3',
      ),
    );
  });

  tearDown(() => database.close());

  Future<void> recordReviews(int count) async {
    for (var index = 0; index < count; index++) {
      await learning.recordAnswer(
        RecordAnswerCommand(
          id: 'synthetic-attempt-$index',
          ownerId: 'synthetic-owner',
          sessionId: 'synthetic-session',
          wordId: 'synthetic-word',
          promptMode: 'srsRecall',
          isCorrect: true,
          responseTimeMs: 500,
          attemptNumber: index + 1,
          occurredAtUtc: firstReview.add(Duration(days: index * 15)),
        ),
      );
    }
  }

  Future<void> deleteWord() => DriftVocabularyRepository(database).deleteWord(
    ownerId: 'synthetic-owner',
    wordId: 'synthetic-word',
    nowUtc: now,
  );

  test(
    'deleted due word is absent from both due deck and due dashboard',
    () async {
      await recordReviews(1);
      final before = await progress.load(
        ownerId: 'synthetic-owner',
        nowUtc: now,
      );
      expect(before.dueReviewCount, 1);
      await deleteWord();
      expect(
        await learning.listDueWords(
          ownerId: 'synthetic-owner',
          nowUtc: now,
          limit: 20,
        ),
        isEmpty,
      );
      final after = await progress.load(
        ownerId: 'synthetic-owner',
        nowUtc: now,
      );
      expect(
        after.dueReviewCount,
        0,
        reason:
            'The dashboard must not recommend a word the due deck excludes.',
      );
    },
  );

  test(
    'deleted mastered word does not remain in the active mastery count',
    () async {
      await recordReviews(4);
      final before = await progress.load(
        ownerId: 'synthetic-owner',
        nowUtc: now,
      );
      expect(before.masteredWordCount, 1);
      await deleteWord();
      final after = await progress.load(
        ownerId: 'synthetic-owner',
        nowUtc: now,
      );
      expect(
        after.masteredWordCount,
        0,
        reason:
            'Historical attempts remain, but deleted vocabulary is not active.',
      );
    },
  );
}
