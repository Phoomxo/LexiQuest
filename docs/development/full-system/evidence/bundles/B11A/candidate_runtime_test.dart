// Explicit local artifact probe; run with verify-scope -TestTargets this file.
// Uses development validation only. It is not a camera quality benchmark.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/data/litert_image_classifier.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

void main() {
  test('pinned trained candidate loads and preserves all native class scores', () async {
    const root = 'C:/Users/Phet/.codex/visualizations/2026/09/13/01a09bc7-f608-7380-bf02-adff13deb6d0/camera-training/run-001';
    const hash = '7d20e11746f986b666b487bb8327edc1ff4cf3dd4f7d7e13e5a3d955b020da96';
    final exported = jsonDecode(await File('$root/export.json').readAsString()) as Map<String, dynamic>;
    final path = exported['localArtifactPath'] as String;
    expect(sha256.convert(await File(path).readAsBytes()).toString(), hash);
    expect(await File(path).length(), 12871389);
    expect(exported['expectedSha256'], hash);
    expect(exported['parityPassed'], isTrue);
    final manifest = ModelManifest(
      id: exported['id'] as String,
      version: exported['version'] as String,
      minimumAppVersion: '1.0.0',
      // Required contract URI, never fetched by this local runtime probe.
      sourceUri: Uri.https('example.invalid', '/local-candidate-not-published'),
      license: exported['modelRights'] as String,
      licenseUri: Uri.https('example.invalid', '/local-development-attribution'),
      expectedSha256: hash,
      expectedBytes: 12871389,
      inputShape: const [1, 224, 224, 3],
      inputType: ModelTensorType.uint8,
      outputShape: const [1, 16],
      outputType: ModelTensorType.float32,
      backgroundClassIndex: null,
      inputEncoding: ModelInputEncoding.rawUint8Rgb,
      labelAssetName: 'labels.txt',
      supportedDelegates: const {ModelDelegate.cpu},
    );
    final runtime = await LiteRtImageClassifier.open(path: path, manifest: manifest, delegate: ModelDelegate.cpu);
    addTearDown(runtime.close);
    final labels = List<String>.from(exported['labels'] as List);
    final probes = exported['probe'] as List;
    expect(probes, hasLength(4));
    for (final entry in probes) {
      final probe = entry as Map<String, dynamic>;
      expect(probe['split'], 'validation');
      final pixels = await File(probe['path'] as String).readAsBytes();
      expect(sha256.convert(pixels).toString(), probe['sha256']);
      final expected = List<num>.from(probe['scores'] as List);
      final predictions = await runtime.classify(pixels, topK: 16);
      expect(predictions, hasLength(16));
      expect(predictions.map((p) => p.index).toSet(), Set<int>.from(List.generate(16, (i) => i)));
      for (final prediction in predictions) {
        expect(prediction.label, labels[prediction.index]);
        expect(prediction.confidence, closeTo(expected[prediction.index], 0.001));
      }
      expect(predictions.singleWhere((p) => p.index == 0).label, 'book');
      final topTen = await runtime.classify(pixels, topK: 10);
      expect(topTen.map((p) => p.index), predictions.take(10).map((p) => p.index));
    }
  });
}
