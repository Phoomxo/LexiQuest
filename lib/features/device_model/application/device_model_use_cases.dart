import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

import '../domain/model_lifecycle.dart';
import '../domain/model_manifest.dart';
import 'model_benchmark.dart';
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

  Future<List<ModelBenchmarkResult>> benchmarkActive({
    required String deviceTier,
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) async {
    final tensorElements = manifest.inputShape.fold<int>(
      1,
      (product, dimension) => product * dimension,
    );
    final bytesPerElement = switch (manifest.inputType) {
      ModelTensorType.uint8 => 1,
      ModelTensorType.float32 => 4,
    };
    final input = Uint8List(tensorElements * bytesPerElement);
    final results = <ModelBenchmarkResult>[];
    for (final delegate in const [ModelDelegate.cpu, ModelDelegate.xnnpack]) {
      if (!manifest.supportedDelegates.contains(delegate)) continue;
      final runtime = await openActive(delegate: delegate);
      try {
        results.add(
          await ModelBenchmark(runtime: runtime).run(
            input: input,
            delegate: delegate,
            modelId: manifest.id,
            modelVersion: manifest.version,
            deviceTier: deviceTier,
            warmupRuns: warmupRuns,
            measuredRuns: measuredRuns,
          ),
        );
      } finally {
        runtime.close();
      }
    }
    return List<ModelBenchmarkResult>.unmodifiable(results);
  }

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
