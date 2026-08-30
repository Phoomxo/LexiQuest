import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('LearnerPreferenceRow')
class LearnerPreferences extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get preferenceVersion => integer()();
  TextColumn get goal => text()();
  IntColumn get availableMinutesPerDay => integer().customConstraint(
    'NOT NULL CHECK (available_minutes_per_day >= 1 AND '
    'available_minutes_per_day <= 240)',
  )();
  TextColumn get activityPreference => text()();
  IntColumn get updatedAtUtcMs => integer()();
  TextColumn get themeMode => text().withDefault(const Constant('system'))();
  TextColumn get motionMode => text().withDefault(const Constant('system'))();
  IntColumn get displayUpdatedAtUtcMs =>
      integer().withDefault(const Constant(0))();
  IntColumn get localRevision => integer().withDefault(const Constant(1))();
  IntColumn get cloudRevision => integer().withDefault(const Constant(0))();
  IntColumn get lastAcknowledgedAtUtcMs => integer().nullable()();
  IntColumn get serverUpdatedAtUtcMs => integer().nullable()();
  BoolColumn get isDeleted => boolean().withDefault(const Constant(false))();

  @override
  Set<Column<Object>> get primaryKey => {ownerId};
}
