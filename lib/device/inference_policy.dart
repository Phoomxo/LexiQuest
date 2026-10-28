import 'device_capability_models.dart';

/// Deterministically selects the safest advisory inference configuration.
///
/// This pure policy checks asserted evidence metadata for consistency. It does
/// not initialize XNNPACK or a GPU delegate, prove hardware execution, or
/// validate a loaded model's SHA-256. Therefore production selection remains
/// on XNNPACK CPU until later adapter-owned evidence is implemented.
class InferencePolicy {
  InferencePolicy._();

  static const int _minimumAvailableMemoryMb = 768;
  static const int _enhancedAvailableMemoryMb = 2048;
  static const int _minimumFreeStorageBytes = 512 * 1024 * 1024;
  static const int _enhancedFreeStorageBytes = 1024 * 1024 * 1024;

  static InferenceDecision select(
    DeviceCapabilitySnapshot snapshot,
    InferenceBenchmark cpuBenchmark, [
    InferenceBenchmark? gpuBenchmark,
  ]) {
    if (!snapshot.hasRequiredPolicyEvidence) {
      return _lite(InferenceDecisionReason.capabilityEvidenceMissing);
    }
    if (cpuBenchmark.backend != InferenceBackend.xnnpackCpu ||
        !cpuBenchmark.successful) {
      return _lite(InferenceDecisionReason.cpuBenchmarkDegraded);
    }
    if (!snapshot.isSupported) {
      return _lite(InferenceDecisionReason.sdkUnsupported);
    }
    if (snapshot.batterySaverEnabled!) {
      return _lite(InferenceDecisionReason.batterySaver);
    }
    if (_isThermallyConstrained(snapshot.thermalState)) {
      return _lite(InferenceDecisionReason.thermalConstrained);
    }
    if (snapshot.lowMemory!) {
      return _lite(InferenceDecisionReason.lowMemory);
    }
    if (snapshot.availableMemoryMb! < _minimumAvailableMemoryMb) {
      return _lite(InferenceDecisionReason.availableMemoryConstrained);
    }
    if (snapshot.freeStorageBytes! < _minimumFreeStorageBytes) {
      return _lite(InferenceDecisionReason.storageConstrained);
    }
    if (snapshot.availableMemoryMb! < _enhancedAvailableMemoryMb) {
      return _balanced(InferenceDecisionReason.balancedMemory);
    }
    if (snapshot.freeStorageBytes! < _enhancedFreeStorageBytes) {
      return _balanced(InferenceDecisionReason.storageNotEnhanced);
    }
    if (!snapshot.gpuApiCandidate!) {
      return _balanced(InferenceDecisionReason.gpuNotCandidate);
    }
    if (gpuBenchmark == null) {
      return _balanced(InferenceDecisionReason.gpuBenchmarkMissing);
    }
    if (gpuBenchmark.backend != InferenceBackend.gpuDelegate ||
        !gpuBenchmark.successful) {
      return _balanced(InferenceDecisionReason.gpuBenchmarkFailed);
    }
    if (cpuBenchmark.provenance !=
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter ||
        gpuBenchmark.provenance !=
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter) {
      return _balanced(InferenceDecisionReason.gpuEvidenceProvenanceMissing);
    }
    if (!cpuBenchmark.hasSameModelAs(gpuBenchmark)) {
      return _balanced(InferenceDecisionReason.gpuEvidenceMismatch);
    }

    final cpuLatency = cpuBenchmark.medianLatencyMicros!;
    final gpuLatency = gpuBenchmark.medianLatencyMicros!;
    final latencyDifference = gpuLatency - cpuLatency;
    // Benchmark bounds cap this multiplication below 600,000,000 microseconds.
    if (latencyDifference > 0 && latencyDifference * 10 > cpuLatency) {
      return _balanced(InferenceDecisionReason.gpuSlowerThanCpu);
    }

    return _balanced(InferenceDecisionReason.gpuAdapterUnverified);
  }

  static bool _isThermallyConstrained(DeviceThermalState state) =>
      state == DeviceThermalState.serious ||
      state == DeviceThermalState.critical ||
      state == DeviceThermalState.unknown;

  static InferenceDecision _lite(InferenceDecisionReason reason) =>
      InferenceDecision.cpu(
        tier: DevicePerformanceTier.lite,
        analysisFrequency: AnalysisFrequency.low,
        reason: reason,
      );

  static InferenceDecision _balanced(InferenceDecisionReason reason) =>
      InferenceDecision.cpu(
        tier: DevicePerformanceTier.balanced,
        analysisFrequency: AnalysisFrequency.standard,
        reason: reason,
      );
}
