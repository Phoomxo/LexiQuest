// Manual QA only. Never changes the shipped model manifest.
// One pinned book fixture; run each condition in a fresh process.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:vocab_learning_app/features/device_model/application/model_benchmark.dart';
import 'package:vocab_learning_app/features/device_model/data/litert_image_classifier.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

// Root's manual-only button can call this with the app-private staging directory.
// Run one model per fresh app launch, then alternate order for the next pair.
Future<Map<String, Object?>> benchmarkStagedCameraModel({
  required Directory stagedDirectory,
  required bool candidate,
  required ModelDelegate delegate,
  required String deviceDescription,
}) async {
  final input = await File(
    '${stagedDirectory.path}/validation-book.rgb',
  ).readAsBytes();
  return benchmarkCameraModelOnAndroid(
    modelPath:
        '${stagedDirectory.path}/${candidate ? 'candidate' : 'baseline'}.tflite',
    manifest: candidate
        ? localPilotManifest()
        : ModelManifest.fieldImageClassifier,
    rawRgb224: input,
    expectedInputSha256:
        'ff711f5c5752447ed2cfe0cab02700bf774ab73c827b9f6188ea30e259237129',
    delegate: delegate,
    deviceDescription: deviceDescription,
  );
}

Future<Map<String, Object?>> benchmarkCameraModelOnAndroid({
  required String modelPath,
  required ModelManifest manifest,
  required Uint8List rawRgb224,
  required String expectedInputSha256,
  required ModelDelegate delegate,
  required String deviceDescription,
}) async {
  if (!Platform.isAndroid) throw StateError('Android device evidence required');
  if (deviceDescription.trim().isEmpty || rawRgb224.length != 224 * 224 * 3) {
    throw ArgumentError('Device provenance and RGB224 fixture required');
  }
  if (sha256.convert(rawRgb224).toString() != expectedInputSha256) {
    throw StateError('Input fixture checksum mismatch');
  }
  final file = File(modelPath);
  if (await file.length() != manifest.expectedBytes ||
      sha256.convert(await file.readAsBytes()).toString() !=
          manifest.expectedSha256) {
    throw StateError('Pinned model checksum or size mismatch');
  }
  final beforeRss = ProcessInfo.currentRss;
  final loadClock = Stopwatch()..start();
  final runtime = await LiteRtImageClassifier.open(
    path: modelPath,
    manifest: manifest,
    delegate: delegate,
    threads: 2,
  );
  loadClock.stop();
  final afterLoadRss = ProcessInfo.currentRss;
  late Map<String, Object?> result;
  try {
    final firstClock = Stopwatch()..start();
    await runtime.run(rawRgb224);
    firstClock.stop();
    final firstRss = ProcessInfo.currentRss;
    final timing = await ModelBenchmark(runtime: runtime).run(
      input: rawRgb224,
      delegate: delegate,
      modelId: manifest.id,
      modelVersion: manifest.version,
      deviceTier: deviceDescription,
      warmupRuns: 5,
      measuredRuns: 50,
    );
    final predictions = await runtime.classify(
      rawRgb224,
      topK: manifest.outputShape.last < 10 ? manifest.outputShape.last : 10,
    );
    result = {
      'device': deviceDescription,
      'os': Platform.operatingSystemVersion,
      'model_sha256': manifest.expectedSha256,
      'model_bytes': manifest.expectedBytes,
      'input_sha256': expectedInputSha256,
      'delegate': delegate.name,
      'threads': 2,
      'load_allocate_us': loadClock.elapsedMicroseconds,
      'first_run_us': firstClock.elapsedMicroseconds,
      'warmups': 5,
      'runs': timing.sampleSize,
      'median_us': timing.medianMicros,
      'p90_us': timing.p90Micros,
      'min_us': timing.minimumMicros,
      'max_us': timing.maximumMicros,
      'rss_before': beforeRss,
      'rss_after_load': afterLoadRss,
      'rss_after_first': firstRss,
      'rss_peak_sampled': timing.peakWorkingSetBytes,
      'top1': predictions.first.label,
      'confidence': predictions.first.confidence,
      'scope':
          'Direct app runtime on one pinned RGB fixture; no camera capture or preprocessing latency.',
    };
  } finally {
    runtime.close();
  }
  result['rss_after_close'] = ProcessInfo.currentRss;
  return result;
}

ModelManifest localPilotManifest() => ModelManifest(
  id: 'local-four-class-pilot',
  version: 'r1',
  minimumAppVersion: '1.0.0+1',
  sourceUri: Uri.https('example.invalid', '/unpublished-pilot'),
  license: 'Apache-2.0 derivative; Open Images attribution retained separately',
  licenseUri: Uri.parse('https://www.apache.org/licenses/LICENSE-2.0'),
  expectedSha256:
      'eb39555e38ecb012c43a16b4300fbe323dfde84c939d22e4f80121fae473798a',
  expectedBytes: 12821512,
  inputShape: [1, 224, 224, 3],
  inputType: ModelTensorType.uint8,
  outputShape: [1, 4],
  outputType: ModelTensorType.float32,
  backgroundClassIndex: null,
  inputEncoding: ModelInputEncoding.rawUint8Rgb,
  labelAssetName: 'labels.txt',
  supportedDelegates: {ModelDelegate.cpu, ModelDelegate.xnnpack},
);

/// Writes only benchmark evidence, never learning data.
Future<File> saveStagedCameraBenchmark({
  required Directory stagedDirectory,
  required bool candidate,
  required ModelDelegate delegate,
}) async {
  final started = DateTime.now().toUtc();
  final result = await benchmarkStagedCameraModel(
    stagedDirectory: stagedDirectory,
    candidate: candidate,
    delegate: delegate,
    deviceDescription: 'vivo V2041 Android 33; local QA debug',
  );
  result.addAll({
    'started_utc': started.toIso8601String(),
    'finished_utc': DateTime.now().toUtc().toIso8601String(),
    'pid': pid,
    'model': candidate ? 'candidate' : 'baseline',
    'fixture': 'validation-book.rgb',
    'rss_limitations':
        'ProcessInfo.currentRss sampled after runs; whole-process RSS, not Android PSS or continuous peak. Model hash reading and app startup can affect allocator state.',
    'timing_limitations':
        'Runtime.run includes tensor copying. Debug build, one book image, no physical camera or lighting test.',
  });
  final stamp = started.toIso8601String().replaceAll(':', '-');
  final file = File(
    '${stagedDirectory.path}/result-$stamp-$pid-${candidate ? 'candidate' : 'baseline'}-${delegate.name}.json',
  );
  await file.writeAsString(
    const JsonEncoder.withIndent('  ').convert(result),
    flush: true,
  );
  return file;
}
