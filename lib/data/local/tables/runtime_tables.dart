import 'package:drift/drift.dart';

class RuntimeFlags extends Table {
  TextColumn get key => text()();
  BoolColumn get boolValue => boolean()();
  TextColumn get source => text().withDefault(const Constant('local'))();
  IntColumn get updatedAtUtcMs => integer()();
  IntColumn get expiresAtUtcMs => integer().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {key};
}
