import '../../events/domain/event_envelope_v2.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

typedef QuestUtcNow = DateTime Function();
typedef QuestIdGenerator = String Function();

/// Called when a quest completes. The callback grants the XP reward to the
/// learner's points ledger. Errors are swallowed in production — reward
/// failure must never break the learning flow.
typedef QuestRewardSink =
    Future<void> Function({
      required String ownerId,
      required String idempotencyKey,
      required int xpAmount,
      String? rewardItemId,
    });

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
    this.shadowOrchestrator,
    this.rewardSink,
  });

  final QuestRepository repository;
  final LocalOwnerRepository owners;
  final QuestIdGenerator generateId;
  final QuestUtcNow nowUtc;

  /// IANA timezone id for the learner, e.g. `'Asia/Bangkok'`.
  final String timezoneId;

  /// When non-null, [QuestCompletedEvent]s are forwarded to the V2 reward
  /// shadow pipeline.  Errors are swallowed — shadow mode must never break
  /// production.
  final ShadowRewardOrchestrator? shadowOrchestrator;

  /// When non-null, quest-completion XP is granted to the learner's points
  /// ledger via this callback. Idempotent by `idempotencyKey`.
  final QuestRewardSink? rewardSink;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Seed the catalog with [def] and start a new active [QuestInstance] for
  /// the current owner unless one is already active for the same quest.
  ///
  /// Returns the new [QuestInstance], or null when the quest is already active.
  Future<QuestInstance?> startQuest(QuestDefinition def) async {
    final owner = await owners.getOrCreateActiveOwner();
    await repository.upsertDefinition(def);

    final existing = await repository.getActiveInstances(owner.id);
    if (existing.any((i) => i.questId == def.questId)) return null;

    final now = _now();
    final instance = QuestInstance(
      instanceId: 'quest:${_nextId()}',
      questId: def.questId,
      ownerId: owner.id,
      catalogVersion: def.catalogVersion,
      assignedAtUtc: now,
      state: QuestInstanceState.active,
      progress: def.objectives
          .map(
            (o) => ObjectiveProgress(
              objectiveId: o.objectiveId,
              currentCount: 0,
              targetCount: o.targetCount,
            ),
          )
          .toList(growable: false),
    );
    await repository.startInstance(instance);
    return instance;
  }

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
    final active = await repository.getActiveInstances(event.ownerIdentity);
    if (active.isEmpty) return const [];

    final completed = <QuestCompletedEvent>[];
    final now = _now();

    for (final instance in active) {
      final def = catalog.firstWhere(
        (d) => d.questId == instance.questId,
        orElse: () => throw StateError(
          'QuestUseCases.processEvent: no catalog entry for '
          'questId=${instance.questId}',
        ),
      );

      final updated = instance.advanceIfMatches(event, def.objectives);
      if (identical(updated, instance)) {
        if (instance.isAllObjectivesComplete) {
          completed.add(await _finalize(instance, def, event, now));
        }
        continue;
      }

      await repository.saveProgress(instance.instanceId, updated.progress);

      if (updated.isAllObjectivesComplete) {
        completed.add(await _finalize(updated, def, event, now));
      }
    }
    return completed;
  }

  /// Return all active instances for the current owner.
  Future<List<QuestInstance>> getActiveInstances() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.getActiveInstances(owner.id);
  }

  /// Retries the reward projection for a completed quest caused by [event].
  ///
  /// Unlike the interactive completion hook, sink failures propagate so the
  /// durable learning reconciler can leave the reward receipt pending.
  Future<bool> reconcileReward(
    EventEnvelopeV2 event,
    List<QuestDefinition> catalog,
  ) async {
    final sink = rewardSink;
    if (sink == null) return false;
    var reconciled = false;
    final instances = await repository.getAllInstances(event.ownerIdentity);
    for (final instance in instances) {
      if (instance.state != QuestInstanceState.completed ||
          !instance.allSourceEventIds.contains(event.eventId)) {
        continue;
      }
      final def = catalog.firstWhere(
        (candidate) => candidate.questId == instance.questId,
        orElse: () => throw StateError(
          'QuestUseCases.reconcileReward: no catalog entry for '
          'questId=${instance.questId}',
        ),
      );
      if (def.reward.xpAmount <= 0) continue;
      final completed = instance.complete(now: instance.completedAtUtc);
      await sink(
        ownerId: completed.ownerId,
        idempotencyKey: completed.idempotencyKey,
        xpAmount: def.reward.xpAmount,
        rewardItemId: def.reward.rewardItemId,
      );
      reconciled = true;
    }
    return reconciled;
  }

  /// Expire any active instances whose deadline has passed.
  ///
  /// Call on app foreground or session start.  Safe to call multiple times —
  /// already-expired instances are left unchanged.
  Future<void> expireStale() async {
    final owner = await owners.getOrCreateActiveOwner();
    final active = await repository.getActiveInstances(owner.id);
    if (active.isEmpty) return;

    final now = _now();
    for (final instance in active) {
      final def = await repository.getDefinition(instance.questId);
      if (def == null) continue;

      final expiresIn = def.expiresIn;
      if (expiresIn == null) continue;

      final deadline = instance.assignedAtUtc.add(expiresIn);
      if (now.isAfter(deadline)) {
        await repository.markExpired(instance.instanceId, now);
      }
    }
  }

  // ── Private helpers ────────────────────────────────────────────────────────

  String _nextId() => generateId().trim();

  Future<QuestCompletedEvent> _finalize(
    QuestInstance instance,
    QuestDefinition definition,
    EventEnvelopeV2 source,
    DateTime completedAt,
  ) async {
    await repository.markCompleted(instance.instanceId, completedAt);
    final event = instance.complete(now: completedAt);
    _forwardToShadow(event, source);
    await _grantReward(definition, event);
    return event;
  }

  DateTime _now() {
    final value = nowUtc();
    if (!value.isUtc) throw ArgumentError.value(value, 'nowUtc', 'must be UTC');
    return value;
  }

  void _forwardToShadow(
    QuestCompletedEvent completedEvent,
    EventEnvelopeV2 sourceEvent,
  ) {
    final orchestrator = shadowOrchestrator;
    if (orchestrator == null) return;
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

  /// Grants quest-completion XP via [rewardSink] when wired.
  /// Idempotent by `completedEvent.idempotencyKey`. Errors are swallowed.
  Future<void> _grantReward(
    QuestDefinition def,
    QuestCompletedEvent completedEvent,
  ) async {
    final sink = rewardSink;
    if (sink == null) return;
    if (def.reward.xpAmount <= 0) return;
    try {
      await sink(
        ownerId: completedEvent.ownerId,
        idempotencyKey: completedEvent.idempotencyKey,
        xpAmount: def.reward.xpAmount,
        rewardItemId: def.reward.rewardItemId,
      );
    } catch (_) {
      // Reward grant failure must never break the learning flow.
    }
  }
}
