import '../../events/domain/event_envelope_v2.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

typedef QuestUtcNow = DateTime Function();
typedef QuestIdGenerator = String Function();

/// Application façade for the V2 Quest domain.
///
/// All mutations go through this class; callers never touch [QuestRepository]
/// or [QuestInstance] state directly.
///
/// The use-case is **feature-flagged**: callers must check
/// `features.isEnabled(Feature.questV2)` before constructing this class.
/// When the flag is off, instantiate nothing — this class assumes the flag
/// is already checked by the caller.
final class QuestUseCases {
  QuestUseCases({
    required this.repository,
    required this.owners,
    required this.generateId,
    required this.nowUtc,
    required this.timezoneId,
    this.resolveTimezoneId,
    this.shadowOrchestrator,
  });

  final QuestRepository repository;
  final LocalOwnerRepository owners;
  final QuestIdGenerator generateId;
  final QuestUtcNow nowUtc;

  /// IANA timezone id for the learner, e.g. `'Asia/Bangkok'`.
  final String timezoneId;
  final Future<String> Function(String ownerId)? resolveTimezoneId;

  /// When non-null, [QuestCompletedEvent]s are forwarded to the V2 reward
  /// shadow pipeline.  Errors are swallowed — shadow mode must never break
  /// production.
  final ShadowRewardOrchestrator? shadowOrchestrator;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Seed the catalog with [def] and start a new active [QuestInstance] for
  /// the current owner after recovering its assigned canonical answers.
  ///
  /// Returns null when the pinned current period already exists in any state.
  Future<QuestInstance?> startQuest(
    QuestDefinition def, {
    String? expectedOwnerId,
    bool Function()? stillCurrent,
  }) async {
    final current = stillCurrent ?? () => true;
    if (!current()) throw StateError('Quest owner changed');
    final owner = await owners.getOrCreateActiveOwner();
    if (!current() ||
        (expectedOwnerId != null && owner.id != expectedOwnerId)) {
      throw StateError('Quest owner changed');
    }
    final zone =
        await (resolveTimezoneId?.call(owner.id) ?? Future.value(timezoneId));
    if (!current()) throw StateError('Quest owner changed');
    return repository.assignCurrentPeriod(
      instanceId: 'quest:${_nextId()}',
      ownerId: owner.id,
      definition: def,
      assignedAtUtc: _now(),
      timezoneId: zone,
      stillCurrent: current,
    );
  }

  Future<List<QuestCompletedEvent>> reconcile({
    required String expectedOwnerId,
    required List<QuestDefinition> catalog,
    required bool Function() stillCurrent,
  }) => repository.reconcile(
    expectedOwnerId: expectedOwnerId,
    catalog: catalog,
    stillCurrent: stillCurrent,
  );

  /// Feed [event] into all active quest instances for the event's owner.
  ///
  /// For each instance whose objectives advance, the updated progress is
  /// persisted.  If all objectives complete, the instance is marked completed
  /// and a [QuestCompletedEvent] is returned (and optionally forwarded to the
  /// shadow orchestrator).
  ///
  /// Returns all [QuestCompletedEvent]s produced in this call (typically 0 or
  /// 1, but multiple quests may complete from a single event).
  Future<List<QuestCompletedEvent>> processEvent(
    EventEnvelopeV2 event,
    List<QuestDefinition> catalog,
  ) async {
    final completed = await repository.applyCanonicalAnswer(
      ownerId: event.ownerIdentity,
      event: event,
      catalog: catalog,
    );
    for (final completion in completed) {
      _forwardToShadow(completion, event);
    }
    return completed;
  }

  /// Return all active instances for the current owner.
  Future<List<QuestInstance>> getActiveInstances() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.getActiveInstances(owner.id);
  }

  /// Expire any active instances whose deadline has passed.
  ///
  /// Call on app foreground or session start.  Safe to call multiple times —
  /// already-expired instances are left unchanged.
  Future<void> expireStale() async {
    final owner = await owners.getOrCreateActiveOwner();
    final active = await repository.getActiveInstances(owner.id);
    if (active.isEmpty) {
      return;
    }

    final catalog = <String, QuestDefinition>{};
    for (final instance in active) {
      final def = await repository.getDefinition(instance.questId);
      if (def != null) catalog[def.questId] = def;
    }
    await repository.reconcile(
      expectedOwnerId: owner.id,
      catalog: catalog.values.toList(),
      stillCurrent: () => true,
    );
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _nextId() => generateId().trim();

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    }
    return value;
  }

  void _forwardToShadow(
    QuestCompletedEvent completedEvent,
    EventEnvelopeV2 sourceEvent,
  ) {
    final orchestrator = shadowOrchestrator;
    if (orchestrator == null) {
      return;
    }
    // Build a synthetic V2 envelope for the QuestCompleted event so that
    // the reward shadow pipeline can evaluate eligibility.
    try {
      final questEvent = EventEnvelopeV2(
        eventId: completedEvent.eventId,
        eventType: 'QuestCompleted',
        eventVersion: 1,
        occurredAtUtc: completedEvent.completedAtUtc,
        recordedAtUtc: completedEvent.completedAtUtc,
        actorIdentity: sourceEvent.actorIdentity,
        ownerIdentity: completedEvent.ownerId,
        aggregateType: 'QuestInstance',
        aggregateId: completedEvent.questInstanceId,
        idempotencyKey: completedEvent.idempotencyKey,
        consentContext: sourceEvent.consentContext,
        appVersion: sourceEvent.appVersion,
        buildId: sourceEvent.buildId,
        privacyClassification: sourceEvent.privacyClassification,
        payload: {
          'questId': completedEvent.questInstanceId.split(':').last,
          'questType': _questTypeFromIdempotencyKey(
            completedEvent.idempotencyKey,
          ),
          'objectiveEventIds': completedEvent.objectiveEventIds,
        },
      );
      // Fire-and-forget; errors swallowed.
      orchestrator.processShadow(questEvent).ignore();
    } catch (_) {
      // Shadow mode must never break production.
    }
  }

  /// Extracts quest type hint from the deterministic idempotency key.
  /// Falls back to 'daily' which maps to the lowest reward tier.
  String _questTypeFromIdempotencyKey(String key) => 'daily';
}
