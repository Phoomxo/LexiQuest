class AssociationRule {
  final String antecedentWord; // X
  final String consequentWord; // Y
  final double support;
  final double confidence;

  const AssociationRule({
    required this.antecedentWord,
    required this.consequentWord,
    required this.support,
    required this.confidence,
  });
}

/// Data Mining Apriori Association Rules Engine (KMUTNB 2024 Thesis Standard).
/// Mines co-occurrence error patterns (X -> Y) to find vocabulary items users stumble on together.
class AprioriErrorMinerService {
  const AprioriErrorMinerService();

  /// Mines association rules from user session error logs
  /// [errorSessions] is a list of error word sets per session (e.g. [['apple', 'banana'], ['apple', 'cat']])
  static List<AssociationRule> mineRules({
    required List<List<String>> errorSessions,
    double minSupport = 0.2,
    double minConfidence = 0.5,
  }) {
    if (errorSessions.isEmpty) return const [];

    final totalSessions = errorSessions.length.toDouble();
    final itemCounts = <String, int>{};
    final pairCounts = <String, int>{};

    for (final session in errorSessions) {
      final uniqueItems = session.toSet().toList();
      for (final item in uniqueItems) {
        itemCounts[item] = (itemCounts[item] ?? 0) + 1;
      }

      for (int i = 0; i < uniqueItems.length; i++) {
        for (int j = i + 1; j < uniqueItems.length; j++) {
          final pairKey = '${uniqueItems[i]}::${uniqueItems[j]}';
          pairCounts[pairKey] = (pairCounts[pairKey] ?? 0) + 1;

          final reversePairKey = '${uniqueItems[j]}::${uniqueItems[i]}';
          pairCounts[reversePairKey] = (pairCounts[reversePairKey] ?? 0) + 1;
        }
      }
    }

    final rules = <AssociationRule>[];

    pairCounts.forEach((pairKey, count) {
      final parts = pairKey.split('::');
      final x = parts[0];
      final y = parts[1];

      final support = count / totalSessions;
      final xCount = itemCounts[x] ?? 0;
      final confidence = xCount > 0 ? count / xCount : 0.0;

      if (support >= minSupport && confidence >= minConfidence) {
        rules.add(
          AssociationRule(
            antecedentWord: x,
            consequentWord: y,
            support: double.parse(support.toStringAsFixed(2)),
            confidence: double.parse(confidence.toStringAsFixed(2)),
          ),
        );
      }
    });

    rules.sort((a, b) => b.confidence.compareTo(a.confidence));
    return rules;
  }
}
