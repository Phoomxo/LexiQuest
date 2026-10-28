// Immutable, storage-independent progress domain types and the repository
// boundary used to record and read aggregated game progress.
//
// Validation (empty session ids, negative or implausibly large counts) is the
// atomic responsibility of ProgressRepository implementations. These value
// types therefore impose no constraints of their own, so callers and tests can
// construct any inbound session and let the repository decide what is valid.

/// A completed game session to be recorded into the progress store.
final class ProgressSession {
  const ProgressSession({
    required this.sessionId,
    required this.correctAnswers,
    required this.wrongAnswers,
  });

  /// Stable identifier for the session; used for idempotent recording.
  final String sessionId;

  /// Number of correctly answered prompts in the session.
  final int correctAnswers;

  /// Number of incorrectly answered prompts in the session.
  final int wrongAnswers;
}

/// An immutable, point-in-time view of the user's aggregated progress.
final class ProgressSnapshot {
  const ProgressSnapshot({
    required this.totalPoints,
    required this.totalCorrectAnswers,
    required this.totalWrongAnswers,
    required this.gamesPlayed,
  });

  /// Lifetime points accumulated from recorded sessions.
  final int totalPoints;

  /// Lifetime count of correctly answered prompts.
  final int totalCorrectAnswers;

  /// Lifetime count of incorrectly answered prompts.
  final int totalWrongAnswers;

  /// Number of distinct sessions recorded.
  final int gamesPlayed;
}

/// Storage-, Firebase-, and Flutter-independent boundary for recording local
/// game progress and reading its aggregated state.
///
/// Implementations own atomic validation and persistence; this interface only
/// defines the contract exercised by callers and tests.
abstract interface class ProgressRepository {
  /// Records [session], accumulating its totals into the user's progress.
  ///
  /// Implementations validate [session] atomically and throw [ArgumentError]
  /// for invalid input without mutating persisted state. Re-recording a session
  /// with an already seen [ProgressSession.sessionId] is idempotent.
  Future<void> recordSession(ProgressSession session);

  /// Returns the current aggregated progress snapshot.
  Future<ProgressSnapshot> readSnapshot();

  /// Returns the sessions recorded locally but not yet synchronized upstream.
  Future<List<ProgressSession>> pendingSessions();
}
