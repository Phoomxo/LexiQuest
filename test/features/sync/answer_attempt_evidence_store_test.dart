import 'dart:convert';

import 'package:drift/drift.dart' show QueryRow;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore store;
  final now = DateTime.utc(2026, 10, 28);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    await seedAnswerEvidenceOwners(database);
  });
  tearDown(() => database.close());

  Future<void> pull(List<SyncEntity> entities) => store.applyPullPage(
    ownerId: 'owner-a',
    collection: SyncCollection.attempts,
    page: PullPage(
      changes: entities,
      nextCursor: SyncCursor(
        serverUpdatedAtUtc: now,
        documentId: entities.last.entityId,
      ),
      hasMore: false,
    ),
  );

  SyncEntity entity(
    Map<String, Object?> payload, {
    int version = 2,
    String id = 'attempt-a',
  }) => SyncEntity(
    collection: SyncCollection.attempts,
    entityId: id,
    revision: 1,
    isDeleted: false,
    payloadVersion: version,
    clientUpdatedAtUtc: now,
    serverUpdatedAtUtc: now,
    payload: payload,
  );

  Future<List<QueryRow>> rows(String table) =>
      database.customSelect('SELECT * FROM $table').get();

  for (final version in [3, 99]) {
    test(
      'unknown queued attempt version $version is preserved for a newer app',
      () async {
        await insertAnswerEvidence(
          database,
          evidence: ordinaryAnswerEvidence(),
          queue: true,
        );
        await database.customStatement(
          'UPDATE outbox_operations SET payload_version = ?',
          [version],
        );
        final before = [
          for (final row in await rows('outbox_operations')) row.data,
        ];
        await expectLater(
          store.claimPending(
            ownerId: 'owner-a',
            firebaseUid: 'uid-a',
            limit: 10,
            leaseToken: 'lease-a',
            leaseDuration: const Duration(minutes: 5),
            nowUtc: now,
          ),
          throwsA(isA<UnsupportedSyncSchemaFailure>()),
        );
        expect([
          for (final row in await rows('outbox_operations')) row.data,
        ], before);
      },
    );
  }

  test(
    'v1 pull and replay retain the exact legacy evidence without duplicate answers',
    () async {
      final remote = entity(answerPayload(), version: 1);
      await pull([remote]);
      await pull([remote]);
      final attempts = await rows('answer_attempts');
      expect(attempts, hasLength(1));
      expect(
        attempts.single.read<String>('evidence_class'),
        'independentRecall',
      );
      expect(
        jsonDecode(attempts.single.read<String>('evidence_context_json')),
        legacyAnswerEvidence().toJson(),
      );
      expect(await rows('sync_conflicts'), isEmpty);
      expect(
        (await database.select(database.srsStates).get()).single.repetitions,
        1,
      );
    },
  );

  test(
    'push chooses v1 only for exact legacy and v2 for declared ordinary metadata',
    () async {
      await insertAnswerEvidence(
        database,
        id: 'legacy',
        evidence: legacyAnswerEvidence(),
        queue: true,
      );
      final declared = ordinaryAnswerEvidence();
      await insertAnswerEvidence(
        database,
        id: 'declared',
        evidence: declared,
        queue: true,
      );
      final claims = await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'uid-a',
        limit: 10,
        leaseToken: 'lease-a',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );
      final legacy = claims
          .singleWhere((claim) => claim.mutation.entityId == 'legacy')
          .mutation;
      final current = claims
          .singleWhere((claim) => claim.mutation.entityId == 'declared')
          .mutation;
      expect(legacy.payloadVersion, 1);
      expect(legacy.payload.keys, unorderedEquals(answerPayload().keys));
      expect(current.payloadVersion, 2);
      expect(current.payload['evidenceClass'], declared.evidenceClass.name);
      expect(current.payload['evidenceContext'], declared.toJson());
      expect(current.payload['evidenceContext'], isA<Map>());
      final operations = await database.select(database.outboxOperations).get();
      expect(
        operations
            .singleWhere((row) => row.entityId == 'legacy')
            .payloadVersion,
        1,
      );
      expect(
        operations
            .singleWhere((row) => row.entityId == 'declared')
            .payloadVersion,
        2,
      );
    },
  );

  test(
    'noncanonical inferred metadata is never silently reduced to v1',
    () async {
      await insertAnswerEvidence(
        database,
        evidence: EvidenceContext.fromJson({
          ...legacyAnswerEvidence().toJson(),
          'skillId': 'not-frozen',
        }),
        queue: true,
      );
      final claims = await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'uid-a',
        limit: 10,
        leaseToken: 'lease-a',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );
      expect(claims, isEmpty);
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(operation.state, 'permanentFailure');
      expect(operation.failureCode, 'invalidPayload');
    },
  );

  test(
    'a changed context on the same attempt ID is quarantined without overwriting',
    () async {
      final original = ordinaryAnswerEvidence();
      await pull([entity(answerPayload(evidence: original))]);
      await pull([entity(answerPayload(evidence: original))]);
      expect(await rows('sync_conflicts'), isEmpty);
      await pull([
        entity(
          answerPayload(
            evidence: ordinaryAnswerEvidence(skillId: 'different-skill'),
          ),
        ),
      ]);
      final attempts = await rows('answer_attempts');
      expect(attempts, hasLength(1));
      expect(
        jsonDecode(attempts.single.read<String>('evidence_context_json')),
        original.toJson(),
      );
      final conflicts = await database.select(database.syncConflicts).get();
      expect(conflicts, hasLength(1));
      expect(conflicts.single.outcome, 'quarantined');
    },
  );

  test(
    'v1 replay cannot silently discard an existing declared context',
    () async {
      final original = ordinaryAnswerEvidence();
      await pull([entity(answerPayload(evidence: original))]);
      await pull([entity(answerPayload(), version: 1)]);
      final conflicts = await database.select(database.syncConflicts).get();
      expect(conflicts.single.outcome, 'quarantined');
      expect(
        jsonDecode(
          (await rows(
            'answer_attempts',
          )).single.read<String>('evidence_context_json'),
        ),
        original.toJson(),
      );
    },
  );

  test(
    'invalid metadata rolls back the entire pull page and its checkpoint',
    () async {
      final valid = answerPayload(evidence: ordinaryAnswerEvidence());
      final invalid = {...valid, 'evidenceClass': 'independentRecall'};
      await expectLater(
        pull([
          entity(valid, id: 'valid-first'),
          entity(invalid, id: 'invalid-second'),
        ]),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      for (final table in [
        'answer_attempts',
        'learning_sessions',
        'srs_states',
        'outbox_operations',
      ]) {
        expect(await rows(table), isEmpty, reason: table);
      }
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.attempts),
        isNull,
      );
    },
  );

  test(
    'a legacy rollout with a research pin is refused before session creation',
    () async {
      final valid = answerPayload(evidence: ordinaryAnswerEvidence());
      final invalid = {
        ...valid,
        'evidenceContext': {
          ...ordinaryAnswerEvidence().toJson(),
          'protocolId': 'synthetic-unapproved-protocol',
        },
      };
      await expectLater(
        pull([entity(invalid)]),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await rows('learning_sessions'), isEmpty);
      expect(await rows('answer_attempts'), isEmpty);
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.attempts),
        isNull,
      );
    },
  );

  test(
    'cross-owner word references still refuse evidence and leave the cursor unchanged',
    () async {
      final invalid = {
        ...answerPayload(evidence: ordinaryAnswerEvidence()),
        'wordId': 'word-b',
      };
      await expectLater(
        pull([entity(invalid)]),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await rows('answer_attempts'), isEmpty);
      expect(await rows('learning_sessions'), isEmpty);
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.attempts),
        isNull,
      );
    },
  );
}
