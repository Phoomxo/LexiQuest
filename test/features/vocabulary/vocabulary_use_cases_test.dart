import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';

void main() {
  late AppDatabase database;
  late VocabularyUseCases useCases;
  late DateTime nowUtc;
  late int idCounter;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    nowUtc = DateTime.utc(2026, 7, 30, 11);
    idCounter = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => nowUtc,
    );
    useCases = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'id-${++idCounter}',
      nowUtc: () => nowUtc,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'create commands normalize text and propagate stable ownership',
    () async {
      final category = await useCases.createCategory('  Travel   Plans ');
      final word = await useCases.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: '  Train   Station ',
          meaning: '  สถานี รถไฟ ',
          partOfSpeech: ' noun ',
        ),
      );

      expect(category.id, 'category:id-1');
      expect(category.ownerId, 'local:guest');
      expect(category.name, 'Travel Plans');
      expect(category.normalizedName, 'travel plans');
      expect(word.id, 'word:id-2');
      expect(word.ownerId, category.ownerId);
      expect(word.spelling, 'Train Station');
      expect(word.normalizedSpelling, 'train station');
      expect(word.meaning, 'สถานี รถไฟ');
      expect(word.partOfSpeech, 'noun');
    },
  );

  test('watchers resolve the active owner and emit local changes', () async {
    final categories = useCases.watchCategories().firstWhere(
      (items) => items.isNotEmpty,
    );

    await useCases.createCategory('Travel');

    expect((await categories).single.name, 'Travel');
  });

  test('blank and oversized fields fail before database mutation', () async {
    await expectLater(
      useCases.createCategory('   '),
      throwsA(isA<InvalidVocabularyFailure>()),
    );
    await expectLater(
      useCases.createCategory(List.filled(81, 'x').join()),
      throwsA(isA<InvalidVocabularyFailure>()),
    );
    final category = await useCases.createCategory('Travel');
    await expectLater(
      useCases.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: '',
          meaning: 'meaning',
          partOfSpeech: 'noun',
        ),
      ),
      throwsA(isA<InvalidVocabularyFailure>()),
    );
    await expectLater(
      useCases.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'word',
          meaning: List.filled(501, 'x').join(),
          partOfSpeech: 'noun',
        ),
      ),
      throwsA(isA<InvalidVocabularyFailure>()),
    );

    expect(await database.select(database.vocabularyWords).get(), isEmpty);
  });

  test('non-UTC application clocks fail closed', () async {
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest-local-time',
      nowUtc: () => DateTime(2026, 7, 30),
    );
    final localClockUseCases = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'category-local-time',
      nowUtc: () => DateTime(2026, 7, 30),
    );

    await expectLater(
      localClockUseCases.createCategory('Travel'),
      throwsArgumentError,
    );
  });

  test('rename and delete commands remain owner scoped', () async {
    final category = await useCases.createCategory('Travel');
    final renamed = await useCases.renameCategory(category.id, 'Trips');

    expect(renamed.name, 'Trips');
    expect(renamed.localRevision, 2);

    await useCases.deleteCategory(category.id);
    expect(await useCases.watchCategories().first, isEmpty);
  });
}
