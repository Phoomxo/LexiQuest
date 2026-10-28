import '../domain/pair_matching_engine.dart';

/// Transient feedback for an acknowledged operation, never learning evidence.
final class PairFeedbackEpisode {
  const PairFeedbackEpisode({
    required this.identity,
    required this.wordId,
    required this.assisted,
    this.fading = false,
  });
  final String identity, wordId;
  final bool assisted, fading;
  PairFeedbackEpisode fade() => PairFeedbackEpisode(
    identity: identity,
    wordId: wordId,
    assisted: assisted,
    fading: true,
  );
  static List<PairFeedbackEpisode> accepted(
    PairMatchingState before,
    PairMatchingState after,
  ) {
    if (before.plan.ownerId != after.plan.ownerId ||
        before.plan.learningSessionId != after.plan.learningSessionId ||
        before.roundOrdinal != after.roundOrdinal ||
        after.pending != null ||
        after.lastOperationId == null ||
        before.lastOperationId == after.lastOperationId) {
      return const [];
    }
    return [
      for (final id in after.matchedWordIds.difference(before.matchedWordIds))
        PairFeedbackEpisode(
          identity:
              '${after.plan.learningSessionId}:${after.roundOrdinal}:${after.lastOperationId}:$id',
          wordId: id,
          assisted: after.supportedWordIds.contains(id),
        ),
    ];
  }
}
