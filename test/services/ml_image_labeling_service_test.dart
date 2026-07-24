import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/ml_image_labeling_service.dart';

void main() {
  group('MockMlImageLabelingService', () {
    test('returns configured fake results', () async {
      final service = MockMlImageLabelingService(
        fakeResults: [
          const LabelResult(label: 'Laptop', confidence: 0.95),
          const LabelResult(label: 'Keyboard', confidence: 0.82),
        ],
      );

      expect(service.isReady, true);
      final results = await service.processImageBytes([0, 1, 2]);
      expect(results.length, 2);
      expect(results[0].label, 'Laptop');
      expect(results[0].confidence, 0.95);
      expect(results[1].label, 'Keyboard');
    });

    test('returns empty after dispose', () async {
      final service = MockMlImageLabelingService(
        fakeResults: [const LabelResult(label: 'Cat', confidence: 0.9)],
      );

      service.dispose();
      expect(service.isReady, false);
      final results = await service.processImageBytes([0, 1, 2]);
      expect(results, isEmpty);
    });
  });

  group('LiveMlImageLabelingService', () {
    test('is ready before dispose', () {
      final service = LiveMlImageLabelingService();
      expect(service.isReady, true);
      service.dispose();
      expect(service.isReady, false);
    });
  });

  group('LabelResult', () {
    test('toString shows label and confidence percentage', () {
      const result = LabelResult(label: 'Dog', confidence: 0.9876);
      expect(result.toString(), 'LabelResult(Dog, 98.8%)');
    });
  });
}
