import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

void main() {
  group('FirestoreSyncCodec', () {
    final clientUpdatedAt = DateTime.utc(2026, 7, 30, 8, 15);
    final serverUpdatedAt = DateTime.utc(2026, 7, 30, 8, 16);

    test('encodes a mutation with immutable operation linkage', () {
      final mutation = PushMutation(
        operationId: 'operation-1',
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.categories,
        entityId: 'category-1',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 2,
        localRevision: 4,
        clientUpdatedAtUtc: clientUpdatedAt,
        payload: const <String, Object?>{
          'name': 'Travel',
          'normalizedName': 'travel',
          'sortOrder': 3,
          'isDeleted': false,
          'createdAtUtcMs': 1000,
          'updatedAtUtcMs': 2000,
        },
      );

      final encoded = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
      );

      expect(encoded['schemaVersion'], 1);
      expect(encoded['entityId'], 'category-1');
      expect(encoded['revision'], 4);
      expect(encoded['lastOperationId'], 'operation-1');
      expect(encoded['payload'], mutation.payload);
      expect(encoded['serverUpdatedAt'], Timestamp.fromDate(serverUpdatedAt));
    });

    test('decodes a word without losing nullable payload fields', () {
      final entity = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.words,
        documentId: 'word-1',
        data: <String, Object?>{
          'schemaVersion': 1,
          'entityId': 'word-1',
          'revision': 7,
          'isDeleted': false,
          'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
          'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
          'lastOperationId': 'operation-7',
          'payload': <String, Object?>{
            'categoryId': 'category-1',
            'spelling': 'station',
            'normalizedSpelling': 'station',
            'meaning': 'สถานี',
            'normalizedMeaning': 'สถานี',
            'partOfSpeech': 'noun',
            'cefrLevel': null,
            'source': 'manual',
            'isGlobal': false,
            'isDeleted': false,
            'createdAtUtcMs': 1000,
            'updatedAtUtcMs': 2000,
          },
        },
      );

      expect(entity.entityId, 'word-1');
      expect(entity.revision, 7);
      expect(entity.payload['cefrLevel'], isNull);
      expect(entity.serverUpdatedAtUtc, serverUpdatedAt);
    });

    test('rejects unknown schemas and mismatched document IDs', () {
      final base = <String, Object?>{
        'schemaVersion': 2,
        'entityId': 'category-1',
        'revision': 1,
        'isDeleted': false,
        'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
        'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
        'lastOperationId': 'operation-1',
        'payload': <String, Object?>{'name': 'Travel'},
      };

      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'category-1',
          data: base,
        ),
        throwsA(isA<UnsupportedSyncSchemaFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'different-id',
          data: <String, Object?>{...base, 'schemaVersion': 1},
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('accepts attempt entity payload versions 1 and 2', () {
      for (final version in const <int>[1, 2]) {
        final entity = FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.attempts,
          documentId: 'attempt-$version',
          data: <String, Object?>{
            'schemaVersion': version,
            'entityId': 'attempt-$version',
            'revision': 1,
            'isDeleted': false,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
            'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
            'lastOperationId': 'operation-$version',
            'payload': version == 1
                ? _attemptPayloadV1()
                : _attemptPayloadV2(_declaredEvidenceContext()),
          },
        );

        expect(entity.payloadVersion, version);
      }
    });

    test('rejects legacy-inferred attempt v2 during inbound decode', () {
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.attempts,
          documentId: 'attempt-legacy-v2',
          data: <String, Object?>{
            'schemaVersion': 2,
            'entityId': 'attempt-legacy-v2',
            'revision': 1,
            'isDeleted': false,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
            'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
            'lastOperationId': 'operation-legacy-v2',
            'payload': _attemptPayloadV2(
              LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
            ),
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('rejects legacy-inferred attempt v2 before encoding a write', () {
      final legacyMutation = PushMutation(
        operationId: 'operation-legacy-v2',
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.attempts,
        entityId: 'attempt-legacy-v2',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 2,
        baseRevision: 0,
        localRevision: 1,
        clientUpdatedAtUtc: clientUpdatedAt,
        payload: _attemptPayloadV2(
          LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
        ),
      );

      expect(
        () => FirestoreSyncCodec.encodeEntity(
          legacyMutation,
          serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('rejects payload v2 for every legacy-v1-only collection', () {
      for (final collection in SyncCollection.values.where(
        (value) => value != SyncCollection.attempts,
      )) {
        expect(
          () => FirestoreSyncCodec.decodeEntity(
            collection: collection,
            documentId: '${collection.entityType}-1',
            data: <String, Object?>{
              'schemaVersion': 2,
              'entityId': '${collection.entityType}-1',
              'revision': 1,
              'isDeleted': false,
              'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
              'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
              'lastOperationId': 'operation-1',
              'payload': const <String, Object?>{'value': 1},
            },
          ),
          throwsA(isA<UnsupportedSyncSchemaFailure>()),
          reason: collection.name,
        );
      }
    });

    test('acknowledgement accepts exact attempt v1 and v2 mutations', () {
      for (final payloadVersion in const <int>[1, 2]) {
        final mutation = _attemptMutation(
          payloadVersion: payloadVersion,
          clientUpdatedAt: clientUpdatedAt,
        );
        final acknowledgement = FirestoreSyncCodec.encodeOperation(
          mutation,
          acknowledgedAt: Timestamp.fromDate(serverUpdatedAt),
        );

        final decoded = FirestoreSyncCodec.decodeAcknowledgement(
          acknowledgement,
          expectedMutation: mutation,
        );

        expect(decoded.operationId, mutation.operationId);
        expect(decoded.resultingRevision, mutation.localRevision);
        expect(decoded.acknowledgedAtUtc, serverUpdatedAt);
      }
    });

    test('acknowledgement rejects every mismatched mutation field', () {
      final mutation = _attemptMutation(
        payloadVersion: 2,
        clientUpdatedAt: clientUpdatedAt,
      );
      final exact = FirestoreSyncCodec.encodeOperation(
        mutation,
        acknowledgedAt: Timestamp.fromDate(serverUpdatedAt),
      );
      final mismatches = <String, Map<String, Object?>>{
        'operation ID': <String, Object?>{
          ...exact,
          'operationId': 'operation-collision',
        },
        'entity type': <String, Object?>{
          ...exact,
          'entityType': SyncCollection.words.entityType,
        },
        'entity ID': <String, Object?>{
          ...exact,
          'entityId': 'attempt-collision',
        },
        'operation kind': <String, Object?>{
          ...exact,
          'operationKind': SyncOperationKind.delete.name,
        },
        'payload version': <String, Object?>{...exact, 'schemaVersion': 1},
        'base revision': <String, Object?>{...exact, 'baseRevision': 3},
        'new revision': <String, Object?>{...exact, 'resultingRevision': 4},
      };

      for (final mismatch in mismatches.entries) {
        expect(
          () => FirestoreSyncCodec.decodeAcknowledgement(
            mismatch.value,
            expectedMutation: mutation,
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: mismatch.key,
        );
      }
    });

    test('rejects a missing server timestamp', () {
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.categories,
          documentId: 'category-1',
          data: <String, Object?>{
            'schemaVersion': 1,
            'entityId': 'category-1',
            'revision': 1,
            'isDeleted': false,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
            'serverUpdatedAt': null,
            'lastOperationId': 'operation-1',
            'payload': <String, Object?>{'name': 'Travel'},
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });
  });

  group('FirestoreSyncPreflight', () {
    test(
      'admits canonical attempt v1/v2 and starts each transaction once',
      () async {
        const dynamic preflight = FirestoreSyncPreflight();
        var transactions = 0;

        for (final version in const <int>[1, 2]) {
          final result = await preflight.beforeTransaction<int>(
            collection: SyncCollection.attempts,
            payloadVersion: version,
            payload: version == 1
                ? _attemptPayloadV1()
                : _attemptPayloadV2(_declaredEvidenceContext()),
            beginTransaction: () async {
              transactions += 1;
              return version;
            },
          );
          expect(result, version);
        }

        expect(transactions, 2);
      },
    );

    test(
      'rejects legacy-inferred attempt v2 before starting a transaction',
      () async {
        const dynamic preflight = FirestoreSyncPreflight();
        var transactions = 0;

        await expectLater(
          preflight.beforeTransaction<void>(
            collection: SyncCollection.attempts,
            payloadVersion: 2,
            payload: _attemptPayloadV2(
              LearningEvidenceContract.frozenV13LegacyEvidenceContext(),
            ),
            beginTransaction: () async {
              transactions += 1;
            },
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );

        expect(transactions, 0);
      },
    );

    test(
      'rejects legacy collection v2 without starting a transaction',
      () async {
        const preflight = FirestoreSyncPreflight();
        var transactions = 0;

        for (final collection in SyncCollection.values.where(
          (value) => value != SyncCollection.attempts,
        )) {
          await expectLater(
            preflight.beforeTransaction<void>(
              collection: collection,
              payloadVersion: 2,
              beginTransaction: () async {
                transactions += 1;
              },
            ),
            throwsA(isA<UnsupportedSyncSchemaFailure>()),
          );
        }

        expect(transactions, 0);
      },
    );
  });

  group('FirestoreSyncErrorMapper', () {
    test(
      'maps retry and terminal provider codes without retaining details',
      () {
        expect(
          FirestoreSyncErrorMapper.fromCode('unavailable'),
          isA<ProviderUnavailableSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('deadline-exceeded'),
          isA<ProviderUnavailableSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('resource-exhausted'),
          isA<QuotaSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('permission-denied'),
          isA<PermissionDeniedSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('unauthenticated'),
          isA<UnauthenticatedSyncFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('invalid-argument'),
          isA<InvalidSyncPayloadFailure>(),
        );
        expect(
          FirestoreSyncErrorMapper.fromCode('anything-else').toString(),
          'SyncFailure(providerUnavailable)',
        );
      },
    );
  });
}

Map<String, Object?> _attemptPayloadV1() => <String, Object?>{
  'sessionId': 'session-1',
  'wordId': 'word-1',
  'promptMode': 'meaningChoice',
  'isCorrect': true,
  'responseTimeMs': 320,
  'attemptNumber': 1,
  'occurredAtUtcMs': 2000,
  'providerProvenance': null,
};

Map<String, Object?> _attemptPayloadV2(EvidenceContext context) =>
    <String, Object?>{
      ..._attemptPayloadV1(),
      'evidenceClass': context.evidenceClass.name,
      'evidenceContext': context.toJson(),
    };

EvidenceContext _declaredEvidenceContext() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'meaning-recall',
  hintLevel: 0,
  contentRevision: 'built-in-v1',
  rolloutMode: EvidencePolicyRolloutMode.shadow,
  protocolId: 'evidence-pilot',
  protocolVersion: '1.0.0',
  experimentId: 'evidence-eligibility',
  experimentVersion: 1,
  assignmentId: 'assignment-1',
  cohort: 'shadow',
  researchConsentVersion: 1,
  engagementAllowed: true,
);

PushMutation _attemptMutation({
  required int payloadVersion,
  required DateTime clientUpdatedAt,
}) => PushMutation(
  operationId: 'operation-$payloadVersion',
  firebaseUid: 'firebase-user-1',
  collection: SyncCollection.attempts,
  entityId: 'attempt-$payloadVersion',
  operationKind: SyncOperationKind.upsert,
  payloadVersion: payloadVersion,
  baseRevision: 4,
  localRevision: 5,
  clientUpdatedAtUtc: clientUpdatedAt,
  payload: payloadVersion == 1
      ? _attemptPayloadV1()
      : _attemptPayloadV2(_declaredEvidenceContext()),
);
