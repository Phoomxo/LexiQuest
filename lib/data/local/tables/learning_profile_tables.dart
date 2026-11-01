import 'package:drift/drift.dart';

import 'identity_tables.dart';

class LearningProfiles extends Table {
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  IntColumn get revision => integer()();
  TextColumn get onboardingState => text()();
  TextColumn get goalText => text().nullable()();
  TextColumn get targetDate => text().nullable()();
  IntColumn get dailyMinutes => integer().nullable()();
  TextColumn get interestCodesJson => text()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(revision) = 'integer' AND revision BETWEEN 1 AND 9007199254740991)",
    "CHECK (onboarding_state IN ('completed','skipped'))",
    'CHECK (goal_text IS NULL OR length(trim(goal_text)) BETWEEN 1 AND 120)',
    "CHECK (target_date IS NULL OR (length(target_date) = 10 AND target_date GLOB '[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]' AND date(target_date, '+0 days') IS NOT NULL AND date(target_date, '+0 days') = target_date))",
    "CHECK (daily_minutes IS NULL OR (typeof(daily_minutes) = 'integer' AND daily_minutes BETWEEN 1 AND 180))",
    'CHECK (length(CAST(interest_codes_json AS BLOB)) BETWEEN 1 AND 1024)',
    "CHECK (typeof(updated_at_utc_ms) = 'integer' AND updated_at_utc_ms BETWEEN 0 AND 8640000000000000)",
  ];
}
