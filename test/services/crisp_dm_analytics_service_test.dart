import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/crisp_dm_analytics_service.dart';

void main() {
  test('calculateBenchmark returns valid metrics for confusion matrix', () {
    final metrics = CrispDmAnalyticsService.calculateBenchmark(
      modelName: 'LexiQuest SRS Model',
      truePositives: 85,
      falsePositives: 5,
      trueNegatives: 80,
      falseNegatives: 10,
    );

    expect(metrics.modelName, 'LexiQuest SRS Model');
    expect(metrics.accuracy, 0.917);
    expect(metrics.precision, 0.944);
    expect(metrics.recall, 0.895);
    expect(metrics.f1Score, 0.919);
  });

  test('crispDmStages contains 6 standard phases', () {
    expect(CrispDmAnalyticsService.crispDmStages.length, 6);
  });
}
