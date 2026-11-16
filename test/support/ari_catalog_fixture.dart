// Test-only native catalog fixture. Never imported by application entry points.
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';

/// Inserts namespaced content atomically; collisions fail without overwriting.
Future<void> insertAriCatalogFixture(AppDatabase database) =>
    database.transaction(() async {
      await _insertVocabularyAuthority(database);
      for (final revision in [1, 2]) {
        await _insertVerifiedPack(
          database,
          packId: 'pack:ari-food-117',
          revision: revision,
          title: 'Ari Food r$revision',
          cefrLevel: 'A1',
          topic: 'food',
          skill: 'vocabulary',
          goal: 'production',
          wordIds: revision == 1
              ? ['word:ari-fixture-market-117']
              : ['word:ari-fixture-market-117', 'word:ari-fixture-station-117'],
        );
      }
      await _insertVerifiedPack(
        database,
        packId: 'pack:ari-travel-117',
        revision: 3,
        title: 'Ari Travel r3',
        cefrLevel: 'A2',
        topic: 'travel',
        skill: 'reading',
        goal: 'recognition',
        wordIds: ['word:ari-fixture-station-117'],
      );
    });

final _createdAt = DateTime.utc(2026, 8, 24, 8);

Future<void> _insertVocabularyAuthority(AppDatabase database) async {
  final activeOwners = await (database.select(
    database.localOwners,
  )..where((owner) => owner.isActive.equals(true))).get();
  if (activeOwners.length > 1) {
    throw StateError('Fixture requires at most one active owner');
  }
  final ownerId = activeOwners.isEmpty
      ? 'ari-fixture-owner-117'
      : activeOwners.single.id;
  // Preserve existing owner and production isolation in device working clones.
  if (activeOwners.isEmpty) {
    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms, is_active) "
      "VALUES (?, 'localGuest', 1, 0)",
      variables: [Variable<String>(ownerId)],
    );
  }
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, "
    "updated_at_utc_ms) VALUES "
    "('category:ari-fixture-117', ?, 'Pack', 'pack', 1, 1)",
    variables: [Variable<String>(ownerId)],
  );
  await _insertVocabularyWord(
    database,
    ownerId: ownerId,
    id: 'word:ari-fixture-station-117',
    spelling: 'station',
    meaning: 'สถานี',
  );
  await _insertVocabularyWord(
    database,
    ownerId: ownerId,
    id: 'word:ari-fixture-market-117',
    spelling: 'market',
    meaning: 'ตลาด',
  );
}

Future<void> _insertVocabularyWord(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String spelling,
  required String meaning,
}) async {
  final checksum = ContentQualityPolicy.vocabularyChecksumSha256(
    categoryId: 'category:ari-fixture-117',
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
          ownerId: ownerId,
          categoryId: 'category:ari-fixture-117',
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
