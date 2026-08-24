import 'package:drift/drift.dart';

import 'identity_tables.dart';
import 'learning_tables.dart';

@DataClassName('LearningTimeSegmentRow')
class LearningTimeSegments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get sessionId =>
      text().references(LearningSessions, #id, onDelete: KeyAction.cascade)();
  IntColumn get activeStartOffsetMs => integer().customConstraint(
    'NOT NULL CHECK (active_start_offset_ms >= 0)',
  )();
  IntColumn get activeDurationMs =>
      integer().customConstraint('NOT NULL CHECK (active_duration_ms > 0)')();
  IntColumn get startedAtUtcMs =>
      integer().customConstraint('NOT NULL CHECK (started_at_utc_ms >= 0)')();
  IntColumn get endedAtUtcMs =>
      integer().customConstraint('NOT NULL CHECK (ended_at_utc_ms >= 0)')();
  TextColumn get timezoneId => text()();
  IntColumn get timezoneOffsetMinutes => integer().customConstraint(
    'NOT NULL CHECK ('
    'timezone_offset_minutes >= -840 AND '
    'timezone_offset_minutes <= 840)',
  )();
  TextColumn get captureSource => text()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {sessionId, activeStartOffsetMs},
  ];
}
