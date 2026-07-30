import 'package:drift/drift.dart';

import 'identity_tables.dart';

class OutboxOperations extends Table {
  TextColumn get operationId => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  TextColumn get operationKind => text()();
  IntColumn get payloadVersion => integer().withDefault(const Constant(1))();
  IntColumn get baseRevision => integer().withDefault(const Constant(0))();
  TextColumn get state => text().withDefault(const Constant('pending'))();
  IntColumn get attemptCount => integer().withDefault(const Constant(0))();
  IntColumn get nextAttemptAtUtcMs => integer().nullable()();
  IntColumn get createdAtUtcMs => integer()();
  IntColumn get acknowledgedAtUtcMs => integer().nullable()();
  TextColumn get failureCode => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {operationId};
}

class SyncCheckpoints extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get collectionName => text()();
  TextColumn get serverCursor => text().nullable()();
  IntColumn get lastSuccessAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, collectionName},
  ];
}

class SyncConflicts extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get entityType => text()();
  TextColumn get entityId => text()();
  IntColumn get localRevision => integer()();
  IntColumn get cloudRevision => integer()();
  TextColumn get resolutionPolicy => text()();
  TextColumn get outcome => text()();
  IntColumn get resolvedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}
