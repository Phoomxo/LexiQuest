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

class RewardTransactions extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get idempotencyKey => text()();
  TextColumn get transactionType => text()();
  IntColumn get amount => integer()();
  TextColumn get itemId => text().nullable()();
  IntColumn get catalogVersion => integer()();
  TextColumn get sourceEventId => text().nullable()();
  IntColumn get occurredAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, idempotencyKey},
  ];
}

class OwnedRewardItems extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get itemId => text()();
  IntColumn get catalogVersion => integer()();
  TextColumn get acquiredByTransactionId =>
      text().references(RewardTransactions, #id)();
  IntColumn get acquiredAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, itemId},
  ];
}

class EquippedRewardItems extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get slot => text()();
  TextColumn get itemId => text()();
  IntColumn get equippedAtUtcMs => integer()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, slot},
  ];
}
