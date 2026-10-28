import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/content_manifest.dart';
import '../domain/content_quality_policy.dart';

typedef ContentArtifactBytesLoader =
    Future<Uint8List?> Function(ContentIdentity identity);

final class DriftContentManifestRepository
    implements ContentManifestRepository {
  const DriftContentManifestRepository(
    this.database, {
    this.policy = const ContentQualityPolicy(),
    this.loadArtifactBytes,
  });

  final AppDatabase database;
  final ContentQualityPolicy policy;
  final ContentArtifactBytesLoader? loadArtifactBytes;

  /// Provisions a compile-time reviewed packaged artifact through the existing
  /// f04 manifest authority. Replays are byte-equivalent no-ops; any row or
  /// identity collision fails closed through the immutable-revision contract.
  Future<void> provisionPackagedArtifact(
    VerifiedContentManifest artifact,
  ) async {
    final verified = policy.requireVerified(
      manifest: artifact.manifest,
      bytes: artifact.bytes,
    );
    final manifest = verified.manifest;
    if (manifest.provenance != ContentProvenance.packaged) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingProvenance,
      );
    }
    await database.transaction(() async {
      final collisions =
          await (database.select(database.contentManifests)..where(
                (row) =>
                    row.id.equals(manifest.storageId) |
                    (row.contentType.equals(manifest.identity.type.name) &
                        row.contentId.equals(manifest.identity.id) &
                        row.revision.equals(manifest.identity.revision)),
              ))
              .get();
      if (collisions.isNotEmpty) {
        if (collisions.length == 1 &&
            _sameManifestRow(collisions.single, manifest)) {
          return;
        }
        throw const ContentQualityFailure(
          ContentQualityFailureCode.immutableRevisionConflict,
        );
      }
      await database
          .into(database.contentManifests)
          .insert(
            ContentManifestsCompanion.insert(
              id: manifest.storageId,
              contentType: manifest.identity.type.name,
              contentId: manifest.identity.id,
              revision: manifest.identity.revision,
              checksumSha256: manifest.checksumSha256,
              byteLength: manifest.byteLength,
              provenance: manifest.provenance.name,
              sourceUri: manifest.sourceUri,
              reviewState: manifest.reviewState.name,
              publicationState: manifest.publicationState.name,
              createdAtUtcMs: manifest.createdAtUtc.millisecondsSinceEpoch,
              reviewedAtUtcMs: Value<int>(
                manifest.reviewedAtUtc!.millisecondsSinceEpoch,
              ),
              publishedAtUtcMs: Value<int>(
                manifest.publishedAtUtc!.millisecondsSinceEpoch,
              ),
            ),
          );
    });
  }

  @override
  Future<VerifiedContentManifest> requireVerified(
    ContentIdentity identity,
  ) async {
    final row =
        await (database.select(database.contentManifests)..where(
              (candidate) =>
                  candidate.contentType.equals(identity.type.name) &
                  candidate.contentId.equals(identity.id) &
                  candidate.revision.equals(identity.revision),
            ))
            .getSingleOrNull();
    if (row == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    final manifest = _manifest(row);
    return switch (identity.type) {
      ContentType.learningPack => _requireVerifiedLearningPack(manifest),
      ContentType.lexicalMetadata ||
      ContentType.assessmentForm ||
      ContentType.offlineArtifact => _requireLoadedArtifact(manifest),
    };
  }

  Future<VerifiedContentManifest> _requireVerifiedLearningPack(
    ContentManifest manifest,
  ) async {
    final pack =
        await (database.select(database.learningPacks)..where(
              (candidate) =>
                  candidate.manifestId.equals(manifest.storageId) &
                  candidate.packId.equals(manifest.identity.id) &
                  candidate.revision.equals(manifest.identity.revision),
            ))
            .getSingleOrNull();
    if (pack == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    final items =
        await (database.select(database.learningPackItems)
              ..where((candidate) => candidate.learningPackId.equals(pack.id))
              ..orderBy([
                (candidate) => OrderingTerm.asc(candidate.position),
                (candidate) => OrderingTerm.asc(candidate.id),
              ]))
            .get();
    if (items.isEmpty ||
        items.indexed.any((entry) => entry.$1 != entry.$2.position)) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    final wordIds = items
        .map((item) => item.vocabularyWordId)
        .toList(growable: false);
    final words = await (database.select(
      database.vocabularyWords,
    )..where((candidate) => candidate.id.isIn(wordIds))).get();
    final wordsById = <String, VocabularyWord>{
      for (final word in words) word.id: word,
    };
    final references = <ContentVocabularyReference>[];
    for (final wordId in wordIds) {
      final word = wordsById[wordId];
      final checksum = word?.contentChecksumSha256;
      if (word == null ||
          word.isDeleted ||
          !word.isGlobal ||
          word.contentRevision <= 0 ||
          checksum == null ||
          word.contentProvenance != ContentProvenance.packaged.name ||
          word.contentReviewState != ContentReviewState.approved.name ||
          word.contentPublicationState !=
              ContentPublicationState.published.name ||
          checksum !=
              ContentQualityPolicy.vocabularyChecksumSha256(
                categoryId: word.categoryId,
                spelling: word.spelling,
                normalizedSpelling: word.normalizedSpelling,
                meaning: word.meaning,
                normalizedMeaning: word.normalizedMeaning,
                partOfSpeech: word.partOfSpeech,
                cefrLevel: word.cefrLevel,
                source: word.source,
                isGlobal: word.isGlobal,
              )) {
        throw const ContentQualityFailure(
          ContentQualityFailureCode.missingReference,
        );
      }
      references.add(
        ContentVocabularyReference(
          id: word.id,
          revision: word.contentRevision,
          checksumSha256: checksum,
        ),
      );
    }
    final bytes = ContentQualityPolicy.canonicalLearningPackBytes(
      packId: pack.packId,
      revision: pack.revision,
      title: pack.title,
      cefrLevel: pack.cefrLevel,
      topic: pack.topic,
      skill: pack.skill,
      goal: pack.goal,
      vocabularyReferences: references,
    );
    return policy.requireVerified(
      manifest: manifest,
      bytes: bytes,
      referencedVocabularyIds: wordIds,
      knownVocabularyIds: references.map((reference) => reference.id).toSet(),
    );
  }

  Future<VerifiedContentManifest> _requireLoadedArtifact(
    ContentManifest manifest,
  ) async {
    final bytes = await loadArtifactBytes?.call(manifest.identity);
    if (bytes == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    return policy.requireVerified(manifest: manifest, bytes: bytes);
  }

  ContentManifest _manifest(ContentManifestRow row) {
    final provenance = _enumByName(ContentProvenance.values, row.provenance);
    if (provenance == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingProvenance,
      );
    }
    final reviewState = _enumByName(ContentReviewState.values, row.reviewState);
    final publicationState = _enumByName(
      ContentPublicationState.values,
      row.publicationState,
    );
    if (reviewState == null || publicationState == null) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.invalidLifecycle,
      );
    }
    return ContentManifest(
      storageId: row.id,
      identity: ContentIdentity(
        type:
            _enumByName(ContentType.values, row.contentType) ??
            (throw const ContentQualityFailure(
              ContentQualityFailureCode.invalidIdentity,
            )),
        id: row.contentId,
        revision: row.revision,
      ),
      checksumSha256: row.checksumSha256,
      byteLength: row.byteLength,
      provenance: provenance,
      sourceUri: row.sourceUri,
      reviewState: reviewState,
      publicationState: publicationState,
      createdAtUtc: _utc(row.createdAtUtcMs),
      reviewedAtUtc: row.reviewedAtUtcMs == null
          ? null
          : _utc(row.reviewedAtUtcMs!),
      publishedAtUtc: row.publishedAtUtcMs == null
          ? null
          : _utc(row.publishedAtUtcMs!),
    );
  }
}

bool _sameManifestRow(ContentManifestRow row, ContentManifest manifest) =>
    row.id == manifest.storageId &&
    row.contentType == manifest.identity.type.name &&
    row.contentId == manifest.identity.id &&
    row.revision == manifest.identity.revision &&
    row.checksumSha256 == manifest.checksumSha256 &&
    row.byteLength == manifest.byteLength &&
    row.provenance == manifest.provenance.name &&
    row.sourceUri == manifest.sourceUri &&
    row.reviewState == manifest.reviewState.name &&
    row.publicationState == manifest.publicationState.name &&
    row.createdAtUtcMs == manifest.createdAtUtc.millisecondsSinceEpoch &&
    row.reviewedAtUtcMs == manifest.reviewedAtUtc?.millisecondsSinceEpoch &&
    row.publishedAtUtcMs == manifest.publishedAtUtc?.millisecondsSinceEpoch;

T? _enumByName<T extends Enum>(Iterable<T> values, String name) {
  for (final value in values) {
    if (value.name == name) return value;
  }
  return null;
}

DateTime _utc(int millisecondsSinceEpoch) =>
    DateTime.fromMillisecondsSinceEpoch(millisecondsSinceEpoch, isUtc: true);
