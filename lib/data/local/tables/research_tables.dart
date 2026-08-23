import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('ExperimentAssignmentRow')
class ExperimentAssignments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get experimentId => text()();
  IntColumn get experimentVersion => integer()();
  TextColumn get cohort => text()();
  TextColumn get protocolVersion => text()();
  IntColumn get assignedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, experimentId, experimentVersion},
  ];
}
