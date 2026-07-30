import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/application/import_vocabulary.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_import_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_import.dart';

void main() {
  late AppDatabase database;
  late VocabularyUseCases vocabulary;
  late ImportVocabulary importer;
  late DateTime nowUtc;
  late int idCounter;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    nowUtc = DateTime.utc(2026, 7, 30, 12);
    idCounter = 0;
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'guest',
      nowUtc: () => nowUtc,
    );
    vocabulary = VocabularyUseCases(
      owners: owners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: () => 'vocab-${++idCounter}',
      nowUtc: () => nowUtc,
    );
    importer = ImportVocabulary(
      owners: owners,
      repository: DriftVocabularyImportRepository(database),
      generateId: () => 'import-${++idCounter}',
      nowUtc: () => nowUtc,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test('empty import returns a stable zero-count result', () async {
    final category = await vocabulary.createCategory('Travel');

    final result = await importer(
      categoryId: category.id,
      rows: const [],
      sourceName: 'empty.csv',
    );

    expect(result.accepted, 0);
    expect(result.duplicates, 0);
    expect(result.rejected, isEmpty);
    expect(
      await database.select(database.vocabularyImports).get(),
      hasLength(1),
    );
  });

  test(
    'mixed rows persist accepted, duplicate, and rejected outcomes',
    () async {
      final category = await vocabulary.createCategory('Travel');

      final result = await importer(
        categoryId: category.id,
        sourceName: 'travel.csv',
        rows: const [
          {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
          {'word': ' station ', 'meaning': ' สถานี ', 'partOfSpeech': 'noun'},
          {'word': '', 'meaning': 'invalid', 'partOfSpeech': 'noun'},
        ],
      );

      expect(result.accepted, 1);
      expect(result.duplicates, 1);
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.rowNumber, 3);
      expect(await vocabulary.watchWords(category.id).first, hasLength(1));
    },
  );

  test(
    'replaying the same source returns stored results without new words',
    () async {
      final category = await vocabulary.createCategory('Travel');
      const rows = [
        {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
      ];

      final first = await importer(
        categoryId: category.id,
        sourceName: 'travel.csv',
        rows: rows,
      );
      final replay = await importer(
        categoryId: category.id,
        sourceName: 'travel.csv',
        rows: rows,
      );

      expect(replay.importId, first.importId);
      expect(replay.accepted, 1);
      expect(
        await database.select(database.vocabularyImports).get(),
        hasLength(1),
      );
      expect(await vocabulary.watchWords(category.id).first, hasLength(1));
    },
  );

  test(
    'capacity rejects rows beyond the 50 active-word category limit',
    () async {
      final category = await vocabulary.createCategory('Travel');
      final rows = List.generate(
        51,
        (index) => {
          'word': 'word $index',
          'meaning': 'meaning $index',
          'partOfSpeech': 'noun',
        },
      );

      final result = await importer(
        categoryId: category.id,
        sourceName: 'large.csv',
        rows: rows,
      );

      expect(result.accepted, 50);
      expect(result.rejected, hasLength(1));
      expect(result.rejected.single.code, 'categoryWordLimit');
      expect(await vocabulary.watchWords(category.id).first, hasLength(50));
    },
  );

  test(
    'cancellation before commit leaves import and words untouched',
    () async {
      final category = await vocabulary.createCategory('Travel');

      await expectLater(
        importer(
          categoryId: category.id,
          sourceName: 'cancelled.csv',
          rows: const [
            {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
          ],
          isCancelled: () => true,
        ),
        throwsA(isA<VocabularyImportCancelled>()),
      );

      expect(await database.select(database.vocabularyImports).get(), isEmpty);
      expect(await database.select(database.vocabularyWords).get(), isEmpty);
    },
  );
}
