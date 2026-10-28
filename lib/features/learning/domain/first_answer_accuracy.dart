import 'evidence_context.dart';

/// Rebuildable display metric; never rewrites evidence or reward grants.
abstract final class FirstAnswerAccuracy {
  static const version = 'first-answer-accuracy-v1';

  static bool includes(EvidenceContext context) =>
      context.hintLevel == 0 &&
      switch (context.evidenceClass) {
        EvidenceClass.independentRecall ||
        EvidenceClass.recognition ||
        EvidenceClass.pronunciation => true,
        EvidenceClass.assessment ||
        EvidenceClass.guidedPractice ||
        EvidenceClass.exposure ||
        EvidenceClass.recreational => false,
      };

  /// Input must be in captured occurrence order. Attempt numbers can be global
  /// session ordinals, so they cannot identify an item's first answer.
  static List<T> select<T>(
    Iterable<T> ordered, {
    required EvidenceContext Function(T) contextOf,
    required Object Function(T, EvidenceContext) identityOf,
  }) {
    final seen = <Object>{};
    final result = <T>[];
    for (final row in ordered) {
      final context = contextOf(row);
      if (includes(context) && seen.add(identityOf(row, context))) {
        result.add(row);
      }
    }
    return result;
  }
}
