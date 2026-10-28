import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/device/device_capability_models.dart';
import 'package:vocab_learning_app/device/inference_policy.dart';

void main() {
  DeviceCapabilitySnapshot snapshot({
    int sdkInt = 29,
    int? availableMemoryMb = 4096,
    int? freeStorageBytes = 2 * 1024 * 1024 * 1024,
    bool? lowMemory = false,
    bool? batterySaverEnabled = false,
    DeviceThermalState thermalState = DeviceThermalState.nominal,
    bool? gpuApiCandidate = true,
  }) {
    return DeviceCapabilitySnapshot(
      sdkInt: sdkInt,
      primaryAbi: 'arm64-v8a',
      memoryClassMb: 256,
      availableMemoryMb: availableMemoryMb,
      freeStorageBytes: freeStorageBytes,
      lowMemory: lowMemory,
      batterySaverEnabled: batterySaverEnabled,
      thermalState: thermalState,
      gpuApiCandidate: gpuApiCandidate,
    );
  }

  InferenceBenchmark cpu({
    bool successful = true,
    int latencyMicros = 10000,
    String modelId = 'lexi.analysis',
    String modelVersion = '1.0.0',
    String modelSha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    InferenceBenchmarkProvenance? provenance =
        InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
  }) {
    return InferenceBenchmark(
      backend: InferenceBackend.xnnpackCpu,
      successful: successful,
      medianLatencyMicros: successful ? latencyMicros : null,
      completedRuns: successful ? 5 : 0,
      failureCode: successful ? null : 'benchmark-failed',
      modelId: modelId,
      modelVersion: modelVersion,
      modelSha256: modelSha256,
      provenance: provenance,
    );
  }

  InferenceBenchmark gpu({
    bool successful = true,
    int latencyMicros = 9000,
    String modelId = 'lexi.analysis',
    String modelVersion = '1.0.0',
    String modelSha256 =
        'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
    InferenceBenchmarkProvenance? provenance =
        InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
  }) {
    return InferenceBenchmark(
      backend: InferenceBackend.gpuDelegate,
      successful: successful,
      medianLatencyMicros: successful ? latencyMicros : null,
      completedRuns: successful ? 5 : 0,
      failureCode: successful ? null : 'delegate-init-failed',
      modelId: modelId,
      modelVersion: modelVersion,
      modelSha256: modelSha256,
      provenance: provenance,
    );
  }

  test('uses CPU when the GPU benchmark is missing', () {
    final decision = InferencePolicy.select(snapshot(), cpu());

    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.reasonCode, 'gpu-benchmark-missing');
  });

  test(
    'uses CPU when a GPU API candidate has no successful delegate benchmark',
    () {
      final decision = InferencePolicy.select(
        snapshot(),
        cpu(),
        gpu(successful: false),
      );

      expect(decision.backend, InferenceBackend.xnnpackCpu);
      expect(decision.reasonCode, 'gpu-benchmark-failed');
    },
  );

  test(
    'keeps executable selection on CPU when advisory GPU evidence qualifies',
    () {
      final decision = InferencePolicy.select(snapshot(), cpu(), gpu());

      expect(decision.tier, DevicePerformanceTier.balanced);
      expect(decision.backend, InferenceBackend.xnnpackCpu);
      expect(decision.analysisFrequency, AnalysisFrequency.standard);
      expect(decision.reasonCode, 'gpu-adapter-unverified');
    },
  );

  test(
    'uses CPU when GPU latency is more than ten percent slower than CPU',
    () {
      final decision = InferencePolicy.select(
        snapshot(),
        cpu(),
        gpu(latencyMicros: 11001),
      );

      expect(decision.backend, InferenceBackend.xnnpackCpu);
      expect(decision.reasonCode, 'gpu-slower-than-cpu');
    },
  );

  test('keeps CPU at the exact ten-percent advisory latency boundary', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(),
      gpu(latencyMicros: 11000),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-adapter-unverified');
  });

  test('uses CPU when benchmark model identities do not match exactly', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(),
      gpu(modelVersion: '1.0.1'),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-evidence-mismatch');
  });

  test('uses CPU when benchmark model IDs do not match', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(),
      gpu(modelId: 'lexi.alternate'),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-evidence-mismatch');
  });

  test('uses CPU when benchmark model SHA-256 values do not match', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(),
      gpu(
        modelSha256:
            'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      ),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-evidence-mismatch');
  });

  test('uses CPU when required adapter provenance is missing', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(provenance: null),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-evidence-provenance-missing');
  });

  test('uses Lite CPU when any required capability signal is unavailable', () {
    final missingSignals = [
      snapshot(batterySaverEnabled: null),
      snapshot(lowMemory: null),
      snapshot(availableMemoryMb: null),
      snapshot(freeStorageBytes: null),
      snapshot(gpuApiCandidate: null),
    ];

    for (final unavailableSnapshot in missingSignals) {
      final decision = InferencePolicy.select(
        unavailableSnapshot,
        cpu(),
        gpu(),
      );

      expect(decision.tier, DevicePerformanceTier.lite);
      expect(decision.backend, InferenceBackend.xnnpackCpu);
      expect(decision.reasonCode, 'capability-evidence-missing');
    }
  });

  test('uses Lite CPU in Battery Saver mode', () {
    final decision = InferencePolicy.select(
      snapshot(batterySaverEnabled: true),
      cpu(),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.lite);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.analysisFrequency, AnalysisFrequency.low);
    expect(decision.reasonCode, 'battery-saver');
  });

  test('uses Lite CPU for serious, critical, and unknown thermal states', () {
    for (final thermalState in const [
      DeviceThermalState.serious,
      DeviceThermalState.critical,
      DeviceThermalState.unknown,
    ]) {
      final decision = InferencePolicy.select(
        snapshot(thermalState: thermalState),
        cpu(),
        gpu(),
      );

      expect(decision.tier, DevicePerformanceTier.lite);
      expect(decision.backend, InferenceBackend.xnnpackCpu);
      expect(decision.reasonCode, 'thermal-constrained');
    }
  });

  test('uses Lite CPU for low-memory signals and storage below 512 MB', () {
    final lowMemory = InferencePolicy.select(
      snapshot(lowMemory: true),
      cpu(),
      gpu(),
    );
    final lowAvailableMemory = InferencePolicy.select(
      snapshot(availableMemoryMb: 767),
      cpu(),
      gpu(),
    );
    final lowStorage = InferencePolicy.select(
      snapshot(freeStorageBytes: 511 * 1024 * 1024),
      cpu(),
      gpu(),
    );

    expect(lowMemory.tier, DevicePerformanceTier.lite);
    expect(lowAvailableMemory.tier, DevicePerformanceTier.lite);
    expect(lowStorage.tier, DevicePerformanceTier.lite);
    expect(lowStorage.reasonCode, 'storage-constrained');
  });

  test('uses Balanced CPU with 768 to 2047 MB of available memory', () {
    final decision = InferencePolicy.select(
      snapshot(availableMemoryMb: 768),
      cpu(),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.analysisFrequency, AnalysisFrequency.standard);
    expect(decision.reasonCode, 'balanced-memory');
  });

  test('uses Balanced CPU at the exact 2047 MB memory boundary', () {
    final decision = InferencePolicy.select(
      snapshot(availableMemoryMb: 2047),
      cpu(),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.reasonCode, 'balanced-memory');
  });

  test('uses Balanced CPU at exactly 512 MiB of free storage', () {
    final decision = InferencePolicy.select(
      snapshot(freeStorageBytes: 512 * 1024 * 1024),
      cpu(),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.reasonCode, 'storage-not-enhanced');
  });

  test('keeps CPU at exactly 1 GiB without an authenticated adapter', () {
    final decision = InferencePolicy.select(
      snapshot(freeStorageBytes: 1024 * 1024 * 1024),
      cpu(),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-adapter-unverified');
  });

  test('requires GPU evidence before the final advisory branch', () {
    final decision = InferencePolicy.select(
      snapshot(availableMemoryMb: 2048, freeStorageBytes: 1024 * 1024 * 1024),
      cpu(),
    );

    expect(decision.tier, DevicePerformanceTier.balanced);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.reasonCode, 'gpu-benchmark-missing');
  });

  test('returns degraded CPU when the CPU benchmark is unsuccessful', () {
    final decision = InferencePolicy.select(
      snapshot(),
      cpu(successful: false),
      gpu(),
    );

    expect(decision.tier, DevicePerformanceTier.lite);
    expect(decision.backend, InferenceBackend.xnnpackCpu);
    expect(decision.analysisFrequency, AnalysisFrequency.low);
    expect(decision.reasonCode, 'cpu-benchmark-degraded');
  });
}
