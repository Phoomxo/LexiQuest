import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/dataset_partitioning_service.dart';
import 'package:vocab_learning_app/services/ghost_model_trainer_service.dart';

void main() {
  test('trainAndEvaluate trains model and computes MAE on test set', () {
    final now = DateTime.now();
    final logs = List.generate(
      100,
      (i) => GameplayTelemetryPoint(
        wordId: 'w_$i',
        responseTimeMs: 2000.0 + (i % 10) * 100,
        isCorrect: i % 2 == 0,
        timestamp: now.add(Duration(minutes: i)),
      ),
    );

    final partitioned = DatasetPartitioningService.partition(logs);
    final trainedModel = GhostModelTrainerService.trainAndEvaluate(
      partitioned,
    );

    expect(trainedModel.predictedAvgLatencyMs > 0, isTrue);
    expect(trainedModel.predictedAccuracyRate, 0.50);
    expect(trainedModel.tunedAttackIntervalSeconds >= 1.5, isTrue);
    expect(trainedModel.meanAbsoluteErrorMs >= 0, isTrue);
    expect(trainedModel.modelEvaluationSummary, contains('MAE'));
  });
}
