import 'dart:math';

class ResearchObservation {
  final double preTestScore;
  final double postTestScore;
  final double preLatencyMs;
  final double postLatencyMs;

  const ResearchObservation({
    required this.preTestScore,
    required this.postTestScore,
    required this.preLatencyMs,
    required this.postLatencyMs,
  });
}

class InsufficientData implements Exception {
  final String message;

  const InsufficientData([
    this.message = 'At least two real research observations are required.',
  ]);

  @override
  String toString() => 'InsufficientData: $message';
}

class ThesisAcademicStats {
  final double preTestMean;
  final double preTestSd;
  final double postTestMean;
  final double postTestSd;
  final double meanGainPercentage;
  final double preLatencyMs;
  final double postLatencyMs;
  final double latencyReductionPercentage;
  final int sampleSize;

  const ThesisAcademicStats({
    required this.preTestMean,
    required this.preTestSd,
    required this.postTestMean,
    required this.postTestSd,
    required this.meanGainPercentage,
    required this.preLatencyMs,
    required this.postLatencyMs,
    required this.latencyReductionPercentage,
    required this.sampleSize,
  });
}

class ResearchReportPdfExporterService {
  const ResearchReportPdfExporterService();

  ThesisAcademicStats calculateAcademicStats(
    List<ResearchObservation> observations,
  ) {
    if (observations.length < 2) {
      throw const InsufficientData();
    }

    final preTestScores = observations
        .map((observation) => observation.preTestScore)
        .toList();
    final postTestScores = observations
        .map((observation) => observation.postTestScore)
        .toList();
    final preLatencies = observations
        .map((observation) => observation.preLatencyMs)
        .toList();
    final postLatencies = observations
        .map((observation) => observation.postLatencyMs)
        .toList();
    final preTestMean = _mean(preTestScores);
    final postTestMean = _mean(postTestScores);
    final preLatencyMs = _mean(preLatencies);
    final postLatencyMs = _mean(postLatencies);

    return ThesisAcademicStats(
      preTestMean: preTestMean,
      preTestSd: _populationStandardDeviation(preTestScores, preTestMean),
      postTestMean: postTestMean,
      postTestSd: _populationStandardDeviation(postTestScores, postTestMean),
      meanGainPercentage: postTestMean - preTestMean,
      preLatencyMs: preLatencyMs,
      postLatencyMs: postLatencyMs,
      latencyReductionPercentage: preLatencyMs == 0
          ? 0
          : (preLatencyMs - postLatencyMs) / preLatencyMs * 100,
      sampleSize: observations.length,
    );
  }

  String generateAcademicPdfReport(List<ResearchObservation> observations) {
    final stats = calculateAcademicStats(observations);
    final buffer = StringBuffer();

    buffer.writeln(
      '===============================================================',
    );
    buffer.writeln('LEXIQUEST RESEARCH SUMMARY REPORT');
    buffer.writeln(
      '===============================================================\n',
    );
    buffer.writeln('1. OBSERVED SUMMARY STATISTICS');
    buffer.writeln('   - Sample Size (N): ${stats.sampleSize} participants');
    buffer.writeln(
      '   - Pre-Test Score (Mean +/- SD): ${stats.preTestMean.toStringAsFixed(1)}% +/- ${stats.preTestSd.toStringAsFixed(1)}',
    );
    buffer.writeln(
      '   - Post-Test Score (Mean +/- SD): ${stats.postTestMean.toStringAsFixed(1)}% +/- ${stats.postTestSd.toStringAsFixed(1)}',
    );
    buffer.writeln(
      '   - Mean Score Gain: +${stats.meanGainPercentage.toStringAsFixed(1)} percentage points',
    );
    buffer.writeln(
      '   - Pre-Test Recall Latency: ${stats.preLatencyMs.toStringAsFixed(0)} ms',
    );
    buffer.writeln(
      '   - Post-Test Recall Latency: ${stats.postLatencyMs.toStringAsFixed(0)} ms',
    );
    buffer.writeln(
      '   - Recall Latency Change: ${stats.latencyReductionPercentage.toStringAsFixed(1)}%',
    );
    buffer.writeln(
      '===============================================================',
    );

    return buffer.toString();
  }

  static double _mean(List<double> values) {
    return values.reduce((sum, value) => sum + value) / values.length;
  }

  static double _populationStandardDeviation(List<double> values, double mean) {
    final variance =
        values
            .map((value) => pow(value - mean, 2))
            .reduce((sum, value) => sum + value) /
        values.length;
    return sqrt(variance);
  }
}
