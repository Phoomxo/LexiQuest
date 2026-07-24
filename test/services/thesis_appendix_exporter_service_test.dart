import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/brahmawong_research_analytics_service.dart';
import 'package:vocab_learning_app/services/crisp_dm_analytics_service.dart';
import 'package:vocab_learning_app/services/thesis_appendix_exporter_service.dart';

void main() {
  test('exportBrahmawongLatex formats clean LaTeX table code', () {
    const report = BrahmawongReport(
      e1ProcessEfficiency: 88.5,
      e2ProductEfficiency: 91.2,
      satisfies8080Standard: true,
      cohensDEffectSize: 1.45,
      effectSizeInterpretation: 'Large / Highly Significant',
    );

    final latex = ThesisAppendixExporterService.exportBrahmawongLatex(report);

    expect(latex, contains('\\begin{table}'));
    expect(latex, contains('88.5'));
    expect(latex, contains('1.45'));
  });

  test('exportBenchmarkLatex formats clean LaTeX table code', () {
    const metrics = ModelBenchmarkMetrics(
      modelName: 'LexiQuest Model',
      accuracy: 0.92,
      precision: 0.95,
      recall: 0.89,
      f1Score: 0.92,
    );

    final latex = ThesisAppendixExporterService.exportBenchmarkLatex(metrics);

    expect(latex, contains('LexiQuest Model'));
    expect(latex, contains('0.92'));
  });
}
