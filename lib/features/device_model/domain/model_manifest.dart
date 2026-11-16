import 'model_lifecycle.dart';
export 'model_lifecycle.dart' show ModelDelegate;

enum ModelTensorType { uint8, float32 }

enum ModelInputEncoding { rawUint8Rgb }

final class ModelManifest {
  ModelManifest({
    required this.id,
    required this.version,
    required this.minimumAppVersion,
    required this.sourceUri,
    required this.license,
    required this.licenseUri,
    required this.expectedSha256,
    required this.expectedBytes,
    required List<int> inputShape,
    required this.inputType,
    required List<int> outputShape,
    required this.outputType,
    required this.inputEncoding,
    required this.labelAssetName,
    required Set<ModelDelegate> supportedDelegates,
  }) : inputShape = List<int>.unmodifiable(inputShape),
       outputShape = List<int>.unmodifiable(outputShape),
       supportedDelegates = Set<ModelDelegate>.unmodifiable(
         supportedDelegates,
       ) {
    final shaPattern = RegExp(r'^[0-9a-f]{64}$');
    final versionPattern = RegExp(r'^[0-9]+\.[0-9]+\.[0-9]+(?:\+[0-9]+)?$');
    if (id.trim().isEmpty ||
        version.trim().isEmpty ||
        !versionPattern.hasMatch(minimumAppVersion) ||
        !sourceUri.hasScheme ||
        sourceUri.scheme != 'https' ||
        license.trim().isEmpty ||
        !licenseUri.hasScheme ||
        !shaPattern.hasMatch(expectedSha256) ||
        expectedBytes <= 0 ||
        inputShape.isEmpty ||
        inputShape.any((dimension) => dimension <= 0) ||
        outputShape.isEmpty ||
        outputShape.any((dimension) => dimension <= 0) ||
        labelAssetName.trim().isEmpty ||
        supportedDelegates.isEmpty ||
        !supportedDelegates.contains(ModelDelegate.cpu)) {
      throw ArgumentError('Invalid model manifest contract.');
    }
  }

  static final fieldImageClassifier = ModelManifest(
    id: 'mobilenet-v1-imagenet',
    version: '1.0.224-quantized-metadata1',
    minimumAppVersion: '1.0.0+1',
    sourceUri: Uri.parse(
      'https://storage.googleapis.com/download.tensorflow.org/models/tflite/'
      'task_library/image_classification/android/'
      'mobilenet_v1_1.0_224_quantized_1_metadata_1.tflite',
    ),
    license: 'Apache-2.0',
    licenseUri: Uri.parse(
      'https://github.com/tensorflow/flutter-tflite/blob/main/LICENSE',
    ),
    expectedSha256:
        'd3949e8a3556c79739cb675e0be7476503bcce76938031c6a1048e13e0cb7d8b',
    expectedBytes: 4287874,
    inputShape: const [1, 224, 224, 3],
    inputType: ModelTensorType.uint8,
    outputShape: const [1, 1001],
    outputType: ModelTensorType.uint8,
    inputEncoding: ModelInputEncoding.rawUint8Rgb,
    labelAssetName: 'labels.txt',
    supportedDelegates: const {ModelDelegate.cpu, ModelDelegate.xnnpack},
  );

  final String id;
  final String version;
  final String minimumAppVersion;
  final Uri sourceUri;
  final String license;
  final Uri licenseUri;
  final String expectedSha256;
  final int expectedBytes;
  final List<int> inputShape;
  final ModelTensorType inputType;
  final List<int> outputShape;
  final ModelTensorType outputType;
  final ModelInputEncoding inputEncoding;
  final String labelAssetName;
  final Set<ModelDelegate> supportedDelegates;

  String get recordId => '$id@$version';

  String get fileStem {
    final raw = '${id}_$version';
    return raw.replaceAll(RegExp('[^A-Za-z0-9._-]'), '_');
  }
}
