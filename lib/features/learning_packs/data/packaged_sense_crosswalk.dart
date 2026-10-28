import 'dart:typed_data';

import '../domain/content_manifest.dart';
import '../domain/content_quality_policy.dart';
import '../domain/sense_crosswalk.dart';

/// Original starter object meanings only. This does not approve CEFR editorial
/// rows or assert human review, certified levels, or sense-level SRS evidence.
/// Keep this reader and its exact artifact when adding later editions.
abstract final class PackagedSenseCrosswalk {
  static const assetPath = 'assets/content/sense_crosswalk/starter-r1.json';
  static const corpusManifestHash =
      '7aa10e008c208e304ce99cf400ec0f985669bb68eddd3210f15928965f04ba41';
  static const artifactHash =
      'a3a639e9487aa69e7e294f7cd9fc70b222c6ee325bae23844afbfa3e3aa1b115';
  static const identity = ContentIdentity(
    type: ContentType.offlineArtifact,
    id: 'sense-crosswalk:$corpusManifestHash',
    revision: 1,
  );
  static final manifest = ContentManifest(
    storageId: 'manifest:sense-crosswalk:starter:r1',
    identity: identity,
    checksumSha256: artifactHash,
    byteLength: 4830,
    provenance: ContentProvenance.packaged,
    sourceUri: 'asset://content/sense_crosswalk/starter-r1.json',
    reviewState: ContentReviewState.approved,
    publicationState: ContentPublicationState.published,
    createdAtUtc: DateTime.utc(2026, 9, 20),
    reviewedAtUtc: DateTime.utc(2026, 9, 20),
    publishedAtUtc: DateTime.utc(2026, 9, 20),
  );

  static VerifiedContentManifest verify(Uint8List bytes) {
    decode(bytes);
    return const ContentQualityPolicy().requireVerified(
      manifest: manifest,
      bytes: bytes,
    );
  }

  static SenseCrosswalk decode(Uint8List bytes) => SenseCrosswalk.fromBytes(
    bytes,
    expectedSha256: artifactHash,
    corpusManifestHash: corpusManifestHash,
    reviewManifest: manifest,
  );
}
