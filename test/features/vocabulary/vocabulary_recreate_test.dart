import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';

void main() {
  late AppDatabase database;
  late VocabularyUseCases vocabulary;
  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    var nextId = 0;
    vocabulary = VocabularyUseCases(
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'synthetic-owner',
        nowUtc: () => DateTime.utc(2026),
      ),
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'synthetic-${++nextId}',
      nowUtc: () => DateTime.utc(2026),
    );
  });
  tearDown(() => database.close());
  test(
    'a learner can create a category with a previously deleted name',
    () async {
      final first = await vocabulary.createCategory('Travel');
      await vocabulary.createWord(
        CreateWordCommand(
          categoryId: first.id,
          spelling: 'station',
          meaning: 'synthetic meaning',
          partOfSpeech: 'noun',
        ),
      );
      await vocabulary.deleteCategory(first.id);
      expect(await vocabulary.watchCategories().first, isEmpty);
      final restored = await vocabulary.createCategory('Travel');
      expect(restored.id, first.id);
      expect(restored.localRevision, 3);
      expect((await vocabulary.watchCategories().first).single.name, 'Travel');
      expect(await vocabulary.watchWords(first.id).first, isEmpty);
    },
  );
  test('a learner can add a previously deleted word again', () async {
    final category = await vocabulary.createCategory('Travel');
    final command = CreateWordCommand(
      categoryId: category.id,
      spelling: 'station',
      meaning: 'synthetic meaning',
      partOfSpeech: 'noun',
    );
    final word = await vocabulary.createWord(command);
    await vocabulary.deleteWord(word.id);
    expect(await vocabulary.watchWords(category.id).first, isEmpty);
    final restored = await vocabulary.createWord(command);
    expect(restored.id, word.id);
    expect(restored.localRevision, 3);
    expect(
      (await vocabulary.watchWords(category.id).first).single.spelling,
      'station',
    );
    final operations = await database.select(database.outboxOperations).get();
    expect(
      operations
          .where((row) => row.entityId == word.id)
          .map((row) => row.operationId),
      ['word:${word.id}:1', 'word:${word.id}:2', 'word:${word.id}:3'],
    );
  });
}
