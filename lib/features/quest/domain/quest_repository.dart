import '../domain/quest_models.dart';

/// Repository port for the V2 Quest domain.
///
/// Implementations must be idempotent: inserting the same [QuestInstance]
/// twice (same [QuestInstance.instanceId]) must be a no-op rather than an
/// error, supporting safe replay and cold-start recovery.
abstract interface class QuestRepository {
  // ── Definitions ────────────────────────────────────────────────────────────

  /// Persist a [QuestDefinition] from the catalog.
  ///
  /// Uses insertOrReplace semantics — a newer [catalogVersion] overwrites the
  /// existing row; the same version is a no-op via insertOrIgnore.
  Future<void> upsertDefinition(QuestDefinition def);

  /// Return the stored definition for [questId], or null if absent.
  Future<QuestDefinition?> getDefinition(String questId);

  // ── Instances ──────────────────────────────────────────────────────────────

  /// Insert a new [QuestInstance] with state [QuestInstanceState.active].
  ///
  /// Idempotent: if [instance.instanceId] already exists, the call is ignored.
  Future<void> startInstance(QuestInstance instance);

  /// Return all instances with state 'active' for [ownerId].
  Future<List<QuestInstance>> getActiveInstances(String ownerId);

  /// Return all instances regardless of state for [ownerId].
  Future<List<QuestInstance>> getAllInstances(String ownerId);

  /// Return a bounded set of completed instances whose durable objective
  /// evidence contains [sourceEventId]. Used to reconstruct a projection
  /// result after a crash between the state transition and receipt commit.
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  });

  // ── Progress ───────────────────────────────────────────────────────────────

  /// Persist updated [progress] list for the given [instanceId].
  ///
  /// Overwrites existing progress rows for the same
  /// `(instanceId, objectiveId)` pair (upsert semantics).
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  );

  // ── State transitions ─────────────────────────────────────────────────────

  /// Mark [instanceId] as completed at [completedAtUtc].
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc);

  /// Mark [instanceId] as expired at [expiredAtUtc].
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc);

  /// Mark [instanceId] as abandoned.
  Future<void> markAbandoned(String instanceId);
}
