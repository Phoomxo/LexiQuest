import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/device/device_capability_models.dart';

void main() {
  DeviceCapabilitySnapshot supportedSnapshot({
    int sdkInt = 29,
    String primaryAbi = '  ARM64-V8A  ',
    int memoryClassMb = 256,
    int? availableMemoryMb = 2048,
    int? freeStorageBytes = 1024 * 1024 * 1024,
    bool? lowMemory = false,
    bool? batterySaverEnabled = false,
    DeviceThermalState thermalState = DeviceThermalState.nominal,
    bool? gpuApiCandidate = true,
  }) {
    return DeviceCapabilitySnapshot(
      sdkInt: sdkInt,
      primaryAbi: primaryAbi,
      memoryClassMb: memoryClassMb,
      availableMemoryMb: availableMemoryMb,
      freeStorageBytes: freeStorageBytes,
      lowMemory: lowMemory,
      batterySaverEnabled: batterySaverEnabled,
      thermalState: thermalState,
      gpuApiCandidate: gpuApiCandidate,
    );
  }

  test('marks snapshots below SDK 29 as unsupported', () {
    final snapshot = supportedSnapshot(sdkInt: 28);

    expect(snapshot.isSupported, isFalse);
  });

  test('normalizes a primary ABI to one non-empty value', () {
    final snapshot = supportedSnapshot(primaryAbi: '  ARM64-V8A  ');

    expect(snapshot.primaryAbi, 'arm64-v8a');
    expect(() => supportedSnapshot(primaryAbi: '   '), throwsArgumentError);
  });

  test('rejects negative memory and storage values', () {
    expect(() => supportedSnapshot(memoryClassMb: -1), throwsArgumentError);
    expect(() => supportedSnapshot(availableMemoryMb: -1), throwsArgumentError);
    expect(() => supportedSnapshot(freeStorageBytes: -1), throwsArgumentError);
  });

  test('maps unknown native thermal values to unknown', () {
    expect(DeviceThermalState.fromNativeValue(-1), DeviceThermalState.unknown);
    expect(DeviceThermalState.fromNativeValue(99), DeviceThermalState.unknown);
  });

  test('maps every known native thermal value to its safety state', () {
    expect(DeviceThermalState.fromNativeValue(0), DeviceThermalState.nominal);
    expect(DeviceThermalState.fromNativeValue(1), DeviceThermalState.fair);
    expect(DeviceThermalState.fromNativeValue(2), DeviceThermalState.fair);
    expect(DeviceThermalState.fromNativeValue(3), DeviceThermalState.serious);
    expect(DeviceThermalState.fromNativeValue(4), DeviceThermalState.critical);
    expect(DeviceThermalState.fromNativeValue(5), DeviceThermalState.critical);
    expect(DeviceThermalState.fromNativeValue(6), DeviceThermalState.critical);
  });

  test('preserves unavailable capability signals as unavailable', () {
    final snapshot = supportedSnapshot(
      availableMemoryMb: null,
      freeStorageBytes: null,
      lowMemory: null,
      batterySaverEnabled: null,
      gpuApiCandidate: null,
    );

    expect(snapshot.availableMemoryMb, isNull);
    expect(snapshot.freeStorageBytes, isNull);
    expect(snapshot.lowMemory, isNull);
    expect(snapshot.batterySaverEnabled, isNull);
    expect(snapshot.gpuApiCandidate, isNull);
  });

  test('normalizes and validates model-specific benchmark identity', () {
    final benchmark = InferenceBenchmark(
      backend: InferenceBackend.xnnpackCpu,
      successful: true,
      medianLatencyMicros: 1000,
      completedRuns: 5,
      modelId: '  Lexi.Analysis  ',
      modelVersion: ' 1.2.3 ',
      modelSha256: 'A' * 64,
      provenance: InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
    );

    expect(benchmark.modelId, 'lexi.analysis');
    expect(benchmark.modelVersion, '1.2.3');
    expect(benchmark.modelSha256, 'a' * 64);
  });

  test('rejects malformed model identity and oversized benchmark values', () {
    expect(
      () => InferenceBenchmark(
        backend: InferenceBackend.xnnpackCpu,
        successful: true,
        medianLatencyMicros: 1000,
        completedRuns: 5,
        modelId: 'lexi.analysis',
        modelVersion: 'not a semantic version',
        modelSha256: 'a' * 64,
        provenance:
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
      ),
      throwsArgumentError,
    );
    expect(
      () => InferenceBenchmark(
        backend: InferenceBackend.xnnpackCpu,
        successful: true,
        medianLatencyMicros: 1000,
        completedRuns: 5,
        modelId: 'lexi.analysis',
        modelVersion: '1.2.3',
        modelSha256: 'a' * 63,
        provenance:
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
      ),
      throwsArgumentError,
    );
    expect(
      () => InferenceBenchmark(
        backend: InferenceBackend.xnnpackCpu,
        successful: true,
        medianLatencyMicros: 60000001,
        completedRuns: 5,
        modelId: 'lexi.analysis',
        modelVersion: '1.2.3',
        modelSha256: 'a' * 64,
        provenance:
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
      ),
      throwsArgumentError,
    );
    expect(
      () => InferenceBenchmark(
        backend: InferenceBackend.xnnpackCpu,
        successful: true,
        medianLatencyMicros: 1000,
        completedRuns: 10001,
        modelId: 'lexi.analysis',
        modelVersion: '1.2.3',
        modelSha256: 'a' * 64,
        provenance:
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
      ),
      throwsArgumentError,
    );
  });

  test('accepts canonical SemVer core versions only', () {
    for (final version in const ['0.0.0', '1.2.3', '12.34.56']) {
      expect(
        () => InferenceBenchmark(
          backend: InferenceBackend.xnnpackCpu,
          successful: true,
          medianLatencyMicros: 1000,
          completedRuns: 5,
          modelId: 'lexi.analysis',
          modelVersion: version,
          modelSha256: 'a' * 64,
          provenance:
              InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
        ),
        returnsNormally,
      );
    }

    for (final version in const [
      '01.2.3',
      '1.02.3',
      '1.2.03',
      '1.2.3-beta',
      '1.2',
      'v1.2.3',
    ]) {
      expect(
        () => InferenceBenchmark(
          backend: InferenceBackend.xnnpackCpu,
          successful: true,
          medianLatencyMicros: 1000,
          completedRuns: 5,
          modelId: 'lexi.analysis',
          modelVersion: version,
          modelSha256: 'a' * 64,
          provenance:
              InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
        ),
        throwsArgumentError,
      );
    }
  });

  test('rejects unstable benchmark failure codes', () {
    expect(
      () => InferenceBenchmark(
        backend: InferenceBackend.gpuDelegate,
        successful: false,
        completedRuns: 0,
        failureCode: 'raw-platform-error',
        modelId: 'lexi.analysis',
        modelVersion: '1.2.3',
        modelSha256: 'a' * 64,
        provenance:
            InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
      ),
      throwsArgumentError,
    );
  });

  test('string representations exclude raw hardware values', () {
    final snapshot = supportedSnapshot(
      primaryAbi: 'device-secret-abi',
      memoryClassMb: 513,
      availableMemoryMb: 2053,
      freeStorageBytes: 123456789,
    );
    final benchmark = InferenceBenchmark(
      backend: InferenceBackend.xnnpackCpu,
      successful: true,
      medianLatencyMicros: 54321,
      completedRuns: 7,
      modelId: 'secret-model-id',
      modelVersion: '9.9.9',
      modelSha256: 'b' * 64,
      provenance: InferenceBenchmarkProvenance.assertedOnDeviceInferenceAdapter,
    );
    final decision = InferenceDecision.cpu(
      tier: DevicePerformanceTier.balanced,
      analysisFrequency: AnalysisFrequency.standard,
      reason: InferenceDecisionReason.gpuBenchmarkMissing,
    );

    final output = '$snapshot $benchmark $decision';

    expect(output, isNot(contains('device-secret-abi')));
    expect(output, isNot(contains('2053')));
    expect(output, isNot(contains('123456789')));
    expect(output, isNot(contains('secret-model-id')));
    expect(output, isNot(contains('9.9.9')));
    expect(output, isNot(contains('54321')));
    expect(output, isNot(contains('b' * 64)));
    expect(output, contains('DeviceCapabilitySnapshot'));
    expect(output, contains('xnnpackCpu'));
    expect(output, contains('balanced'));
    expect(output, contains('gpu-benchmark-missing'));
  });

  test('decision reasons cannot be supplied as arbitrary caller text', () {
    dynamic untrustedReason = 'untrusted-reason';

    expect(
      () => InferenceDecision.cpu(
        tier: DevicePerformanceTier.lite,
        analysisFrequency: AnalysisFrequency.low,
        reason: untrustedReason,
      ),
      throwsA(isA<TypeError>()),
    );
  });

  test('analysis frequency cannot be supplied as arbitrary caller text', () {
    dynamic untrustedFrequency = 'continuous';

    expect(
      () => InferenceDecision.cpu(
        tier: DevicePerformanceTier.lite,
        analysisFrequency: untrustedFrequency,
        reason: InferenceDecisionReason.batterySaver,
      ),
      throwsA(isA<TypeError>()),
    );
  });
}
