import 'package:drift/drift.dart';
import 'identity_tables.dart';
import 'learning_tables.dart';

class GuidedRepairOperations extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get operationId => text()();
  TextColumn get originId =>
      text().references(AnswerAttempts, #id, onDelete: KeyAction.cascade)();
  IntColumn get revision =>
      integer().customConstraint('NOT NULL CHECK (revision BETWEEN 1 AND 6)')();
  TextColumn get payloadJson => text()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId, operationId};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, originId, revision},
  ];
}
