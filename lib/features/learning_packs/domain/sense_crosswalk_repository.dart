import 'content_manifest.dart';
import 'content_quality_policy.dart';
import 'sense_crosswalk.dart';

/// Pin to serialize with every personal revision, alongside its SenseRefs. Neither
/// a corpus ID alone nor a current-edition lookup can recover this binding.
final class SenseCrosswalkPin {
  const SenseCrosswalkPin._(
    this.corpusManifestHash,
    this.revision,
    this.artifactHash,
  );

  factory SenseCrosswalkPin.fromJson(Map<String, Object?> json) {
    final corpus = json['corpusManifestHash'];
    final revision = json['revision'];
    final artifact = json['artifactHash'];
    if (json.length != 3 ||
        corpus is! String ||
        !_sha256.hasMatch(corpus) ||
        artifact is! String ||
        !_sha256.hasMatch(artifact) ||
        revision is! int ||
        revision <= 0 ||
        revision > 0x7fffffff) {
      throw const FormatException('Invalid crosswalk pin');
    }
    return SenseCrosswalkPin._(corpus, revision, artifact);
  }
  final String corpusManifestHash, artifactHash;
  final int revision;
  ContentIdentity get identity => ContentIdentity(
    type: ContentType.offlineArtifact,
    id: 'sense-crosswalk:$corpusManifestHash',
    revision: revision,
  );
  Map<String, Object?> toJson() => {
    'corpusManifestHash': corpusManifestHash,
    'revision': revision,
    'artifactHash': artifactHash,
  };
}

final class SenseCrosswalkRepository {
  const SenseCrosswalkRepository(this.manifests);
  final ContentManifestRepository manifests;

  Future<SenseCrosswalk> requirePinned(SenseCrosswalkPin pin) async {
    final artifact = await manifests.requireVerified(pin.identity);
    if (artifact.manifest.identity != pin.identity ||
        artifact.manifest.checksumSha256 != pin.artifactHash) {
      throw const ContentQualityFailure(
        ContentQualityFailureCode.missingReference,
      );
    }
    // Do not trust a publicly constructible VerifiedContentManifest wrapper.
    // The decoder rechecks the current review/publication state and exact bytes.
    return SenseCrosswalk.fromBytes(
      artifact.bytes,
      expectedSha256: pin.artifactHash,
      corpusManifestHash: pin.corpusManifestHash,
      reviewManifest: artifact.manifest,
    );
  }
}

final _sha256 = RegExp(r'^[0-9a-f]{64}$');
