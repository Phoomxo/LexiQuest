import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/dataset_partitioning_service.dart';

void main() {
  test('partition splits dataset into 70:15:15 proportions', () {
    final now = DateTime.now();
    final logs = List.generate(
      100,
      (i) => GameplayTelemetryPoint(
        wordId: 'w_$i',
        responseTimeMs: 2000.0 + i,
        isCorrect: i % 2 == 0,
        timestamp: now.add(Duration(minutes: i)),
      ),
    );

    final dataset = DatasetPartitioningService.partition(logs);

    expect(dataset.trainSet.length, 70);
    expect(dataset.validationSet.length, 15);
    expect(dataset.testSet.length, 15);
  });

  test('partition handles small dataset safely', () {
    final dataset = DatasetPartitioningService.partition([]);
    expect(dataset.trainSet, isEmpty);
    expect(dataset.validationSet, isEmpty);
    expect(dataset.testSet, isEmpty);
  });
}
