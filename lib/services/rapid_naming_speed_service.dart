class RapidNamingReport {
  final String targetWord;
  final int responseTimeMs;
  final String
  fluencyRating; // 'Ultra-Fast (Native-like)', 'Fluent', 'Hesitant'
  final int automaticityScore; // 0 to 100

  const RapidNamingReport({
    required this.targetWord,
    required this.responseTimeMs,
    required this.fluencyRating,
    required this.automaticityScore,
  });
}

/// Rapid Automatized Naming (RAN) & Lexical Retrieval Speed Engine
/// (Cognitive Science 2024 & Brain and Language 2023 Standard).
class RapidNamingSpeedService {
  const RapidNamingSpeedService();

  /// Evaluates response latency in milliseconds to benchmark speech automaticity
  static RapidNamingReport evaluateSpeed({
    required String targetWord,
    required int responseTimeMs,
  }) {
    final String rating;
    final int score;

    if (responseTimeMs <= 400) {
      rating = 'Ultra-Fast (Native-like Automaticity)';
      score = 100;
    } else if (responseTimeMs <= 800) {
      rating = 'Fluent & Accurate';
      score = 85;
    } else if (responseTimeMs <= 1500) {
      rating = 'Moderate Retrieval';
      score = 65;
    } else {
      rating = 'Hesitant (Needs Phonological Practice)';
      score = 40;
    }

    return RapidNamingReport(
      targetWord: targetWord,
      responseTimeMs: responseTimeMs,
      fluencyRating: rating,
      automaticityScore: score,
    );
  }
}
