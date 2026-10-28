import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('LearningGoalRow')
class LearningGoals extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get kind => text()();
  TextColumn get title => text()();
  IntColumn get deadlineAtUtcMs => integer()();
  TextColumn get timezoneId => text()();
  IntColumn get timezoneOffsetMinutes => integer().customConstraint(
    'NOT NULL CHECK (timezone_offset_minutes >= -840 AND '
    'timezone_offset_minutes <= 840)',
  )();
  TextColumn get status => text()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

/// Reserved by schema v19 for f27. f26 deliberately has no reminder writer.
@DataClassName('StudyReminderRow')
class StudyReminders extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get goalId => text().nullable().references(
    LearningGoals,
    #id,
    onDelete: KeyAction.cascade,
  )();
  TextColumn get sourceKind => text()();
  IntColumn get scheduledAtUtcMs => integer()();
  TextColumn get timezoneId => text()();
  IntColumn get timezoneOffsetMinutes => integer().customConstraint(
    'NOT NULL CHECK (timezone_offset_minutes >= -840 AND '
    'timezone_offset_minutes <= 840)',
  )();
  IntColumn get quietHoursStartMinutes => integer().nullable()();
  IntColumn get quietHoursEndMinutes => integer().nullable()();
  BoolColumn get isEnabled => boolean().withDefault(const Constant(false))();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get updatedAtUtcMs => integer()();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
