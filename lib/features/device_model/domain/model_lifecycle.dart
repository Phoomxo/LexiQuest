import 'dart:async';
import 'dart:typed_data';

enum ModelDownloadState {
  notStarted,
  downloading,
  verifying,
  ready,
  active,
  failed,
  cancelled,
}

enum ModelFailureCode {
  network,
  invalidResponse,
  writeFailed,
  sizeMismatch,
  checksumMismatch,
  interpreterRejected,
  incompatibleTensor,
  unavailable,
  cancelled,
  busy,
}

enum ModelDelegate { cpu, xnnpack, gpu }

final class ModelLifecycleException implements Exception {
  const ModelLifecycleException(this.code);

  final ModelFailureCode code;

  @override
  String toString() => 'ModelLifecycleException(${code.name})';
}

final class ModelCancellation {
  final Completer<void> _cancelled = Completer<void>();
  bool _isCancelled = false;

  bool get isCancelled => _isCancelled;
  Future<void> get whenCancelled => _cancelled.future;

  void cancel() {
    if (_isCancelled) return;
    _isCancelled = true;
    _cancelled.complete();
  }
}

final class ModelDownloadRecord {
  const ModelDownloadRecord({
    required this.id,
    required this.modelVersion,
    required this.sourceUrl,
    required this.expectedChecksum,
    required this.expectedBytes,
    required this.downloadedBytes,
    required this.retryCount,
    required this.state,
    required this.updatedAtUtc,
    this.localPath,
    this.failureCode,
  });

  final String id;
  final String modelVersion;
  final String sourceUrl;
  final String expectedChecksum;
  final int expectedBytes;
  final int downloadedBytes;
  final int retryCount;
  final ModelDownloadState state;
  final DateTime updatedAtUtc;
  final String? localPath;
  final ModelFailureCode? failureCode;

  ModelDownloadRecord copyWith({
    int? downloadedBytes,
    int? retryCount,
    ModelDownloadState? state,
    DateTime? updatedAtUtc,
    String? localPath,
    bool clearFailure = false,
    ModelFailureCode? failureCode,
  }) {
    return ModelDownloadRecord(
      id: id,
      modelVersion: modelVersion,
      sourceUrl: sourceUrl,
      expectedChecksum: expectedChecksum,
      expectedBytes: expectedBytes,
      downloadedBytes: downloadedBytes ?? this.downloadedBytes,
      retryCount: retryCount ?? this.retryCount,
      state: state ?? this.state,
      updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
      localPath: localPath ?? this.localPath,
      failureCode: clearFailure ? null : failureCode ?? this.failureCode,
    );
  }
}

abstract interface class ModelRuntime {
  Future<void> run(Uint8List input);
}

final class ModelClassification {
  const ModelClassification({
    required this.index,
    required this.label,
    required this.confidence,
  });

  final int index;
  final String label;
  final double confidence;
}

abstract interface class ImageClassifierRuntime implements ModelRuntime {
  ModelDelegate get delegate;

  Future<List<ModelClassification>> classify(
    Uint8List rgbBytes, {
    int topK = 5,
  });

  void close();
}

final class DeviceModelFingerprint {
  const DeviceModelFingerprint({
    required this.manufacturer,
    required this.model,
    required this.androidSdk,
    required this.gpuDriver,
  });

  final String manufacturer;
  final String model;
  final int androidSdk;
  final String gpuDriver;

  @override
  bool operator ==(Object other) =>
      other is DeviceModelFingerprint &&
      other.manufacturer == manufacturer &&
      other.model == model &&
      other.androidSdk == androidSdk &&
      other.gpuDriver == gpuDriver;

  @override
  int get hashCode => Object.hash(manufacturer, model, androidSdk, gpuDriver);
}

final class GpuAllowlistEntry {
  const GpuAllowlistEntry({
    required this.modelId,
    required this.modelVersion,
    required this.fingerprint,
  });

  final String modelId;
  final String modelVersion;
  final DeviceModelFingerprint fingerprint;

  @override
  bool operator ==(Object other) =>
      other is GpuAllowlistEntry &&
      other.modelId == modelId &&
      other.modelVersion == modelVersion &&
      other.fingerprint == fingerprint;

  @override
  int get hashCode => Object.hash(modelId, modelVersion, fingerprint);
}

abstract final class ModelDelegatePolicy {
  // GPU execution stays disabled until an Android hardware gate proves the
  // delegate, driver fingerprint, thermal behaviour, and fallback path.
  static const bool gpuDelegateAvailable = false;

  static ModelDelegate select({
    required bool requestGpu,
    required String modelId,
    required String modelVersion,
    required DeviceModelFingerprint fingerprint,
    required Set<GpuAllowlistEntry> gpuAllowlist,
  }) {
    if (gpuDelegateAvailable &&
        requestGpu &&
        gpuAllowlist.contains(
          GpuAllowlistEntry(
            modelId: modelId,
            modelVersion: modelVersion,
            fingerprint: fingerprint,
          ),
        )) {
      return ModelDelegate.gpu;
    }
    return ModelDelegate.xnnpack;
  }
}
