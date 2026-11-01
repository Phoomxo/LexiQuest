import 'package:drift/drift.dart';

import 'identity_tables.dart';

class StudyReminderPreferences extends Table {
  TextColumn get ownerId =>
      text().references(LocalOwners, #id, onDelete: KeyAction.restrict)();
  BoolColumn get enabled => boolean().withDefault(const Constant(false))();
  IntColumn get minuteOfDay => integer()();
  TextColumn get timezoneId => text().withLength(min: 1, max: 100)();
  IntColumn get revision => integer()();
  IntColumn get updatedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {ownerId};

  @override
  List<String> get customConstraints => [
    "CHECK (typeof(minute_of_day) = 'integer' AND minute_of_day BETWEEN 0 AND 1439)",
    "CHECK (typeof(revision) = 'integer' AND revision BETWEEN 1 AND 9007199254740991)",
    "CHECK (typeof(updated_at_utc_ms) = 'integer' AND updated_at_utc_ms BETWEEN 0 AND 8640000000000000)",
  ];
}
