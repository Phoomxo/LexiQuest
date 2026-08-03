import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  group('Schema v6→v7 migration — D3.2', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async {
      await db.close();
    });

    test('events_v2 table exists after fresh onCreate', () async {
      // Trigger creation (fresh in-memory database)
      await db.customSelect("SELECT 1").get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='events_v2'",
          )
          .get();
      expect(tables, hasLength(1), reason: 'events_v2 table must exist');
    });

    test('can insert and retrieve an EventsV2 row', () async {
      final now = DateTime.now().toUtc();
      // First seed the required FK row in local_owners
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-v7', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db.into(db.eventsV2).insert(
        EventsV2Companion(
          eventId: const Value('evt-v7-001'),
          eventType: const Value('QuizCompleted'),
          eventVersion: const Value(1),
          occurredAtUtc: Value(now),
          recordedAtUtc: Value(now),
          actorIdentity: const Value('owner-v7'),
          ownerId: const Value('owner-v7'),
          aggregateType: const Value('LearningSession'),
          aggregateId: const Value('sess-v7'),
          idempotencyKey: const Value('idem-v7-001'),
          consentContextJson: const Value('{}'),
          appVersion: const Value('1.0.0'),
          buildId: const Value('sha7777'),
          privacyClassification: const Value('ownerOnly'),
          payloadJson: const Value('{"score":100}'),
        ),
      );

      final rows =
          await (db.select(db.eventsV2)
                ..where((r) => r.eventId.equals('evt-v7-001')))
              .get();
      expect(rows, hasLength(1));
      expect(rows.first.eventType, 'QuizCompleted');
      expect(rows.first.payloadJson, '{"score":100}');
    });

    test('idempotency constraint prevents duplicate events', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-idem', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      final companion = EventsV2Companion(
        eventId: const Value('evt-idem-01'),
        eventType: const Value('SrsReviewCompleted'),
        eventVersion: const Value(1),
        occurredAtUtc: Value(now),
        recordedAtUtc: Value(now),
        actorIdentity: const Value('owner-idem'),
        ownerId: const Value('owner-idem'),
        aggregateType: const Value('SrsSession'),
        aggregateId: const Value('srs-01'),
          idempotencyKey: const Value('same-key'),
          consentContextJson: const Value('{}'),
          appVersion: const Value('1.0.0'),
          buildId: const Value('sha7777'),
          privacyClassification: const Value('anonymized'),
          payloadJson: const Value('{}'),
      );

      await db.into(db.eventsV2).insert(companion);

      // Second insert with same (owner_id, idempotencyKey) must fail.
      expect(
        () => db.into(db.eventsV2).insert(
          companion.copyWith(eventId: const Value('evt-idem-02')),
        ),
        throwsA(anything),
        reason:
            'Unique constraint on (owner_id, idempotency_key) must reject replays',
      );
    });

    test('owner-occurred index exists', () async {
      await db.customSelect("SELECT 1").get();
      final indexes = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='index' AND name='idx_events_v2_owner_occurred'",
          )
          .get();
      expect(indexes, hasLength(1), reason: 'owner-occurred index must exist');
    });

    test('nullable fields accept NULL values without error', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-null', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db.into(db.eventsV2).insert(
        EventsV2Companion(
          eventId: const Value('evt-null-01'),
          eventType: const Value('X'),
          eventVersion: const Value(1),
          occurredAtUtc: Value(now),
          recordedAtUtc: Value(now),
          actorIdentity: const Value('owner-null'),
          ownerId: const Value('owner-null'),
          aggregateType: const Value('T'),
          aggregateId: const Value('a'),
          idempotencyKey: const Value('idem-null'),
          consentContextJson: const Value('{}'),
          appVersion: const Value('1.0.0'),
          buildId: const Value('sha7777'),
          privacyClassification: const Value('public'),
          payloadJson: const Value('{}'),
          // Nullable fields deliberately absent (should default to NULL)
        ),
      );

      final row =
          await (db.select(db.eventsV2)
                ..where((r) => r.eventId.equals('evt-null-01')))
              .getSingle();
      expect(row.tenantContextJson, isNull);
      expect(row.correlationId, isNull);
      expect(row.causationId, isNull);
      expect(row.experimentContextJson, isNull);
      expect(row.contentRevision, isNull);
      expect(row.policyVersion, isNull);
      expect(row.providerProvenanceJson, isNull);
    });
  });
}
