import 'dart:math';

class SemanticEvaluationResult {
  final double similarityScore; // 0.0 to 1.0
  final bool isSemanticallyEquivalent;
  final String feedback;

  const SemanticEvaluationResult({
    required this.similarityScore,
    required this.isSemanticallyEquivalent,
    required this.feedback,
  });
}

/// Cosine Similarity NLP Vector Space Engine (Vector Space Model Standard).
class CosineSimilarityEvaluatorService {
  const CosineSimilarityEvaluatorService();

  /// Calculates cosine similarity between two sentences: cos(theta) = (A . B) / (||A|| ||B||)
  static SemanticEvaluationResult evaluateSimilarity({
    required String studentSentence,
    required String modelSentence,
    double threshold = 0.70,
  }) {
    final cleanStudent = _tokenize(studentSentence);
    final cleanModel = _tokenize(modelSentence);

    if (cleanStudent.isEmpty || cleanModel.isEmpty) {
      return const SemanticEvaluationResult(
        similarityScore: 0.0,
        isSemanticallyEquivalent: false,
        feedback: 'ไม่พบข้อความประโยคสำหรับการประเมิน',
      );
    }

    final vocabulary = <String>{...cleanStudent, ...cleanModel};

    final vecA = vocabulary.map((w) => _tf(w, cleanStudent)).toList();
    final vecB = vocabulary.map((w) => _tf(w, cleanModel)).toList();

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < vocabulary.length; i++) {
      dotProduct += vecA[i] * vecB[i];
      normA += vecA[i] * vecA[i];
      normB += vecB[i] * vecB[i];
    }

    if (normA == 0 || normB == 0) {
      return const SemanticEvaluationResult(
        similarityScore: 0.0,
        isSemanticallyEquivalent: false,
        feedback: 'ไม่สามารถคำนวณความเหมือนเชิงความหมายได้',
      );
    }

    final score = dotProduct / (sqrt(normA) * sqrt(normB));
    final isPass = score >= threshold;

    return SemanticEvaluationResult(
      similarityScore: double.parse(score.toStringAsFixed(3)),
      isSemanticallyEquivalent: isPass,
      feedback:
          isPass
              ? 'ประโยคตรงตามความหมายและบริบทสากล (ความเหมือน ${(score * 100).toStringAsFixed(1)}%)'
              : 'ประโยคยังมีความหมายคลาดเคลื่อนจากบริบทเป้าหมาย',
    );
  }

  static List<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .toList();
  }

  static double _tf(String word, List<String> tokens) {
    final count = tokens.where((t) => t == word).length;
    return count / tokens.length;
  }
}
