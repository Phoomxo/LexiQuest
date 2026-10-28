import 'package:drift/drift.dart';
import 'identity_tables.dart';

@DataClassName('StudyPlanRevisionRow')
class StudyPlanRevisions extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get operationId => text()();
  IntColumn get revision =>
      integer().customConstraint('NOT NULL CHECK (revision > 0)')();
  TextColumn get payloadHash => text()();
  TextColumn get payloadJson => text()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId, operationId};
}

class ActivePlanPointers extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get operationId => text()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId};
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (owner_id, operation_id) REFERENCES study_plan_revisions '
        '(owner_id, operation_id) ON UPDATE CASCADE ON DELETE CASCADE',
  ];
}
