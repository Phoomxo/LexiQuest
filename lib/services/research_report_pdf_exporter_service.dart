import 'dart:math';

import 'research_export_errors.dart';

export 'research_export_errors.dart';

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

class InvalidResearchData implements Exception {
  final String message;

  const InvalidResearchData(this.message);

  @override
  String toString() => 'InvalidResearchData: $message';
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

    for (var index = 0; index < observations.length; index++) {
      final observation = observations[index];
      if (!_isBoundedScore(observation.preTestScore) ||
          !_isBoundedScore(observation.postTestScore) ||
          !_isPositiveFinite(observation.preLatencyMs) ||
          !_isPositiveFinite(observation.postLatencyMs)) {
        throw InvalidResearchData(
          'Observation ${index + 1} contains an invalid score or latency.',
        );
      }
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
      preTestSd: _sampleStandardDeviation(preTestScores, preTestMean),
      postTestMean: postTestMean,
      postTestSd: _sampleStandardDeviation(postTestScores, postTestMean),
      meanGainPercentage: postTestMean - preTestMean,
      preLatencyMs: preLatencyMs,
      postLatencyMs: postLatencyMs,
      latencyReductionPercentage:
          (preLatencyMs - postLatencyMs) / preLatencyMs * 100,
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
    buffer.writeln('   - Paired Observations (N): ${stats.sampleSize}');
    buffer.writeln(
      '   - Pre-Test Score (Mean +/- Sample SD (N-1)): ${stats.preTestMean.toStringAsFixed(1)}% +/- ${stats.preTestSd.toStringAsFixed(1)}',
    );
    buffer.writeln(
      '   - Post-Test Score (Mean +/- Sample SD (N-1)): ${stats.postTestMean.toStringAsFixed(1)}% +/- ${stats.postTestSd.toStringAsFixed(1)}',
    );
    buffer.writeln(
      '   - Mean Score Change: ${_formatSigned(stats.meanGainPercentage)} percentage points',
    );
    buffer.writeln(
      '   - Pre-Test Recall Latency: ${stats.preLatencyMs.toStringAsFixed(0)} ms',
    );
    buffer.writeln(
      '   - Post-Test Recall Latency: ${stats.postLatencyMs.toStringAsFixed(0)} ms',
    );
    buffer.writeln(
      '   - ${_formatLatencyChange(stats.latencyReductionPercentage)}',
    );
    buffer.writeln(
      '===============================================================',
    );

    return buffer.toString();
  }

  static double _mean(List<double> values) {
    return values.reduce((sum, value) => sum + value) / values.length;
  }

  static bool _isBoundedScore(double value) {
    return value.isFinite && value >= 0 && value <= 100;
  }

  static bool _isPositiveFinite(double value) {
    return value.isFinite && value > 0;
  }

  static double _sampleStandardDeviation(List<double> values, double mean) {
    final variance =
        values
            .map((value) => pow(value - mean, 2))
            .reduce((sum, value) => sum + value) /
        (values.length - 1);
    return sqrt(variance);
  }

  static String _formatSigned(double value) {
    final sign = value > 0 ? '+' : '';
    return '$sign${value.toStringAsFixed(1)}';
  }

  static String _formatLatencyChange(double reductionPercentage) {
    if (reductionPercentage > 0) {
      return 'Recall Latency Reduction: '
          '${reductionPercentage.toStringAsFixed(1)}%';
    }
    if (reductionPercentage < 0) {
      return 'Recall Latency Increase: '
          '${(-reductionPercentage).toStringAsFixed(1)}%';
    }
    return 'Recall Latency Change: 0.0% (no change)';
  }
}
