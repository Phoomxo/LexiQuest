import 'pair_matching_engine.dart';

/// Descriptive read model. Never an evidence or reward authority.
final class PairStarResult {
  const PairStarResult({
    required this.matched,
    required this.independent,
    required this.assisted,
    required this.stars,
    required this.policyVersion,
  });
  final int matched, independent, assisted, policyVersion;
  final int? stars;
}

abstract final class PairStarPolicy {
  static PairStarResult project(
    PairMatchingState state, {
    required bool terminalAcknowledged,
  }) {
    if (state.plan.starPolicyVersion != 1) {
      throw StateError('Unsupported Pair star policy');
    }
    final independent = <String>{};
    final first = <String, PairAttemptRequested>{};
    for (final attempt in state.attempts) {
      first.putIfAbsent(attempt.promptWordId, () => attempt);
      if (attempt.isCorrect &&
          state.classificationFor(attempt).hintLevel == 0) {
        independent.add(attempt.promptWordId);
      }
    }
    final matched = state.matchedWordIds.length;
    final count = independent.intersection(state.matchedWordIds).length;
    final complete =
        terminalAcknowledged && state.complete && state.pending == null;
    final perfect =
        state.supportedWordIds.isEmpty &&
        first.length == state.plan.orderedLexicalItems.length &&
        first.values.every((a) => a.isCorrect);
    return PairStarResult(
      matched: matched,
      independent: count,
      assisted: matched - count,
      policyVersion: state.plan.starPolicyVersion,
      stars: !complete
          ? null
          : perfect
          ? 3
          : count * 4 >= matched * 3
          ? 2
          : 1,
    );
  }
}
