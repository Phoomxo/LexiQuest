import 'package:drift/drift.dart';

class LocalOwners extends Table {
  TextColumn get id => text()();
  TextColumn get firebaseUid => text().nullable().unique()();
  TextColumn get accountState =>
      text().withDefault(const Constant('localGuest'))();
  IntColumn get createdAtUtcMs =>
      integer().customConstraint('NOT NULL CHECK (created_at_utc_ms >= 0)')();
  IntColumn get upgradedAtUtcMs => integer().nullable()();
  BoolColumn get isActive => boolean().withDefault(const Constant(true))();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

class ResearchConsents extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get consentVersion => integer()();
  TextColumn get consentState => text()();
  IntColumn get decidedAtUtcMs => integer()();
  IntColumn get withdrawnAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};

  @override
  List<Set<Column<Object>>> get uniqueKeys => [
    {ownerId, consentVersion},
  ];
}
