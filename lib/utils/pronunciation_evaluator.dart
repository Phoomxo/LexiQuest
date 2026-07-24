import 'dart:math';

final class PronunciationDiff {
  final String targetWord;
  final String spokenText;
  final int scorePercentage;
  final bool isExactMatch;

  const PronunciationDiff({
    required this.targetWord,
    required this.spokenText,
    required this.scorePercentage,
    required this.isExactMatch,
  });
}

/// Evaluates pronunciation precision using normalized Levenshtein distance.
final class PronunciationEvaluator {
  const PronunciationEvaluator._();

  static PronunciationDiff evaluate(String target, String spoken) {
    final cleanTarget = target.trim().toLowerCase();
    final cleanSpoken = spoken.trim().toLowerCase();

    if (cleanTarget.isEmpty) {
      return PronunciationDiff(
        targetWord: target,
        spokenText: spoken,
        scorePercentage: 0,
        isExactMatch: false,
      );
    }

    if (cleanTarget == cleanSpoken) {
      return PronunciationDiff(
        targetWord: target,
        spokenText: spoken,
        scorePercentage: 100,
        isExactMatch: true,
      );
    }

    final distance = _levenshteinDistance(cleanTarget, cleanSpoken);
    final maxLen = max(cleanTarget.length, cleanSpoken.length);
    final similarity = (1.0 - (distance / maxLen)).clamp(0.0, 1.0);
    final score = (similarity * 100).round();

    return PronunciationDiff(
      targetWord: target,
      spokenText: spoken,
      scorePercentage: score,
      isExactMatch: false,
    );
  }

  static int _levenshteinDistance(String s1, String s2) {
    if (s1 == s2) return 0;
    if (s1.isEmpty) return s2.length;
    if (s2.isEmpty) return s1.length;

    List<int> v0 = List<int>.generate(s2.length + 1, (i) => i);
    List<int> v1 = List<int>.filled(s2.length + 1, 0);

    for (int i = 0; i < s1.length; i++) {
      v1[0] = i + 1;
      for (int j = 0; j < s2.length; j++) {
        int cost = (s1[i] == s2[j]) ? 0 : 1;
        v1[j + 1] = min(v1[j] + 1, min(v0[j + 1] + 1, v0[j] + cost));
      }
      for (int j = 0; j <= s2.length; j++) {
        v0[j] = v1[j];
      }
    }
    return v1[s2.length];
  }
}
