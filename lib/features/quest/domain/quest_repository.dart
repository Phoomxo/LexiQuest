import '../domain/quest_models.dart';
import '../../events/domain/event_envelope_v2.dart';

/// Repository port for the V2 Quest domain.
///
/// Exact instance-identity replays preserve existing progress; conflicting
/// identities are rejected.
abstract interface class QuestRepository {
  // ── Definitions ────────────────────────────────────────────────────────────

  /// Persist a [QuestDefinition] from the catalog.
  ///
  /// Exact same-version content is a no-op. Changed same-version content and
  /// revision downgrades are rejected; a newer version replaces the definition.
  Future<void> upsertDefinition(QuestDefinition def);

  /// Return the stored definition for [questId], or null if absent.
  Future<QuestDefinition?> getDefinition(String questId);

  // ── Instances ──────────────────────────────────────────────────────────────

  /// Insert a new [QuestInstance] with state [QuestInstanceState.active].
  ///
  /// An exact identity replay preserves existing state and objective rows.
  Future<void> startInstance(QuestInstance instance);

  /// Return all instances with state 'active' for [ownerId].
  Future<List<QuestInstance>> getActiveInstances(String ownerId);

  /// Return all instances regardless of state for [ownerId].
  Future<List<QuestInstance>> getAllInstances(String ownerId);

  // ── Progress ───────────────────────────────────────────────────────────────

  /// Applies one persisted answer under a top-level current-owner transaction.
  /// [EventEnvelopeV2.eventId] is its canonical attempt ID, not proof itself. Load
  /// the actual owned attempt/session, validate eligibility and every prior
  /// objective source, and pin catalog/window facts before advancing. Persist
  /// progress and first completion together; replay emits no new completion.
  /// Returned completions follow durable commit. No grants or event-row writes.
  Future<List<QuestCompletedEvent>> applyCanonicalAnswer({
    required String ownerId,
    required EventEnvelopeV2 event,
    required List<QuestDefinition> catalog,
  });

  // ── State transitions ─────────────────────────────────────────────────────

  /// Mark [instanceId] as expired at [expiredAtUtc].
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc);

  /// Mark [instanceId] as abandoned.
  Future<void> markAbandoned(String instanceId);
}
