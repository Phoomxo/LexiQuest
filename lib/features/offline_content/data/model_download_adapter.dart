import 'dart:io';

import 'package:crypto/crypto.dart';

import '../../device_model/application/model_download_manager.dart';
import '../../device_model/domain/model_manifest.dart';
import '../../device_model/domain/model_lifecycle.dart';
import '../../learning_packs/domain/content_manifest.dart';
import '../application/offline_content_manager.dart';
import '../domain/offline_content_state.dart';

typedef OfflineModelManifestResolver =
    ModelManifest? Function(ContentIdentity identity);
typedef OfflineModelRemoval = Future<void> Function(ModelManifest manifest);

/// Adapter over the existing verified model lifecycle. The existing manager
/// remains the sole model download/activation authority; f44 stores a verified
/// copy under the shared content-download state only after that authority
/// succeeds.
final class ModelDownloadAdapter
    implements
        OfflineContentDownloadAdapter,
        OfflineContentRemovalLeaseAdapter {
  const ModelDownloadAdapter({
    required this.manager,
    required this.resolveManifest,
    this.removeModel,
  });

  final ModelDownloadManager manager;
  final OfflineModelManifestResolver resolveManifest;
  final OfflineModelRemoval? removeModel;

  @override
  bool supports(ContentManifest manifest) =>
      manifest.identity.type == ContentType.offlineArtifact &&
      resolveManifest(manifest.identity) != null;

  @override
  Future<void> stage(ContentManifest manifest, File temporaryFile) async {
    final model = resolveManifest(manifest.identity);
    if (model == null ||
        model.expectedSha256 != manifest.checksumSha256 ||
        model.expectedBytes != manifest.byteLength) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final installed = await manager.downloadAndActivate(model);
    final path = installed.localPath;
    if (path == null || path.isEmpty) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    }
    await requireInstalledValid(manifest);
    await File(path).copy(temporaryFile.path);
  }

  @override
  Future<void> requireInstalledValid(ContentManifest manifest) async {
    final model = resolveManifest(manifest.identity);
    if (model == null ||
        model.expectedSha256 != manifest.checksumSha256 ||
        model.expectedBytes != manifest.byteLength) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final record = await manager.repository.find(model.recordId);
    final path = record?.localPath;
    if (record == null ||
        path == null ||
        (record.state != ModelDownloadState.ready &&
            record.state != ModelDownloadState.active) ||
        record.id != model.recordId ||
        record.modelVersion != model.version ||
        record.expectedChecksum != model.expectedSha256 ||
        record.expectedBytes != model.expectedBytes ||
        record.downloadedBytes != model.expectedBytes) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    }
    final root = await manager.modelDirectory();
    await root.create(recursive: true);
    final resolvedRoot = await root.absolute.resolveSymbolicLinks();
    final expectedPath =
        '$resolvedRoot${Platform.pathSeparator}${model.fileStem}.tflite';
    final file = File(path);
    if (!await file.exists()) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    }
    final resolvedFile = await file.absolute.resolveSymbolicLinks();
    final prefix = '$resolvedRoot${Platform.pathSeparator}';
    if (!_pathStartsWith(resolvedFile, prefix) ||
        _normalizedPath(resolvedFile) != _normalizedPath(expectedPath) ||
        await file.length() != model.expectedBytes ||
        (await file.openRead().transform(sha256).single).toString() !=
            model.expectedSha256) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.checksumMismatch,
      );
    }
    try {
      await manager.verifier.verify(resolvedFile, model);
    } on Object catch (error) {
      throw OfflineContentFailure(
        OfflineContentFailureCode.invalidState,
        error,
      );
    }
  }

  @override
  Future<int> installedBytes(ContentManifest manifest) async {
    final model = resolveManifest(manifest.identity);
    if (model == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    await requireInstalledValid(manifest);
    final file = await _canonicalModelFile(model);
    return file.length();
  }

  @override
  Future<int> removeInstalled(ContentManifest manifest) async {
    return withRemovalLease(manifest, (removeInstalled) => removeInstalled());
  }

  @override
  Future<T> withRemovalLease<T>(
    ContentManifest manifest,
    Future<T> Function(OfflineInstalledContentRemoval removeInstalled)
    operation,
  ) async {
    final model = resolveManifest(manifest.identity);
    if (model == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.revisionMismatch,
      );
    }
    final removal = removeModel;
    if (removal == null) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.unsupportedContent,
      );
    }
    try {
      return await manager.withRemovalLease(
        model,
        (removeModelBytes) => operation(
          () => removeModelBytes(removeRecord: () => removal(model)),
        ),
      );
    } on ModelLifecycleException catch (error) {
      final code = switch (error.code) {
        ModelFailureCode.checksumMismatch ||
        ModelFailureCode.interpreterRejected =>
          OfflineContentFailureCode.checksumMismatch,
        _ => OfflineContentFailureCode.invalidState,
      };
      throw OfflineContentFailure(code, error);
    }
  }

  Future<File> _canonicalModelFile(ModelManifest model) async {
    final root = await manager.modelDirectory();
    await root.create(recursive: true);
    final absoluteRoot = root.absolute;
    final resolvedRoot = await absoluteRoot.resolveSymbolicLinks();
    if (_normalizedPath(absoluteRoot.path) != _normalizedPath(resolvedRoot)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final file = File(
      '$resolvedRoot${Platform.pathSeparator}${model.fileStem}.tflite',
    );
    final type = await FileSystemEntity.type(file.path, followLinks: false);
    if (type == FileSystemEntityType.notFound) {
      throw const OfflineContentFailure(
        OfflineContentFailureCode.missingArtifact,
      );
    }
    if (type != FileSystemEntityType.file) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    final resolvedFile = await file.absolute.resolveSymbolicLinks();
    if (_normalizedPath(resolvedFile) != _normalizedPath(file.absolute.path)) {
      throw const OfflineContentFailure(OfflineContentFailureCode.invalidState);
    }
    return file;
  }
}

bool _pathStartsWith(String value, String prefix) {
  if (Platform.isWindows) {
    return value.toLowerCase().startsWith(prefix.toLowerCase());
  }
  return value.startsWith(prefix);
}

String _normalizedPath(String value) {
  final normalized = value.replaceAll('\\', '/');
  return Platform.isWindows ? normalized.toLowerCase() : normalized;
}
