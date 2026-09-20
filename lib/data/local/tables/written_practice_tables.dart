import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Immutable supplemental rubric revisions. Owner remapping is allowed;
/// response and scoring payloads are never canonical learning events.
class WrittenPracticeResults extends Table {
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
