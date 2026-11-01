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

import 'dart:convert';

import 'package:timezone/timezone.dart' as timezone;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';

import '../../learning_profile/domain/learning_timezone.dart';

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

final class QuestPeriod {
  const QuestPeriod._({
    required this.key,
    required this.kind,
    required this.civilLabel,
    required this.timezoneId,
    required this.startUtc,
    required this.endUtc,
  });

  factory QuestPeriod.at({
    required QuestType type,
    required DateTime atUtc,
    required String timezoneId,
  }) {
    if (!atUtc.isUtc || atUtc.millisecondsSinceEpoch < 0) {
      throw StateError('Quest period requires a UTC instant');
    }
    final location = timezone.getLocation(requireLearningTimezone(timezoneId));
    if (type == QuestType.milestone || type == QuestType.story) {
      return const QuestPeriod._(
        key: 'quest-period-v1:once',
        kind: 'once',
        civilLabel: 'once',
        timezoneId: 'UTC',
        startUtc: null,
        endUtc: null,
      );
    }
    final local = timezone.TZDateTime.from(atUtc, location);
    final day = DateTime.utc(local.year, local.month, local.day);
    final startDay = type == QuestType.weekly
        ? day.subtract(Duration(days: day.weekday - DateTime.monday))
        : day;
    final endDay = startDay.add(
      Duration(days: type == QuestType.weekly ? 7 : 1),
    );
    final label =
        '${startDay.year.toString().padLeft(4, '0')}-'
        '${startDay.month.toString().padLeft(2, '0')}-'
        '${startDay.day.toString().padLeft(2, '0')}';
    DateTime utcBoundary(DateTime civil) => DateTime.fromMillisecondsSinceEpoch(
      timezone.TZDateTime(
        location,
        civil.year,
        civil.month,
        civil.day,
      ).millisecondsSinceEpoch,
      isUtc: true,
    );
    return QuestPeriod._(
      key: 'quest-period-v1:${type.name}:$label',
      kind: type.name,
      civilLabel: label,
      timezoneId: timezoneId,
      startUtc: utcBoundary(startDay),
      endUtc: utcBoundary(endDay),
    );
  }

  factory QuestPeriod.parse(String source) {
    if (utf8.encode(source).length > 2048) {
      throw StateError('Quest period is too large');
    }
    final value = jsonDecode(source);
    const keys = {
      'schemaVersion',
      'key',
      'kind',
      'civilLabel',
      'timezoneId',
      'startUtcMs',
      'endUtcMs',
      'policyVersion',
    };
    if (value is! Map<String, dynamic> ||
        value.length != keys.length ||
        !value.keys.toSet().containsAll(keys) ||
        value['schemaVersion'] != 1 ||
        value['policyVersion'] != 1 ||
        value['key'] is! String ||
        value['kind'] is! String ||
        value['civilLabel'] is! String ||
        value['timezoneId'] is! String) {
      throw StateError('Quest period contract is unavailable');
    }
    final kind = value['kind'] as String;
    final start = value['startUtcMs'];
    final end = value['endUtcMs'];
    final QuestPeriod result;
    if (kind == 'once' && start == null && end == null) {
      result = QuestPeriod.at(
        type: QuestType.milestone,
        atUtc: DateTime.utc(2026),
        timezoneId: 'UTC',
      );
    } else if ((kind == 'daily' || kind == 'weekly') &&
        start is int &&
        end is int &&
        start >= 0 &&
        end > start) {
      result = QuestPeriod.at(
        type: kind == 'daily' ? QuestType.daily : QuestType.weekly,
        atUtc: DateTime.fromMillisecondsSinceEpoch(start, isUtc: true),
        timezoneId: value['timezoneId'] as String,
      );
    } else {
      throw StateError('Quest period contract is unavailable');
    }
    if (result.json != source) {
      throw StateError('Quest period pin changed');
    }
    return result;
  }

  final String key, kind, civilLabel, timezoneId;
  final DateTime? startUtc, endUtc;
  int get policyVersion => 1;
  bool contains(DateTime atUtc) =>
      (startUtc == null || !atUtc.isBefore(startUtc!)) &&
      (endUtc == null || atUtc.isBefore(endUtc!));
  String get json => jsonEncode({
    'schemaVersion': 1,
    'key': key,
    'kind': kind,
    'civilLabel': civilLabel,
    'timezoneId': timezoneId,
    'startUtcMs': startUtc?.millisecondsSinceEpoch,
    'endUtcMs': endUtc?.millisecondsSinceEpoch,
    'policyVersion': policyVersion,
  });
}

// ─── Objective matching ───────────────────────────────────────────────────────

/// Filter that decides whether a given [EventEnvelopeV2] counts toward an
/// objective.
final class ObjectiveCriteria {
  ObjectiveCriteria({required this.eventType, Map<String, dynamic>? filters})
    : filters = filters == null ? null : Map.unmodifiable(filters);

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

  /// Engagement XP granted from a validated completion receipt.
  final int xpAmount;

  /// Optional cosmetic reward item ID (added to [OwnedRewardItems]).
  final String? rewardItemId;
}

/// Immutable content definition authored by game designers.
///
/// [QuestDefinition]s are shipped with the app (catalog) or downloaded as
/// content updates.  They are never mutated at runtime.
final class QuestDefinition {
  QuestDefinition({
    required this.questId,
    required this.catalogVersion,
    required this.title,
    required this.description,
    required this.type,
    required List<QuestObjective> objectives,
    required this.reward,
    this.expiresIn,
    List<String> tags = const [],
  }) : assert(objectives.isNotEmpty, 'quest must have at least one objective'),
       objectives = List.unmodifiable(objectives),
       tags = List.unmodifiable(tags);

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
  ObjectiveProgress({
    required this.objectiveId,
    required this.currentCount,
    required this.targetCount,
    List<String> sourceEventIds = const [],
  }) : sourceEventIds = List.unmodifiable(sourceEventIds);

  final String objectiveId;
  final int currentCount;
  final int targetCount;

  /// IDs of the [EventEnvelopeV2] events that contributed to [currentCount].
  /// Forms the evidence chain for audit and idempotency.
  final List<String> sourceEventIds;

  bool get isComplete => currentCount >= targetCount;

  /// Counts a canonical source once and never advances a completed objective.
  ObjectiveProgress advance(String eventId) {
    if (isComplete || sourceEventIds.contains(eventId)) return this;
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
  QuestCompletedEvent({
    required this.eventId,
    required this.questInstanceId,
    required this.ownerId,
    required this.completedAtUtc,
    required List<String> objectiveEventIds,
    required this.idempotencyKey,
  }) : objectiveEventIds = List.unmodifiable(objectiveEventIds);

  final String eventId;
  final String questInstanceId;
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
  QuestInstance({
    required this.instanceId,
    required this.questId,
    required this.ownerId,
    required this.catalogVersion,
    required this.assignedAtUtc,
    required this.state,
    required List<ObjectiveProgress> progress,
    this.completedAtUtc,
    this.expiredAtUtc,
    this.period,
    this.definition,
    this.definitionSha256,
  }) : progress = List.unmodifiable(progress);

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
  final QuestPeriod? period;
  final QuestDefinition? definition;
  final String? definitionSha256;

  // ── Derived ──────────────────────────────────────────────────────────────

  bool get isAllObjectivesComplete =>
      progress.isNotEmpty && progress.every((p) => p.isComplete);

  /// Collects all source event IDs across all objectives.
  List<String> get allSourceEventIds =>
      List.unmodifiable(progress.expand((p) => p.sourceEventIds));

  // ── Projection helpers ────────────────────────────────────────────────────

  /// Evaluates [event] against each objective's [ObjectiveCriteria].
  ///
  /// Returns a new [QuestInstance] with updated [progress] if any objective
  /// matched; returns `this` unchanged when no objective matched.
  QuestInstance advanceIfMatches(
    EventEnvelopeV2 event,
    List<QuestObjective> objectives,
  ) {
    if (state != QuestInstanceState.active ||
        event.ownerIdentity != ownerId ||
        event.actorIdentity != ownerId ||
        event.occurredAtUtc.isBefore(assignedAtUtc)) {
      return this;
    }
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
        if (!identical(next, p)) changed = true;
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
      period: period,
      definition: definition,
      definitionSha256: definitionSha256,
    );
  }

  /// Produces a [QuestCompletedEvent] for this instance.
  ///
  /// The [idempotencyKey] is deterministic — calling this twice returns equal
  /// keys, so reward grant is idempotent.
  QuestCompletedEvent complete({DateTime? now}) {
    if (!isAllObjectivesComplete ||
        state == QuestInstanceState.expired ||
        state == QuestInstanceState.abandoned) {
      throw StateError('Quest has no completed active objectives');
    }
    final completedAt = state == QuestInstanceState.completed
        ? completedAtUtc ??
              (throw StateError('Quest completion has no original time'))
        : now ?? DateTime.now().toUtc();
    return QuestCompletedEvent(
      eventId: 'qcomplete-$instanceId',
      questInstanceId: instanceId,
      ownerId: ownerId,
      completedAtUtc: completedAt,
      objectiveEventIds: allSourceEventIds,
      idempotencyKey: 'quest_complete_${instanceId}_$questId',
    );
  }
}

final class QuestCompletionReceipt {
  const QuestCompletionReceipt({
    required this.instance,
    required this.definition,
    required this.completion,
  });
  final QuestInstance instance;
  final QuestDefinition definition;
  final QuestCompletedEvent completion;
}
