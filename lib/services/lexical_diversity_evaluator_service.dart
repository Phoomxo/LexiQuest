class LexicalDiversityReport {
  final int totalTokens;
  final int uniqueTypes;
  final double ttrScore; // 0.0 to 1.0
  final String diversityLevel;
  final String feedback;

  const LexicalDiversityReport({
    required this.totalTokens,
    required this.uniqueTypes,
    required this.ttrScore,
    required this.diversityLevel,
    required this.feedback,
  });
}

/// Lexical Diversity & TTR Evaluator Engine (Read 2000 Vocabulary Standard).
class LexicalDiversityEvaluatorService {
  const LexicalDiversityEvaluatorService();

  /// Calculates Type-Token Ratio (TTR = Unique Types / Total Tokens)
  static LexicalDiversityReport evaluateText(String text) {
    final tokens = _tokenize(text);
    if (tokens.isEmpty) {
      return const LexicalDiversityReport(
        totalTokens: 0,
        uniqueTypes: 0,
        ttrScore: 0.0,
        diversityLevel: 'ไม่มีข้อมูล',
        feedback: 'ไม่พบข้อความประโยคสำหรับการวิเคราะห์',
      );
    }

    final types = tokens.toSet();
    final ttr = types.length / tokens.length;

    final String level;
    final String feedbackText;

    if (ttr >= 0.80) {
      level = 'สูงมาก (Highly Diverse)';
      feedbackText = 'คลังคำศัพท์หลากหลายสละสลวย โดดเด่นระดับสูง';
    } else if (ttr >= 0.60) {
      level = 'ปานกลาง (Moderate)';
      feedbackText = 'คลังคำศัพท์มีความหลากหลายปานกลาง';
    } else {
      level = 'ค่อนข้างน้อย (Repetitive)';
      feedbackText = 'มีการใช้คำศัพท์ซ้ำเดิม ควรลองสลับใช้คำไวพจน์ (Synonyms)';
    }

    return LexicalDiversityReport(
      totalTokens: tokens.length,
      uniqueTypes: types.length,
      ttrScore: double.parse(ttr.toStringAsFixed(3)),
      diversityLevel: level,
      feedback: feedbackText,
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
}
