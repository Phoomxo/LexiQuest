import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner, VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
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
  late bool databaseClosed;

  setUp(() {
    database = AppDatabase(NativeDatabase.memory());
    databaseClosed = false;
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
    if (!databaseClosed) await database.close();
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

  test('a soft-deleted natural key is reported as duplicate', () async {
    final category = await vocabulary.createCategory('Travel');
    final deleted = await vocabulary.createWord(
      CreateWordCommand(
        categoryId: category.id,
        spelling: 'station',
        meaning: 'สถานี',
        partOfSpeech: 'noun',
      ),
    );
    await vocabulary.deleteWord(deleted.id);

    final result = await importer(
      categoryId: category.id,
      sourceName: 'after-delete.csv',
      rows: const [
        {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
      ],
    );

    expect(result.accepted, 0);
    expect(result.duplicates, 1);
    expect(result.rejected, isEmpty);
    expect(await vocabulary.watchWords(category.id).first, isEmpty);
  });

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

  test('imports stay isolated to the active owner and category', () async {
    final ownerA = LocalOwner(id: 'local:owner-a', createdAtUtc: nowUtc);
    final ownerB = LocalOwner(id: 'local:owner-b', createdAtUtc: nowUtc);
    for (final owner in [ownerA, ownerB]) {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: owner.id,
              createdAtUtcMs: owner.createdAtUtc.millisecondsSinceEpoch,
            ),
          );
    }
    final repository = DriftVocabularyRepository(database);
    final imports = DriftVocabularyImportRepository(database);
    var ownerAId = 0;
    var ownerBId = 0;
    final vocabularyA = VocabularyUseCases(
      owners: _FixedOwnerRepository(ownerA),
      vocabulary: repository,
      generateId: () => 'owner-a-${++ownerAId}',
      nowUtc: () => nowUtc,
    );
    final vocabularyB = VocabularyUseCases(
      owners: _FixedOwnerRepository(ownerB),
      vocabulary: repository,
      generateId: () => 'owner-b-${++ownerBId}',
      nowUtc: () => nowUtc,
    );
    final categoryA = await vocabularyA.createCategory('Travel A');
    final categoryB = await vocabularyB.createCategory('Travel B');
    final importerA = ImportVocabulary(
      owners: _FixedOwnerRepository(ownerA),
      repository: imports,
      generateId: () => 'owner-a-import-${++ownerAId}',
      nowUtc: () => nowUtc,
    );
    final importerB = ImportVocabulary(
      owners: _FixedOwnerRepository(ownerB),
      repository: imports,
      generateId: () => 'owner-b-import-${++ownerBId}',
      nowUtc: () => nowUtc,
    );
    const rows = [
      {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
    ];

    expect(
      (await importerA(
        categoryId: categoryA.id,
        rows: rows,
        sourceName: 'travel.csv',
      )).accepted,
      1,
    );
    expect(
      (await importerB(
        categoryId: categoryB.id,
        rows: rows,
        sourceName: 'travel.csv',
      )).accepted,
      1,
    );
    await expectLater(
      importerB(
        categoryId: categoryA.id,
        rows: rows,
        sourceName: 'wrong-owner.csv',
      ),
      throwsA(isA<StateError>()),
    );

    final storedWords = await database.select(database.vocabularyWords).get();
    expect(
      storedWords.where((word) => word.ownerId == ownerA.id),
      hasLength(1),
    );
    expect(
      storedWords.where((word) => word.ownerId == ownerB.id),
      hasLength(1),
    );
    expect(
      await database.select(database.vocabularyImports).get(),
      hasLength(2),
    );
  });

  test('reopen keeps imported words and replays the same import', () async {
    await database.close();
    databaseClosed = true;
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-vocabulary-import-',
    );
    final databaseFile = File(
      '${directory.path}${Platform.pathSeparator}app.db',
    );
    AppDatabase? reopened;
    try {
      final firstDatabase = AppDatabase(NativeDatabase(databaseFile));
      final firstOwners = DriftLocalOwnerRepository(
        firstDatabase,
        generateId: () => 'restart-owner',
        nowUtc: () => nowUtc,
      );
      final firstVocabulary = VocabularyUseCases(
        owners: firstOwners,
        vocabulary: DriftVocabularyRepository(firstDatabase),
        generateId: () => 'restart-category',
        nowUtc: () => nowUtc,
      );
      final firstImporter = ImportVocabulary(
        owners: firstOwners,
        repository: DriftVocabularyImportRepository(firstDatabase),
        generateId: () => 'restart-import',
        nowUtc: () => nowUtc,
      );
      final category = await firstVocabulary.createCategory('Restart');
      const rows = [
        {'word': 'station', 'meaning': 'สถานี', 'partOfSpeech': 'noun'},
      ];
      final first = await firstImporter(
        categoryId: category.id,
        rows: rows,
        sourceName: 'restart.csv',
      );
      await firstDatabase.close();

      reopened = AppDatabase(NativeDatabase(databaseFile));
      final reopenedOwners = DriftLocalOwnerRepository(
        reopened,
        generateId: () => 'must-not-create-another-owner',
        nowUtc: () => nowUtc,
      );
      final reopenedVocabulary = VocabularyUseCases(
        owners: reopenedOwners,
        vocabulary: DriftVocabularyRepository(reopened),
        generateId: () => 'must-not-create-another-word',
        nowUtc: () => nowUtc,
      );
      final replay = await ImportVocabulary(
        owners: reopenedOwners,
        repository: DriftVocabularyImportRepository(reopened),
        generateId: () => 'must-not-create-another-import',
        nowUtc: () => nowUtc,
      )(categoryId: category.id, rows: rows, sourceName: 'restart.csv');

      expect(
        await reopenedVocabulary.watchWords(category.id).first,
        hasLength(1),
      );
      expect(replay.importId, first.importId);
      expect(
        await reopened.select(reopened.vocabularyImports).get(),
        hasLength(1),
      );
    } finally {
      await reopened?.close();
      await directory.delete(recursive: true);
    }
  });
}

final class _FixedOwnerRepository implements LocalOwnerRepository {
  const _FixedOwnerRepository(this.owner);

  final LocalOwner owner;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) {
    throw UnimplementedError();
  }
}
