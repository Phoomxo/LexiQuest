/// Canonical local-only signals which may produce reviewed companion copy.
///
/// `unknown` is intentionally representable so callers can fail closed when a
/// future producer crosses the v1 boundary without adding a reaction.
enum CompanionReactionSignal {
  sessionStarted,
  retryAfterIncorrectCommit,
  sessionCompleted,
  unknown,
}

/// Minimal immutable context for one ephemeral companion reaction.
///
/// It deliberately has no owner, raw answer, provider, transcript, or
/// persistence identity. The lesson controller owns the canonical session and
/// response evidence; this value is only a post-commit display consumer.
final class CompanionReactionEvent {
  const CompanionReactionEvent({
    required this.catalogVersion,
    required this.signal,
    required this.sessionId,
    required this.committedResponseCount,
  });

  final int catalogVersion;
  final CompanionReactionSignal signal;
  final String sessionId;
  final int committedResponseCount;

  bool get isCanonicalV1 =>
      catalogVersion == 1 &&
      sessionId.isNotEmpty &&
      sessionId == sessionId.trim() &&
      sessionId.runes.length <= 256 &&
      committedResponseCount >= 0 &&
      switch (signal) {
        CompanionReactionSignal.sessionStarted => committedResponseCount == 0,
        CompanionReactionSignal.retryAfterIncorrectCommit =>
          committedResponseCount > 0,
        CompanionReactionSignal.sessionCompleted => true,
        CompanionReactionSignal.unknown => false,
      };

  @override
  bool operator ==(Object other) =>
      other is CompanionReactionEvent &&
      other.catalogVersion == catalogVersion &&
      other.signal == signal &&
      other.sessionId == sessionId &&
      other.committedResponseCount == committedResponseCount;

  @override
  int get hashCode =>
      Object.hash(catalogVersion, signal, sessionId, committedResponseCount);
}

/// Reviewed, deterministic copy resolved from a compile-time catalog.
final class CompanionReaction {
  const CompanionReaction({
    required this.catalogVersion,
    required this.event,
    required this.copy,
  });

  final int catalogVersion;
  final CompanionReactionEvent event;
  final String copy;

  @override
  bool operator ==(Object other) =>
      other is CompanionReaction &&
      other.catalogVersion == catalogVersion &&
      other.event == event &&
      other.copy == copy;

  @override
  int get hashCode => Object.hash(catalogVersion, event, copy);
}
