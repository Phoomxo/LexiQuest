class ModelBenchmarkMetrics {
  final String modelName;
  final double accuracy;
  final double precision;
  final double recall;
  final double f1Score;

  const ModelBenchmarkMetrics({
    required this.modelName,
    required this.accuracy,
    required this.precision,
    required this.recall,
    required this.f1Score,
  });
}

/// Implements CRISP-DM 6-Stage Process Analytics Engine (KMUTNB 2024 Thesis Standard).
class CrispDmAnalyticsService {
  const CrispDmAnalyticsService();

  static const List<String> crispDmStages = [
    '1. Business Understanding',
    '2. Data Understanding',
    '3. Data Preparation',
    '4. Modeling',
    '5. Evaluation',
    '6. Deployment',
  ];

  /// Calculates model benchmark metrics for thesis Chapter 4 reporting
  static ModelBenchmarkMetrics calculateBenchmark({
    required String modelName,
    required int truePositives,
    required int falsePositives,
    required int trueNegatives,
    required int falseNegatives,
  }) {
    final total =
        truePositives + falsePositives + trueNegatives + falseNegatives;
    if (total == 0) {
      return ModelBenchmarkMetrics(
        modelName: modelName,
        accuracy: 0,
        precision: 0,
        recall: 0,
        f1Score: 0,
      );
    }

    final accuracy = (truePositives + trueNegatives) / total;
    final precision = (truePositives + falsePositives) > 0
        ? truePositives / (truePositives + falsePositives)
        : 0.0;
    final recall = (truePositives + falseNegatives) > 0
        ? truePositives / (truePositives + falseNegatives)
        : 0.0;
    final f1 = (precision + recall) > 0
        ? (2 * precision * recall) / (precision + recall)
        : 0.0;

    return ModelBenchmarkMetrics(
      modelName: modelName,
      accuracy: double.parse(accuracy.toStringAsFixed(3)),
      precision: double.parse(precision.toStringAsFixed(3)),
      recall: double.parse(recall.toStringAsFixed(3)),
      f1Score: double.parse(f1.toStringAsFixed(3)),
    );
  }
}
