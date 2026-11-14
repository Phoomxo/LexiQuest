import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'motivation_tables.dart';

class LocalContentReports extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get sourceKind => text()();
  TextColumn get sourceId => text()();
  IntColumn get sourceRevision => integer()();
  TextColumn get spelling => text()();
  TextColumn get meaning => text()();
  TextColumn get sentence => text().nullable()();
  TextColumn get reason => text()();
  IntColumn get createdAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => ['CHECK (source_revision > 0)'];
}

class FocusSessions extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get originOwnerId => text()();
  IntColumn get targetMs => integer()();
  IntColumn get startedAtUtcMs => integer()();
  TextColumn get startRuleId =>
      text().nullable().references(OwnerCalendarEpochs, #ruleId)();
  TextColumn get startCivilWeek => text().nullable()();
  TextColumn get state => text()();
  IntColumn get revision => integer().withDefault(const Constant(1))();
  TextColumn get spansJson => text()();
  IntColumn get endedAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<String> get customConstraints => [
    'CHECK (target_ms > 0)',
    'CHECK (revision >= 1)',
    'CHECK (length(spans_json) > 0)',
    'CHECK ((start_rule_id IS NULL AND start_civil_week IS NULL) OR '
        '(start_rule_id IS NOT NULL AND start_civil_week IS NOT NULL))',
    "CHECK (state IN ('running', 'paused', 'completed', 'interrupted'))",
    "CHECK ((state IN ('running', 'paused') AND ended_at_utc_ms IS NULL) OR "
        "(state = 'completed' AND ended_at_utc_ms IS NOT NULL) OR "
        "state = 'interrupted')",
  ];
}

class LearningPreferences extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get onboardingState =>
      text().withDefault(const Constant('unset'))();
  TextColumn get purpose => text().nullable()();
  IntColumn get plannedMinutes => integer().nullable()();
  TextColumn get learningMethod => text().nullable()();
  TextColumn get goalCivilDate => text().nullable()();
  TextColumn get goalState => text().withDefault(const Constant('unset'))();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId};

  @override
  List<String> get customConstraints => [
    'CHECK (planned_minutes IS NULL OR planned_minutes > 0)',
    "CHECK (onboarding_state IN ('unset', 'skipped', 'completed'))",
    "CHECK (goal_state IN ('unset', 'active', 'closed'))",
    "CHECK (goal_state <> 'active' OR goal_civil_date IS NOT NULL)",
  ];
}
