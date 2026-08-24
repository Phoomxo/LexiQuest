import 'dart:typed_data';

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

abstract interface class ContentManifestRepository {
  Future<VerifiedContentManifest> requireVerified(ContentIdentity identity);
}
