import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  final now = DateTime.utc(2026, 10, 28);

  test(
    'v2 attempt codec round-trip preserves the map and operation schema',
    () {
      final evidence = ordinaryAnswerEvidence();
      final mutation = PushMutation(
        operationId: 'operation-a',
        firebaseUid: 'uid-a',
        collection: SyncCollection.attempts,
        entityId: 'attempt-a',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 2,
        baseRevision: 0,
        localRevision: 1,
        clientUpdatedAtUtc: now,
        payload: answerPayload(evidence: evidence),
      );
      final entity = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(now),
      );
      final operation = FirestoreSyncCodec.encodeOperation(
        mutation,
        acknowledgedAt: Timestamp.fromDate(now),
      );
      final restored = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.attempts,
        documentId: 'attempt-a',
        data: entity,
      );
      expect(restored.payloadVersion, 2);
      expect(restored.payload['evidenceContext'], evidence.toJson());
      expect(operation['schemaVersion'], 2);
      expect(
        FirestoreSyncCodec.decodeAcknowledgement(
          operation,
          expectedOperationId: 'operation-a',
          expectedPayloadVersion: 2,
        ).resultingRevision,
        1,
      );
      expect(
        () => FirestoreSyncCodec.decodeAcknowledgement(
          operation,
          expectedOperationId: 'operation-a',
          expectedPayloadVersion: 1,
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.decodeAcknowledgement(
          {...operation, 'schemaVersion': 1},
          expectedOperationId: 'operation-a',
          expectedPayloadVersion: 2,
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    },
  );

  test('a v2 attempt envelope cannot be decoded as an ordinary word', () {
    expect(
      () => FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.words,
        documentId: 'word-a',
        data: {
          'schemaVersion': 2,
          'entityId': 'word-a',
          'revision': 1,
          'isDeleted': false,
          'clientUpdatedAtUtcMs': 2000,
          'serverUpdatedAt': Timestamp.fromDate(now),
          'lastOperationId': 'operation-a',
          'payload': answerPayload(evidence: ordinaryAnswerEvidence()),
        },
      ),
      throwsA(isA<UnsupportedSyncSchemaFailure>()),
    );
  });
}
