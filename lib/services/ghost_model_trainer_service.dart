import 'package:vocab_learning_app/services/dataset_partitioning_service.dart';

class TrainedGhostModel {
  final double predictedAvgLatencyMs;
  final double predictedAccuracyRate;
  final double tunedAttackIntervalSeconds;
  final double meanAbsoluteErrorMs;
  final String modelEvaluationSummary;

  const TrainedGhostModel({
    required this.predictedAvgLatencyMs,
    required this.predictedAccuracyRate,
    required this.tunedAttackIntervalSeconds,
    required this.meanAbsoluteErrorMs,
    required this.modelEvaluationSummary,
  });
}

/// Ghost Model Trainer & Evaluator Engine (Machine Learning Protocol Standard).
class GhostModelTrainerService {
  const GhostModelTrainerService();

  /// Trains ghost parameters on Train Set, tunes on Validation Set, and measures MAE on Test Set
  static TrainedGhostModel trainAndEvaluate(PartitionedDataset dataset) {
    if (dataset.trainSet.isEmpty) {
      return const TrainedGhostModel(
        predictedAvgLatencyMs: 2500,
        predictedAccuracyRate: 0.80,
        tunedAttackIntervalSeconds: 2.5,
        meanAbsoluteErrorMs: 0.0,
        modelEvaluationSummary: 'ข้อมูลไม่เพียงพอในการฝึกสอนโมเดลร่างเงา',
      );
    }

    // 1. Train Step: Compute base parameters from Train Set
    final trainTotal = dataset.trainSet.length;
    final trainCorrectCount = dataset.trainSet.where((p) => p.isCorrect).length;
    final trainAccuracy = trainCorrectCount / trainTotal;
    final trainAvgLatency =
        dataset.trainSet.map((p) => p.responseTimeMs).reduce((a, b) => a + b) /
        trainTotal;

    // 2. Validation Step: Tune attack interval hyperparameter
    double tunedInterval = trainAvgLatency / 1000.0;
    if (dataset.validationSet.isNotEmpty) {
      final valAvgLatency =
          dataset.validationSet
              .map((p) => p.responseTimeMs)
              .reduce((a, b) => a + b) /
          dataset.validationSet.length;
      // Hyperparameter fine-tuning blending train and validation
      tunedInterval = ((trainAvgLatency + valAvgLatency) / 2.0) / 1000.0;
    }
    tunedInterval = tunedInterval.clamp(1.5, 5.0);

    // 3. Test Step: Compute Mean Absolute Error (MAE) on unseen Test Set
    double maeSum = 0.0;
    if (dataset.testSet.isNotEmpty) {
      for (final testPoint in dataset.testSet) {
        maeSum += (testPoint.responseTimeMs - trainAvgLatency).abs();
      }
      final mae = maeSum / dataset.testSet.length;
      return TrainedGhostModel(
        predictedAvgLatencyMs: double.parse(trainAvgLatency.toStringAsFixed(1)),
        predictedAccuracyRate: double.parse(trainAccuracy.toStringAsFixed(2)),
        tunedAttackIntervalSeconds: double.parse(
          tunedInterval.toStringAsFixed(2),
        ),
        meanAbsoluteErrorMs: double.parse(mae.toStringAsFixed(1)),
        modelEvaluationSummary:
            'ฝึกสอนโมเดลร่างเงาสมบูรณ์ (ค่าความคลาดเคลื่อน MAE: ${mae.toStringAsFixed(1)} ms)',
      );
    }

    return TrainedGhostModel(
      predictedAvgLatencyMs: double.parse(trainAvgLatency.toStringAsFixed(1)),
      predictedAccuracyRate: double.parse(trainAccuracy.toStringAsFixed(2)),
      tunedAttackIntervalSeconds: double.parse(
        tunedInterval.toStringAsFixed(2),
      ),
      meanAbsoluteErrorMs: 0.0,
      modelEvaluationSummary: 'ฝึกสอนโมเดลร่างเงาเบื้องต้น',
    );
  }
}
