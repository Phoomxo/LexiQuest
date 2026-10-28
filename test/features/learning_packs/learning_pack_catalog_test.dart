import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_learning_pack_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';

void main() {
  late AppDatabase database;
  late DriftLearningPackRepository repository;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    repository = DriftLearningPackRepository(
      database,
      contentManifests: DriftContentManifestRepository(database),
    );
    await _insertVocabularyAuthority(database);
  });

  tearDown(() => database.close());

  test(
    'matches every multi-value catalog filter and orders pinned revisions',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 2,
        title: 'Zulu travel',
        cefrLevel: 'A2',
        topic: 'travel',
        skill: 'reading',
        goal: 'recognition',
        wordIds: const ['word:station'],
      );
      await _insertVerifiedPack(
        database,
        packId: 'pack:food',
        revision: 1,
        title: 'Alpha food',
        cefrLevel: 'A1',
        topic: 'food',
        skill: 'vocabulary',
        goal: 'production',
        wordIds: const ['word:market'],
      );
      await _insertVerifiedPack(
        database,
        packId: 'pack:work',
        revision: 3,
        title: 'Bravo work',
        cefrLevel: 'B1',
        topic: 'work',
        skill: 'listening',
        goal: 'recognition',
        wordIds: const ['word:station'],
      );

      final matched = await repository.list(
        LearningPackFilter(
          cefrLevels: {'A1', 'A2'},
          topics: {'food', 'travel'},
          skills: {'vocabulary', 'reading'},
          goals: {'production', 'recognition'},
        ),
      );

      expect(
        matched.map((pack) => (pack.packId, pack.revision)),
        <(String, int)>[('pack:food', 1), ('pack:travel', 2)],
      );
      expect(
        matched.map((pack) => pack.contentIdentity).toList(growable: false),
        const <ContentIdentity>[
          ContentIdentity(
            type: ContentType.learningPack,
            id: 'pack:food',
            revision: 1,
          ),
          ContentIdentity(
            type: ContentType.learningPack,
            id: 'pack:travel',
            revision: 2,
          ),
        ],
      );
    },
  );

  test('fails closed for an unknown canonical vocabulary id', () async {
    await _insertVerifiedPack(
      database,
      packId: 'pack:invalid',
      revision: 1,
      title: 'Unknown reference',
      cefrLevel: 'A1',
      topic: 'travel',
      skill: 'vocabulary',
      goal: 'recognition',
      wordIds: const ['word:unknown'],
      referenceChecksums: const {
        'word:unknown':
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      },
    );

    await expectLater(
      repository.list(LearningPackFilter()),
      throwsA(
        isA<ContentQualityFailure>().having(
          (failure) => failure.code,
          'code',
          ContentQualityFailureCode.missingReference,
        ),
      ),
    );
  });

  test(
    'reads the verified catalog without inserting or duplicating words',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:travel',
        revision: 1,
        title: 'Travel basics',
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'vocabulary',
        goal: 'recognition',
        wordIds: const ['word:station'],
      );
      final before = await _vocabularyRows(database);

      final packs = await repository.list(LearningPackFilter());

      expect(packs, hasLength(1));
      expect(await _vocabularyRows(database), before);
    },
  );

  test(
    'does not expose a pack revision that is not verified and published',
    () async {
      await _insertVerifiedPack(
        database,
        packId: 'pack:published',
        revision: 1,
        title: 'Published',
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'vocabulary',
        goal: 'recognition',
        wordIds: const ['word:station'],
      );
      await _insertVerifiedPack(
        database,
        packId: 'pack:private',
        revision: 1,
        title: 'Private',
        cefrLevel: 'A1',
        topic: 'travel',
        skill: 'vocabulary',
        goal: 'recognition',
        wordIds: const ['word:market'],
        publicationState: ContentPublicationState.private,
      );

      final packs = await repository.list(LearningPackFilter());

      expect(packs.map((pack) => pack.packId), ['pack:published']);
    },
  );
}

final _createdAt = DateTime.utc(2026, 8, 24, 8);

Future<void> _insertVocabularyAuthority(AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('packaged-owner', 'localGuest', 1, 0)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, "
    "updated_at_utc_ms) VALUES "
    "('category:pack', 'packaged-owner', 'Pack', 'pack', 1, 1)",
  );
  await _insertVocabularyWord(
    database,
    id: 'word:station',
    spelling: 'station',
    meaning: 'สถานี',
  );
  await _insertVocabularyWord(
    database,
    id: 'word:market',
    spelling: 'market',
    meaning: 'ตลาด',
  );
}

Future<void> _insertVocabularyWord(
  AppDatabase database, {
  required String id,
  required String spelling,
  required String meaning,
}) async {
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:pack',
    spelling: spelling,
    normalizedSpelling: spelling,
    meaning: meaning,
    normalizedMeaning: meaning,
    partOfSpeech: 'noun',
    cefrLevel: null,
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
          source: const Value('pack:v1'),
          isGlobal: const Value(true),
          contentRevision: const Value(1),
          contentChecksumSha256: Value(checksum),
          contentProvenance: Value(ContentProvenance.packaged.name),
          contentReviewState: Value(ContentReviewState.approved.name),
          contentPublicationState: Value(
            ContentPublicationState.published.name,
          ),
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _insertVerifiedPack(
  AppDatabase database, {
  required String packId,
  required int revision,
  required String title,
  required String cefrLevel,
  required String topic,
  required String skill,
  required String goal,
  required List<String> wordIds,
  Map<String, String> referenceChecksums = const {},
  ContentPublicationState publicationState = ContentPublicationState.published,
}) async {
  final words = await (database.select(
    database.vocabularyWords,
  )..where((word) => word.id.isIn(wordIds))).get();
  final wordsById = {for (final word in words) word.id: word};
  final references = wordIds
      .map(
        (id) => ContentVocabularyReference(
          id: id,
          revision: wordsById[id]?.contentRevision ?? 1,
          checksumSha256:
              wordsById[id]?.contentChecksumSha256 ??
              referenceChecksums[id] ??
              (throw StateError('missing test checksum for $id')),
        ),
      )
      .toList(growable: false);
  final bytes = ContentQualityPolicy.canonicalLearningPackBytes(
    packId: packId,
    revision: revision,
    title: title,
    cefrLevel: cefrLevel,
    topic: topic,
    skill: skill,
    goal: goal,
    vocabularyReferences: references,
  );
  final storageId = 'manifest:$packId:r$revision';
  final rowId = '$packId:r$revision';
  await database
      .into(database.contentManifests)
      .insert(
        ContentManifestsCompanion.insert(
          id: storageId,
          contentType: ContentType.learningPack.name,
          contentId: packId,
          revision: revision,
          checksumSha256: sha256.convert(bytes).toString(),
          byteLength: bytes.length,
          provenance: ContentProvenance.packaged.name,
          sourceUri: 'asset://learning-packs/$packId-r$revision.json',
          reviewState: ContentReviewState.approved.name,
          publicationState: publicationState.name,
          createdAtUtcMs: _createdAt.millisecondsSinceEpoch,
          reviewedAtUtcMs: Value(
            _createdAt.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
          ),
          publishedAtUtcMs:
              publicationState == ContentPublicationState.published
              ? Value(
                  _createdAt
                      .add(const Duration(minutes: 2))
                      .millisecondsSinceEpoch,
                )
              : const Value.absent(),
        ),
      );
  await database
      .into(database.learningPacks)
      .insert(
        LearningPacksCompanion.insert(
          id: rowId,
          packId: packId,
          revision: revision,
          manifestId: storageId,
          title: title,
          cefrLevel: cefrLevel,
          topic: topic,
          skill: skill,
          goal: goal,
          createdAtUtcMs: _createdAt.millisecondsSinceEpoch,
        ),
      );
  for (final entry in wordIds.indexed) {
    await database
        .into(database.learningPackItems)
        .insert(
          LearningPackItemsCompanion.insert(
            id: '$rowId:item:${entry.$1}',
            learningPackId: rowId,
            vocabularyWordId: entry.$2,
            position: entry.$1,
          ),
        );
  }
}

Future<List<Map<String, Object?>>> _vocabularyRows(AppDatabase database) async {
  final rows = await database
      .customSelect(
        'SELECT id, owner_id, category_id, spelling, normalized_spelling, '
        'meaning, normalized_meaning, content_revision, '
        'content_checksum_sha256, content_provenance, content_review_state, '
        'content_publication_state FROM vocabulary_words ORDER BY id',
      )
      .get();
  return rows
      .map((row) => Map<String, Object?>.unmodifiable(row.data))
      .toList(growable: false);
}
