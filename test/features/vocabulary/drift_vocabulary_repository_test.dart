import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
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

  test(
    'pinned reads preserve requested order and attach only verified lexical metadata',
    () async {
      await _insertPackagedVocabularyWord(
        database,
        id: 'word:station',
        spelling: 'station',
        meaning: 'สถานี',
      );
      await _insertPackagedVocabularyWord(
        database,
        id: 'word:market',
        spelling: 'market',
        meaning: 'ตลาด',
      );
      final resolver = _LexicalArtifactResolver(<String, Uint8List>{
        'word:station': Uint8List.fromList(
          utf8.encode(
            jsonEncode(<String, Object?>{
              'schemaVersion': 1,
              'wordId': 'word:station',
              'contentRevision': 1,
              'ipa': '/ˈsteɪ.ʃən/',
              'examples': <String>['The station is near the market.'],
              'synonyms': <String>['terminal'],
              'antonyms': <String>[],
              'audio': <String, Object?>{
                'language': 'en',
                'assetId': 'audio:station:en',
              },
            }),
          ),
        ),
      });
      final pinned = DriftVocabularyRepository(
        database,
        contentManifests: resolver,
      );
      final before = await database.customSelect('''
            SELECT (SELECT COUNT(*) FROM vocabulary_words) AS word_count,
                   (SELECT COUNT(*) FROM sqlite_master
                     WHERE type = 'table' AND name = 'lexical_metadata')
                     AS lexical_table_count
          ''').getSingle();

      final words = await pinned.readPinnedByIds(const [
        'word:market',
        'word:station',
      ]);

      expect(words.map((word) => word.id), ['word:market', 'word:station']);
      expect(words.first.richMetadata, isNull);
      expect(words.last.richMetadata!.ipa, '/ˈsteɪ.ʃən/');
      expect(words.last.richMetadata!.synonyms, const ['terminal']);
      expect(words.last.richMetadata!.audio!.assetId, 'audio:station:en');
      expect(
        words.last.richMetadata!.verifiedArtifactChecksumSha256,
        sha256.convert(resolver.artifacts['word:station']!).toString(),
      );
      final after = await database.customSelect('''
            SELECT (SELECT COUNT(*) FROM vocabulary_words) AS word_count,
                   (SELECT COUNT(*) FROM sqlite_master
                     WHERE type = 'table' AND name = 'lexical_metadata')
                     AS lexical_table_count
          ''').getSingle();
      expect(after.read<int>('word_count'), before.read<int>('word_count'));
      expect(
        after.read<int>('lexical_table_count'),
        before.read<int>('lexical_table_count'),
      );
    },
  );

  test(
    'malformed, unbounded, or checksum-mismatched metadata falls back to core words',
    () async {
      await _insertPackagedVocabularyWord(
        database,
        id: 'word:station',
        spelling: 'station',
        meaning: 'สถานี',
      );
      final malformed = DriftVocabularyRepository(
        database,
        contentManifests: _LexicalArtifactResolver(<String, Uint8List>{
          'word:station': Uint8List.fromList(utf8.encode('{"wordId":true}')),
        }),
      );
      final checksumMismatch = DriftVocabularyRepository(
        database,
        contentManifests: _LexicalArtifactResolver(
          const <String, Uint8List>{},
          failure: const ContentQualityFailure(
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
      final revisionMismatch = DriftVocabularyRepository(
        database,
        contentManifests: _LexicalArtifactResolver(<String, Uint8List>{
          'word:station': Uint8List.fromList(
            utf8.encode(
              jsonEncode(<String, Object?>{
                'schemaVersion': 1,
                'wordId': 'word:station',
                'contentRevision': 2,
                'ipa': null,
                'examples': <String>[],
                'synonyms': <String>[],
                'antonyms': <String>[],
                'audio': null,
              }),
            ),
          ),
        }),
      );
      final oversized = DriftVocabularyRepository(
        database,
        contentManifests: _LexicalArtifactResolver(<String, Uint8List>{
          'word:station': _maximalValidLexicalArtifact(),
        }),
      );
      final overNested = DriftVocabularyRepository(
        database,
        contentManifests: _LexicalArtifactResolver(<String, Uint8List>{
          'word:station': _overNestedLexicalArtifact(),
        }),
      );

      expect(
        (await malformed.readPinnedByIds(const [
          'word:station',
        ])).single.richMetadata,
        isNull,
      );
      expect(
        (await checksumMismatch.readPinnedByIds(const [
          'word:station',
        ])).single.richMetadata,
        isNull,
      );
      expect(
        (await revisionMismatch.readPinnedByIds(const [
          'word:station',
        ])).single.richMetadata,
        isNull,
      );
      expect(
        (await oversized.readPinnedByIds(const [
          'word:station',
        ])).single.richMetadata,
        isNull,
      );
      expect(
        (await overNested.readPinnedByIds(const [
          'word:station',
        ])).single.richMetadata,
        isNull,
      );
    },
  );

  test(
    'pinned reads fail closed for unknown ids and never enrich user-authored words',
    () async {
      await repository.createCategory(category());
      await repository.createWord(word(1));

      await expectLater(
        repository.readPinnedByIds(const ['word:unknown']),
        throwsA(isA<VocabularyNotFoundFailure>()),
      );
      final userWord = (await repository.readPinnedByIds(const [
        'word-1',
      ])).single;
      expect(userWord.richMetadata, isNull);
      expect(userWord.contentProvenance, ContentProvenance.userAuthored);
      expect(userWord.contentReviewState, ContentReviewState.unreviewed);
      expect(userWord.contentPublicationState, ContentPublicationState.private);
    },
  );
}

Uint8List _maximalValidLexicalArtifact() {
  final values = List<String>.generate(
    8,
    (index) => '${index.toString().padLeft(3, '0')}${'x' * 397}',
    growable: false,
  );
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'wordId': 'word:station',
        'contentRevision': 1,
        'ipa': null,
        'examples': values,
        'synonyms': values,
        'antonyms': values,
        'audio': null,
      }),
    ),
  );
}

Uint8List _overNestedLexicalArtifact() {
  Object nested = const <Object>[];
  for (var depth = 0; depth < 12; depth += 1) {
    nested = <Object>[nested];
  }
  return Uint8List.fromList(
    utf8.encode(
      jsonEncode(<String, Object?>{
        'schemaVersion': 1,
        'wordId': 'word:station',
        'contentRevision': 1,
        'ipa': null,
        'examples': nested,
        'synonyms': <String>[],
        'antonyms': <String>[],
        'audio': null,
      }),
    ),
  );
}

Future<void> _insertPackagedVocabularyWord(
  AppDatabase database, {
  required String id,
  required String spelling,
  required String meaning,
}) async {
  await database.customInsert(
    "INSERT OR IGNORE INTO local_owners(id, account_state, "
    "created_at_utc_ms, is_active) VALUES "
    "('packaged-owner', 'localGuest', 1, 0)",
  );
  await database.customInsert(
    "INSERT OR IGNORE INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, "
    "updated_at_utc_ms) VALUES "
    "('category:pack', 'packaged-owner', 'Pack', 'pack', 1, 1)",
  );
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:pack',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: 'A1',
    source: 'pack:v1',
    isGlobal: true,
  );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: id,
          ownerId: 'packaged-owner',
          categoryId: 'category:pack',
          spelling: spelling,
          normalizedSpelling: spelling,
          meaning: meaning,
          normalizedMeaning: meaning,
          partOfSpeech: 'noun',
          cefrLevel: const Value('A1'),
          source: const Value('pack:v1'),
          isGlobal: const Value(true),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: const Value('packaged'),
          contentReviewState: const Value('approved'),
          contentPublicationState: const Value('published'),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

final class _LexicalArtifactResolver implements ContentManifestRepository {
  _LexicalArtifactResolver(this.artifacts, {this.failure});

  final Map<String, Uint8List> artifacts;
  final ContentQualityFailure? failure;

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async {
    final error = failure;
    if (error != null) throw error;
    final bytes = artifacts[identity.id];
    if (bytes == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    return VerifiedContentManifest(
      manifest: ContentManifest(
        storageId: 'manifest:${identity.id}:${identity.revision}',
        identity: identity,
        checksumSha256: sha256.convert(bytes).toString(),
        byteLength: bytes.length,
        provenance: ContentProvenance.packaged,
        sourceUri: 'asset://lexical/${identity.id}.json',
        reviewState: ContentReviewState.approved,
        publicationState: ContentPublicationState.published,
        createdAtUtc: DateTime.utc(2026, 8, 24),
        reviewedAtUtc: DateTime.utc(2026, 8, 24, 1),
        publishedAtUtc: DateTime.utc(2026, 8, 24, 2),
      ),
      bytes: bytes,
    );
  }
}
