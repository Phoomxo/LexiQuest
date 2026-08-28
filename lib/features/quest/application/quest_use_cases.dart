import '../../events/domain/event_envelope_v2.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../rewards/application/shadow_reward_orchestrator.dart';
import '../domain/quest_models.dart';
import '../domain/quest_repository.dart';

typedef QuestUtcNow = DateTime Function();
typedef QuestIdGenerator = String Function();

final class QuestProjectionEvaluation {
  const QuestProjectionEvaluation({
    required this.eligible,
    required this.completed,
  });

  final bool eligible;
  final List<QuestCompletedEvent> completed;
}

/// Called when a quest completes. The callback grants the paired XP and Coin
/// reward. Errors are swallowed in production — reward failure must never
/// break the learning flow.
typedef QuestRewardSink =
    Future<void> Function({
      required String ownerId,
      required String idempotencyKey,
      required int xpAmount,
      required String sourceEventId,
      required DateTime occurredAtUtc,
      String? rewardItemId,
    });

/// Application façade for the V2 Quest domain.
///
/// All mutations go through this class; callers never touch [QuestRepository]
/// or [QuestInstance] state directly.
///
/// The durable projection is always composed. `Feature.questV2` controls only
/// learner-facing invocation; it must never disable event projection, reward
/// reconciliation, or scheduling.
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

  /// When non-null, the quest-completion economy award is granted via this
  /// callback. Idempotent by the durable completion source identity.
  final QuestRewardSink? rewardSink;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Seed the catalog with [def] and start a new active [QuestInstance] for
  /// the current owner unless one is already active for the same quest.
  ///
  /// Returns the new [QuestInstance], or null when the quest is already active.
  Future<QuestInstance?> startQuest(QuestDefinition def) async {
    _validateDefinition(def);
    final owner = await owners.getOrCreateActiveOwner();
    final existing = await repository.getActiveInstances(owner.id);
    QuestInstance? active;
    for (final instance in existing) {
      if (instance.questId != def.questId) continue;
      if (active != null) {
        throw StateError('duplicate active quest authority state');
      }
      active = instance;
    }
    if (active != null) {
      final stored = await repository.getDefinition(def.questId);
      _requirePinnedInstance(
        instance: active,
        catalogDefinition: def,
        storedDefinition: stored,
        expectedOwnerId: owner.id,
      );
      return null;
    }

    await repository.upsertDefinition(def);

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

  /// Retained only so older callers fail closed instead of silently bypassing
  /// evidence eligibility, receipt versioning, and prerequisite ordering.
  @Deprecated(
    'Direct Quest events are unsupported; use durable reconciliation.',
  )
  Future<List<QuestCompletedEvent>> processEvent(
    EventEnvelopeV2 event,
    List<QuestDefinition> catalog,
  ) async {
    throw UnsupportedError(
      'Quest progress requires the durable evidence projection reconciler.',
    );
  }

  /// Projects one event and reports whether any active quest existed at the
  /// event time. Equality with assignment time is explicitly eligible.
  Future<QuestProjectionEvaluation> projectEvent(
    EventEnvelopeV2 event,
    List<QuestDefinition> catalog,
  ) async {
    final catalogById = _validatedCatalog(catalog);
    final active = await repository.getActiveInstances(event.ownerIdentity);
    final completedByEvent = await repository
        .getCompletedInstancesForSourceEvent(
          ownerId: event.ownerIdentity,
          sourceEventId: event.eventId,
          questIds: catalogById.keys,
        );
    if (active.isEmpty && completedByEvent.isEmpty) {
      return const QuestProjectionEvaluation(eligible: false, completed: []);
    }

    final relevant = <QuestInstance>[...active, ...completedByEvent];
    for (final instance in relevant) {
      final definition = catalogById[instance.questId];
      final stored = await repository.getDefinition(instance.questId);
      _requirePinnedInstance(
        instance: instance,
        catalogDefinition: definition,
        storedDefinition: stored,
        expectedOwnerId: event.ownerIdentity,
      );
    }

    final completed = <QuestCompletedEvent>[];
    final now = _now();
    var eligible = false;

    for (final instance in active) {
      if (event.occurredAtUtc.isBefore(instance.assignedAtUtc)) continue;
      eligible = true;
      final def = catalogById[instance.questId]!;

      final updated = instance.advanceIfMatches(
        _eventForObjectiveMatching(event),
        def.objectives,
      );
      if (identical(updated, instance)) {
        if (instance.isAllObjectivesComplete) {
          completed.add(await _finalize(instance, event, now));
        }
        continue;
      }

      await repository.saveProgress(instance.instanceId, updated.progress);

      if (updated.isAllObjectivesComplete) {
        completed.add(await _finalize(updated, event, now));
      }
    }
    for (final instance in completedByEvent) {
      if (event.occurredAtUtc.isBefore(instance.assignedAtUtc)) continue;
      eligible = true;
      final completion = instance.complete(
        now: instance.completedAtUtc ?? event.recordedAtUtc,
      );
      _forwardToShadow(completion, event);
      completed.add(completion);
    }
    return QuestProjectionEvaluation(eligible: eligible, completed: completed);
  }

  Map<String, dynamic> projectionPayload(
    QuestProjectionEvaluation evaluation,
    List<QuestDefinition> catalog,
  ) {
    return <String, dynamic>{
      'eligible': evaluation.eligible,
      'rewardGrants': evaluation.completed
          .map((completion) {
            final definition = catalog.firstWhere(
              (candidate) => candidate.questId == completion.questId,
            );
            final rewardItemId = definition.reward.rewardItemId;
            return <String, dynamic>{
              'ownerId': completion.ownerId,
              'idempotencyKey': completion.idempotencyKey,
              'xpAmount': definition.reward.xpAmount,
              // This is also the source identity written by the deployed
              // Quest XP path. Keeping it canonical lets an interrupted
              // pre-separation grant replay without creating duplicate XP.
              'sourceEventId': completion.idempotencyKey,
              'occurredAtUtcMs':
                  completion.completedAtUtc.millisecondsSinceEpoch,
              'rewardItemId': ?rewardItemId,
            };
          })
          .toList(growable: false),
    };
  }

  /// Return all active instances for the current owner.
  Future<List<QuestInstance>> getActiveInstances() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.getActiveInstances(owner.id);
  }

  /// Returns a bounded read-only status projection for the active owner.
  Future<List<QuestInstance>> getAllInstancesForCurrentOwner({
    int limit = 50,
  }) async {
    if (limit < 1 || limit > 50) {
      throw RangeError.range(limit, 1, 50, 'limit');
    }
    final owner = await owners.getOrCreateActiveOwner();
    return repository.getAllInstances(owner.id, limit: limit);
  }

  /// Retries the reward projection for a completed quest caused by [event].
  ///
  /// Unlike the interactive completion hook, sink failures propagate so the
  /// durable learning reconciler can leave the reward receipt pending.
  Future<bool> reconcileReward(
    EventEnvelopeV2 event,
    Map<String, dynamic> questProjection,
  ) async {
    final grants = _validatedRewardGrants(event, questProjection);
    final sink = rewardSink;
    if (sink == null) return false;
    var reconciled = false;
    for (final grant in grants) {
      await sink(
        ownerId: grant.ownerId,
        idempotencyKey: grant.idempotencyKey,
        xpAmount: grant.xpAmount,
        sourceEventId: grant.sourceEventId,
        occurredAtUtc: grant.occurredAtUtc,
        rewardItemId: grant.rewardItemId,
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

  Map<String, QuestDefinition> _validatedCatalog(
    List<QuestDefinition> catalog,
  ) {
    if (catalog.length > 64) {
      throw StateError('quest projection catalog exceeds 64 definitions');
    }
    final byId = <String, QuestDefinition>{};
    for (final definition in catalog) {
      _validateDefinition(definition);
      if (byId.containsKey(definition.questId)) {
        throw StateError('duplicate quest catalog definition');
      }
      byId[definition.questId] = definition;
    }
    return Map<String, QuestDefinition>.unmodifiable(byId);
  }

  void _requirePinnedInstance({
    required QuestInstance instance,
    required QuestDefinition? catalogDefinition,
    required QuestDefinition? storedDefinition,
    required String expectedOwnerId,
  }) {
    final definition = catalogDefinition;
    final stored = storedDefinition;
    if (instance.ownerId != expectedOwnerId ||
        definition == null ||
        stored == null ||
        instance.catalogVersion != definition.catalogVersion ||
        !_sameDefinition(stored, definition) ||
        !_progressMatchesDefinition(instance.progress, definition)) {
      throw StateError('quest catalog pin does not match durable instance');
    }
  }

  void _validateDefinition(QuestDefinition definition) {
    if (!_validIdentifier(definition.questId) ||
        definition.catalogVersion < 1 ||
        definition.objectives.isEmpty ||
        definition.objectives.length > 64 ||
        definition.reward.xpAmount < 0) {
      throw StateError('invalid quest catalog definition');
    }
    final objectiveIds = <String>{};
    for (final objective in definition.objectives) {
      if (!_validIdentifier(objective.objectiveId) ||
          !_validIdentifier(objective.criteria.eventType) ||
          objective.targetCount < 1 ||
          !objectiveIds.add(objective.objectiveId)) {
        throw StateError('invalid quest catalog objective');
      }
    }
  }

  bool _progressMatchesDefinition(
    List<ObjectiveProgress> progress,
    QuestDefinition definition,
  ) {
    if (progress.length != definition.objectives.length) return false;
    final byId = <String, ObjectiveProgress>{};
    for (final value in progress) {
      if (byId.containsKey(value.objectiveId) ||
          value.currentCount < 0 ||
          value.currentCount > value.targetCount ||
          value.sourceEventIds.length != value.sourceEventIds.toSet().length) {
        return false;
      }
      byId[value.objectiveId] = value;
    }
    for (final objective in definition.objectives) {
      final value = byId[objective.objectiveId];
      if (value == null || value.targetCount != objective.targetCount) {
        return false;
      }
    }
    return true;
  }

  bool _sameDefinition(QuestDefinition left, QuestDefinition right) {
    if (left.questId != right.questId ||
        left.catalogVersion != right.catalogVersion ||
        left.title != right.title ||
        left.description != right.description ||
        left.type != right.type ||
        left.reward.xpAmount != right.reward.xpAmount ||
        left.reward.rewardItemId != right.reward.rewardItemId ||
        left.expiresIn != right.expiresIn ||
        !_sameList(left.tags, right.tags) ||
        left.objectives.length != right.objectives.length) {
      return false;
    }
    for (var index = 0; index < left.objectives.length; index++) {
      final a = left.objectives[index];
      final b = right.objectives[index];
      if (a.objectiveId != b.objectiveId ||
          a.description != b.description ||
          a.targetCount != b.targetCount ||
          a.criteria.eventType != b.criteria.eventType ||
          !_sameValue(a.criteria.filters, b.criteria.filters)) {
        return false;
      }
    }
    return true;
  }

  bool _sameList(List<Object?> left, List<Object?> right) {
    if (left.length != right.length) return false;
    for (var index = 0; index < left.length; index++) {
      if (!_sameValue(left[index], right[index])) return false;
    }
    return true;
  }

  bool _sameValue(Object? left, Object? right) {
    if (left is Map && right is Map) {
      if (left.length != right.length || !left.keys.every(right.containsKey)) {
        return false;
      }
      return left.keys.every((key) => _sameValue(left[key], right[key]));
    }
    if (left is List && right is List) return _sameList(left, right);
    return left == right;
  }

  bool _validIdentifier(String value) =>
      value.trim() == value && value.isNotEmpty && value.runes.length <= 256;

  String _nextId() => generateId().trim();

  EventEnvelopeV2 _eventForObjectiveMatching(EventEnvelopeV2 source) {
    if (source.payload.containsKey('correct') ||
        (source.eventType != 'QuizCompleted' &&
            source.eventType != 'QuizAttempted')) {
      return source;
    }
    return EventEnvelopeV2(
      eventId: source.eventId,
      eventType: source.eventType,
      eventVersion: source.eventVersion,
      occurredAtUtc: source.occurredAtUtc,
      recordedAtUtc: source.recordedAtUtc,
      actorIdentity: source.actorIdentity,
      ownerIdentity: source.ownerIdentity,
      tenantContext: source.tenantContext,
      aggregateType: source.aggregateType,
      aggregateId: source.aggregateId,
      correlationId: source.correlationId,
      causationId: source.causationId,
      idempotencyKey: source.idempotencyKey,
      consentContext: source.consentContext,
      experimentContext: source.experimentContext,
      contentRevision: source.contentRevision,
      policyVersion: source.policyVersion,
      appVersion: source.appVersion,
      buildId: source.buildId,
      providerProvenance: source.providerProvenance,
      privacyClassification: source.privacyClassification,
      payload: <String, dynamic>{
        ...source.payload,
        'correct': source.eventType == 'QuizCompleted',
      },
    );
  }

  Future<QuestCompletedEvent> _finalize(
    QuestInstance instance,
    EventEnvelopeV2 source,
    DateTime completedAt,
  ) async {
    await repository.markCompleted(instance.instanceId, completedAt);
    final event = instance.complete(now: completedAt);
    _forwardToShadow(event, source);
    return event;
  }

  List<_ValidatedQuestRewardGrant> _validatedRewardGrants(
    EventEnvelopeV2 event,
    Map<String, dynamic> questProjection,
  ) {
    const resultKeys = <String>{'eligible', 'rewardGrants'};
    if (questProjection.length != resultKeys.length ||
        !questProjection.keys.every(resultKeys.contains) ||
        questProjection['eligible'] is! bool ||
        questProjection['eligible'] != true ||
        questProjection['rewardGrants'] is! List) {
      throw StateError('invalid applied quest projection result');
    }
    final rawGrants = questProjection['rewardGrants'] as List;
    if (rawGrants.length > 64) {
      throw StateError('quest projection reward grant batch exceeds 64');
    }
    const requiredKeys = <String>{
      'ownerId',
      'idempotencyKey',
      'xpAmount',
      'sourceEventId',
      'occurredAtUtcMs',
    };
    const allowedKeys = <String>{
      'ownerId',
      'idempotencyKey',
      'xpAmount',
      'sourceEventId',
      'occurredAtUtcMs',
      'rewardItemId',
    };
    final keys = <String>{};
    final validated = <_ValidatedQuestRewardGrant>[];
    for (final raw in rawGrants) {
      if (raw is! Map) throw StateError('invalid quest reward grant');
      final grant = raw.cast<Object?, Object?>();
      if (grant.keys.any((key) => key is! String) ||
          !requiredKeys.every(grant.containsKey) ||
          grant.keys.any((key) => !allowedKeys.contains(key))) {
        throw StateError('invalid quest reward grant shape');
      }
      final ownerId = grant['ownerId'];
      final idempotencyKey = grant['idempotencyKey'];
      final xpAmount = grant['xpAmount'];
      final sourceEventId = grant['sourceEventId'];
      final occurredAtUtcMs = grant['occurredAtUtcMs'];
      final rewardItemId = grant['rewardItemId'];
      final hasRewardItemId = grant.containsKey('rewardItemId');
      if (ownerId is! String || ownerId != event.ownerIdentity) {
        throw StateError('quest reward owner does not match source event');
      }
      if (idempotencyKey is! String ||
          idempotencyKey.trim() != idempotencyKey ||
          idempotencyKey.isEmpty ||
          idempotencyKey.runes.length > 256 ||
          !keys.add(idempotencyKey)) {
        throw StateError('invalid quest reward idempotency key');
      }
      if (xpAmount is! int || xpAmount <= 0 || xpAmount > 0x7fffffffffffffff) {
        throw StateError('invalid quest reward XP amount');
      }
      if (sourceEventId is! String ||
          sourceEventId.trim() != sourceEventId ||
          sourceEventId.isEmpty ||
          sourceEventId.runes.length > 256 ||
          sourceEventId != idempotencyKey) {
        throw StateError('invalid quest reward source event ID');
      }
      if (occurredAtUtcMs is! int ||
          occurredAtUtcMs < 0 ||
          occurredAtUtcMs > 8640000000000000) {
        throw StateError('invalid quest reward occurrence time');
      }
      if (hasRewardItemId &&
          (rewardItemId == null ||
              rewardItemId is! String ||
              rewardItemId.trim() != rewardItemId ||
              rewardItemId.isEmpty ||
              rewardItemId.runes.length > 256)) {
        throw StateError('invalid quest reward item ID');
      }
      validated.add(
        _ValidatedQuestRewardGrant(
          ownerId: ownerId,
          idempotencyKey: idempotencyKey,
          xpAmount: xpAmount,
          sourceEventId: sourceEventId,
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
            occurredAtUtcMs,
            isUtc: true,
          ),
          rewardItemId: rewardItemId as String?,
        ),
      );
    }
    return validated;
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
}

final class _ValidatedQuestRewardGrant {
  const _ValidatedQuestRewardGrant({
    required this.ownerId,
    required this.idempotencyKey,
    required this.xpAmount,
    required this.sourceEventId,
    required this.occurredAtUtc,
    this.rewardItemId,
  });

  final String ownerId;
  final String idempotencyKey;
  final int xpAmount;
  final String sourceEventId;
  final DateTime occurredAtUtc;
  final String? rewardItemId;
}
