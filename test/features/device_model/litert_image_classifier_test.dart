import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/data/litert_image_classifier.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

const _modelPath = String.fromEnvironment(
  'LEXIQUEST_TEST_MODEL_PATH',
  defaultValue: 'build/model-fixtures/mobilenet.tflite',
);

void main() {
  test(
    'opens the checksum-pinned model and runs real XNNPACK inference',
    () async {
      final model = File(_modelPath);
      expect(
        await model.exists(),
        isTrue,
        reason: 'Run tool/cli/prepare-field-model.ps1 before this test.',
      );
      final classifier = await LiteRtImageClassifier.open(
        path: model.path,
        manifest: ModelManifest.fieldImageClassifier,
        delegate: ModelDelegate.xnnpack,
        threads: 2,
      );
      addTearDown(classifier.close);

      final results = await classifier.classify(
        Uint8List(224 * 224 * 3),
        topK: 3,
      );

      expect(results, hasLength(3));
      expect(results.every((result) => result.label.isNotEmpty), isTrue);
      expect(
        results.every(
          (result) => result.confidence >= 0 && result.confidence <= 1,
        ),
        isTrue,
      );
      expect(classifier.delegate, ModelDelegate.xnnpack);
    },
  );

  test('verifier rejects a manifest with the wrong output contract', () async {
    final model = File(_modelPath);
    final manifest = ModelManifest(
      id: 'wrong-contract',
      version: '1',
      minimumAppVersion: '1.0.0+1',
      sourceUri: Uri.https('models.example', '/wrong.tflite'),
      license: 'Apache-2.0',
      licenseUri: Uri.https('models.example', '/LICENSE'),
      expectedSha256: 'a' * 64,
      expectedBytes: await model.length(),
      inputShape: const [1, 224, 224, 3],
      inputType: ModelTensorType.uint8,
      outputShape: const [1, 2],
      outputType: ModelTensorType.uint8,
      inputEncoding: ModelInputEncoding.rawUint8Rgb,
      labelAssetName: 'labels.txt',
      supportedDelegates: const {ModelDelegate.cpu},
    );

    await expectLater(
      const LiteRtModelFileVerifier().verify(model.path, manifest),
      throwsA(
        isA<ModelLifecycleException>().having(
          (error) => error.code,
          'code',
          ModelFailureCode.incompatibleTensor,
        ),
      ),
    );
  });
}
