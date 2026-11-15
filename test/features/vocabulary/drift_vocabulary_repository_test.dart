import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_failure.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';

void main() {
  late AppDatabase database;
  late DriftVocabularyRepository repository;
  final createdAt = DateTime.utc(2026, 7, 30, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftVocabularyRepository(database);
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-1',
            createdAtUtcMs: createdAt.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-2',
            createdAtUtcMs: createdAt.millisecondsSinceEpoch,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  VocabularyCategory category({
    String id = 'category-1',
    String ownerId = 'owner-1',
    String name = 'Travel',
    String normalizedName = 'travel',
  }) {
    return VocabularyCategory(
      id: id,
      ownerId: ownerId,
      name: name,
      normalizedName: normalizedName,
      sortOrder: 0,
      localRevision: 1,
      isDeleted: false,
      createdAtUtc: createdAt,
      updatedAtUtc: createdAt,
    );
  }

  VocabularyWord word(
    int index, {
    String ownerId = 'owner-1',
    String categoryId = 'category-1',
  }) {
    return VocabularyWord(
      id: 'word-$index',
      ownerId: ownerId,
      categoryId: categoryId,
      spelling: 'Word $index',
      normalizedSpelling: 'word $index',
      meaning: 'Meaning $index',
      normalizedMeaning: 'meaning $index',
      partOfSpeech: 'noun',
      source: 'manual',
      isGlobal: false,
      localRevision: 1,
      isDeleted: false,
      createdAtUtc: createdAt,
      updatedAtUtc: createdAt,
    );
  }

  test('category and word streams emit committed local changes', () async {
    final categories = repository
        .watchCategories('owner-1')
        .firstWhere((items) => items.isNotEmpty);
    await repository.createCategory(category());

    expect((await categories).single.name, 'Travel');

    final words = repository
        .watchWords('owner-1', 'category-1')
        .firstWhere((items) => items.isNotEmpty);
    await repository.createWord(word(1));

    expect((await words).single.spelling, 'Word 1');
  });

  test(
    'library summaries count active owner words and retain empty sets',
    () async {
      await repository.createCategory(category());
      await repository.createCategory(
        category(id: 'empty-set', name: 'Empty', normalizedName: 'empty'),
      );
      await repository.createCategory(
        category(id: 'other-set', ownerId: 'owner-2'),
      );
      for (var index = 1; index <= 4; index++) {
        await repository.createWord(word(index));
      }
      await repository.createWord(
        word(99, ownerId: 'owner-2', categoryId: 'other-set'),
      );
      final summaries = await repository.watchLibrary('owner-1').first;
      expect(summaries, hasLength(2));
      final travel = summaries.singleWhere(
        (entry) => entry.category.id == 'category-1',
      );
      expect(travel.wordCount, 4);
      expect(travel.previewSpellings, ['Word 1', 'Word 2', 'Word 3']);
      expect(
        summaries
            .singleWhere((entry) => entry.category.id == 'empty-set')
            .wordCount,
        0,
      );
      final changed = repository
          .watchLibrary('owner-1')
          .firstWhere(
            (entries) => entries.any(
              (entry) =>
                  entry.category.id == 'category-1' && entry.wordCount == 3,
            ),
          );
      await repository.deleteWord(
        ownerId: 'owner-1',
        wordId: 'word-1',
        nowUtc: createdAt,
      );
      expect(
        (await changed)
            .singleWhere((entry) => entry.category.id == 'category-1')
            .previewSpellings,
        ['Word 2', 'Word 3', 'Word 4'],
      );
    },
  );

  test(
    'global search spans sets, excludes other owners and treats wildcards literally',
    () async {
      await repository.createCategory(category());
      await repository.createCategory(
        category(id: 'set-b', name: 'Food', normalizedName: 'food'),
      );
      await repository.createCategory(
        category(id: 'other-set', ownerId: 'owner-2'),
      );
      await repository.createWord(word(1));
      await repository.createWord(word(2, categoryId: 'set-b'));
      await repository.createWord(
        word(3, ownerId: 'owner-2', categoryId: 'other-set'),
      );
      await repository.createWord(
        word(
          4,
        ).copyWith(spelling: '100%_safe', normalizedSpelling: '100%_safe'),
      );
      expect(
        (await repository.searchWords('owner-1', 'word').first).map(
          (word) => word.id,
        ),
        ['word-1', 'word-2'],
      );
      expect(
        (await repository.searchWords('owner-1', 'meaning 2').first)
            .single
            .categoryId,
        'set-b',
      );
      expect(
        (await repository.searchWords('owner-1', '%').first).single.id,
        'word-4',
      );
      expect(
        (await repository.searchWords('owner-1', '_').first).single.id,
        'word-4',
      );
      expect(await repository.searchWords('owner-1', '').first, isEmpty);
      await repository.deleteCategory(
        ownerId: 'owner-1',
        categoryId: 'set-b',
        nowUtc: createdAt,
      );
      expect(
        await repository.searchWords('owner-1', 'meaning 2').first,
        isEmpty,
      );
    },
  );

  test(
    'global search limits owner results after filtering on stored level',
    () async {
      await repository.createCategory(category());
      await repository.createCategory(
        category(id: 'set-b', name: 'Food', normalizedName: 'food'),
      );
      await repository.createCategory(
        category(id: 'other-set', ownerId: 'owner-2'),
      );
      for (var index = 0; index < 60; index++) {
        await repository.createWord(
          word(index, categoryId: index < 30 ? 'category-1' : 'set-b'),
        );
      }
      final matching = word(
        99,
        categoryId: 'set-b',
      ).copyWith(cefrLevel: ' a2 ');
      await repository.createWord(matching);
      await repository.createWord(
        word(
          100,
          ownerId: 'owner-2',
          categoryId: 'other-set',
        ).copyWith(cefrLevel: 'A2'),
      );
      final found = await repository.searchWords('owner-1', 'word').first;
      expect(found, hasLength(50));
      expect(found.map((word) => word.id).toSet(), hasLength(50));
      expect(found.map((word) => word.id), isNot(contains(matching.id)));
      expect(
        (await repository.searchWords('owner-1', 'word', cefrLevel: 'A2').first)
            .single
            .id,
        matching.id,
      );
      final summaries = await repository.watchLibrary('owner-1').first;
      expect(
        summaries
            .singleWhere((entry) => entry.category.id == 'set-b')
            .cefrLevels,
        {'A2'},
      );
      expect(
        summaries
            .singleWhere((entry) => entry.category.id == 'category-1')
            .cefrLevels,
        isEmpty,
      );
      final updated = repository
          .watchLibrary('owner-1')
          .firstWhere(
            (items) => items.every((entry) => entry.cefrLevels.isEmpty),
          );
      await repository.deleteWord(
        ownerId: 'owner-1',
        wordId: matching.id,
        nowUtc: createdAt,
      );
      expect(await updated, hasLength(2));
    },
  );

  test('repository reconstruction reads persisted vocabulary', () async {
    await repository.createCategory(category());
    await repository.createWord(word(1));

    final restored = DriftVocabularyRepository(database);

    expect(
      (await restored.watchCategories('owner-1').first).single.id,
      'category-1',
    );
    expect(
      (await restored.watchWords('owner-1', 'category-1').first).single.id,
      'word-1',
    );
  });

  test('normalized category and word duplicates are rejected', () async {
    await repository.createCategory(category());

    await expectLater(
      repository.createCategory(
        category(id: 'category-2', name: ' travel ', normalizedName: 'travel'),
      ),
      throwsA(isA<DuplicateVocabularyFailure>()),
    );

    await repository.createWord(word(1));
    final duplicateWord = word(2).copyWith(
      spelling: ' WORD 1 ',
      normalizedSpelling: 'word 1',
      meaning: ' meaning 1 ',
      normalizedMeaning: 'meaning 1',
    );
    await expectLater(
      repository.createWord(duplicateWord),
      throwsA(isA<DuplicateVocabularyFailure>()),
    );
  });

  test('category enforces the active 50-word limit transactionally', () async {
    await repository.createCategory(category());
    for (var index = 0; index < 50; index++) {
      await repository.createWord(word(index));
    }

    await expectLater(
      repository.createWord(word(50)),
      throwsA(
        isA<CategoryWordLimitFailure>().having(
          (failure) => failure.limit,
          'limit',
          50,
        ),
      ),
    );

    expect(
      await repository.watchWords('owner-1', 'category-1').first,
      hasLength(50),
    );
  });

  test(
    'edits increment revisions and deletes leave hidden tombstones',
    () async {
      await repository.createCategory(category());
      await repository.createWord(word(1));
      final editedAt = createdAt.add(const Duration(minutes: 1));

      final renamed = await repository.renameCategory(
        ownerId: 'owner-1',
        categoryId: 'category-1',
        name: 'Trips',
        normalizedName: 'trips',
        nowUtc: editedAt,
      );
      final editedWord = await repository.updateWord(
        word(1).copyWith(
          spelling: 'Station',
          normalizedSpelling: 'station',
          updatedAtUtc: editedAt,
        ),
      );
      await repository.deleteWord(
        ownerId: 'owner-1',
        wordId: 'word-1',
        nowUtc: editedAt.add(const Duration(minutes: 1)),
      );

      expect(renamed.localRevision, 2);
      expect(editedWord.localRevision, 2);
      expect(
        await repository.watchWords('owner-1', 'category-1').first,
        isEmpty,
      );
      final storedWord = await (database.select(
        database.vocabularyWords,
      )..where((row) => row.id.equals('word-1'))).getSingle();
      expect(storedWord.isDeleted, isTrue);
      expect(storedWord.localRevision, 3);
    },
  );

  test(
    'a pinned edit cannot overwrite a newer word or append another mutation',
    () async {
      await database.customStatement(
        'UPDATE local_owners SET is_active = 0 WHERE id = ?',
        ['owner-2'],
      );
      await repository.createCategory(category());
      final original = await repository.createWord(word(1));
      final winner = await repository.updateWord(
        original.copyWith(
          meaning: 'New meaning',
          normalizedMeaning: 'new meaning',
          updatedAtUtc: createdAt.add(const Duration(minutes: 1)),
        ),
      );
      final winningRow = await database
          .select(database.vocabularyWords)
          .getSingle();

      await expectLater(
        repository.updateWord(
          original.copyWith(
            meaning: 'Stale meaning',
            normalizedMeaning: 'stale meaning',
            updatedAtUtc: createdAt.add(const Duration(minutes: 2)),
          ),
          expectedWord: original,
        ),
        throwsA(isA<StaleVocabularyWordFailure>()),
      );
      expect(winner.localRevision, 2);
      expect(winningRow.meaning, 'New meaning');
      expect(
        await database.select(database.vocabularyWords).getSingle(),
        winningRow,
      );
      final wordWrites = await (database.select(
        database.outboxOperations,
      )..where((row) => row.entityId.equals(original.id))).get();
      expect(
        wordWrites.map((row) => row.operationId),
        unorderedEquals(['word:word-1:1', 'word:word-1:2']),
      );
    },
  );

  test(
    'a pinned edit cannot overwrite synced content at the same revision',
    () async {
      await database.customStatement(
        'UPDATE local_owners SET is_active = 0 WHERE id = ?',
        ['owner-2'],
      );
      await repository.createCategory(category());
      final original = await repository.createWord(word(1));
      await database.customStatement(
        'UPDATE vocabulary_words '
        'SET meaning = ?, normalized_meaning = ?, cloud_revision = local_revision '
        'WHERE id = ?',
        ['Synced meaning', 'synced meaning', original.id],
      );
      final synced = await database
          .select(database.vocabularyWords)
          .getSingle();
      expect(synced.localRevision, original.localRevision);
      expect(synced.meaning, 'Synced meaning');
      final outbox = await database.select(database.outboxOperations).get();

      await expectLater(
        repository.updateWord(
          original.copyWith(
            meaning: 'Stale meaning',
            normalizedMeaning: 'stale meaning',
            updatedAtUtc: createdAt.add(const Duration(minutes: 1)),
          ),
          expectedWord: original,
        ),
        throwsA(isA<StaleVocabularyWordFailure>()),
      );
      expect(
        await database.select(database.vocabularyWords).getSingle(),
        synced,
      );
      expect(await database.select(database.outboxOperations).get(), outbox);
    },
  );

  test('a pinned edit cannot write after its owner goes inactive', () async {
    await repository.createCategory(category());
    final original = await repository.createWord(word(1));
    await database.customStatement(
      'UPDATE local_owners SET is_active = 0 WHERE id = ?',
      [original.ownerId],
    );
    final before = await database.select(database.vocabularyWords).getSingle();
    final outbox = await database.select(database.outboxOperations).get();

    await expectLater(
      repository.updateWord(
        original.copyWith(
          meaning: 'Stale owner meaning',
          normalizedMeaning: 'stale owner meaning',
          updatedAtUtc: createdAt.add(const Duration(minutes: 1)),
        ),
        expectedWord: original,
      ),
      throwsA(isA<VocabularyFailure>()),
    );
    expect(await database.select(database.vocabularyWords).getSingle(), before);
    expect(await database.select(database.outboxOperations).get(), outbox);
  });

  test(
    'every accepted mutation appends one deterministic outbox row',
    () async {
      await repository.createCategory(category());
      await repository.createWord(word(1));
      await repository.createWord(word(1));

      final outbox = await database.select(database.outboxOperations).get();
      expect(outbox, hasLength(2));
      expect(outbox.map((operation) => operation.operationId).toSet(), {
        'category:category-1:1',
        'word:word-1:1',
      });
    },
  );

  test('owners cannot read or mutate each other vocabulary', () async {
    await repository.createCategory(category());
    await repository.createWord(word(1));

    expect(await repository.watchCategories('owner-2').first, isEmpty);
    expect(await repository.watchWords('owner-2', 'category-1').first, isEmpty);
    await expectLater(
      repository.deleteWord(
        ownerId: 'owner-2',
        wordId: 'word-1',
        nowUtc: createdAt,
      ),
      throwsA(isA<VocabularyNotFoundFailure>()),
    );
  });
}
