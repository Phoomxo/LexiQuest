import 'package:drift/drift.dart';

import 'identity_tables.dart';

@DataClassName('AiUsageEventRow')
class AiUsageEvents extends Table {
  TextColumn get eventId => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get occurredAtUtcMs => integer()();
  TextColumn get providerId => text()();
  TextColumn get model => text()();
  TextColumn get requestType => text()();
  TextColumn get outcome => text()();
  TextColumn get errorCategory => text().nullable()();
  IntColumn get latencyMs => integer()();
  IntColumn get inputTokens => integer().nullable()();
  IntColumn get outputTokens => integer().nullable()();
  IntColumn get totalTokens => integer().nullable()();
  IntColumn get cachedTokens => integer().nullable()();
  IntColumn get providerReportedCostMicrosUsd => integer().nullable()();
  IntColumn get schemaVersion => integer().withDefault(const Constant(1))();

  @override
  Set<Column<Object>> get primaryKey => {ownerId, eventId};
}
