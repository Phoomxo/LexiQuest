import 'dart:io';
import 'dart:typed_data';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/data/litert_image_classifier.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

void main() {
  test(
    'float tensor decodes one probability per class, including class zero',
    () async {
      const path =
          'test/features/device_model/fixtures/synthetic_float_classifier.tflite';
      const hash =
          '9d9b1b6ac4c1fb05e60a74a7b8fd9da954e36245d0f7432dd998fa9e625ac187';
      final file = File(path);
      expect(sha256.convert(await file.readAsBytes()).toString(), hash);
      final manifest = ModelManifest(
        id: 'synthetic-float-fixture',
        version: '1',
        minimumAppVersion: '1.0.0',
        sourceUri: Uri.https('example.invalid', '/synthetic-fixture'),
        license: 'Synthetic test fixture',
        licenseUri: Uri.https('example.invalid', '/fixture-license'),
        expectedSha256: hash,
        expectedBytes: await file.length(),
        inputShape: [1, 1, 1, 3],
        inputType: ModelTensorType.uint8,
        outputShape: [1, 4],
        outputType: ModelTensorType.float32,
        backgroundClassIndex: null,
        inputEncoding: ModelInputEncoding.rawUint8Rgb,
        labelAssetName: 'labels.txt',
        supportedDelegates: {ModelDelegate.cpu},
      );
      final runtime = await LiteRtImageClassifier.open(
        path: path,
        manifest: manifest,
        delegate: ModelDelegate.cpu,
      );
      addTearDown(runtime.close);
      final result = await runtime.classify(Uint8List(3), topK: 4);
      expect(result, hasLength(4));
      expect(result.first.index, 0);
      expect(result.first.label, 'book');
      expect(result.first.confidence, closeTo(0.6, 0.00001));
      expect(
        result.map((p) => p.confidence).reduce((a, b) => a + b),
        closeTo(1, 0.00001),
      );
    },
  );
}
