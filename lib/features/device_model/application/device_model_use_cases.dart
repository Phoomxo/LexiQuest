import 'dart:io';

import 'package:crypto/crypto.dart';

import '../domain/model_lifecycle.dart';
import '../domain/model_manifest.dart';
import 'model_download_manager.dart';

typedef ImageRuntimeFactory =
    Future<ImageClassifierRuntime> Function({
      required String path,
      required ModelManifest manifest,
      required ModelDelegate delegate,
    });

final class DeviceModelUseCases {
  const DeviceModelUseCases({
    required this.manifest,
    required this.repository,
    required this.downloadManager,
    required this.openRuntime,
  });

  final ModelManifest manifest;
  final ModelDownloadRepository repository;
  final ModelDownloadManager downloadManager;
  final ImageRuntimeFactory openRuntime;

  Future<ModelDownloadRecord?> status() {
    return repository.find(manifest.recordId);
  }

  Future<ModelDownloadRecord> downloadAndActivate({
    ModelCancellation? cancellation,
  }) {
    return downloadManager.downloadAndActivate(
      manifest,
      cancellation: cancellation,
    );
  }

  Future<void> dispose() => downloadManager.dispose();

  Future<ImageClassifierRuntime> openActive({
    ModelDelegate delegate = ModelDelegate.xnnpack,
  }) async {
    final record = await repository.find(manifest.recordId);
    final path = record?.localPath;
    if (record == null ||
        record.state != ModelDownloadState.active ||
        path == null ||
        !manifest.supportedDelegates.contains(delegate)) {
      throw const ModelLifecycleException(ModelFailureCode.unavailable);
    }
    final file = File(path);
    final exists = await file.exists();
    final length = exists ? await file.length() : 0;
    final digest = exists && length == manifest.expectedBytes
        ? await file.openRead().transform(sha256).single
        : null;
    if (digest?.toString() != manifest.expectedSha256) {
      await repository.save(
        record.copyWith(
          state: ModelDownloadState.failed,
          downloadedBytes: length,
          updatedAtUtc: DateTime.now().toUtc(),
          failureCode: ModelFailureCode.checksumMismatch,
        ),
      );
      throw const ModelLifecycleException(ModelFailureCode.checksumMismatch);
    }
    return openRuntime(path: path, manifest: manifest, delegate: delegate);
  }
}
