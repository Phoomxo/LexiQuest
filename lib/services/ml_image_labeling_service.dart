/// ML Image Labeling Service abstraction for on-device object recognition.
///
/// Uses abstract interface pattern for dependency injection:
/// - [LiveMlImageLabelingService] wraps Google ML Kit (production)
/// - [MockMlImageLabelingService] provides fake results (widget tests)
library;

/// Result of an ML image labeling operation.
class LabelResult {
  final String label;
  final double confidence;

  const LabelResult({required this.label, required this.confidence});

  @override
  String toString() =>
      'LabelResult($label, ${(confidence * 100).toStringAsFixed(1)}%)';
}

/// Abstract interface for ML image labeling services.
abstract class MlImageLabelingService {
  /// Process image bytes and return detected labels with confidence scores.
  Future<List<LabelResult>> processImageBytes(List<int> imageBytes);

  /// Whether the ML model is ready for inference.
  bool get isReady;

  /// Release ML model resources.
  void dispose();
}

/// Production implementation wrapping Google ML Kit Image Labeling.
///
/// On real devices, this delegates to `google_mlkit_image_labeling`.
/// The actual ML Kit integration requires platform channels and is
/// initialized when the camera provides an [InputImage].
class LiveMlImageLabelingService implements MlImageLabelingService {
  bool _isDisposed = false;

  @override
  bool get isReady => !_isDisposed;

  @override
  Future<List<LabelResult>> processImageBytes(List<int> imageBytes) async {
    if (_isDisposed) return [];
    // In production APK build, this will delegate to:
    //   final labeler = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.5));
    //   final labels = await labeler.processImage(inputImage);
    // For now, this returns empty until camera integration wires it up.
    return [];
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}

/// Mock implementation for widget tests — returns configurable fake labels.
class MockMlImageLabelingService implements MlImageLabelingService {
  final List<LabelResult> fakeResults;
  bool _isDisposed = false;

  MockMlImageLabelingService({this.fakeResults = const []});

  @override
  bool get isReady => !_isDisposed;

  @override
  Future<List<LabelResult>> processImageBytes(List<int> imageBytes) async {
    if (_isDisposed) return [];
    return fakeResults;
  }

  @override
  void dispose() {
    _isDisposed = true;
  }
}
