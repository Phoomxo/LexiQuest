import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'learning_tables.dart';

class LearningTimePreferences extends Table {
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  BoolColumn get enabled => boolean()();
  IntColumn get revision => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(revision) = 'integer' AND revision BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(updated_at_utc_ms) = 'integer' AND updated_at_utc_ms BETWEEN 0 AND 8640000000000000)",
  ];
}

class LearningTimeScopes extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  TextColumn get sourceKind => text()();
  TextColumn get sourceBindingJson => text()();
  IntColumn get createdAtUtcMs => integer()();
  TextColumn get linkedSessionId => text()
      .nullable()
      .references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  TextColumn get sessionLinkBindingJson => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    "CHECK (substr(id, 1, 11) = 'time-scope:' AND length(CAST(id AS BLOB)) BETWEEN 12 AND 256 AND length(trim(substr(id, 12))) > 0)",
    "CHECK (source_kind IN ('configuredQuiz','ownedSrs','dictation','cloze','voicePractice','reading','tutor'))",
    'CHECK (length(CAST(source_binding_json AS BLOB)) BETWEEN 1 AND 16384)',
    "CHECK (typeof(created_at_utc_ms) = 'integer' AND created_at_utc_ms BETWEEN 0 AND 8640000000000000)",
    'CHECK ((linked_session_id IS NULL AND session_link_binding_json IS NULL) OR (linked_session_id IS NOT NULL AND session_link_binding_json IS NOT NULL))',
    'CHECK (session_link_binding_json IS NULL OR length(CAST(session_link_binding_json AS BLOB)) BETWEEN 1 AND 16384)',
  ];
}

class LearningTimeSegments extends Table {
  TextColumn get id => text()();
  TextColumn get scopeId =>
      text().references(LearningTimeScopes, #id, onDelete: KeyAction.cascade)();
  IntColumn get ordinal => integer()();
  TextColumn get eligibilityContextJson => text()();
  IntColumn get startedAtUtcMs => integer()();
  IntColumn get endedAtUtcMs => integer()();
  IntColumn get activeDurationUs => integer()();
  TextColumn get capturePolicyRevision => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {scopeId, ordinal},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK (substr(id, 1, 13) = 'time-segment:' AND length(CAST(id AS BLOB)) BETWEEN 14 AND 256 AND length(trim(substr(id, 14))) > 0)",
    "CHECK (typeof(ordinal) = 'integer' AND ordinal BETWEEN 0 AND 9007199254740991)",
    'CHECK (length(CAST(eligibility_context_json AS BLOB)) BETWEEN 1 AND 16384)',
    "CHECK (typeof(started_at_utc_ms) = 'integer' AND started_at_utc_ms BETWEEN 0 AND 8640000000000000)",
    "CHECK (typeof(ended_at_utc_ms) = 'integer' AND ended_at_utc_ms BETWEEN 0 AND 8640000000000000)",
    "CHECK (typeof(active_duration_us) = 'integer' AND active_duration_us BETWEEN 1 AND 120000000)",
    "CHECK (capture_policy_revision = 'confirmed-interaction-v1')",
  ];
}
