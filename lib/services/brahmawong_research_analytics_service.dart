import 'dart:math';

class BrahmawongReport {
  final double e1ProcessEfficiency;
  final double e2ProductEfficiency;
  final bool satisfies8080Standard;
  final double cohensDEffectSize;
  final String effectSizeInterpretation;

  const BrahmawongReport({
    required this.e1ProcessEfficiency,
    required this.e2ProductEfficiency,
    required this.satisfies8080Standard,
    required this.cohensDEffectSize,
    required this.effectSizeInterpretation,
  });
}

/// Calculates Brahmawong 80/80 Efficiency Standard (E1/E2) & Cohen's d Effect Size.
class BrahmawongResearchAnalyticsService {
  const BrahmawongResearchAnalyticsService();

  /// Calculates E1 (process efficiency) and E2 (product efficiency)
  /// E1 = (Total Quiz Scores / Total Max Process Score) * 100
  /// E2 = (Total Post-test Scores / Total Max Product Score) * 100
  static BrahmawongReport evaluateEfficiency({
    required List<double> processQuizScores,
    required double maxProcessScore,
    required List<double> postTestScores,
    required double maxPostTestScore,
    required List<double> preTestScores,
  }) {
    if (processQuizScores.isEmpty ||
        postTestScores.isEmpty ||
        maxProcessScore <= 0 ||
        maxPostTestScore <= 0) {
      return const BrahmawongReport(
        e1ProcessEfficiency: 0,
        e2ProductEfficiency: 0,
        satisfies8080Standard: false,
        cohensDEffectSize: 0,
        effectSizeInterpretation: 'Insufficient data',
      );
    }

    final avgProcess =
        processQuizScores.reduce((a, b) => a + b) / processQuizScores.length;
    final e1 = (avgProcess / maxProcessScore) * 100;

    final avgPost =
        postTestScores.reduce((a, b) => a + b) / postTestScores.length;
    final e2 = (avgPost / maxPostTestScore) * 100;

    final satisfies8080 = e1 >= 80.0 && e2 >= 80.0;

    final cohensD = _calculateCohensD(preTestScores, postTestScores);
    final String interpretation;
    if (cohensD >= 0.8) {
      interpretation = 'Large / Highly Significant (สูงยิ่งยวด)';
    } else if (cohensD >= 0.5) {
      interpretation = 'Medium / Moderate (ปานกลาง)';
    } else {
      interpretation = 'Small (น้อย)';
    }

    return BrahmawongReport(
      e1ProcessEfficiency: double.parse(e1.toStringAsFixed(2)),
      e2ProductEfficiency: double.parse(e2.toStringAsFixed(2)),
      satisfies8080Standard: satisfies8080,
      cohensDEffectSize: double.parse(cohensD.toStringAsFixed(2)),
      effectSizeInterpretation: interpretation,
    );
  }

  static double _calculateCohensD(
    List<double> preScores,
    List<double> postScores,
  ) {
    if (preScores.isEmpty || postScores.isEmpty) return 0.0;

    final meanPre = preScores.reduce((a, b) => a + b) / preScores.length;
    final meanPost = postScores.reduce((a, b) => a + b) / postScores.length;

    final varPre =
        preScores.map((x) => pow(x - meanPre, 2)).reduce((a, b) => a + b) /
        (preScores.length > 1 ? preScores.length - 1 : 1);
    final varPost =
        postScores.map((x) => pow(x - meanPost, 2)).reduce((a, b) => a + b) /
        (postScores.length > 1 ? postScores.length - 1 : 1);

    final pooledSd = sqrt((varPre + varPost) / 2);
    if (pooledSd == 0) return 0.0;

    return (meanPost - meanPre) / pooledSd;
  }
}
