import 'dart:typed_data';

/// Bounded f04 lexical artifact envelope, including two maximum-length f18
/// rationales encoded with four-byte Unicode scalar values.
const int maxLexicalMetadataArtifactBytes = 48 * 1024;

enum ContentType {
  learningPack,
  lexicalMetadata,
  assessmentForm,
  offlineArtifact,
}

enum ContentProvenance { packaged, userAuthored }

enum ContentReviewState { unreviewed, approved, rejected }

enum ContentPublicationState { private, published, retired }

final class ContentIdentity {
  const ContentIdentity({
    required this.type,
    required this.id,
    required this.revision,
  });

  final ContentType type;
  final String id;
  final int revision;

  @override
  bool operator ==(Object other) =>
      other is ContentIdentity &&
      other.type == type &&
      other.id == id &&
      other.revision == revision;

  @override
  int get hashCode => Object.hash(type, id, revision);
}

final class ContentManifest {
  const ContentManifest({
    required this.storageId,
    required this.identity,
    required this.checksumSha256,
    required this.byteLength,
    required this.provenance,
    required this.sourceUri,
    required this.reviewState,
    required this.publicationState,
    required this.createdAtUtc,
    required this.reviewedAtUtc,
    required this.publishedAtUtc,
  });

  final String storageId;
  final ContentIdentity identity;
  final String checksumSha256;
  final int byteLength;
  final ContentProvenance provenance;
  final String sourceUri;
  final ContentReviewState reviewState;
  final ContentPublicationState publicationState;
  final DateTime createdAtUtc;
  final DateTime? reviewedAtUtc;
  final DateTime? publishedAtUtc;
}

final class VerifiedContentManifest {
  const VerifiedContentManifest({required this.manifest, required this.bytes});

  final ContentManifest manifest;
  final Uint8List bytes;
}

final class ContentVocabularyReference {
  const ContentVocabularyReference({
    required this.id,
    required this.revision,
    required this.checksumSha256,
  });

  final String id;
  final int revision;
  final String checksumSha256;
}

/// Immutable identity of the optional rich lexical artifact observed when a
/// durable review queue item was composed.
final class ReviewedLexicalArtifactSnapshot {
  ReviewedLexicalArtifactSnapshot({
    required this.storageId,
    required this.identity,
    required this.checksumSha256,
    required this.byteLength,
  }) {
    _requireSnapshotText(storageId, 'storageId');
    if (identity.type != ContentType.lexicalMetadata ||
        identity.revision <= 0 ||
        !_snapshotSha256.hasMatch(checksumSha256) ||
        byteLength <= 0) {
      throw ArgumentError('invalid reviewed lexical artifact snapshot');
    }
  }

  final String storageId;
  final ContentIdentity identity;
  final String checksumSha256;
  final int byteLength;

  @override
  bool operator ==(Object other) =>
      other is ReviewedLexicalArtifactSnapshot &&
      other.storageId == storageId &&
      other.identity == identity &&
      other.checksumSha256 == checksumSha256 &&
      other.byteLength == byteLength;

  @override
  int get hashCode =>
      Object.hash(storageId, identity, checksumSha256, byteLength);
}

/// Exact lexical row and availability-policy token reviewed by the user.
/// This value crosses the queue-to-session transaction boundary unchanged.
final class ReviewedLexicalContentSnapshot {
  ReviewedLexicalContentSnapshot({
    required this.identity,
    required this.categoryId,
    required this.spelling,
    required this.normalizedSpelling,
    required this.meaning,
    required this.normalizedMeaning,
    required this.partOfSpeech,
    required this.cefrLevel,
    required this.source,
    required this.isGlobal,
    required this.coreChecksumSha256,
    required this.provenance,
    required this.reviewState,
    required this.publicationState,
    required this.artifact,
  }) {
    if (identity.type != ContentType.lexicalMetadata ||
        identity.revision <= 0 ||
        !_snapshotSha256.hasMatch(coreChecksumSha256)) {
      throw ArgumentError('invalid reviewed lexical content identity');
    }
    for (final entry in <MapEntry<String, String>>[
      MapEntry('identity.id', identity.id),
      MapEntry('categoryId', categoryId),
      MapEntry('spelling', spelling),
      MapEntry('normalizedSpelling', normalizedSpelling),
      MapEntry('meaning', meaning),
      MapEntry('normalizedMeaning', normalizedMeaning),
      MapEntry('partOfSpeech', partOfSpeech),
      MapEntry('source', source),
    ]) {
      _requireSnapshotText(entry.value, entry.key);
    }
    final artifactIdentity = artifact?.identity;
    if (artifactIdentity != null && artifactIdentity != identity) {
      throw ArgumentError('reviewed artifact does not match lexical content');
    }
  }

  final ContentIdentity identity;
  final String categoryId;
  final String spelling;
  final String normalizedSpelling;
  final String meaning;
  final String normalizedMeaning;
  final String partOfSpeech;
  final String? cefrLevel;
  final String source;
  final bool isGlobal;
  final String coreChecksumSha256;
  final ContentProvenance provenance;
  final ContentReviewState reviewState;
  final ContentPublicationState publicationState;
  final ReviewedLexicalArtifactSnapshot? artifact;
}

abstract interface class ContentManifestRepository {
  Future<VerifiedContentManifest> requireVerified(ContentIdentity identity);
}

void _requireSnapshotText(String value, String name) {
  if (value.isEmpty || value != value.trim() || value.runes.length > 1024) {
    throw ArgumentError.value(value, name, 'must be canonical nonblank text');
  }
}

final RegExp _snapshotSha256 = RegExp(r'^[0-9a-f]{64}$');
