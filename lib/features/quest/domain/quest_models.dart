/// Quest domain contracts — V2 authority for quest tracking.
///
/// This contract replaces the two incompatible legacy quest implementations
/// that are listed in the Quarantine Registry.  New code must use these
/// types instead of the quarantined services.
///
/// All types are immutable.  Mutation is expressed through projection rebuilding
/// rather than in-place state changes.
///
/// **Contract freeze:** Frozen after Week 5-6.  Schema v9 reserved for Drift
/// persistence of these models.
library;

import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';

// ─── Enums ────────────────────────────────────────────────────────────────────

/// Category of a quest, which determines its reset schedule.
enum QuestType {
  /// Resets at the learner's local-timezone learning day boundary.
  daily,

  /// Resets at the start of the learner's local-timezone week.
  weekly,

  /// One-time achievement; never resets.
  milestone,

  /// Multi-chapter narrative arc; advances sequentially.
  story,
}

/// Lifecycle state of a [QuestInstance].
enum QuestInstanceState {
  /// Quest is in progress.
  active,

  /// All objectives met.
  completed,

  /// Time limit elapsed before completion.
  expired,

  /// Explicitly abandoned by the learner or system.
  abandoned,
}

// ─── Objective matching ───────────────────────────────────────────────────────

/// Filter that decides whether a given [EventEnvelopeV2] counts toward an
/// objective.
final class ObjectiveCriteria {
  const ObjectiveCriteria({required this.eventType, this.filters});

  /// The V2 event type that this criterion listens for.
  final String eventType;

  /// Optional key→value pairs that must all match [EventEnvelopeV2.payload].
  final Map<String, dynamic>? filters;

  /// Returns `true` when [event] satisfies this criterion.
  bool matches(EventEnvelopeV2 event) {
    if (event.eventType != eventType) return false;
    final f = filters;
    if (f == null) return true;
    return f.entries.every((e) => event.payload[e.key] == e.value);
  }
}

// ─── Quest definition (authored content) ─────────────────────────────────────

/// A single trackable goal within a [QuestDefinition].
final class QuestObjective {
  const QuestObjective({
    required this.objectiveId,
    required this.description,
    required this.targetCount,
    required this.criteria,
  });

  final String objectiveId;
  final String description;

  /// Number of matching events required to complete this objective.
  final int targetCount;

  final ObjectiveCriteria criteria;
}

/// Reward specification attached to a completed quest.
final class RewardSpec {
  const RewardSpec({required this.xpAmount, this.rewardItemId});

  /// XP granted on completion (added to the learner's [PointsLedgerEntries]).
  final int xpAmount;

  /// Optional cosmetic reward item ID (added to [OwnedRewardItems]).
  final String? rewardItemId;
}

/// Immutable content definition authored by game designers.
///
/// [QuestDefinition]s are shipped with the app (catalog) or downloaded as
/// content updates.  They are never mutated at runtime.
final class QuestDefinition {
  const QuestDefinition({
    required this.questId,
    required this.catalogVersion,
    required this.title,
    required this.description,
    required this.type,
    required this.objectives,
    required this.reward,
    this.expiresIn,
    this.tags = const [],
  }) : assert(objectives.length > 0, 'quest must have at least one objective');

  final String questId;
  final int catalogVersion;
  final String title;
  final String description;
  final QuestType type;
  final List<QuestObjective> objectives;
  final RewardSpec reward;

  /// Duration after assignment before the quest expires; `null` = no expiry.
  final Duration? expiresIn;
  final List<String> tags;
}

// ─── Quest instance (learner progress) ───────────────────────────────────────

/// Progress toward a single [QuestObjective].
///
/// Immutable; a new [ObjectiveProgress] is created whenever progress advances.
final class ObjectiveProgress {
  const ObjectiveProgress({
    required this.objectiveId,
    required this.currentCount,
    required this.targetCount,
    this.sourceEventIds = const [],
  });

  final String objectiveId;
  final int currentCount;
  final int targetCount;

  /// IDs of the [EventEnvelopeV2] events that contributed to [currentCount].
  /// Forms the evidence chain for audit and idempotency.
  final List<String> sourceEventIds;

  bool get isComplete => currentCount >= targetCount;

  /// Returns a copy with [currentCount] incremented and [eventId] appended.
  /// Replaying an already-applied event returns this instance unchanged.
  ObjectiveProgress advance(String eventId) {
    if (sourceEventIds.contains(eventId)) return this;
    return ObjectiveProgress(
      objectiveId: objectiveId,
      currentCount: currentCount + 1,
      targetCount: targetCount,
      sourceEventIds: [...sourceEventIds, eventId],
    );
  }
}

/// The completion event emitted when a [QuestInstance] reaches all objectives.
final class QuestCompletedEvent {
  const QuestCompletedEvent({
    required this.eventId,
    required this.questInstanceId,
    required this.questId,
    required this.ownerId,
    required this.completedAtUtc,
    required this.objectiveEventIds,
    required this.idempotencyKey,
  });

  final String eventId;
  final String questInstanceId;
  final String questId;
  final String ownerId;
  final DateTime completedAtUtc;

  /// All [EventEnvelopeV2] event IDs that contributed to completion — the
  /// full evidence chain.
  final List<String> objectiveEventIds;

  /// Stable key that prevents duplicate reward grants on replay.
  final String idempotencyKey;
}

/// A learner's live progress on one [QuestDefinition].
///
/// Immutable.  Call [advanceIfMatches] to get a new instance with updated
/// progress, and [complete] to obtain the completion event.
final class QuestInstance {
  const QuestInstance({
    required this.instanceId,
    required this.questId,
    required this.ownerId,
    required this.catalogVersion,
    required this.assignedAtUtc,
    required this.state,
    required this.progress,
    this.completedAtUtc,
    this.expiredAtUtc,
  });

  final String instanceId;
  final String questId;
  final String ownerId;
  final int catalogVersion;
  final DateTime assignedAtUtc;
  final QuestInstanceState state;

  /// One [ObjectiveProgress] per objective in the quest definition.
  final List<ObjectiveProgress> progress;

  final DateTime? completedAtUtc;
  final DateTime? expiredAtUtc;

  // ── Derived ──────────────────────────────────────────────────────────────

  bool get isAllObjectivesComplete => progress.every((p) => p.isComplete);

  /// Collects all source event IDs across all objectives.
  List<String> get allSourceEventIds =>
      progress.expand((p) => p.sourceEventIds).toList(growable: false);

  // ── Projection helpers ────────────────────────────────────────────────────

  /// Evaluates [event] against each objective's [ObjectiveCriteria].
  ///
  /// Returns a new [QuestInstance] with updated [progress] if any objective
  /// matched; returns `this` unchanged when no objective matched.
  QuestInstance advanceIfMatches(
    EventEnvelopeV2 event,
    List<QuestObjective> objectives,
  ) {
    var changed = false;
    final updated = <ObjectiveProgress>[];
    for (final p in progress) {
      if (p.isComplete) {
        updated.add(p);
        continue;
      }
      final obj = objectives.cast<QuestObjective?>().firstWhere(
        (o) => o!.objectiveId == p.objectiveId,
        orElse: () => null,
      );
      if (obj != null && obj.criteria.matches(event)) {
        final next = p.advance(event.eventId);
        updated.add(next);
        changed = changed || !identical(next, p);
      } else {
        updated.add(p);
      }
    }
    if (!changed) return this;
    return QuestInstance(
      instanceId: instanceId,
      questId: questId,
      ownerId: ownerId,
      catalogVersion: catalogVersion,
      assignedAtUtc: assignedAtUtc,
      state: state,
      progress: updated,
      completedAtUtc: completedAtUtc,
      expiredAtUtc: expiredAtUtc,
    );
  }

  /// Produces a [QuestCompletedEvent] for this instance.
  ///
  /// The [idempotencyKey] is deterministic — calling this twice returns equal
  /// keys, so reward grant is idempotent.
  QuestCompletedEvent complete({DateTime? now}) {
    final completedAt = now ?? DateTime.now().toUtc();
    return QuestCompletedEvent(
      eventId: 'qcomplete-$instanceId',
      questInstanceId: instanceId,
      questId: questId,
      ownerId: ownerId,
      completedAtUtc: completedAt,
      objectiveEventIds: allSourceEventIds,
      idempotencyKey: 'quest_complete_${instanceId}_$questId',
    );
  }
}
