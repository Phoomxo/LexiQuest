import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Persistent storage for the V2 Quest domain contracts.
///
/// Schema v8 — added in Phase 0 Week 10-11.
///
/// Three tables mirror the frozen domain types from
/// [quest_models.dart]:
///   - [QuestDefinitions]      — catalog authored content (no owner FK)
///   - [QuestInstances]        — per-learner active/completed instances
///   - [QuestObjectiveProgress] — per-objective counters keyed by instance
///
/// All migrations are additive.  Downgrading from v8 to v7 is safe because
/// only new tables are added.

// ─── QuestDefinitions ────────────────────────────────────────────────────────

/// Authored quest catalog entry.
///
/// Catalog rows are not owner-scoped — they are shared data shipped with the
/// app or downloaded as content updates.  They are never mutated at runtime
/// and are therefore excluded from [ownerUpgradeInventory].
class QuestDefinitions extends Table {
  /// Primary key: matches [QuestDefinition.questId].
  TextColumn get questId => text()();

  /// Monotonically increasing version for this definition's content.
  IntColumn get catalogVersion => integer()();

  TextColumn get title => text()();
  TextColumn get description => text()();

  /// Wire value of [QuestType] enum: 'daily' | 'weekly' | 'milestone' | 'story'.
  TextColumn get type => text()();

  /// JSON-encoded [List<QuestObjective>].
  TextColumn get objectivesJson => text()();

  /// JSON-encoded [RewardSpec].
  TextColumn get rewardJson => text()();

  /// Duration in milliseconds; null means no expiry.
  IntColumn get expiresInMs => integer().nullable()();

  /// JSON-encoded [List<String>] tags.
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {questId};
}

// ─── QuestInstances ───────────────────────────────────────────────────────────

/// A learner's live progress record for one [QuestDefinition].
///
/// Owner-scoped; included in [ownerUpgradeInventory] so guest→user upgrade
/// carries quest progress forward.
///
/// The unique constraint on `(owner_id, quest_id)` prevents duplicate active
/// instances for the same quest.  When a quest is completed/expired it remains
/// in the table with a terminal state so history is preserved.
class QuestInstances extends Table {
  /// Primary key: matches [QuestInstance.instanceId].
  TextColumn get instanceId => text()();

  TextColumn get questId => text().references(QuestDefinitions, #questId)();

  TextColumn get ownerId => text().references(LocalOwners, #id)();

  IntColumn get catalogVersion => integer()();

  IntColumn get assignedAtUtcMs => integer()();

  /// Wire value of [QuestInstanceState]: 'active' | 'completed' | 'expired' | 'abandoned'.
  TextColumn get state => text()();

  IntColumn get completedAtUtcMs => integer().nullable()();
  IntColumn get expiredAtUtcMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {instanceId};

  /// One active instance per quest per owner.
  @override
  List<Set<Column>> get uniqueKeys => [
    {ownerId, questId},
  ];
}

// ─── QuestObjectiveProgress ───────────────────────────────────────────────────

/// Per-objective progress counters for one [QuestInstance].
///
/// Cascades on instance deletion so orphaned rows are never left behind.
class QuestObjectiveProgress extends Table {
  TextColumn get id => text()();

  TextColumn get instanceId => text().references(
    QuestInstances,
    #instanceId,
    onDelete: KeyAction.cascade,
  )();

  TextColumn get objectiveId => text()();

  IntColumn get currentCount => integer().withDefault(const Constant(0))();
  IntColumn get targetCount => integer()();

  /// JSON-encoded [List<String>] of source [EventEnvelopeV2] event IDs.
  /// Forms the evidence chain for audit and idempotency.
  TextColumn get sourceEventIdsJson =>
      text().withDefault(const Constant('[]'))();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {instanceId, objectiveId},
  ];
}
