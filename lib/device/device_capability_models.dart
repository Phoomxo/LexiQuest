/// Coarse capability bands used by the on-device inference policy.
enum DevicePerformanceTier { lite, balanced, enhanced }

/// Normalized thermal states that are safe to carry across platform boundaries.
enum DeviceThermalState {
  nominal,
  fair,
  serious,
  critical,
  unknown;

  /// Converts Android's numeric thermal status to the safe internal taxonomy.
  static DeviceThermalState fromNativeValue(int value) {
    switch (value) {
      case 0:
        return DeviceThermalState.nominal;
      case 1:
      case 2:
        return DeviceThermalState.fair;
      case 3:
        return DeviceThermalState.serious;
      case 4:
      case 5:
      case 6:
        return DeviceThermalState.critical;
      default:
        return DeviceThermalState.unknown;
    }
  }

  /// Alias retained for platform adapters that use the shorter conversion name.
  static DeviceThermalState fromNative(int value) => fromNativeValue(value);
}

enum InferenceBackend { xnnpackCpu, gpuDelegate }

enum AnalysisFrequency { low, standard, enhanced }

/// Caller-asserted provenance metadata; it is not proof of hardware execution.
enum InferenceBenchmarkProvenance { assertedOnDeviceInferenceAdapter }

/// Closed, privacy-safe reason codes produced by [InferencePolicy].
enum InferenceDecisionReason {
  cpuBenchmarkDegraded('cpu-benchmark-degraded'),
  sdkUnsupported('sdk-unsupported'),
  capabilityEvidenceMissing('capability-evidence-missing'),
  batterySaver('battery-saver'),
  thermalConstrained('thermal-constrained'),
  lowMemory('low-memory'),
  availableMemoryConstrained('available-memory-constrained'),
  storageConstrained('storage-constrained'),
  balancedMemory('balanced-memory'),
  storageNotEnhanced('storage-not-enhanced'),
  gpuNotCandidate('gpu-not-candidate'),
  gpuBenchmarkMissing('gpu-benchmark-missing'),
  gpuBenchmarkFailed('gpu-benchmark-failed'),
  gpuEvidenceMismatch('gpu-evidence-mismatch'),
  gpuEvidenceProvenanceMissing('gpu-evidence-provenance-missing'),
  gpuSlowerThanCpu('gpu-slower-than-cpu'),
  gpuAdapterUnverified('gpu-adapter-unverified');

  const InferenceDecisionReason(this.code);

  final String code;
}

/// An immutable, privacy-safe view of the capability signals used by policy.
class DeviceCapabilitySnapshot {
  factory DeviceCapabilitySnapshot({
    required int sdkInt,
    required String primaryAbi,
    required int memoryClassMb,
    required int? availableMemoryMb,
    required int? freeStorageBytes,
    required bool? lowMemory,
    required bool? batterySaverEnabled,
    required DeviceThermalState thermalState,
    required bool? gpuApiCandidate,
  }) {
    final normalizedAbi = primaryAbi.trim().toLowerCase();
    if (normalizedAbi.isEmpty) {
      throw ArgumentError.value(primaryAbi, 'primaryAbi', 'must not be empty');
    }
    if (memoryClassMb < 0 ||
        (availableMemoryMb != null && availableMemoryMb < 0) ||
        (freeStorageBytes != null && freeStorageBytes < 0)) {
      throw ArgumentError('memory and storage values must not be negative');
    }

    return DeviceCapabilitySnapshot._(
      sdkInt: sdkInt,
      primaryAbi: normalizedAbi,
      memoryClassMb: memoryClassMb,
      availableMemoryMb: availableMemoryMb,
      freeStorageBytes: freeStorageBytes,
      lowMemory: lowMemory,
      batterySaverEnabled: batterySaverEnabled,
      thermalState: thermalState,
      gpuApiCandidate: gpuApiCandidate,
    );
  }

  const DeviceCapabilitySnapshot._({
    required this.sdkInt,
    required this.primaryAbi,
    required this.memoryClassMb,
    required this.availableMemoryMb,
    required this.freeStorageBytes,
    required this.lowMemory,
    required this.batterySaverEnabled,
    required this.thermalState,
    required this.gpuApiCandidate,
  });

  final int sdkInt;
  final String primaryAbi;
  final int memoryClassMb;
  final int? availableMemoryMb;
  final int? freeStorageBytes;
  final bool? lowMemory;
  final bool? batterySaverEnabled;
  final DeviceThermalState thermalState;
  final bool? gpuApiCandidate;

  bool get isSupported => sdkInt >= 29;

  bool get hasRequiredPolicyEvidence =>
      availableMemoryMb != null &&
      freeStorageBytes != null &&
      lowMemory != null &&
      batterySaverEnabled != null &&
      gpuApiCandidate != null;

  @override
  String toString() => 'DeviceCapabilitySnapshot';
}

/// Result of a bounded benchmark for one inference backend.
///
/// Model identity and provenance are asserted metadata supplied by the caller.
/// This value object and the pure policy can verify internal consistency only;
/// they cannot prove that a backend ran or that a model was loaded. Production
/// adapter construction and loaded-model SHA validation are required later
/// inference-adapter integration work.
class InferenceBenchmark {
  factory InferenceBenchmark({
    required InferenceBackend backend,
    required bool successful,
    int? medianLatencyMicros,
    required int completedRuns,
    String? failureCode,
    required String modelId,
    required String modelVersion,
    required String modelSha256,
    required InferenceBenchmarkProvenance? provenance,
  }) {
    final normalizedModelId = modelId.trim().toLowerCase();
    final normalizedModelVersion = modelVersion.trim();
    final normalizedModelSha256 = modelSha256.trim().toLowerCase();
    if (normalizedModelId.isEmpty ||
        !_semanticVersionPattern.hasMatch(normalizedModelVersion)) {
      throw ArgumentError('model identity values are invalid');
    }
    if (!_sha256Pattern.hasMatch(normalizedModelSha256)) {
      throw ArgumentError.value(
        modelSha256,
        'modelSha256',
        'must be a 64-character hexadecimal SHA-256 fingerprint',
      );
    }
    if (completedRuns < 0 ||
        completedRuns > maximumCompletedRuns ||
        (medianLatencyMicros != null &&
            (medianLatencyMicros < 0 ||
                medianLatencyMicros > maximumMedianLatencyMicros))) {
      throw ArgumentError('benchmark values are outside safe bounds');
    }
    if (successful &&
        (medianLatencyMicros == null ||
            medianLatencyMicros == 0 ||
            completedRuns == 0 ||
            failureCode != null)) {
      throw ArgumentError(
        'successful benchmarks require completed measurements',
      );
    }
    if (!successful &&
        (failureCode == null || !_stableFailureCodes.contains(failureCode))) {
      throw ArgumentError.value(failureCode, 'failureCode', 'is not stable');
    }

    return InferenceBenchmark._(
      backend: backend,
      successful: successful,
      medianLatencyMicros: medianLatencyMicros,
      completedRuns: completedRuns,
      failureCode: failureCode,
      modelId: normalizedModelId,
      modelVersion: normalizedModelVersion,
      modelSha256: normalizedModelSha256,
      provenance: provenance,
    );
  }

  const InferenceBenchmark._({
    required this.backend,
    required this.successful,
    required this.medianLatencyMicros,
    required this.completedRuns,
    required this.failureCode,
    required this.modelId,
    required this.modelVersion,
    required this.modelSha256,
    required this.provenance,
  });

  static const int maximumMedianLatencyMicros = 60000000;
  static const int maximumCompletedRuns = 10000;
  static const Set<String> _stableFailureCodes = {
    'delegate-unavailable',
    'delegate-init-failed',
    'model-unsupported',
    'benchmark-failed',
    'benchmark-missing',
  };
  static final RegExp _sha256Pattern = RegExp(r'^[a-f0-9]{64}$');
  // Supported form is canonical SemVer core only: MAJOR.MINOR.PATCH.
  static final RegExp _semanticVersionPattern = RegExp(
    r'^(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)$',
  );

  final InferenceBackend backend;
  final bool successful;
  final int? medianLatencyMicros;
  final int completedRuns;
  final String? failureCode;
  final String modelId;
  final String modelVersion;
  final String modelSha256;
  final InferenceBenchmarkProvenance? provenance;

  bool hasSameModelAs(InferenceBenchmark other) =>
      modelId == other.modelId &&
      modelVersion == other.modelVersion &&
      modelSha256 == other.modelSha256;

  @override
  String toString() =>
      'InferenceBenchmark(backend: ${backend.name}, failureCode: $failureCode)';
}

/// The single safe configuration selected for a snapshot and its evidence.
final class InferenceDecision {
  factory InferenceDecision.cpu({
    required DevicePerformanceTier tier,
    required AnalysisFrequency analysisFrequency,
    required InferenceDecisionReason reason,
  }) => InferenceDecision._(
    tier: tier,
    backend: InferenceBackend.xnnpackCpu,
    analysisFrequency: analysisFrequency,
    reason: reason,
  );

  const InferenceDecision._({
    required this.tier,
    required this.backend,
    required this.analysisFrequency,
    required this.reason,
  });

  final DevicePerformanceTier tier;
  final InferenceBackend backend;
  final AnalysisFrequency analysisFrequency;
  final InferenceDecisionReason reason;

  String get reasonCode => reason.code;

  @override
  String toString() =>
      'InferenceDecision(tier: ${tier.name}, backend: ${backend.name}, '
      'reasonCode: ${reason.code})';
}
