import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/brahmawong_research_analytics_service.dart';

void main() {
  test('evaluateEfficiency handles empty scores safely', () {
    final report = BrahmawongResearchAnalyticsService.evaluateEfficiency(
      processQuizScores: [],
      maxProcessScore: 10,
      postTestScores: [],
      maxPostTestScore: 10,
      preTestScores: [],
    );

    expect(report.e1ProcessEfficiency, 0);
    expect(report.satisfies8080Standard, isFalse);
  });

  test(
    'evaluateEfficiency calculates E1/E2 80/80 and Cohen d correctly',
    () {
      final report = BrahmawongResearchAnalyticsService.evaluateEfficiency(
        processQuizScores: [8, 9, 9, 8, 10],
        maxProcessScore: 10,
        postTestScores: [9, 8, 9, 10, 9],
        maxPostTestScore: 10,
        preTestScores: [4, 5, 4, 3, 5],
      );

      expect(report.e1ProcessEfficiency, 88.0);
      expect(report.e2ProductEfficiency, 90.0);
      expect(report.satisfies8080Standard, isTrue);
      expect(report.cohensDEffectSize > 1.0, isTrue);
      expect(report.effectSizeInterpretation, contains('Large'));
    },
  );
}
