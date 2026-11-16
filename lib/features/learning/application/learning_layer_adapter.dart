import 'learning_use_cases.dart';

/// Port that bridges the in-memory associative learning prototype layer
/// (`lib/learning/`) with the authoritative V2 feature layer.
///
/// **Purpose:**
/// `lib/learning/` is an in-memory prototype for the associative reading
/// loop feature (branch: `feature/associative-reading-loop`).  It stores
/// associations, memory states, and recall attempts in plain Dart collections
/// that are lost on app restart.  This interface defines the contract that a
/// Drift-backed adapter will implement in Phase 1, when the associative
/// reading feature graduates from prototype to production.
///
/// **Phase 0 scope:**
/// Only the in-memory adapter [InMemoryAssociativeLearningAdapter] is
/// provided here.  Drift persistence (schema v9) is deferred to Phase 1.
///
/// **Relationship to [LearningUseCases]:**
/// SRS scheduling for production vocabulary words must go through
/// [LearningUseCases.startDueReview] / [LearningUseCases.recordAnswer].
/// This port handles supplementary associative-memory data only — it does
/// not replace the core SRS authority.
abstract interface class AssociativeLearningPort {
  // ── Associations ──────────────────────────────────────────────────────────

  /// Persist an association record (keyword, story, image link, etc.)
  /// for a word owned by [ownerId].
  Future<void> saveAssociation(AssociationRecord record);

  /// Return all associations the [ownerId] has created for [wordKey].
  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  );

  /// Remove an association by its ID.
  Future<void> deleteAssociation(String associationId);

  // ── Memory states ─────────────────────────────────────────────────────────

  /// Return the current [AssociativeMemoryState] for the (ownerId, wordKey)
  /// pair, or null when no review has been recorded yet.
  Future<AssociativeMemoryState?> getMemoryState(
    String ownerId,
    String wordKey,
  );

  /// Persist an updated [AssociativeMemoryState].
  Future<void> updateMemoryState(AssociativeMemoryState state);

  /// Return all [AssociativeMemoryState] rows for [ownerId].
  Future<List<AssociativeMemoryState>> getAllMemoryStates(String ownerId);
}

// ─── Value objects ────────────────────────────────────────────────────────────

/// An association created by the learner for a word — keyword, mnemonic
/// story, image URL, or other personal memory anchor.
final class AssociationRecord {
  const AssociationRecord({
    required this.associationId,
    required this.ownerId,
    required this.wordKey,
    required this.type,
    required this.content,
    required this.createdAtUtc,
  });

  final String associationId;
  final String ownerId;
  final String wordKey;

  /// E.g. 'keyword', 'story', 'image_url'.
  final String type;

  final String content;
  final DateTime createdAtUtc;
}

/// In-memory snapshot of associative-memory algorithm state for one word.
final class AssociativeMemoryState {
  const AssociativeMemoryState({
    required this.ownerId,
    required this.wordKey,
    required this.stability,
    required this.difficulty,
    required this.cueDependency,
    required this.lapseCount,
    this.lastReviewedAtUtc,
    required this.nextDueAtUtc,
    required this.algorithmVersion,
  });

  final String ownerId;
  final String wordKey;
  final double stability;
  final double difficulty;
  final double cueDependency;
  final int lapseCount;
  final DateTime? lastReviewedAtUtc;
  final DateTime nextDueAtUtc;
  final String algorithmVersion;
}

// ─── In-memory adapter (Phase 0) ─────────────────────────────────────────────

/// In-memory [AssociativeLearningPort] for use in tests and during Phase 0
/// while Drift persistence (schema v9) is not yet implemented.
///
/// All state is held in plain Dart collections and is **lost on app restart**.
final class InMemoryAssociativeLearningAdapter
    implements AssociativeLearningPort {
  final Map<String, AssociationRecord> _associations = {};
  final Map<String, AssociativeMemoryState> _states = {};

  @override
  Future<void> saveAssociation(AssociationRecord record) async =>
      _associations[record.associationId] = record;

  @override
  Future<List<AssociationRecord>> getAssociationsForWord(
    String ownerId,
    String wordKey,
  ) async => _associations.values
      .where((a) => a.ownerId == ownerId && a.wordKey == wordKey)
      .toList(growable: false);

  @override
  Future<void> deleteAssociation(String associationId) async =>
      _associations.remove(associationId);

  @override
  Future<AssociativeMemoryState?> getMemoryState(
    String ownerId,
    String wordKey,
  ) async => _states['$ownerId:$wordKey'];

  @override
  Future<void> updateMemoryState(AssociativeMemoryState state) async =>
      _states['${state.ownerId}:${state.wordKey}'] = state;

  @override
  Future<List<AssociativeMemoryState>> getAllMemoryStates(
    String ownerId,
  ) async =>
      _states.values.where((s) => s.ownerId == ownerId).toList(growable: false);
}
