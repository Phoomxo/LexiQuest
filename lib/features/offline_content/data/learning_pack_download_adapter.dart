import 'dart:io';

import '../../learning_packs/domain/content_manifest.dart';
import '../application/offline_content_manager.dart';

/// Bridges the canonical packaged learning-pack authority into the unified
/// f44 download pipeline. No second pack catalog or checksum is introduced.
final class LearningPackDownloadAdapter
    implements OfflineContentDownloadAdapter {
  const LearningPackDownloadAdapter(this.manifests);

  final ContentManifestRepository manifests;

  @override
  bool supports(ContentManifest manifest) =>
      manifest.identity.type == ContentType.learningPack;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    final verified = await manifests.requireVerified(manifest.identity);
    if (verified.manifest.storageId != manifest.storageId ||
        verified.manifest.checksumSha256 != manifest.checksumSha256 ||
        verified.manifest.byteLength != manifest.byteLength) {
      throw StateError('Learning-pack manifest changed during staging.');
    }
    await temporaryFile.writeAsBytes(verified.bytes, flush: true);
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {
    final verified = await manifests.requireVerified(manifest.identity);
    if (verified.manifest.storageId != manifest.storageId ||
        verified.manifest.checksumSha256 != manifest.checksumSha256 ||
        verified.manifest.byteLength != manifest.byteLength) {
      throw StateError('Learning-pack authority changed after staging.');
    }
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async => 0;

  @override
  Future<int> removeInstalled(ContentManifest manifest) async {
    // The manager owns the only downloaded file for this adapter. Canonical
    // pack rows and vocabulary references deliberately remain durable.
    return 0;
  }
}
