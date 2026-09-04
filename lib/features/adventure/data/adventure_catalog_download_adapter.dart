import 'dart:io';

import '../../learning_packs/domain/content_manifest.dart';
import '../../offline_content/application/offline_content_manager.dart';
import 'packaged_adventure_world_catalog.dart';

/// Installs the reviewed Adventure catalog bundle through the existing
/// offline-content authority. The product catalog and recoverable bytes share
/// one immutable identity and checksum.
final class AdventureCatalogDownloadAdapter
    implements OfflineContentDownloadAdapter {
  const AdventureCatalogDownloadAdapter();

  @override
  bool supports(ContentManifest manifest) =>
      manifest.identity == PackagedAdventureWorldCatalog.contentIdentity;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    _requireExact(manifest);
    await temporaryFile.writeAsBytes(
      PackagedAdventureWorldCatalog.bundleBytes,
      flush: true,
    );
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {
    _requireExact(manifest);
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async {
    _requireExact(manifest);
    return 0;
  }

  @override
  Future<int> removeInstalled(ContentManifest manifest) async {
    _requireExact(manifest);
    return 0;
  }

  void _requireExact(ContentManifest manifest) {
    final expected = PackagedAdventureWorldCatalog.contentArtifact.manifest;
    if (manifest.storageId != expected.storageId ||
        manifest.identity != expected.identity ||
        manifest.checksumSha256 != expected.checksumSha256 ||
        manifest.byteLength != expected.byteLength) {
      throw StateError('Adventure catalog manifest identity changed.');
    }
  }
}
