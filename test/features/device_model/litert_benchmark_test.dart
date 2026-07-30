import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/data/litert_image_classifier.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

const _modelPath = String.fromEnvironment(
  'LEXIQUEST_TEST_MODEL_PATH',
  defaultValue: 'build/model-fixtures/mobilenet.tflite',
);

void main() {
  test('runs bounded real CPU and XNNPACK benchmarks', () async {
    expect(await File(_modelPath).exists(), isTrue);
    final input = Uint8List(224 * 224 * 3);
    final results = <ModelDelegate, ModelBenchmarkResult>{};

    for (final delegate in [ModelDelegate.cpu, ModelDelegate.xnnpack]) {
      final runtime = await LiteRtImageClassifier.open(
        path: _modelPath,
        manifest: ModelManifest.fieldImageClassifier,
        delegate: delegate,
        threads: 2,
      );
      try {
        results[delegate] = await ModelBenchmark(runtime: runtime).run(
          input: input,
          delegate: delegate,
          modelId: ModelManifest.fieldImageClassifier.id,
          modelVersion: ModelManifest.fieldImageClassifier.version,
          deviceTier: 'host-gate',
          warmupRuns: 3,
          measuredRuns: 10,
        );
      } finally {
        runtime.close();
      }
    }

    for (final entry in results.entries) {
      final result = entry.value;
      expect(result.sampleSize, 10);
      expect(result.minimumMicros, greaterThan(0));
      expect(result.medianMicros, greaterThanOrEqualTo(result.minimumMicros));
      expect(result.p90Micros, greaterThanOrEqualTo(result.medianMicros));
      expect(result.maximumMicros, greaterThanOrEqualTo(result.p90Micros));
      // Bounded machine-readable evidence without device or personal data.
      // ignore: avoid_print
      print(
        'MODEL_BENCHMARK delegate=${entry.key.name} samples=10 '
        'median_us=${result.medianMicros} p90_us=${result.p90Micros} '
        'min_us=${result.minimumMicros} max_us=${result.maximumMicros} '
        'peak_rss_bytes=${result.peakWorkingSetBytes}',
      );
    }
  });
}
