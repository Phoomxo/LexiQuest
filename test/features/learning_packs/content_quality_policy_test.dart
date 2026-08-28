import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning_packs/data/drift_content_manifest_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';

void main() {
  const policy = ContentQualityPolicy();
  final bytes = Uint8List.fromList(utf8.encode('pack:v1'));
  final createdAt = DateTime.utc(2026, 8, 24, 8);

  ContentManifest manifest({
    String storageId = 'manifest:pack:travel:r1',
    ContentType type = ContentType.learningPack,
    String id = 'pack:travel',
    int revision = 1,
    String? checksumSha256,
    int? byteLength,
    ContentProvenance provenance = ContentProvenance.packaged,
    String sourceUri = 'asset://learning-packs/travel-v1.json',
    ContentReviewState reviewState = ContentReviewState.approved,
    ContentPublicationState publicationState =
        ContentPublicationState.published,
    DateTime? reviewedAtUtc,
    DateTime? publishedAtUtc,
  }) => ContentManifest(
    storageId: storageId,
    identity: ContentIdentity(type: type, id: id, revision: revision),
    checksumSha256: checksumSha256 ?? sha256.convert(bytes).toString(),
    byteLength: byteLength ?? bytes.length,
    provenance: provenance,
    sourceUri: sourceUri,
    reviewState: reviewState,
    publicationState: publicationState,
    createdAtUtc: createdAt,
    reviewedAtUtc: reviewedAtUtc ?? createdAt.add(const Duration(minutes: 1)),
    publishedAtUtc: publishedAtUtc ?? createdAt.add(const Duration(minutes: 2)),
  );

  ContentManifestsCompanion persistedManifest({
    String id = 'manifest:immutable:r1',
    String contentId = 'artifact:immutable',
    String sourceUri = 'asset://immutable.bin',
  }) => ContentManifestsCompanion.insert(
    id: id,
    contentType: ContentType.offlineArtifact.name,
    contentId: contentId,
    revision: 1,
    checksumSha256: sha256.convert(bytes).toString(),
    byteLength: bytes.length,
    provenance: ContentProvenance.packaged.name,
    sourceUri: sourceUri,
    reviewState: ContentReviewState.approved.name,
    publicationState: ContentPublicationState.published.name,
    createdAtUtcMs: createdAt.millisecondsSinceEpoch,
    reviewedAtUtcMs: Value(
      createdAt.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    ),
    publishedAtUtcMs: Value(
      createdAt.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
    ),
  );

  test(
    'approved published packaged content verifies exact SHA-256 and refs',
    () {
      final candidate = manifest();

      final verified = policy.requireVerified(
        manifest: candidate,
        bytes: bytes,
        referencedVocabularyIds: const <String>['word:station'],
        knownVocabularyIds: const <String>{'word:station'},
      );

      expect(verified.manifest, same(candidate));
      expect(verified.bytes, bytes);
    },
  );

  test('quality policy fails closed for checksum and byte mismatches', () {
    for (final candidate in <ContentManifest>[
      manifest(checksumSha256: 'ABC'),
      manifest(
        checksumSha256:
            'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      ),
      manifest(
        checksumSha256:
            'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      ),
      manifest(byteLength: bytes.length + 1),
    ]) {
      expect(
        () => policy.requireVerified(manifest: candidate, bytes: bytes),
        throwsA(isA<ContentQualityFailure>()),
      );
    }
  });

  test(
    'quality policy rejects unreviewed unpublished and false provenance',
    () {
      for (final candidate in <ContentManifest>[
        manifest(reviewState: ContentReviewState.unreviewed),
        manifest(publicationState: ContentPublicationState.private),
        manifest(provenance: ContentProvenance.userAuthored),
        manifest(sourceUri: '  '),
        manifest(reviewedAtUtc: createdAt.subtract(const Duration(seconds: 1))),
        manifest(publishedAtUtc: createdAt),
      ]) {
        expect(
          () => policy.requireVerified(manifest: candidate, bytes: bytes),
          throwsA(isA<ContentQualityFailure>()),
        );
      }
    },
  );

  test('quality policy rejects unknown and non-canonical vocabulary refs', () {
    for (final reference in const <String>['word:unknown', ' word:station ']) {
      expect(
        () => policy.requireVerified(
          manifest: manifest(),
          bytes: bytes,
          referencedVocabularyIds: <String>[reference],
          knownVocabularyIds: const <String>{'word:station'},
        ),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.missingReference,
          ),
        ),
      );
    }
  });

  test('an immutable identity accepts replay but rejects changed metadata', () {
    final existing = manifest();
    expect(
      () => policy.requireImmutableRevision(
        existing: existing,
        candidate: manifest(),
      ),
      returnsNormally,
    );
    expect(
      () => policy.requireImmutableRevision(
        existing: existing,
        candidate: manifest(sourceUri: 'asset://changed.json'),
      ),
      throwsA(
        isA<ContentQualityFailure>().having(
          (failure) => failure.code,
          'code',
          ContentQualityFailureCode.immutableRevisionConflict,
        ),
      ),
    );
  });

  test('quality failures expose only stable codes', () {
    expect(
      const ContentQualityFailure(
        ContentQualityFailureCode.checksumMismatch,
      ).toString(),
      'ContentQualityFailure(checksumMismatch)',
    );
  });

  test(
    'legacy null checksum normalizes but a stored mismatch fails closed',
    () {
      String effective(String? stored) =>
          ContentQualityPolicy.effectiveVocabularyChecksumSha256(
            categoryId: 'category:user',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            cefrLevel: null,
            source: 'manual',
            isGlobal: false,
            storedChecksumSha256: stored,
          );
      final canonical = ContentQualityPolicy.vocabularyChecksumSha256(
        categoryId: 'category:user',
        spelling: 'station',
        normalizedSpelling: 'station',
        meaning: 'สถานี',
        normalizedMeaning: 'สถานี',
        partOfSpeech: 'noun',
        cefrLevel: null,
        source: 'manual',
        isGlobal: false,
      );

      expect(effective(null), canonical);
      expect(effective(canonical), canonical);
      expect(
        () => effective('a' * 64),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.checksumMismatch,
          ),
        ),
      );
      expect(
        () => effective('not-a-checksum'),
        throwsA(
          isA<ContentQualityFailure>().having(
            (failure) => failure.code,
            'code',
            ContentQualityFailureCode.invalidChecksum,
          ),
        ),
      );
    },
  );

  test('persisted manifest revisions reject update and delete', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database
        .into(database.contentManifests)
        .insert(
          ContentManifestsCompanion.insert(
            id: 'manifest:immutable:r1',
            contentType: ContentType.offlineArtifact.name,
            contentId: 'artifact:immutable',
            revision: 1,
            checksumSha256: sha256.convert(bytes).toString(),
            byteLength: bytes.length,
            provenance: ContentProvenance.packaged.name,
            sourceUri: 'asset://immutable.bin',
            reviewState: ContentReviewState.approved.name,
            publicationState: ContentPublicationState.published.name,
            createdAtUtcMs: createdAt.millisecondsSinceEpoch,
            reviewedAtUtcMs: Value(
              createdAt.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
            ),
            publishedAtUtcMs: Value(
              createdAt.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
            ),
          ),
        );

    await expectLater(
      database.customUpdate(
        "UPDATE content_manifests SET source_uri = 'asset://changed.bin' "
        "WHERE id = 'manifest:immutable:r1'",
      ),
      throwsA(anything),
    );
    await expectLater(
      database.customUpdate(
        "DELETE FROM content_manifests WHERE id = 'manifest:immutable:r1'",
      ),
      throwsA(anything),
    );
  });

  test('persisted manifest rejects replace by storage id', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.contentManifests).insert(persistedManifest());
    await expectLater(
      database
          .into(database.contentManifests)
          .insert(persistedManifest(), mode: InsertMode.insertOrIgnore),
      completes,
    );

    await expectLater(
      database
          .into(database.contentManifests)
          .insert(
            persistedManifest(
              contentId: 'artifact:replacement',
              sourceUri: 'asset://replacement.bin',
            ),
            mode: InsertMode.insertOrReplace,
          ),
      throwsA(anything),
    );
  });

  test('persisted manifest rejects replace by content identity', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.into(database.contentManifests).insert(persistedManifest());

    await expectLater(
      database
          .into(database.contentManifests)
          .insert(
            persistedManifest(
              id: 'manifest:replacement:r1',
              sourceUri: 'asset://replacement.bin',
            ),
            mode: InsertMode.insertOrReplace,
          ),
      throwsA(anything),
    );
  });

  test('Drift repository pins reviewed packaged lexical revisions', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customInsert(
      "INSERT INTO local_owners "
      "(id, account_state, created_at_utc_ms, is_active) "
      "VALUES ('packaged-owner', 'localGuest', 1, 0)",
    );
    await database.customInsert(
      "INSERT INTO vocabulary_categories "
      "(id, owner_id, name, normalized_name, created_at_utc_ms, "
      "updated_at_utc_ms) VALUES "
      "('category:pack', 'packaged-owner', 'Pack', 'pack', 1, 1)",
    );
    final wordChecksum = _lexicalChecksum(
      meaning: 'สถานี',
      normalizedMeaning: 'สถานี',
    );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word:station',
            ownerId: 'packaged-owner',
            categoryId: 'category:pack',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            source: const Value('pack:v1'),
            isGlobal: const Value(true),
            contentRevision: const Value(1),
            contentChecksumSha256: Value(wordChecksum),
            contentProvenance: Value(ContentProvenance.packaged.name),
            contentReviewState: Value(ContentReviewState.approved.name),
            contentPublicationState: Value(
              ContentPublicationState.published.name,
            ),
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    final packBytes = _versionedPackBytes(
      wordChecksum: wordChecksum,
      wordRevision: 1,
    );
    await database
        .into(database.contentManifests)
        .insert(
          ContentManifestsCompanion.insert(
            id: 'manifest:pack:travel:r1',
            contentType: ContentType.learningPack.name,
            contentId: 'pack:travel',
            revision: 1,
            checksumSha256: sha256.convert(packBytes).toString(),
            byteLength: packBytes.length,
            provenance: ContentProvenance.packaged.name,
            sourceUri: 'asset://learning-packs/travel-v1.json',
            reviewState: ContentReviewState.approved.name,
            publicationState: ContentPublicationState.published.name,
            createdAtUtcMs: createdAt.millisecondsSinceEpoch,
            reviewedAtUtcMs: Value(
              createdAt.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
            ),
            publishedAtUtcMs: Value(
              createdAt.add(const Duration(minutes: 2)).millisecondsSinceEpoch,
            ),
          ),
        );
    await database
        .into(database.learningPacks)
        .insert(
          LearningPacksCompanion.insert(
            id: 'pack:travel:r1',
            packId: 'pack:travel',
            revision: 1,
            manifestId: 'manifest:pack:travel:r1',
            title: 'Travel basics',
            cefrLevel: 'A1',
            topic: 'travel',
            skill: 'vocabulary',
            goal: 'recognition',
            createdAtUtcMs: createdAt.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.learningPackItems)
        .insert(
          const LearningPackItemsCompanion(
            id: Value('pack:travel:r1:item:0'),
            learningPackId: Value('pack:travel:r1'),
            vocabularyWordId: Value('word:station'),
            position: Value(0),
          ),
        );
    final repository = DriftContentManifestRepository(database);

    const identity = ContentIdentity(
      type: ContentType.learningPack,
      id: 'pack:travel',
      revision: 1,
    );
    final verified = await repository.requireVerified(identity);
    expect(
      verified.manifest.checksumSha256,
      sha256.convert(packBytes).toString(),
    );

    await (database.update(
      database.vocabularyWords,
    )..where((word) => word.id.equals('word:station'))).write(
      VocabularyWordsCompanion(
        contentProvenance: Value(ContentProvenance.userAuthored.name),
        contentReviewState: Value(ContentReviewState.unreviewed.name),
        contentPublicationState: Value(ContentPublicationState.private.name),
      ),
    );
    await expectLater(
      repository.requireVerified(identity),
      throwsA(
        isA<ContentQualityFailure>().having(
          (failure) => failure.code,
          'code',
          ContentQualityFailureCode.missingReference,
        ),
      ),
    );

    final changedChecksum = _lexicalChecksum(
      meaning: 'สถานีรถไฟ',
      normalizedMeaning: 'สถานีรถไฟ',
    );
    await (database.update(
      database.vocabularyWords,
    )..where((word) => word.id.equals('word:station'))).write(
      VocabularyWordsCompanion(
        meaning: const Value('สถานีรถไฟ'),
        normalizedMeaning: const Value('สถานีรถไฟ'),
        contentRevision: const Value(2),
        contentChecksumSha256: Value(changedChecksum),
        contentProvenance: Value(ContentProvenance.packaged.name),
        contentReviewState: Value(ContentReviewState.approved.name),
        contentPublicationState: Value(ContentPublicationState.published.name),
      ),
    );
    await expectLater(
      repository.requireVerified(identity),
      throwsA(isA<ContentQualityFailure>()),
    );

    await database.customUpdate(
      "DELETE FROM vocabulary_words WHERE id = 'word:station'",
    );
    await expectLater(
      repository.requireVerified(identity),
      throwsA(isA<ContentQualityFailure>()),
    );
  });
}

String _lexicalChecksum({
  required String meaning,
  required String normalizedMeaning,
}) => ContentQualityPolicy.vocabularyChecksumSha256(
  categoryId: 'category:pack',
  spelling: 'station',
  normalizedSpelling: 'station',
  meaning: meaning,
  normalizedMeaning: normalizedMeaning,
  partOfSpeech: 'noun',
  cefrLevel: null,
  source: 'pack:v1',
  isGlobal: true,
);

Uint8List _versionedPackBytes({
  required String wordChecksum,
  required int wordRevision,
}) => ContentQualityPolicy.canonicalLearningPackBytes(
  packId: 'pack:travel',
  revision: 1,
  title: 'Travel basics',
  cefrLevel: 'A1',
  topic: 'travel',
  skill: 'vocabulary',
  goal: 'recognition',
  vocabularyReferences: <ContentVocabularyReference>[
    ContentVocabularyReference(
      id: 'word:station',
      revision: wordRevision,
      checksumSha256: wordChecksum,
    ),
  ],
);
