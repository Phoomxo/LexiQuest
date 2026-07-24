import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/cognitive_attention_analyzer_service.dart';

void main() {
  test(
    'analyzeDwellTime identifies hesitation when dwell time exceeds 600ms',
    () {
      final report = CognitiveAttentionAnalyzerService.analyzeDwellTime(
        word: 'extraordinary',
        dwellTimeMs: 850,
      );

      expect(report.targetWord, 'extraordinary');
      expect(report.dwellTimeMs, 850);
      expect(report.isHesitated, true);
      expect(report.cognitiveLoadIndex, 0.85);
      expect(report.recommendation, contains('พบความลังเล'));
    },
  );

  test('analyzeDwellTime identifies normal fluent reading under 600ms', () {
    final report = CognitiveAttentionAnalyzerService.analyzeDwellTime(
      word: 'cat',
      dwellTimeMs: 250,
    );

    expect(report.isHesitated, false);
    expect(report.cognitiveLoadIndex, 0.25);
    expect(report.recommendation, contains('ความเร็วการประมวลผลปกติ'));
  });
}
