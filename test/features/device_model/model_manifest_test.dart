import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';

void main() {
  test('field image model freezes a licensed reproducible tensor contract', () {
    final manifest = ModelManifest.fieldImageClassifier;

    expect(manifest.id, 'mobilenet-v1-imagenet');
    expect(manifest.version, '1.0.224-quantized-metadata1');
    expect(manifest.minimumAppVersion, '1.0.0+1');
    expect(manifest.license, 'Apache-2.0');
    expect(manifest.expectedBytes, 4287874);
    expect(
      manifest.expectedSha256,
      'd3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b',
    );
    expect(manifest.inputShape, [1, 224, 224, 3]);
    expect(manifest.inputType, ModelTensorType.uint8);
    expect(manifest.outputShape, [1, 1001]);
    expect(manifest.outputType, ModelTensorType.uint8);
    expect(manifest.inputEncoding, ModelInputEncoding.rawUint8Rgb);
    expect(manifest.labelAssetName, 'labels.txt');
    expect(manifest.supportedDelegates, {
      ModelDelegate.cpu,
      ModelDelegate.xnnpack,
    });
  });

  test('manifest rejects an invalid checksum and tensor contract', () {
    expect(
      () => ModelManifest(
        id: 'bad',
        version: '1',
        minimumAppVersion: 'invalid',
        sourceUri: Uri.https('example.invalid', '/model.tflite'),
        license: 'Apache-2.0',
        licenseUri: Uri.https('example.invalid', '/license'),
        expectedSha256: 'not-a-sha',
        expectedBytes: 0,
        inputShape: const [1, 0, 0, 3],
        inputType: ModelTensorType.uint8,
        outputShape: const [1, 1],
        outputType: ModelTensorType.uint8,
        inputEncoding: ModelInputEncoding.rawUint8Rgb,
        labelAssetName: 'labels.txt',
        supportedDelegates: const {ModelDelegate.cpu},
      ),
      throwsArgumentError,
    );
  });
}
