import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';

void main() {
  test(
    'benchmark reports bounded warmup, median, p90, and sample size',
    () async {
      final clock = _SequenceClock([
        0,
        1000,
        1000,
        3000,
        3000,
        6000,
        6000,
        10000,
        10000,
        15000,
      ]);
      final runtime = _CountingRuntime();
      final benchmark = ModelBenchmark(
        runtime: runtime,
        monotonicMicros: clock.call,
        workingSetBytes: () => 64 * 1024 * 1024,
      );

      final result = await benchmark.run(
        input: Uint8List(1),
        delegate: ModelDelegate.xnnpack,
        modelId: 'test-model',
        modelVersion: 'v1',
        deviceTier: 'test-tier',
        warmupRuns: 1,
        measuredRuns: 5,
      );

      expect(runtime.calls, 6);
      expect(result.sampleSize, 5);
      expect(result.medianMicros, 3000);
      expect(result.p90Micros, 5000);
      expect(result.minimumMicros, 1000);
      expect(result.maximumMicros, 5000);
      expect(result.delegate, ModelDelegate.xnnpack);
      expect(result.modelId, 'test-model');
      expect(result.modelVersion, 'v1');
      expect(result.deviceTier, 'test-tier');
      expect(result.peakWorkingSetBytes, 64 * 1024 * 1024);
    },
  );

  test('GPU remains disabled until the Android hardware gate passes', () {
    const fingerprint = DeviceModelFingerprint(
      manufacturer: 'vendor',
      model: 'phone',
      androidSdk: 35,
      gpuDriver: 'driver-1',
    );
    const entry = GpuAllowlistEntry(
      modelId: 'vision',
      modelVersion: '1',
      fingerprint: fingerprint,
    );

    expect(
      ModelDelegatePolicy.select(
        requestGpu: true,
        modelId: 'vision',
        modelVersion: '1',
        fingerprint: fingerprint,
        gpuAllowlist: {entry},
      ),
      ModelDelegate.xnnpack,
    );
    expect(
      ModelDelegatePolicy.select(
        requestGpu: true,
        modelId: 'vision',
        modelVersion: '2',
        fingerprint: fingerprint,
        gpuAllowlist: {entry},
      ),
      ModelDelegate.xnnpack,
    );
    expect(
      ModelDelegatePolicy.select(
        requestGpu: false,
        modelId: 'vision',
        modelVersion: '1',
        fingerprint: fingerprint,
        gpuAllowlist: {entry},
      ),
      ModelDelegate.xnnpack,
    );
  });
}

final class _SequenceClock {
  _SequenceClock(this.values);

  final List<int> values;
  var index = 0;

  int call() => values[index++];
}

final class _CountingRuntime implements ModelRuntime {
  int calls = 0;

  @override
  Future<void> run(Uint8List input) async {
    calls += 1;
  }
}
