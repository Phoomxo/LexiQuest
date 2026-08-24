import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';

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
        SyncCollection.savedLearningItems,
        SyncCollection.contentQualityReports,
        SyncCollection.learningTimeSegments,
      };
      expect(SyncCollection.values.toSet(), expectedCollections);

      for (final collection in SyncCollection.values) {
        final entityId = switch (collection) {
          SyncCollection.experimentAssignments => _canonicalAssignmentId(),
          SyncCollection.assessmentRuns => 'assessment-run-pre',
          SyncCollection.savedLearningItems =>
            _savedLearningItemCloudEntityId(),
          SyncCollection.contentQualityReports =>
            _contentQualityReportCloudEntityId(),
          SyncCollection.learningTimeSegments => _learningTimeSegmentId(),
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
          SyncCollection.savedLearningItems => _savedLearningItemPayload(
            updatedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          SyncCollection.contentQualityReports => _contentQualityReportPayload(
            submittedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          SyncCollection.learningTimeSegments => _learningTimeSegmentPayload(
            endedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
          ),
          _ => <String, Object?>{'collection': collection.wireName},
        };
        final mutation = PushMutation(
          operationId: switch (collection) {
            SyncCollection.contentQualityReports =>
              ContentQualityReportSyncPayloadContract.canonicalOperationId(
                localOperationId: 'contentQualityReport:generic:v1',
                reportId: payload['reportId']! as String,
                submittedAtUtcMs: payload['submittedAtUtcMs']! as int,
              ),
            SyncCollection.learningTimeSegments =>
              LearningTimeSegmentSyncPayloadContract.canonicalOperationId(
                entityId,
              ),
            _ => 'operation:${collection.entityType}:v1',
          },
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

    test('saved item codec binds exact payload tombstone and timestamp', () {
      final payload = _savedLearningItemPayload(
        updatedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
        isDeleted: true,
      );
      final mutation = PushMutation(
        operationId: 'savedLearningItem:saved-1:2',
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.savedLearningItems,
        entityId: _savedLearningItemCloudEntityId(),
        operationKind: SyncOperationKind.delete,
        payloadVersion: 1,
        baseRevision: 1,
        localRevision: 2,
        clientUpdatedAtUtc: clientUpdatedAt,
        payload: payload,
      );

      final encoded = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
      );
      expect(
        FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.savedLearningItems,
          documentId: mutation.entityId,
          data: encoded,
        ).payload,
        payload,
      );
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.savedLearningItems,
          documentId: mutation.entityId,
          data: <String, Object?>{
            ...encoded,
            'clientUpdatedAtUtcMs': clientUpdatedAt.millisecondsSinceEpoch + 1,
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.encodeEntity(
          PushMutation(
            operationId: 'savedLearningItem:noncanonical:2',
            firebaseUid: 'firebase-user-1',
            collection: SyncCollection.savedLearningItems,
            entityId: 'saved-1',
            operationKind: SyncOperationKind.delete,
            payloadVersion: 1,
            baseRevision: 1,
            localRevision: 2,
            clientUpdatedAtUtc: clientUpdatedAt,
            payload: payload,
          ),
          serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(
        () => FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.savedLearningItems,
          documentId: 'saved-1',
          data: <String, Object?>{...encoded, 'entityId': 'saved-1'},
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
    });

    test('content report codec is exact immutable and secret-free', () {
      final payload = _contentQualityReportPayload(
        submittedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
      );
      final mutation = PushMutation(
        operationId:
            ContentQualityReportSyncPayloadContract.canonicalOperationId(
              localOperationId: 'contentQualityReport:report:station:audio:1',
              reportId: 'report:station:audio',
              submittedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
            ),
        firebaseUid: 'firebase-user-1',
        collection: SyncCollection.contentQualityReports,
        entityId: _contentQualityReportCloudEntityId(),
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
      expect(
        FirestoreSyncCodec.decodeEntity(
          collection: SyncCollection.contentQualityReports,
          documentId: mutation.entityId,
          data: encoded,
        ).payload,
        payload,
      );
      for (final invalid in <Map<String, Object?>>[
        <String, Object?>{
          ...payload,
          'comment': 'providerToken=provider-secret-SENTINEL',
        },
        <String, Object?>{...payload, 'isDeleted': true},
      ]) {
        expect(
          () => FirestoreSyncCodec.encodeEntity(
            PushMutation(
              operationId: 'content-quality-operation:invalid',
              firebaseUid: 'firebase-user-1',
              collection: SyncCollection.contentQualityReports,
              entityId: mutation.entityId,
              operationKind: SyncOperationKind.upsert,
              payloadVersion: 1,
              baseRevision: 0,
              localRevision: 1,
              clientUpdatedAtUtc: clientUpdatedAt,
              payload: invalid,
            ),
            serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
      }
    });

    test(
      'learning time codec is exact immutable and wall-clock independent',
      () {
        final entityId = _learningTimeSegmentId();
        final payload = _learningTimeSegmentPayload(
          endedAtUtcMs: clientUpdatedAt.millisecondsSinceEpoch,
        );
        final mutation = PushMutation(
          operationId:
              LearningTimeSegmentSyncPayloadContract.canonicalOperationId(
                entityId,
              ),
          firebaseUid: 'firebase-user-1',
          collection: SyncCollection.learningTimeSegments,
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
        expect(
          FirestoreSyncCodec.decodeEntity(
            collection: SyncCollection.learningTimeSegments,
            documentId: entityId,
            data: encoded,
          ).payload,
          payload,
        );
        for (final invalid in <PushMutation>[
          PushMutation(
            operationId: 'learning-time-operation:wrong',
            firebaseUid: 'firebase-user-1',
            collection: SyncCollection.learningTimeSegments,
            entityId: entityId,
            operationKind: SyncOperationKind.upsert,
            payloadVersion: 1,
            baseRevision: 0,
            localRevision: 1,
            clientUpdatedAtUtc: clientUpdatedAt,
            payload: payload,
          ),
          PushMutation(
            operationId:
                LearningTimeSegmentSyncPayloadContract.canonicalOperationId(
                  entityId,
                ),
            firebaseUid: 'firebase-user-1',
            collection: SyncCollection.learningTimeSegments,
            entityId: entityId,
            operationKind: SyncOperationKind.delete,
            payloadVersion: 1,
            baseRevision: 0,
            localRevision: 1,
            clientUpdatedAtUtc: clientUpdatedAt,
            payload: payload,
          ),
        ]) {
          expect(
            () => FirestoreSyncCodec.encodeEntity(
              invalid,
              serverTimestamp: Timestamp.fromDate(serverUpdatedAt),
            ),
            throwsA(isA<InvalidSyncPayloadFailure>()),
          );
        }
      },
    );

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

    test('rejects a noncanonical saved id before a transaction', () async {
      const preflight = FirestoreSyncPreflight();
      var transactions = 0;

      await expectLater(
        preflight.beforeTransaction<void>(
          collection: SyncCollection.savedLearningItems,
          payloadVersion: 1,
          payload: _savedLearningItemPayload(updatedAtUtcMs: 2000),
          entityId: 'device-local-id',
          isDeleted: false,
          clientUpdatedAtUtcMs: 2000,
          beginTransaction: () async {
            transactions += 1;
          },
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(transactions, 0);
    });

    test(
      'rechecks report consent immediately before the Firestore transaction',
      () async {
        const preflight = FirestoreSyncPreflight();
        var transactions = 0;

        await expectLater(
          preflight.beforeTransaction<void>(
            collection: SyncCollection.contentQualityReports,
            payloadVersion: 1,
            payload: _contentQualityReportPayload(submittedAtUtcMs: 2000),
            entityId: _contentQualityReportCloudEntityId(),
            firebaseUid: 'firebase-user-1',
            isDeleted: false,
            clientUpdatedAtUtcMs: 2000,
            authorizeContentQualityReportPush: () async => false,
            beginTransaction: () async {
              transactions += 1;
            },
          ),
          throwsA(isA<ContentReportConsentWithdrawnSyncFailure>()),
        );

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

    test(
      'saved tombstone claims are off by default and coalesce when enabled',
      () async {
        await database.customInsert('''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES (
          'saved-1', 'owner-1', 'lexicalMetadata', 'word:station', 3,
          1000, 2000, 2, 0, 1
        )
      ''');
        await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES
          ('savedLearningItem:saved-1:1', 'owner-1', 'savedLearningItem',
           'saved-1', 'upsert', 1, 0, 'pending', 0, 1000),
          ('savedLearningItem:saved-1:2', 'owner-1', 'savedLearningItem',
           'saved-1', 'delete', 1, 1, 'pending', 0, 2000)
      ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 11);
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'f20-saved-rollout',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );

        final offClaims = await DriftSyncStore(database).claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f20-off-lease',
          ownerGateToken: 'f20-saved-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );
        expect(offClaims, isEmpty);

        final enabled = DriftSyncStore(
          database,
          savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
            deployedRulesRevision: savedLearningItemV1RulesRevision,
          ),
        );
        final claims = await enabled.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f20-on-lease',
          ownerGateToken: 'f20-saved-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );

        expect(claims, hasLength(1));
        expect(
          claims.single.mutation.collection,
          SyncCollection.savedLearningItems,
        );
        expect(claims.single.mutation.operationKind, SyncOperationKind.delete);
        expect(claims.single.mutation.baseRevision, 0);
        expect(claims.single.mutation.localRevision, 2);
        expect(
          claims.single.mutation.entityId,
          _savedLearningItemCloudEntityId(),
        );
        expect(
          claims.single.mutation.payload,
          _savedLearningItemPayload(updatedAtUtcMs: 2000, isDeleted: true),
        );
      },
    );

    test(
      'learning time claims are deploy-gated and emit one immutable mutation',
      () async {
        const sessionId = 'session:time-sync';
        final segmentId = _learningTimeSegmentId(sessionId: sessionId);
        final operationId =
            LearningTimeSegmentSyncPayloadContract.canonicalOperationId(
              segmentId,
            );
        await database.customInsert('''
          INSERT INTO learning_sessions(
            id, owner_id, activity_type, state, started_at_utc_ms,
            app_version, build_id
          ) VALUES (
            '$sessionId', 'owner-1', 'meaning-quiz', 'active', 2000,
            'test', 'f24-sync'
          )
        ''');
        await database.customInsert('''
          INSERT INTO learning_time_segments(
            id, owner_id, session_id, active_start_offset_ms,
            active_duration_ms, started_at_utc_ms, ended_at_utc_ms,
            timezone_id, timezone_offset_minutes, capture_source
          ) VALUES (
            '$segmentId', 'owner-1', '$sessionId', 0, 7000, 2000, 1000,
            'Asia/Bangkok', 420, 'automaticLesson'
          )
        ''');
        await database.customInsert('''
          INSERT INTO outbox_operations(
            operation_id, owner_id, entity_type, entity_id, operation_kind,
            payload_version, base_revision, state, attempt_count,
            created_at_utc_ms
          ) VALUES (
            '$operationId', 'owner-1', 'learningTimeSegment', '$segmentId',
            'upsert', 1, 0, 'pending', 0, 1000
          )
        ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 11);
        const gateToken = 'f24-learning-time-rollout';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );

        final offClaims = await DriftSyncStore(database).claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f24-off-lease',
          ownerGateToken: gateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );
        expect(offClaims, isEmpty);

        final claims =
            await DriftSyncStore(
              database,
              learningTimeSegmentSyncRollout:
                  const LearningTimeSegmentSyncRollout.v1(
                    deployedRulesRevision: learningTimeSegmentV1RulesRevision,
                  ),
            ).claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-user-1',
              limit: 1,
              leaseToken: 'f24-on-lease',
              ownerGateToken: gateToken,
              leaseDuration: const Duration(minutes: 1),
              nowUtc: nowUtc,
            );

        expect(claims, hasLength(1));
        final mutation = claims.single.mutation;
        expect(mutation.collection, SyncCollection.learningTimeSegments);
        expect(mutation.entityId, segmentId);
        expect(mutation.operationId, operationId);
        expect(mutation.operationKind, SyncOperationKind.upsert);
        expect(mutation.baseRevision, 0);
        expect(mutation.localRevision, 1);
        expect(
          mutation.payload,
          _learningTimeSegmentPayload(
            sessionId: sessionId,
            startedAtUtcMs: 2000,
            endedAtUtcMs: 1000,
          ),
        );
      },
    );

    test(
      'learning time pull is immutable owner-bound and restart-idempotent',
      () async {
        const sessionId = 'session:remote-time';
        final entityId = _learningTimeSegmentId(sessionId: sessionId);
        final payload = _learningTimeSegmentPayload(
          sessionId: sessionId,
          startedAtUtcMs: 2000,
          endedAtUtcMs: 1000,
        );
        final serverTime = DateTime.utc(2026, 8, 24, 11);
        final page = PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.learningTimeSegments,
              entityId: entityId,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                1000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: serverTime,
              payload: payload,
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: serverTime,
            documentId: entityId,
          ),
          hasMore: false,
        );
        final store = DriftSyncStore(
          database,
          learningTimeSegmentSyncRollout:
              const LearningTimeSegmentSyncRollout.v1(
                deployedRulesRevision: learningTimeSegmentV1RulesRevision,
              ),
        );

        await store.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.learningTimeSegments,
          page: page,
        );
        await store.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.learningTimeSegments,
          page: page,
        );
        expect(
          await database.select(database.learningTimeSegments).get(),
          hasLength(1),
        );
        expect(
          await (database.select(
            database.learningSessions,
          )..where((row) => row.id.equals(sessionId))).getSingle(),
          isNotNull,
        );

        final mismatch = <String, Object?>{
          ...payload,
          'activeDurationMs': 8000,
        };
        await store.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.learningTimeSegments,
          page: PullPage(
            changes: <SyncEntity>[
              SyncEntity(
                collection: SyncCollection.learningTimeSegments,
                entityId: entityId,
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                  1000,
                  isUtc: true,
                ),
                serverUpdatedAtUtc: serverTime.add(const Duration(seconds: 1)),
                payload: mismatch,
              ),
            ],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: serverTime.add(const Duration(seconds: 1)),
              documentId: entityId,
            ),
            hasMore: false,
          ),
        );
        expect(
          (await database.select(database.learningTimeSegments).get())
              .single
              .activeDurationMs,
          7000,
        );
        expect(
          await database.select(database.syncConflicts).get(),
          hasLength(1),
        );

        final latestTime = serverTime.add(const Duration(seconds: 2));
        await store.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.learningTimeSegments,
          page: PullPage(
            changes: <SyncEntity>[
              SyncEntity(
                collection: SyncCollection.learningTimeSegments,
                entityId: entityId,
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                  1000,
                  isUtc: true,
                ),
                serverUpdatedAtUtc: latestTime,
                payload: mismatch,
              ),
            ],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: latestTime,
              documentId: entityId,
            ),
            hasMore: false,
          ),
        );
        expect(
          await database.select(database.syncConflicts).get(),
          hasLength(1),
        );
        expect(
          await store.readCheckpoint(
            'owner-1',
            SyncCollection.learningTimeSegments,
          ),
          SyncCursor(serverUpdatedAtUtc: latestTime, documentId: entityId),
        );
      },
    );

    test(
      'learning time pull quarantines overlapping canonical identities and advances',
      () async {
        const sessionId = 'session:remote-overlap';
        final retainedId = _learningTimeSegmentId(sessionId: sessionId);
        final overlappingId = _learningTimeSegmentId(
          sessionId: sessionId,
          captureSource: 'focusTimer',
        );
        final serverTime = DateTime.utc(2026, 8, 24, 11, 30);
        final finalServerTime = serverTime.add(const Duration(seconds: 1));
        final page = PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.learningTimeSegments,
              entityId: retainedId,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                1000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: serverTime,
              payload: _learningTimeSegmentPayload(
                sessionId: sessionId,
                endedAtUtcMs: 1000,
              ),
            ),
            SyncEntity(
              collection: SyncCollection.learningTimeSegments,
              entityId: overlappingId,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                1000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: finalServerTime,
              payload: _learningTimeSegmentPayload(
                sessionId: sessionId,
                activeDurationMs: 6000,
                endedAtUtcMs: 1000,
                captureSource: 'focusTimer',
              ),
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: finalServerTime,
            documentId: overlappingId,
          ),
          hasMore: false,
        );
        final store = DriftSyncStore(
          database,
          learningTimeSegmentSyncRollout:
              const LearningTimeSegmentSyncRollout.v1(
                deployedRulesRevision: learningTimeSegmentV1RulesRevision,
              ),
        );

        expect(
          await store.applyPullPage(
            ownerId: 'owner-1',
            collection: SyncCollection.learningTimeSegments,
            page: page,
          ),
          isTrue,
        );
        expect(
          await store.applyPullPage(
            ownerId: 'owner-1',
            collection: SyncCollection.learningTimeSegments,
            page: page,
          ),
          isTrue,
        );

        final segments = await database
            .select(database.learningTimeSegments)
            .get();
        expect(segments, hasLength(1));
        expect(segments.single.id, retainedId);
        expect(segments.single.captureSource, 'automaticLesson');
        final conflicts = await database.select(database.syncConflicts).get();
        expect(conflicts, hasLength(1));
        expect(conflicts.single.entityId, overlappingId);
        expect(conflicts.single.outcome, 'quarantined');
        expect(
          await store.readCheckpoint(
            'owner-1',
            SyncCollection.learningTimeSegments,
          ),
          SyncCursor(
            serverUpdatedAtUtc: finalServerTime,
            documentId: overlappingId,
          ),
        );
      },
    );

    test(
      'content report queued before consent withdrawal stays pending without retry',
      () async {
        final consent = DriftResearchConsentRepository(database);
        await consent.decide(
          ownerId: 'owner-1',
          version: 1,
          accepted: true,
          decidedAtUtc: DateTime.utc(2026, 8, 24, 10),
        );
        await database.customInsert('''
          INSERT INTO content_quality_reports(
            id, owner_id, content_type, content_id, content_revision,
            reason_code, comment, submitted_at_utc_ms
          ) VALUES (
            'report-queued', 'owner-1', 'lexicalMetadata', 'word:station', 3,
            'audio', 'Pronunciation is unclear', 2000
          )
        ''');
        await database.customInsert('''
          INSERT INTO outbox_operations(
            operation_id, owner_id, entity_type, entity_id, operation_kind,
            payload_version, base_revision, state, attempt_count,
            created_at_utc_ms
          ) VALUES (
            'contentQualityReport:report-queued:1', 'owner-1',
            'contentQualityReport', 'report-queued', 'upsert', 1, 0,
            'pending', 0, 2000
          )
        ''');
        await consent.decide(
          ownerId: 'owner-1',
          version: 1,
          accepted: false,
          decidedAtUtc: DateTime.utc(2026, 8, 24, 10, 1),
        );
        final nowUtc = DateTime.utc(2026, 8, 24, 10, 2);
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'f21-report-rollout',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );

        final claims =
            await DriftSyncStore(
              database,
              consentRegistry: DriftConsentRegistry(database),
              contentQualityReportSyncRollout:
                  const ContentQualityReportSyncRollout.v1(
                    deployedRulesRevision: contentQualityReportV1RulesRevision,
                    consentVersion: 1,
                  ),
            ).claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-user-1',
              limit: 1,
              leaseToken: 'f21-report-lease',
              ownerGateToken: 'f21-report-rollout',
              leaseDuration: const Duration(minutes: 1),
              nowUtc: nowUtc,
            );

        expect(claims, isEmpty);
        final outbox = await database.customSelect('''
          SELECT state, attempt_count FROM outbox_operations
          WHERE operation_id = 'contentQualityReport:report-queued:1'
        ''').getSingle();
        expect(outbox.read<String>('state'), 'pending');
        expect(outbox.read<int>('attempt_count'), 0);
      },
    );

    test(
      'content report claim emits one exact immutable canonical mutation',
      () async {
        await DriftResearchConsentRepository(database).decide(
          ownerId: 'owner-1',
          version: 1,
          accepted: true,
          decidedAtUtc: DateTime.utc(2026, 8, 24, 10),
        );
        await database.customInsert('''
        INSERT INTO content_quality_reports(
          id, owner_id, content_type, content_id, content_revision,
          reason_code, comment, submitted_at_utc_ms
        ) VALUES (
          'report-claim', 'owner-1', 'lexicalMetadata', 'word:station', 3,
          'audio', 'Pronunciation is unclear', 2000
        )
      ''');
        const localOperationId = 'contentQualityReport:report-claim:1';
        await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES (
          '$localOperationId', 'owner-1', 'contentQualityReport',
          'report-claim', 'upsert', 1, 0, 'pending', 0, 2000
        )
      ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 10, 2);
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'f21-report-claim-rollout',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final store = DriftSyncStore(
          database,
          consentRegistry: DriftConsentRegistry(database),
          contentQualityReportSyncRollout:
              const ContentQualityReportSyncRollout.v1(
                deployedRulesRevision: contentQualityReportV1RulesRevision,
                consentVersion: 1,
              ),
        );

        final claim = (await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f21-report-claim-lease',
          ownerGateToken: 'f21-report-claim-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        )).single;

        final expectedPayload = _contentQualityReportPayload(
          reportId: 'report-claim',
          submittedAtUtcMs: 2000,
        );
        expect(claim.mutation.collection, SyncCollection.contentQualityReports);
        expect(claim.mutation.operationKind, SyncOperationKind.upsert);
        expect(claim.mutation.baseRevision, 0);
        expect(claim.mutation.localRevision, 1);
        expect(claim.mutation.payload, expectedPayload);
        expect(
          claim.mutation.entityId,
          ContentQualityReportSyncPayloadContract.canonicalEntityId(
            reportId: 'report-claim',
          ),
        );
        expect(
          claim.mutation.operationId,
          ContentQualityReportSyncPayloadContract.canonicalOperationId(
            localOperationId: localOperationId,
            reportId: 'report-claim',
            submittedAtUtcMs: 2000,
          ),
        );
      },
    );

    test(
      'content report withdrawal after claim releases without an attempt',
      () async {
        final consent = DriftResearchConsentRepository(database);
        await consent.decide(
          ownerId: 'owner-1',
          version: 1,
          accepted: true,
          decidedAtUtc: DateTime.utc(2026, 8, 24, 10),
        );
        await database.customInsert('''
          INSERT INTO content_quality_reports(
            id, owner_id, content_type, content_id, content_revision,
            reason_code, comment, submitted_at_utc_ms
          ) VALUES (
            'report-withdraw-after-claim', 'owner-1', 'lexicalMetadata',
            'word:station', 3, 'audio', null, 2000
          )
        ''');
        const localOperationId =
            'contentQualityReport:report-withdraw-after-claim:1';
        await database.customInsert('''
          INSERT INTO outbox_operations(
            operation_id, owner_id, entity_type, entity_id, operation_kind,
            payload_version, base_revision, state, attempt_count,
            created_at_utc_ms
          ) VALUES (
            '$localOperationId', 'owner-1', 'contentQualityReport',
            'report-withdraw-after-claim', 'upsert', 1, 0, 'pending', 0, 2000
          )
        ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 10, 2);
        const gateToken = 'f21-report-withdraw-after-claim';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final store = DriftSyncStore(
          database,
          consentRegistry: DriftConsentRegistry(database),
          contentQualityReportSyncRollout:
              const ContentQualityReportSyncRollout.v1(
                deployedRulesRevision: contentQualityReportV1RulesRevision,
                consentVersion: 1,
              ),
        );
        final claim = (await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f21-report-withdraw-after-claim-lease',
          ownerGateToken: gateToken,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        )).single;

        await consent.decide(
          ownerId: 'owner-1',
          version: 1,
          accepted: false,
          decidedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        );

        expect(
          await store.beginAttempt(
            claim: claim,
            ownerGateToken: gateToken,
            nowUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
          isNull,
        );
        final outbox = await database.customSelect('''
          SELECT state, attempt_count, lease_token
          FROM outbox_operations
          WHERE operation_id = '$localOperationId'
        ''').getSingle();
        expect(outbox.read<String>('state'), 'pending');
        expect(outbox.read<int>('attempt_count'), 0);
        expect(outbox.readNullable<String>('lease_token'), isNull);
      },
    );

    test(
      'saved retries reconstruct the exact attempted intent revision',
      () async {
        await database.customInsert('''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES
          ('saved-retry-upsert', 'owner-1', 'lexicalMetadata',
           'word:retry-upsert', 1, 1000, 2000, 2, 0, 1),
          ('saved-retry-delete', 'owner-1', 'lexicalMetadata',
           'word:retry-delete', 1, 1000, 3000, 3, 1, 0)
      ''');
        await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES
          ('savedLearningItem:saved-retry-upsert:1', 'owner-1',
           'savedLearningItem', 'saved-retry-upsert', 'upsert', 1, 0,
           'retryWaiting', 1, 1000),
          ('savedLearningItem:saved-retry-upsert:2', 'owner-1',
           'savedLearningItem', 'saved-retry-upsert', 'delete', 1, 1,
           'pending', 0, 2000),
          ('savedLearningItem:saved-retry-delete:2', 'owner-1',
           'savedLearningItem', 'saved-retry-delete', 'delete', 1, 1,
           'retryWaiting', 1, 2000),
          ('savedLearningItem:saved-retry-delete:3', 'owner-1',
           'savedLearningItem', 'saved-retry-delete', 'upsert', 1, 2,
           'pending', 0, 3000)
      ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 12);
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'f20-saved-retry-rollout',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final store = DriftSyncStore(
          database,
          savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
            deployedRulesRevision: savedLearningItemV1RulesRevision,
          ),
        );

        final claims = await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 2,
          leaseToken: 'f20-saved-retry-lease',
          ownerGateToken: 'f20-saved-retry-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        );

        expect(claims, hasLength(2));
        final upsert = claims.singleWhere(
          (claim) => claim.localOperationId.endsWith('retry-upsert:1'),
        );
        expect(upsert.mutation.operationKind, SyncOperationKind.upsert);
        expect(upsert.mutation.baseRevision, 0);
        expect(upsert.mutation.localRevision, 1);
        expect(upsert.mutation.clientUpdatedAtUtc.millisecondsSinceEpoch, 1000);
        expect(
          upsert.mutation.entityId,
          _savedLearningItemCloudEntityId(
            contentId: 'word:retry-upsert',
            contentRevision: 1,
          ),
        );
        expect(
          upsert.mutation.payload,
          _savedLearningItemPayload(
            contentId: 'word:retry-upsert',
            contentRevision: 1,
            updatedAtUtcMs: 1000,
          ),
        );

        final delete = claims.singleWhere(
          (claim) => claim.localOperationId.endsWith('retry-delete:2'),
        );
        expect(delete.mutation.operationKind, SyncOperationKind.delete);
        expect(delete.mutation.baseRevision, 1);
        expect(delete.mutation.localRevision, 2);
        expect(delete.mutation.clientUpdatedAtUtc.millisecondsSinceEpoch, 2000);
        expect(
          delete.mutation.entityId,
          _savedLearningItemCloudEntityId(
            contentId: 'word:retry-delete',
            contentRevision: 1,
          ),
        );
        expect(
          delete.mutation.payload,
          _savedLearningItemPayload(
            contentId: 'word:retry-delete',
            contentRevision: 1,
            updatedAtUtcMs: 2000,
            isDeleted: true,
          ),
        );
      },
    );

    test('saved pull coalesces a canonical cloud id by natural key', () async {
      await database.customInsert('''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES (
          'device-local-id', 'owner-1', 'lexicalMetadata', 'word:station', 3,
          1000, 1000, 3, 0, 0
        )
      ''');
      await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES
          ('savedLearningItem:device-local-id:1', 'owner-1',
           'savedLearningItem', 'device-local-id', 'upsert', 1, 0,
           'conflictResolved', 1, 1000),
          ('savedLearningItem:device-local-id:2', 'owner-1',
           'savedLearningItem', 'device-local-id', 'delete', 1, 0,
           'conflictResolved', 1, 1000),
          ('savedLearningItem:device-local-id:3', 'owner-1',
           'savedLearningItem', 'device-local-id', 'upsert', 1, 0,
           'pending', 0, 1000)
      ''');
      final serverUpdatedAtUtc = DateTime.utc(2026, 8, 24, 12, 30);
      final canonicalEntityId = _savedLearningItemCloudEntityId();
      final store = DriftSyncStore(
        database,
        savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
          deployedRulesRevision: savedLearningItemV1RulesRevision,
        ),
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.savedLearningItems,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.savedLearningItems,
              entityId: canonicalEntityId,
              revision: 1,
              isDeleted: true,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                2000,
                isUtc: true,
              ),
              serverUpdatedAtUtc: serverUpdatedAtUtc,
              payload: _savedLearningItemPayload(
                updatedAtUtcMs: 2000,
                isDeleted: true,
              ),
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: serverUpdatedAtUtc,
            documentId: canonicalEntityId,
          ),
          hasMore: false,
        ),
      );

      final rows = await database.customSelect('''
        SELECT id, local_revision, cloud_revision, is_deleted
        FROM saved_learning_items
      ''').get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'device-local-id');
      expect(rows.single.read<int>('local_revision'), 3);
      expect(rows.single.read<int>('cloud_revision'), 1);
      expect(rows.single.read<int>('is_deleted'), 1);
      final outbox = await database.customSelect('''
        SELECT state, failure_code FROM outbox_operations
        WHERE operation_id = 'savedLearningItem:device-local-id:3'
      ''').getSingle();
      expect(outbox.read<String>('state'), 'conflictResolved');
      expect(outbox.read<String>('failure_code'), 'cloudWins');
    });

    test(
      'saved conflict preserves and rebases a newer queued intent',
      () async {
        await database.customInsert('''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES (
          'device-local-id', 'owner-1', 'lexicalMetadata', 'word:station', 3,
          1000, 2000, 10, 8, 1
        )
      ''');
        await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES
          ('savedLearningItem:device-local-id:9', 'owner-1',
           'savedLearningItem', 'device-local-id', 'upsert', 1, 8,
           'retryWaiting', 1, 2000),
          ('savedLearningItem:device-local-id:10', 'owner-1',
           'savedLearningItem', 'device-local-id', 'delete', 1, 9,
           'pending', 0, 2000)
      ''');
        final nowUtc = DateTime.utc(2026, 8, 24, 13);
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: 'f20-saved-conflict-rollout',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final store = DriftSyncStore(
          database,
          savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
            deployedRulesRevision: savedLearningItemV1RulesRevision,
          ),
        );
        final claim = (await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f20-saved-conflict-lease',
          ownerGateToken: 'f20-saved-conflict-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc,
        )).single;
        final attempted = (await store.beginAttempt(
          claim: claim,
          ownerGateToken: 'f20-saved-conflict-rollout',
          nowUtc: nowUtc,
        ))!;
        final canonicalEntityId = _savedLearningItemCloudEntityId();

        expect(
          await store.resolvePushConflict(
            claim: attempted,
            ownerGateToken: 'f20-saved-conflict-rollout',
            cloudEntity: SyncEntity(
              collection: SyncCollection.savedLearningItems,
              entityId: canonicalEntityId,
              revision: 9,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
                1500,
                isUtc: true,
              ),
              serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
              payload: _savedLearningItemPayload(updatedAtUtcMs: 1500),
            ),
            resolvedAtUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
          isTrue,
        );

        final row = await database.customSelect('''
        SELECT saved_at_utc_ms, updated_at_utc_ms, local_revision,
               cloud_revision, is_deleted
        FROM saved_learning_items
      ''').getSingle();
        expect(row.read<int>('saved_at_utc_ms'), 1000);
        expect(row.read<int>('updated_at_utc_ms'), 2000);
        expect(row.read<int>('local_revision'), 10);
        expect(row.read<int>('cloud_revision'), 9);
        expect(row.read<int>('is_deleted'), 1);
        final outbox = await database.customSelect('''
        SELECT operation_id, state, base_revision FROM outbox_operations
      ''').get();
        final attemptedRow = outbox.singleWhere(
          (entry) => entry.read<String>('operation_id').endsWith(':9'),
        );
        final queuedRow = outbox.singleWhere(
          (entry) => entry.read<String>('operation_id').endsWith(':10'),
        );
        expect(attemptedRow.read<String>('state'), 'conflictResolved');
        expect(queuedRow.read<String>('state'), 'pending');
        expect(queuedRow.read<int>('base_revision'), 9);

        final rebased = (await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-user-1',
          limit: 1,
          leaseToken: 'f20-saved-rebased-lease',
          ownerGateToken: 'f20-saved-conflict-rollout',
          leaseDuration: const Duration(minutes: 1),
          nowUtc: nowUtc.add(const Duration(seconds: 3)),
        )).single;
        expect(rebased.mutation.operationKind, SyncOperationKind.delete);
        expect(rebased.mutation.baseRevision, 9);
        expect(rebased.mutation.localRevision, 10);
        expect(rebased.mutation.entityId, canonicalEntityId);
        expect(
          rebased.mutation.payload,
          _savedLearningItemPayload(updatedAtUtcMs: 2000, isDeleted: true),
        );
      },
    );

    test('saved coalescing orders equal-time revisions numerically', () async {
      await database.customInsert('''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES (
          'saved-equal-time', 'owner-1', 'lexicalMetadata', 'word:station', 3,
          1000, 2000, 10, 8, 1
        )
      ''');
      await database.customInsert('''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES
          ('savedLearningItem:saved-equal-time:9', 'owner-1',
           'savedLearningItem', 'saved-equal-time', 'upsert', 1, 8,
           'pending', 0, 2000),
          ('savedLearningItem:saved-equal-time:10', 'owner-1',
           'savedLearningItem', 'saved-equal-time', 'delete', 1, 9,
           'pending', 0, 2000)
      ''');
      final nowUtc = DateTime.utc(2026, 8, 24, 14);
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'f20-saved-equal-time-rollout',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 5),
        ),
        isTrue,
      );
      final store = DriftSyncStore(
        database,
        savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
          deployedRulesRevision: savedLearningItemV1RulesRevision,
        ),
      );

      final claim = (await store.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'f20-saved-equal-time-lease',
        ownerGateToken: 'f20-saved-equal-time-rollout',
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc,
      )).single;

      expect(claim.localOperationId, endsWith(':10'));
      expect(claim.mutation.operationKind, SyncOperationKind.delete);
      expect(claim.mutation.baseRevision, 8);
      expect(claim.mutation.localRevision, 10);
    });

    test('saved wire operation id is bounded for a long local id', () async {
      final localEntityId = 'x' * 256;
      final localOperationId = 'savedLearningItem:$localEntityId:1';
      await database.customInsert(
        '''
        INSERT INTO saved_learning_items(
          id, owner_id, content_type, content_id, content_revision,
          saved_at_utc_ms, updated_at_utc_ms, local_revision, cloud_revision,
          is_deleted
        ) VALUES (
          ?, 'owner-1', 'lexicalMetadata', 'word:station', 3,
          1000, 1000, 1, 0, 0
        )
      ''',
        variables: <Variable<Object>>[Variable<String>(localEntityId)],
      );
      await database.customInsert(
        '''
        INSERT INTO outbox_operations(
          operation_id, owner_id, entity_type, entity_id, operation_kind,
          payload_version, base_revision, state, attempt_count,
          created_at_utc_ms
        ) VALUES (
          ?, 'owner-1', 'savedLearningItem', ?, 'upsert', 1, 0,
          'pending', 0, 1000
        )
      ''',
        variables: <Variable<Object>>[
          Variable<String>(localOperationId),
          Variable<String>(localEntityId),
        ],
      );
      final nowUtc = DateTime.utc(2026, 8, 24, 15);
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'f20-saved-long-id-rollout',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 5),
        ),
        isTrue,
      );
      final store = DriftSyncStore(
        database,
        savedLearningItemSyncRollout: const SavedLearningItemSyncRollout.v1(
          deployedRulesRevision: savedLearningItemV1RulesRevision,
        ),
      );

      final claim = (await store.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-user-1',
        limit: 1,
        leaseToken: 'f20-saved-long-id-lease',
        ownerGateToken: 'f20-saved-long-id-rollout',
        leaseDuration: const Duration(minutes: 1),
        nowUtc: nowUtc,
      )).single;

      expect(claim.localOperationId, localOperationId);
      expect(claim.localOperationId.length, greaterThan(256));
      expect(
        claim.mutation.operationId,
        matches(RegExp(r'^saved-learning-operation:[0-9a-f]{64}$')),
      );
      expect(claim.mutation.operationId.length, lessThanOrEqualTo(256));
      expect(claim.mutation.entityId, _savedLearningItemCloudEntityId());

      final attempted = (await store.beginAttempt(
        claim: claim,
        ownerGateToken: 'f20-saved-long-id-rollout',
        nowUtc: nowUtc.add(const Duration(seconds: 1)),
      ))!;
      expect(
        await store.acknowledge(
          operationId: attempted.localOperationId,
          leaseToken: attempted.leaseToken,
          ownerGateToken: 'f20-saved-long-id-rollout',
          nowUtc: nowUtc.add(const Duration(seconds: 2)),
          acknowledgement: PushAcknowledged(
            operationId: attempted.localOperationId,
            resultingRevision: 1,
            acknowledgedAtUtc: nowUtc.add(const Duration(seconds: 2)),
          ),
        ),
        isTrue,
      );
      final outbox = await database
          .customSelect(
            'SELECT state FROM outbox_operations WHERE operation_id = ?',
            variables: <Variable<Object>>[Variable<String>(localOperationId)],
          )
          .getSingle();
      expect(outbox.read<String>('state'), 'acknowledged');
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

Map<String, Object?> _savedLearningItemPayload({
  String contentType = 'lexicalMetadata',
  String contentId = 'word:station',
  int contentRevision = 3,
  required int updatedAtUtcMs,
  bool isDeleted = false,
}) => <String, Object?>{
  'contentType': contentType,
  'contentId': contentId,
  'contentRevision': contentRevision,
  'savedAtUtcMs': 1000,
  'updatedAtUtcMs': updatedAtUtcMs,
  'isDeleted': isDeleted,
};

String _savedLearningItemCloudEntityId({
  String contentType = 'lexicalMetadata',
  String contentId = 'word:station',
  int contentRevision = 3,
}) =>
    'saved-learning-item:${sha256.convert(utf8.encode('$contentType|$contentId|$contentRevision'))}';

Map<String, Object?> _contentQualityReportPayload({
  String reportId = 'report:station:audio',
  required int submittedAtUtcMs,
}) => <String, Object?>{
  'reportId': reportId,
  'contentType': 'lexicalMetadata',
  'contentId': 'word:station',
  'contentRevision': 3,
  'reasonCode': 'audio',
  'comment': 'Pronunciation is unclear',
  'submittedAtUtcMs': submittedAtUtcMs,
  'isDeleted': false,
};

String _contentQualityReportCloudEntityId({
  String reportId = 'report:station:audio',
}) => 'content-quality-report:${sha256.convert(utf8.encode(reportId))}';

String _learningTimeSegmentId({
  String sessionId = 'session:meaning:1',
  int activeStartOffsetMs = 0,
  String captureSource = 'automaticLesson',
}) => LearningTimeSegmentSyncPayloadContract.canonicalEntityId(
  sessionId: sessionId,
  activeStartOffsetMs: activeStartOffsetMs,
  captureSource: captureSource,
);

Map<String, Object?> _learningTimeSegmentPayload({
  String sessionId = 'session:meaning:1',
  int activeStartOffsetMs = 0,
  int activeDurationMs = 7000,
  int startedAtUtcMs = 2000,
  required int endedAtUtcMs,
  String captureSource = 'automaticLesson',
}) => <String, Object?>{
  'segmentId': _learningTimeSegmentId(
    sessionId: sessionId,
    activeStartOffsetMs: activeStartOffsetMs,
    captureSource: captureSource,
  ),
  'sessionId': sessionId,
  'activeStartOffsetMs': activeStartOffsetMs,
  'activeDurationMs': activeDurationMs,
  'startedAtUtcMs': startedAtUtcMs,
  'endedAtUtcMs': endedAtUtcMs,
  'timezoneId': 'Asia/Bangkok',
  'timezoneOffsetMinutes': 420,
  'captureSource': captureSource,
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
