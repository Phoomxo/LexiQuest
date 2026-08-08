import 'dart:math';

/// RESEARCH_ONLY: Cosine Similarity NLP Vector Evaluator.
///
/// Owner-only research tool. Computes cosine similarity between two text
/// vectors using term-frequency representation. Returns 0.0 for empty inputs.
class CosineSimilarityEvaluatorService {
  const CosineSimilarityEvaluatorService();

  /// Computes cosine similarity between [textA] and [textB].
  /// Returns a value in [0.0, 1.0]. Returns 0.0 for empty inputs.
  double evaluate(String textA, String textB) {
    final tokensA = _tokenize(textA);
    final tokensB = _tokenize(textB);
    if (tokensA.isEmpty || tokensB.isEmpty) return 0.0;

    final vecA = _termFrequency(tokensA);
    final vecB = _termFrequency(tokensB);

    final allTerms = {...vecA.keys, ...vecB.keys};
    var dotProduct = 0.0;
    var normA = 0.0;
    var normB = 0.0;

    for (final term in allTerms) {
      final a = vecA[term] ?? 0.0;
      final b = vecB[term] ?? 0.0;
      dotProduct += a * b;
      normA += a * a;
      normB += b * b;
    }

    if (normA == 0 || normB == 0) return 0.0;
    return dotProduct / (sqrt(normA) * sqrt(normB));
  }

  List<String> _tokenize(String text) {
    final lower = text.toLowerCase();
    final tokens = <String>[];
    for (final raw in lower.split(RegExp(r'[^a-z0-9]+'))) {
      if (raw.isNotEmpty) tokens.add(raw);
    }
    return tokens;
  }

  Map<String, double> _termFrequency(List<String> tokens) {
    final counts = <String, int>{};
    for (final token in tokens) {
      counts[token] = (counts[token] ?? 0) + 1;
    }
    final total = tokens.length;
    return counts.map((k, v) => MapEntry(k, v / total));
  }
}
