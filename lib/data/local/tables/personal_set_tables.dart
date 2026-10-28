import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Immutable local organization. No SRS, reward or sync projection is written.
@DataClassName('PersonalSetRevisionRow')
class PersonalSetRevisions extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get setId => text()();
  IntColumn get revision =>
      integer().customConstraint('NOT NULL CHECK (revision > 0)')();
  TextColumn get operationId => text()();
  TextColumn get payloadHash => text()();
  TextColumn get payloadJson => text()();
  BoolColumn get archived => boolean()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId, setId, revision};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, operationId},
  ];
}

@DataClassName('PersonalSetMemberRow')
class PersonalSetMembers extends Table {
  TextColumn get ownerId => text()();
  TextColumn get setId => text()();
  IntColumn get revision => integer()();
  IntColumn get position =>
      integer().customConstraint('NOT NULL CHECK (position >= 0)')();
  TextColumn get senseRefHash => text()();
  TextColumn get senseRefJson => text()();
  @override
  Set<Column<Object>> get primaryKey => {ownerId, setId, revision, position};
  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, setId, revision, senseRefHash},
  ];
  @override
  List<String> get customConstraints => [
    'FOREIGN KEY (owner_id, set_id, revision) REFERENCES personal_set_revisions '
        '(owner_id, set_id, revision) ON UPDATE CASCADE ON DELETE CASCADE',
  ];
}
