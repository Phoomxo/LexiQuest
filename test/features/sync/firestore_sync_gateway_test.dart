import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

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
          'payload': _wordPayloadV1(
            updatedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
        },
      );

      expect(entity.entityId, 'word-1');
      expect(entity.revision, 7);
      expect(entity.payload['cefrLevel'], isNull);
      expect(entity.serverUpdatedAtUtc, serverUpdatedAt);
    });

    test(
      'decodes exact versioned vocabulary payloads without review inflation',
      () {
        final entity = FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.words,
          documentId: 'word-v2',
          data: <String, Object?>{
            'schemaVersion': 2,
            'entityId': 'word-v2',
            'revision': 2,
            'isDeleted': false,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
            'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
            'lastOperationId': 'word-v2-operation',
            'payload': _wordPayloadV2(
              updatedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
            ),
          },
        );

        expect(entity.payloadVersion, 2);
        expect(entity.payload['contentRevision'], 2);
        expect(entity.payload['contentProvenance'], 'userAuthored');
        expect(entity.payload['contentReviewState'], 'unreviewed');
        expect(entity.payload['contentPublicationState'], 'private');
      },
    );

    test('round-trips every declared collection generically at v1', () {
      const expectedCollections = <SyncCollection>{
        SyncCollection.categories,
        SyncCollection.words,
        SyncCollection.attempts,
        SyncCollection.readingEvents,
        SyncCollection.rewardTransactions,
        SyncCollection.srsStates,
        SyncCollection.achievementUnlocks,
        SyncCollection.experimentAssignments,
        SyncCollection.assessmentRuns,
      };
      expect(SyncCollection.values.toSet(), expectedCollections);

      for (final collection in SyncCollection.values) {
        final entityId = switch (collection) {
          SyncCollection.experimentAssignments => _canonicalAssignmentId(),
          SyncCollection.assessmentRuns => 'assessment-run-pre',
          _ => '${collection.entityType}-v1',
        };
        final payload = switch (collection) {
          SyncCollection.words => _wordPayloadV1(
            updatedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          SyncCollection.attempts => _attemptPayloadV1(),
          SyncCollection.experimentAssignments => _assignmentPayload(
            assignmentId: entityId,
            assignedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          SyncCollection.assessmentRuns => _assessmentRunPayload(
            assignmentId: _canonicalAssignmentId(),
            startedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          _ => <String, Object?>{'collection': collection.wireName},
        };
        final mutation = PushMutation(
          operationId: 'operation:${collection.entityType}:v1',
          firebaseUid: 'firebase-user-1',
          collection: collection,
          entityId: entityId,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 1,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: clientUpdatedAt,
          payload: payload,
        );

        final encoded = FirestoreSyncCodec.encodeEntity(
          mutation,
          serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
        );
        final decoded = FirestoreSyncCodec.decodeEntity(
          collection: collection,
          documentId: entityId,
          data: encoded,
        );

        expect(decoded.collection, collection, reason: collection.name);
        expect(decoded.entityId, entityId, reason: collection.name);
        expect(decoded.payloadVersion, 1, reason: collection.name);
        expect(decoded.payload, payload, reason: collection.name);
      }
    });

    test('experiment assignment uses one exact v1 wire contract', () {
      final assignmentId = _canonicalAssignmentId();
      final payload = _assignmentPayload(
        assignmentId: assignmentId,
        assignedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
      );
      final mutation = PushMutation(
        operationId: 'experimentAssignment:$assignmentId:1',
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.experimentAssignments,
        entityId: assignmentId,
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 0,
        localRevision: 1,
        clientUpdatedAtUtc: clientUpdatedAt,
        payload: payload,
      );

      final encoded = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
      );
      final decoded = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.experimentAssignments,
        documentId: assignmentId,
        data: encoded,
      );

      expect(
        SyncCollection.experimentAssignments.wireName,
        'experiment_assignments',
      );
      expect(
        SyncCollection.experimentAssignments.entityType,
        'experimentAssignment',
      );
      expect(
        SyncCollection.experimentAssignments.supportedPayloadVersions,
        <int>{1},
      );
      expect(decoded.payload.keys.toSet(), <String>{
        'assignmentId',
        'ownerId',
        'experimentId',
        'experimentVersion',
        'cohort',
        'protocolVersion',
        'assignedAtUtcMs',
      });
      expect(decoded.payload, payload);
      expect(SyncCollection.attempts.supportedPayloadVersions, <int>{1, 2});
    });

    test('assessment run uses one exact revision-aware v1 wire contract', () {
      final assignmentId = _canonicalAssignmentId();
      final activePayload = _assessmentRunPayload(
        assignmentId: assignmentId,
        startedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
      );
      final active = _assessmentRunMutation(
        payload: activePayload,
        clientUpdatedAtUtc: clientUpdatedAt,
      );

      final activeEncoded = FirestoreSyncCodec.encodeEntity(
        active,
        serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
      );
      final activeDecoded = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.assessmentRuns,
        documentId: active.entityId,
        data: activeEncoded,
      );

      expect(SyncCollection.assessmentRuns.wireName, 'assessment_runs');
      expect(SyncCollection.assessmentRuns.entityType, 'assessmentRun');
      expect(SyncCollection.assessmentRuns.supportedPayloadVersions, <int>{1});
      expect(activeDecoded.revision, 1);
      expect(activeDecoded.payload, activePayload);
      expect(activeDecoded.payload.keys.toSet(), _assessmentRunPayloadKeys);

      final completedAt = clientUpdatedAt.add(const Duration(minutes: 30));
      final terminalPayload = _assessmentRunPayload(
        assignmentId: assignmentId,
        state: AssessmentRunState.completed,
        startedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
        completedAtUtcMs: completedAt.millisecondsSinceEpoch,
      );
      final terminal = _assessmentRunMutation(
        payload: terminalPayload,
        baseRevision: 1,
        localRevision: 2,
        clientUpdatedAtUtc: completedAt,
      );
      final terminalDecoded = FirestoreSyncCodec.decodeEntity(
        collection: SyncCollection.assessmentRuns,
        documentId: terminal.entityId,
        data: FirestoreSyncCodec.encodeEntity(
          terminal,
          serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
        ),
      );

      expect(terminalDecoded.revision, 2);
      expect(terminalDecoded.payload, terminalPayload);
      expect(terminalDecoded.clientUpdatedAtUtc, completedAt);
      expect(SyncCollection.attempts.supportedPayloadVersions, <int>{1, 2});
    });

    test('assessment run codec rejects every noncanonical v1 shape', () {
      final assignmentId = _canonicalAssignmentId();
      final exact = _assessmentRunPayload(
        assignmentId: assignmentId,
        startedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
      );
      final invalidPayloads = <String, Map<String, Object?>>{
        'missing key': <String, Object?>{...exact}..remove('formVersion'),
        'extra key': <String, Object?>{...exact, 'rawResponse': 'forbidden'},
        'wrong owner': <String, Object?>{...exact, 'ownerId': 'other-user'},
        'wrong assignment identity': <String, Object?>{
          ...exact,
          'assignmentId': 'foreign-local-assignment',
        },
        'wrong type': <String, Object?>{
          ...exact,
          'databaseSchemaVersion': '15',
        },
        'blank identifier': <String, Object?>{...exact, 'instrumentId': ''},
        'trimmed identifier': <String, Object?>{...exact, 'formId': ' form-a'},
        'overlong identifier': <String, Object?>{
          ...exact,
          'studyCycleId': List<String>.filled(257, 'x').join(),
        },
        'malformed checksum': <String, Object?>{
          ...exact,
          'formChecksumSha256': 'not-sha256',
        },
        'negative start': <String, Object?>{...exact, 'startedAtUtcMs': -1},
        'active with terminal time': <String, Object?>{
          ...exact,
          'completedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
        },
        'completed without timestamp': <String, Object?>{
          ...exact,
          'state': AssessmentRunState.completed.name,
        },
        'abandoned with both terminal timestamps': <String, Object?>{
          ...exact,
          'state': AssessmentRunState.abandoned.name,
          'completedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch + 1,
          'abandonedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch + 2,
        },
      };

      for (final invalid in invalidPayloads.entries) {
        final mutation = _assessmentRunMutation(
          payload: invalid.value,
          clientUpdatedAtUtc: clientUpdatedAt,
        );
        expect(
          () => FirestoreSyncCodec.encodeEntity(
            mutation,
            serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: 'encode ${invalid.key}',
        );
        expect(
          () => FirestoreSyncCodec.decodeEntity(
            collection: SyncCollection.assessmentRuns,
            documentId: mutation.entityId,
            data: <String, Object?>{
              'schemaVersion': 1,
              'entityId': mutation.entityId,
              'revision': 1,
              'isDeleted': false,
              'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
              'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
              'lastOperationId': mutation.operationId,
              'payload': invalid.value,
            },
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: 'decode ${invalid.key}',
        );
      }
    });

    test('assessment run codec pins the only legal revision/state graph', () {
      final assignmentId = _canonicalAssignmentId();
      final startedAtMs = clientUpdatedAt.millisecondsSinceEpoch;
      final completedAtMs =
          startedAtMs + const Duration(minutes: 30).inMilliseconds;
      final invalidEntities = <String, Map<String, Object?>>{
        'create completed': <String, Object?>{
          'revision': 1,
          'clientUpdatedAtUtcMs': completedAtMs,
          'payload': _assessmentRunPayload(
            assignmentId: assignmentId,
            state: AssessmentRunState.completed,
            startedAtUtcMs: startedAtMs,
            completedAtUtcMs: completedAtMs,
          ),
        },
        'revision two active': <String, Object?>{
          'revision': 2,
          'clientUpdatedAtUtcMs': startedAtMs,
          'payload': _assessmentRunPayload(
            assignmentId: assignmentId,
            startedAtUtcMs: startedAtMs,
          ),
        },
        'revision three terminal': <String, Object?>{
          'revision': 3,
          'clientUpdatedAtUtcMs': completedAtMs,
          'payload': _assessmentRunPayload(
            assignmentId: assignmentId,
            state: AssessmentRunState.completed,
            startedAtUtcMs: startedAtMs,
            completedAtUtcMs: completedAtMs,
          ),
        },
      };

      for (final invalid in invalidEntities.entries) {
        expect(
          () => FirestoreSyncCodec.decodeEntity(
            collection: SyncCollection.assessmentRuns,
            documentId: 'assessment-run-pre',
            data: <String, Object?>{
              'schemaVersion': 1,
              'entityId': 'assessment-run-pre',
              'revision': invalid.value['revision'],
              'isDeleted': false,
              'clientUpdatedAtUtcMs': invalid.value['clientUpdatedAtUtcMs'],
              'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
              'lastOperationId': 'assessmentRun:assessment-run-pre:invalid',
              'payload': invalid.value['payload'],
            },
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: invalid.key,
        );
      }

      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.assessmentRuns,
          documentId: 'assessment-run-pre',
          data: <String, Object?>{
            'schemaVersion': 1,
            'entityId': 'assessment-run-pre',
            'revision': 1,
            'isDeleted': true,
            'clientUpdatedAtUtcMs': startedAtMs,
            'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
            'lastOperationId': 'assessmentRun:assessment-run-pre:delete',
            'payload': _assessmentRunPayload(
              assignmentId: assignmentId,
              startedAtUtcMs: startedAtMs,
            ),
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.encodeEntity(
          _assessmentRunMutation(
            payload: _assessmentRunPayload(
              assignmentId: assignmentId,
              startedAtUtcMs: startedAtMs,
            ),
            clientUpdatedAtUtc: clientUpdatedAt,
            operationKind: SyncOperationKind.delete,
          ),
          serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('experiment assignment rejects non-exact payloads at the codec', () {
      final assignmentId = _canonicalAssignmentId();
      final exact = _assignmentPayload(
        assignmentId: assignmentId,
        assignedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
      );
      final invalidPayloads = <Map<String, Object?>>[
        <String, Object?>{...exact}..remove('protocolVersion'),
        <String, Object?>{...exact, 'extra': true},
        <String, Object?>{...exact, 'ownerId': 'other-owner'},
        <String, Object?>{...exact, 'experimentId': 'study-b'},
        <String, Object?>{...exact, 'experimentVersion': 2},
        <String, Object?>{...exact, 'experimentVersion': 0},
        <String, Object?>{...exact, 'assignedAtUtcMs': -1},
      ];

      for (var index = 0; index < invalidPayloads.length; index += 1) {
        final payload = invalidPayloads[index];
        final mutation = PushMutation(
          operationId: 'invalid-assignment-$index',
          firebaseUid: 'firebase-user-1',
          collection: SyncCollection.experimentAssignments,
          entityId: assignmentId,
          operationKind: SyncOperationKind.upsert,
          payloadVersion: 1,
          baseRevision: 0,
          localRevision: 1,
          clientUpdatedAtUtc: clientUpdatedAt,
          payload: payload,
        );
        expect(
          () => FirestoreSyncCodec.encodeEntity(
            mutation,
            serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: 'encode case $index',
        );
        expect(
          () => FirestoreSyncCodec.decodeEntity(
            collection: SyncCollection.experimentAssignments,
            documentId: assignmentId,
            data: <String, Object?>{
              'schemaVersion': 1,
              'entityId': assignmentId,
              'revision': 1,
              'isDeleted': false,
              'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch,
              'serverUpdatedAt': Timestamp.fromDate(serverUpdatedAt),
              'lastOperationId': 'invalid-assignment-$index',
              'payload': payload,
            },
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: 'decode case $index',
        );
      }
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

    test('rejects payload v2 for every remaining v1-only collection', () {
      for (final collection in SyncCollection.values.where(
        (value) =>
            value != SyncCollection.attempts && value != SyncCollection.words,
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
      'admits exact vocabulary v1/v2 and starts each transaction once',
      () async {
        const preflight = FirestoreSyncPreflight();
        var transactions = 0;

        for (final version in const <int>[1, 2]) {
          final result = await preflight.beforeTransaction<int>(
            collection: SyncCollection.words,
            payloadVersion: version,
            payload: version == 1 ? _wordPayloadV1() : _wordPayloadV2(),
            clientUpdatedAtUtcMs: 2000,
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
      'rejects remaining legacy collection v2 without a transaction',
      () async {
        const preflight = FirestoreSyncPreflight();
        var transactions = 0;

        for (final collection in SyncCollection.values.where(
          (value) =>
              value != SyncCollection.attempts && value != SyncCollection.words,
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

  group('DriftSyncStore vocabulary compatibility', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await database.customInsert(
        "INSERT INTO local_owners "
        "(id, firebase_uid, account_state, created_at_utc_ms, is_active) "
        "VALUES ('owner-1', 'firebase-user-1', 'firebaseBound', 1, 1)",
      );
      await database.customInsert(
        "INSERT INTO vocabulary_categories "
        "(id, owner_id, name, normalized_name, created_at_utc_ms, "
        "updated_at_utc_ms) VALUES "
        "('category-1', 'owner-1', 'Travel', 'travel', 1, 1)",
      );
    });

    tearDown(() => database.close());

    test('dual-reads legacy and versioned learner vocabulary', () async {
      final store = DriftSyncStore(database);
      final legacyServerTime = DateTime.utc(2026, 8, 24, 10, 1);
      final versionedServerTime = DateTime.utc(2026, 8, 24, 10, 2);

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.words,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.words,
              entityId: 'word-v1',
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: legacyServerTime,
              payload: _wordPayloadV1(),
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: legacyServerTime,
            documentId: 'word-v1',
          ),
          hasMore: false,
        ),
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.words,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.words,
              entityId: 'word-v2',
              revision: 2,
              isDeleted: false,
              payloadVersion: 2,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: versionedServerTime,
              payload: _wordPayloadV2(),
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: versionedServerTime,
            documentId: 'word-v2',
          ),
          hasMore: false,
        ),
      );

      final rows = await database.customSelect('''
        SELECT id, content_revision, content_checksum_sha256,
               content_provenance, content_review_state,
               content_publication_state
        FROM vocabulary_words ORDER BY id
      ''').get();
      expect(rows, hasLength(2));
      expect(rows.first.read<String>('id'), 'word-v1');
      expect(rows.first.read<int>('content_revision'), 1);
      expect(
        rows.first.readNullable<String>('content_checksum_sha256'),
        isNull,
      );
      expect(rows.first.read<String>('content_provenance'), 'userAuthored');
      expect(rows.first.read<String>('content_review_state'), 'unreviewed');
      expect(rows.first.read<String>('content_publication_state'), 'private');
      expect(rows.last.read<String>('id'), 'word-v2');
      expect(rows.last.read<int>('content_revision'), 2);
      expect(
        rows.last.read<String>('content_checksum_sha256'),
        _wordPayloadV2()['contentChecksumSha256'],
      );
    });

    test('legacy pull cannot erase a versioned content identity', () async {
      final store = DriftSyncStore(database);
      final versioned = _wordPayloadV2();
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.words,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.words,
              entityId: 'word-mixed',
              revision: 2,
              isDeleted: false,
              payloadVersion: 2,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 24, 10, 2),
              payload: versioned,
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: DateTime.utc(2026, 8, 24, 10, 2),
            documentId: 'word-mixed',
          ),
          hasMore: false,
        ),
      );
      final legacyUpdate = <String, Object?>{
        ..._wordPayloadV1(updatedAtUtcMs: 3000),
        'spelling': 'platform updated',
        'normalizedSpelling': 'platform updated',
        'meaning': 'ชานชาลาใหม่',
        'normalizedMeaning': 'ชานชาลาใหม่',
      };
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.words,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.words,
              entityId: 'word-mixed',
              revision: 3,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                3000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 24, 10, 3),
              payload: legacyUpdate,
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: DateTime.utc(2026, 8, 24, 10, 3),
            documentId: 'word-mixed',
          ),
          hasMore: false,
        ),
      );

      final row = await (database.select(
        database.vocabularyWords,
      )..where((word) => word.id.equals('word-mixed'))).getSingle();
      expect(row.contentRevision, 3);
      expect(
        row.contentChecksumSha256,
        _gatewayWordPayloadChecksum(legacyUpdate),
      );
      expect(row.contentProvenance, 'userAuthored');
      expect(row.contentReviewState, 'unreviewed');
      expect(row.contentPublicationState, 'private');
    });

    test('word v2 rollout keeps migrated null-checksum rows on v1', () async {
      final legacy = _wordPayloadV1();
      await database
          .into(database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: 'word-legacy-outbox',
              ownerId: 'owner-1',
              categoryId: legacy['categoryId']! as String,
              spelling: legacy['spelling']! as String,
              normalizedSpelling: legacy['normalizedSpelling']! as String,
              meaning: legacy['meaning']! as String,
              normalizedMeaning: legacy['normalizedMeaning']! as String,
              partOfSpeech: legacy['partOfSpeech']! as String,
              cefrLevel: Value(legacy['cefrLevel'] as String?),
              source: Value(legacy['source']! as String),
              isGlobal: Value(legacy['isGlobal']! as bool),
              isDeleted: Value(legacy['isDeleted']! as bool),
              createdAtUtcMs: legacy['createdAtUtcMs']! as int,
              updatedAtUtcMs: legacy['updatedAtUtcMs']! as int,
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'word:word-legacy-outbox:1',
              ownerId: 'owner-1',
              entityType: 'word',
              entityId: 'word-legacy-outbox',
              operationKind: SyncOperationKind.upsert.name,
              createdAtUtcMs: 2000,
            ),
          );
      final nowUtc = DateTime.utc(2026, 8, 24, 10, 4);
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'f04-word-rollout',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 5),
        ),
        isTrue,
      );
      final store = DriftSyncStore(
        database,
        payloadRollout: const SyncPayloadRollout.vocabularyWordV2(
          vocabularyWordRulesRevision: vocabularyWordV2RulesRevision,
        ),
      );

      final claims = await store.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'f04-word-lease',
        ownerGateToken: 'f04-word-rollout',
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc,
      );

      expect(claims, hasLength(1));
      expect(claims.single.mutation.payloadVersion, 1);
      expect(
        claims.single.mutation.payload.keys.toSet(),
        VocabularyWordSyncPayloadContract.payloadV1Keys,
      );
    });
  });
}

Map<String, Object?> _wordPayloadV1({int updatedAtUtcMs = 2000}) =>
    <String, Object?>{
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
      'updatedAtUtcMs': updatedAtUtcMs,
    };

Map<String, Object?> _wordPayloadV2({int updatedAtUtcMs = 2000}) {
  final content = <String, Object?>{
    ..._wordPayloadV1(updatedAtUtcMs: updatedAtUtcMs),
    'spelling': 'platform',
    'normalizedSpelling': 'platform',
    'meaning': 'ชานชาลา',
    'normalizedMeaning': 'ชานชาลา',
  };
  return <String, Object?>{
    ...content,
    'contentRevision': 2,
    'contentChecksumSha256': _gatewayWordPayloadChecksum(content),
    'contentProvenance': 'userAuthored',
    'contentReviewState': 'unreviewed',
    'contentPublicationState': 'private',
  };
}

String _gatewayWordPayloadChecksum(Map<String, Object?> payload) => sha256
    .convert(
      utf8.encode(
        jsonEncode(<String, Object?>{
          'categoryId': payload['categoryId'],
          'spelling': payload['spelling'],
          'normalizedSpelling': payload['normalizedSpelling'],
          'meaning': payload['meaning'],
          'normalizedMeaning': payload['normalizedMeaning'],
          'partOfSpeech': payload['partOfSpeech'],
          'cefrLevel': payload['cefrLevel'],
          'source': payload['source'],
          'isGlobal': payload['isGlobal'],
        }),
      ),
    )
    .toString();

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

String _canonicalAssignmentId({
  String ownerId = 'firebase-user-1',
  String experimentId = 'study-a',
  int experimentVersion = 1,
}) => DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
  firebaseUid: ownerId,
  experimentId: experimentId,
  experimentVersion: experimentVersion,
);

Map<String, Object?> _assignmentPayload({
  required String assignmentId,
  required int assignedAtUtcMs,
}) => <String, Object?>{
  'assignmentId': assignmentId,
  'ownerId': 'firebase-user-1',
  'experimentId': 'study-a',
  'experimentVersion': 1,
  'cohort': 'intervention',
  'protocolVersion': 'protocol-1',
  'assignedAtUtcMs': assignedAtUtcMs,
};

const Set<String> _assessmentRunPayloadKeys = <String>{
  'runId',
  'ownerId',
  'learningSessionId',
  'studyCycleId',
  'phase',
  'state',
  'protocolId',
  'protocolVersion',
  'experimentId',
  'experimentVersion',
  'assignmentId',
  'cohort',
  'consentVersion',
  'consentDecidedAtUtcMs',
  'instrumentId',
  'instrumentVersion',
  'formId',
  'formVersion',
  'instrumentChecksumSha256',
  'formChecksumSha256',
  'appVersion',
  'buildId',
  'databaseSchemaVersion',
  'contentRevision',
  'evidencePolicyVersion',
  'featureContractRevision',
  'featureContractHash',
  'startedAtUtcMs',
  'completedAtUtcMs',
  'abandonedAtUtcMs',
};

Map<String, Object?> _assessmentRunPayload({
  required String assignmentId,
  required int startedAtUtcMs,
  AssessmentRunState state = AssessmentRunState.active,
  int? completedAtUtcMs,
  int? abandonedAtUtcMs,
}) => <String, Object?>{
  'runId': 'assessment-run-pre',
  'ownerId': 'firebase-user-1',
  'learningSessionId': 'assessment-session-pre',
  'studyCycleId': 'study-cycle-2026',
  'phase': AssessmentPhase.pre.name,
  'state': state.name,
  'protocolId': 'assessment-protocol',
  'protocolVersion': 'protocol-1',
  'experimentId': 'study-a',
  'experimentVersion': 1,
  'assignmentId': assignmentId,
  'cohort': 'intervention',
  'consentVersion': 1,
  'consentDecidedAtUtcMs': startedAtUtcMs - 2000,
  'instrumentId': 'instrument-core',
  'instrumentVersion': 'instrument-v1',
  'formId': 'form-a',
  'formVersion': 'form-v1',
  'instrumentChecksumSha256':
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
  'formChecksumSha256':
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
  'appVersion': '1.0.0',
  'buildId': 'task-12-sync',
  'databaseSchemaVersion': 15,
  'contentRevision': 'assessment-content-v1',
  'evidencePolicyVersion': 'learning-evidence-v1',
  'featureContractRevision': '1.0.0',
  'featureContractHash':
      'f60ad6c20312b7e898c9961cf55618d9c8a5995c11d254cf32efad0c6d8a4cb0',
  'startedAtUtcMs': startedAtUtcMs,
  'completedAtUtcMs': completedAtUtcMs,
  'abandonedAtUtcMs': abandonedAtUtcMs,
};

PushMutation _assessmentRunMutation({
  required Map<String, Object?> payload,
  required DateTime clientUpdatedAtUtc,
  int baseRevision = 0,
  int localRevision = 1,
  SyncOperationKind operationKind = SyncOperationKind.upsert,
}) => PushMutation(
  operationId: 'assessmentRun:assessment-run-pre:$localRevision',
  firebaseUid: 'firebase-user-1',
  collection: SyncCollection.assessmentRuns,
  entityId: 'assessment-run-pre',
  operationKind: operationKind,
  payloadVersion: 1,
  baseRevision: baseRevision,
  localRevision: localRevision,
  clientUpdatedAtUtc: clientUpdatedAtUtc,
  payload: payload,
);

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
