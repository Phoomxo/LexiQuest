import 'package:drift/drift.dart';

import 'identity_tables.dart';

/// Persistent storage for [EventEnvelopeV2] events.
///
/// Schema v7 — added in Phase -1 Week 5-6.
///
/// The uniqueness constraint on `(owner_identity, idempotency_key)` enforces
/// the idempotency guarantee: inserting the same event twice raises a
/// [SqliteException] rather than creating a duplicate row.
class EventsV2 extends Table {
  // Field 1 — UUID v7 primary key
  TextColumn get eventId => text()();
  // Field 2
  TextColumn get eventType => text()();
  // Field 3
  IntColumn get eventVersion => integer()();
  // Field 4
  DateTimeColumn get occurredAtUtc => dateTime()();
  // Field 5
  DateTimeColumn get recordedAtUtc => dateTime()();
  // Field 6
  TextColumn get actorIdentity => text()();
  // Field 7 — FK to local_owners (column name owner_id matches project convention)
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  // Field 8 — serialised TenantContext JSON (nullable)
  TextColumn get tenantContextJson => text().nullable()();
  // Field 9
  TextColumn get aggregateType => text()();
  // Field 10
  TextColumn get aggregateId => text()();
  // Field 11
  TextColumn get correlationId => text().nullable()();
  // Field 12
  TextColumn get causationId => text().nullable()();
  // Field 13 — part of unique replay-protection key
  TextColumn get idempotencyKey => text()();
  // Field 14 — serialised ConsentContext JSON
  TextColumn get consentContextJson => text()();
  // Field 15 — serialised ExperimentContext JSON (nullable)
  TextColumn get experimentContextJson => text().nullable()();
  // Field 16
  TextColumn get contentRevision => text().nullable()();
  // Field 17
  TextColumn get policyVersion => text().nullable()();
  // Field 18
  TextColumn get appVersion => text()();
  // Field 19
  TextColumn get buildId => text()();
  // Field 20 — serialised ProviderProvenance JSON (nullable)
  TextColumn get providerProvenanceJson => text().nullable()();
  // Field 21 — string form of PrivacyClassification enum value
  TextColumn get privacyClassification => text()();
  // Field 22 — actual domain event data as JSON
  TextColumn get payloadJson => text()();

  @override
  Set<Column> get primaryKey => {eventId};

  @override
  List<Set<Column>> get uniqueKeys => [
    // Prevent replay: same owner may not insert the same idempotency key twice.
    {ownerId, idempotencyKey},
  ];
}
