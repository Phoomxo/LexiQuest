import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import '../domain/model_lifecycle.dart';

final class ModelBenchmarkResult {
  const ModelBenchmarkResult({
    required this.delegate,
    required this.modelId,
    required this.modelVersion,
    required this.deviceTier,
    required this.sampleSize,
    required this.medianMicros,
    required this.p90Micros,
    required this.minimumMicros,
    required this.maximumMicros,
    required this.peakWorkingSetBytes,
  });

  final ModelDelegate delegate;
  final String modelId;
  final String modelVersion;
  final String deviceTier;
  final int sampleSize;
  final int medianMicros;
  final int p90Micros;
  final int minimumMicros;
  final int maximumMicros;
  final int peakWorkingSetBytes;
}

final class ModelBenchmark {
  ModelBenchmark({
    required this.runtime,
    int Function()? monotonicMicros,
    int Function()? workingSetBytes,
  }) : monotonicMicros = monotonicMicros ?? _systemMonotonicMicros,
       workingSetBytes = workingSetBytes ?? _systemWorkingSetBytes;

  final ModelRuntime runtime;
  final int Function() monotonicMicros;
  final int Function() workingSetBytes;
  static final Stopwatch _systemClock = Stopwatch()..start();

  static int _systemMonotonicMicros() => _systemClock.elapsedMicroseconds;
  static int _systemWorkingSetBytes() => ProcessInfo.currentRss;

  Future<ModelBenchmarkResult> run({
    required Uint8List input,
    required ModelDelegate delegate,
    required String modelId,
    required String modelVersion,
    required String deviceTier,
    int warmupRuns = 3,
    int measuredRuns = 20,
  }) async {
    if (warmupRuns < 0 || measuredRuns < 1 || measuredRuns > 100) {
      throw ArgumentError('Benchmark run counts are out of bounds.');
    }
    if (modelId.trim().isEmpty ||
        modelVersion.trim().isEmpty ||
        deviceTier.trim().isEmpty) {
      throw ArgumentError('Benchmark provenance must not be empty.');
    }
    var peakWorkingSetBytes = workingSetBytes();
    for (var index = 0; index < warmupRuns; index += 1) {
      await runtime.run(input);
      peakWorkingSetBytes = math.max(peakWorkingSetBytes, workingSetBytes());
    }
    final samples = <int>[];
    for (var index = 0; index < measuredRuns; index += 1) {
      final started = monotonicMicros();
      await runtime.run(input);
      samples.add(monotonicMicros() - started);
      peakWorkingSetBytes = math.max(peakWorkingSetBytes, workingSetBytes());
    }
    samples.sort();
    final median = samples[samples.length ~/ 2];
    final p90Index = math.min(
      samples.length - 1,
      (samples.length * 0.9).ceil() - 1,
    );
    return ModelBenchmarkResult(
      delegate: delegate,
      modelId: modelId,
      modelVersion: modelVersion,
      deviceTier: deviceTier,
      sampleSize: samples.length,
      medianMicros: median,
      p90Micros: samples[p90Index],
      minimumMicros: samples.first,
      maximumMicros: samples.last,
      peakWorkingSetBytes: peakWorkingSetBytes,
    );
  }
}
