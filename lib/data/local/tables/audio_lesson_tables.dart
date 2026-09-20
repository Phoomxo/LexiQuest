import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Immutable exposure checkpoints; deliberately separate from learning events.
class AudioLessonCheckpoints extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get activityId => text()();
  IntColumn get revision =>
      integer().customConstraint('NOT NULL CHECK (revision > 0)')();
  TextColumn get operationId => text()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId, activityId, revision};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, operationId},
  ];
}
