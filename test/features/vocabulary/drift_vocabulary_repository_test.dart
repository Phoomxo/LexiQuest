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

  test('learner-authored words persist versioned private provenance', () async {
    await repository.createCategory(category());
    await repository.createWord(word(1));

    final created = await database.customSelect('''
          SELECT content_revision, content_checksum_sha256,
                 content_provenance, content_review_state,
                 content_publication_state
          FROM vocabulary_words WHERE id = 'word-1'
        ''').getSingle();
    final createdChecksum = created.read<String>('content_checksum_sha256');
    expect(created.read<int>('content_revision'), 1);
    expect(createdChecksum, matches(RegExp(r'^[0-9a-f]{64}$')));
    expect(created.read<String>('content_provenance'), 'userAuthored');
    expect(created.read<String>('content_review_state'), 'unreviewed');
    expect(created.read<String>('content_publication_state'), 'private');

    await repository.updateWord(
      word(1).copyWith(
        spelling: 'Station',
        normalizedSpelling: 'station',
        updatedAtUtc: createdAt.add(const Duration(minutes: 1)),
      ),
    );
    final updated = await database.customSelect('''
          SELECT content_revision, content_checksum_sha256,
                 content_provenance, content_review_state,
                 content_publication_state
          FROM vocabulary_words WHERE id = 'word-1'
        ''').getSingle();
    expect(updated.read<int>('content_revision'), 2);
    expect(
      updated.read<String>('content_checksum_sha256'),
      isNot(createdChecksum),
    );
    expect(updated.read<String>('content_provenance'), 'userAuthored');
    expect(updated.read<String>('content_review_state'), 'unreviewed');
    expect(updated.read<String>('content_publication_state'), 'private');
  });
}
