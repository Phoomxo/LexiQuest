/// ML Image Labeling Service abstraction for on-device object recognition.
///
/// Uses abstract interface pattern for dependency injection:
/// - [UnavailableMlImageLabelingService] reports that real labeling is absent
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

/// Placeholder implementation that does not perform real image labeling.
///
/// Real on-device recognition is not implemented in this version. The object
/// scanner uses a separate, explicitly labelled vocabulary simulation.
class UnavailableMlImageLabelingService implements MlImageLabelingService {
  @override
  bool get isReady => false;

  @override
  Future<List<LabelResult>> processImageBytes(List<int> imageBytes) async => [];

  @override
  void dispose() {}
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
