import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Shared v8 catalog identity and historical content.
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

/// A pinned catalog body used to verify an issued occurrence.
class QuestDefinitionRevisions extends Table {
  TextColumn get questId => text()();
  IntColumn get catalogVersion => integer()();
  TextColumn get definitionDigest => text()();
  TextColumn get canonicalDefinition => text()();

  @override
  Set<Column> get primaryKey => {questId, catalogVersion};

  @override
  List<Set<Column>> get uniqueKeys => [
    {questId, catalogVersion, definitionDigest},
  ];
}

/// One historical record or pinned occurrence of a recurring Quest.
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
  TextColumn get originOwnerId => text().nullable()();
  TextColumn get periodKey => text().nullable()();
  TextColumn get calendarRuleId => text().nullable()();
  TextColumn get civilLabel => text().nullable()();
  TextColumn get segmentsJson => text().nullable()();
  TextColumn get definitionDigest => text().nullable()();
  TextColumn get canonicalInstanceId =>
      text().nullable().references(QuestInstances, #instanceId)();
  TextColumn get recordKind => text().withDefault(const Constant('legacy'))();

  @override
  Set<Column> get primaryKey => {instanceId};

  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (quest_id, catalog_version, definition_digest) '
        'REFERENCES quest_definition_revisions '
        '(quest_id, catalog_version, definition_digest)',
    "CHECK ((record_kind = 'legacy' AND origin_owner_id IS NULL "
        'AND period_key IS NULL AND calendar_rule_id IS NULL '
        'AND civil_label IS NULL AND segments_json IS NULL '
        'AND definition_digest IS NULL AND canonical_instance_id IS NULL) '
        "OR (record_kind IN ('canonical', 'alias', 'conflict') "
        "AND COALESCE(origin_owner_id, '') <> '' AND COALESCE(period_key, '') <> '' "
        "AND COALESCE(calendar_rule_id, '') <> '' AND COALESCE(civil_label, '') <> '' "
        "AND COALESCE(segments_json, '') <> '' AND COALESCE(definition_digest, '') <> '' "
        "AND ((record_kind = 'alias' AND canonical_instance_id IS NOT NULL "
        'AND canonical_instance_id <> instance_id) '
        "OR (record_kind <> 'alias' AND canonical_instance_id IS NULL))))",
  ];
}

/// Immutable evidence of one explicit local XP claim.
class QuestClaimReceipts extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get originOwnerId => text()();
  TextColumn get instanceId => text().references(QuestInstances, #instanceId)();
  IntColumn get issuedAtUtcMs => integer()();
  IntColumn get completedAtUtcMs => integer()();
  IntColumn get xpAmount => integer()();
  TextColumn get evidenceJson => text()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {instanceId},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (xp_amount > 0 AND length(evidence_json) > 0)',
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
