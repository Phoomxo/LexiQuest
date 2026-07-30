import 'package:drift/drift.dart';

import 'identity_tables.dart';

class PointsLedgerEntries extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get idempotencyKey => text()();
  TextColumn get entryType => text()();
  IntColumn get amount => integer()();
  TextColumn get sourceEventId => text().nullable()();
  IntColumn get occurredAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, idempotencyKey},
  ];
}

class AchievementUnlocks extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get achievementId => text()();
  IntColumn get definitionVersion => integer()();
  TextColumn get sourceEventId => text()();
  IntColumn get unlockedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, achievementId, definitionVersion},
  ];
}
