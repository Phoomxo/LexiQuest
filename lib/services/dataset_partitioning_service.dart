class GameplayTelemetryPoint {
  final String wordId;
  final double responseTimeMs;
  final bool isCorrect;
  final DateTime timestamp;

  const GameplayTelemetryPoint({
    required this.wordId,
    required this.responseTimeMs,
    required this.isCorrect,
    required this.timestamp,
  });
}

class PartitionedDataset {
  final List<GameplayTelemetryPoint> trainSet; // 70%
  final List<GameplayTelemetryPoint> validationSet; // 15%
  final List<GameplayTelemetryPoint> testSet; // 15%

  const PartitionedDataset({
    required this.trainSet,
    required this.validationSet,
    required this.testSet,
  });
}

/// Machine Learning Dataset Partitioning Service (Standard 70:15:15 Ratio Protocol).
class DatasetPartitioningService {
  const DatasetPartitioningService();

  /// Partition a list of gameplay telemetry points into Train (70%), Validation (15%), Test (15%)
  static PartitionedDataset partition(List<GameplayTelemetryPoint> logs) {
    if (logs.isEmpty) {
      return const PartitionedDataset(
        trainSet: [],
        validationSet: [],
        testSet: [],
      );
    }

    final sortedLogs = List<GameplayTelemetryPoint>.from(logs)
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));

    final total = sortedLogs.length;
    final trainEnd = (total * 0.70).round();
    final valEnd = (total * 0.85).round();

    final train = sortedLogs.sublist(0, trainEnd);
    final validation = sortedLogs.sublist(trainEnd, valEnd);
    final test = sortedLogs.sublist(valEnd);

    return PartitionedDataset(
      trainSet: train,
      validationSet: validation,
      testSet: test,
    );
  }
}
