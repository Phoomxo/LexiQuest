import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

import '../../support/motivation_research_fixture.dart';

const _rollout = ResearchMeasurementSyncRollout.localEmulatorV1(
  deployedRulesRevision: researchMeasurementV1RulesRevision,
);

void main() {
  for (final host in [
    'firestore.googleapis.com',
    'example.com:8080',
    '127.0.0.1.attacker.invalid:8080',
    'localhost',
    null,
  ]) {
    test('research transport rejects non-emulator host $host', () {
      expect(isResearchEmulatorHost(host), isFalse);
    });
  }
  for (final host in [
    'localhost:8080',
    '127.0.0.1:8080',
    '10.0.2.2:8080',
    '[::1]:8080',
  ]) {
    test('synthetic transport allows explicit emulator host $host', () {
      expect(isResearchEmulatorHost(host), isTrue);
    });
  }
  test('permit round trip retains signed canonical data exactly', () async {
    final f = MotivationResearchFixture();
    addTearDown(f.database.close);
    final original = f.permit();
    final payload = ResearchSyncContract.permitPayload(original);
    final restored = ResearchSyncContract.permitFromPayload(payload);
    expect(restored.canonicalPayload(), original.canonicalPayload());
    expect(restored.signature, original.signature);
    for (final field in [
      'ownerId',
      'assignmentId',
      'protocolVersion',
      'consentReceiptId',
      'issuerKeyId',
    ]) {
      expect(
        () => ResearchSyncContract.permitFromPayload({
          ...payload,
          field: 'forged',
        }),
        throwsA(isA<SyncFailure>()),
      );
    }
    expect(
      () => ResearchSyncContract.permitFromPayload({
        ...payload,
        'cloudRevision': 2,
      }),
      throwsA(isA<SyncFailure>()),
    );
  });
  test(
    'permit acknowledgement reads server evidence and preserves revisions',
    () async {
      final f = MotivationResearchFixture();
      addTearDown(f.database.close);
      final p = ResearchSyncContract.permitPayload(f.permit());
      final mutation = PushMutation(
        operationId: 'permit-read',
        firebaseUid: 'uid',
        collection: SyncCollection.researchParticipationPermits,
        entityId: f.permit().id,
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 0,
        localRevision: 1,
        clientUpdatedAtUtc: f.now,
        payload: p,
        ownerGateToken: 'secret-local-token',
      );
      final trusted = SyncEntity(
        collection: mutation.collection,
        entityId: mutation.entityId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: f.now,
        serverUpdatedAtUtc: f.now,
        payload: p,
      );
      expect(
        acknowledgeTrustedResearchPermit(mutation, trusted).resultingRevision,
        1,
      );
      expect(
        jsonEncode(
          FirestoreSyncCodec.encodeEntity(
            mutation,
            serverTimestamp: 'timestamp',
          ),
        ),
        isNot(contains('secret-local-token')),
      );
      final fake = SyncEntity(
        collection: mutation.collection,
        entityId: mutation.entityId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: f.now,
        serverUpdatedAtUtc: f.now,
        payload: {...p, 'signature': 'forged'},
      );
      expect(
        () => acknowledgeTrustedResearchPermit(mutation, fake),
        throwsA(isA<SyncFailure>()),
      );
    },
  );
  test(
    'download codec preserves signed deletion and binds outer revision and tombstone',
    () {
      final f = MotivationResearchFixture();
      addTearDown(f.database.close);
      final signed =
          Map<String, Object?>.from(
              jsonDecode(f.permit().canonicalPayload()) as Map,
            )
            ..['localRevision'] = 2
            ..['cloudRevision'] = 2
            ..['isDeleted'] = true;
      final payload = <String, Object?>{
        ...signed,
        'payloadSha256': sha256
            .convert(utf8.encode(jsonEncode(signed)))
            .toString(),
        'signature': 'synthetic-signature',
      };
      final document = <String, Object?>{
        'schemaVersion': 1,
        'entityId': f.permit().id,
        'revision': 2,
        'isDeleted': true,
        'clientUpdatedAtUtcMs': f.now.millisecondsSinceEpoch,
        'serverUpdatedAt': Timestamp.fromDate(f.now),
        'lastOperationId': 'trusted-issuer:2',
        'payload': payload,
      };
      SyncEntity decode(Map<String, Object?> data) =>
          FirestoreSyncCodec.decodeEntity(
            collection: SyncCollection.researchParticipationPermits,
            documentId: f.permit().id,
            data: data,
          );
      final result = decode(document);
      expect(result.isDeleted, isTrue);
      expect(result.revision, 2);
      expect(result.payload, payload);
      expect(
        () => decode({...document, 'revision': 1}),
        throwsA(isA<SyncFailure>()),
      );
      expect(
        () => decode({...document, 'isDeleted': false}),
        throwsA(isA<SyncFailure>()),
      );
      expect(
        () => decode({
          ...document,
          'payload': {...payload, 'signature': ''},
        }),
        throwsA(isA<SyncFailure>()),
      );
      // Structural permission to receive a signed tombstone is never permission
      // for a client to upload/mint one.
      expect(
        () => FirestoreSyncCodec.encodeEntity(
          PushMutation(
            operationId: 'client-forgery',
            firebaseUid: 'uid',
            collection: SyncCollection.researchParticipationPermits,
            entityId: f.permit().id,
            operationKind: SyncOperationKind.delete,
            payloadVersion: 1,
            baseRevision: 1,
            localRevision: 2,
            clientUpdatedAtUtc: f.now,
            payload: payload,
          ),
          serverTimestamp: Timestamp.fromDate(f.now),
        ),
        throwsA(isA<SyncFailure>()),
      );
    },
  );
  test(
    'withdrawal receipt is immutable and lost acknowledgement reuses the marker',
    () {
      final at = DateTime.utc(2026, 9, 5, 12);
      final mutation = PushMutation(
        operationId: 'denial:permit:a',
        firebaseUid: 'uid',
        collection: SyncCollection.researchWithdrawals,
        entityId: 'permit:a',
        operationKind: SyncOperationKind.upsert,
        payloadVersion: 1,
        baseRevision: 0,
        localRevision: 1,
        clientUpdatedAtUtc: at,
        payload: const {'permitId': 'permit:a', 'ownerId': 'owner:a'},
        ownerGateToken: 'local-lease',
      );
      final marker = <String, Object?>{
        'schemaVersion': 1,
        'permitId': 'permit:a',
        'ownerId': 'owner:a',
        'withdrawnAt': Timestamp.fromDate(at),
      };
      for (var retry = 0; retry < 3; retry++) {
        final ack = acknowledgeResearchWithdrawal(mutation, marker);
        expect(ack.operationId, mutation.operationId);
        expect(ack.resultingRevision, 1);
        expect(ack.acknowledgedAtUtc, at);
      }
      for (final forged in <Map<String, Object?>>[
        {...marker, 'ownerId': 'owner:other'},
        {...marker, 'permitId': 'permit:other'},
        {...marker, 'active': true},
        {...marker, 'withdrawnAt': at.toIso8601String()},
      ]) {
        expect(
          () => acknowledgeResearchWithdrawal(mutation, forged),
          throwsA(isA<SyncFailure>()),
        );
      }
      expect(
        () => FirestoreSyncCodec.encodeEntity(
          mutation,
          serverTimestamp: Timestamp.fromDate(at),
        ),
        throwsA(isA<SyncFailure>()),
        reason: 'generic transport cannot write a mutable denial',
      );
      expect(
        ResearchSyncContract.collections,
        isNot(contains(SyncCollection.researchWithdrawals)),
      );
    },
  );
  // Remaining gap: authorizer approval alone must never waive structural
  // validation before a provider transaction begins. Run RED after slot grant.
  test(
    'research preflight rejects malformed payload despite positive authorizer',
    () async {
      var transactions = 0;
      await expectLater(
        const FirestoreSyncPreflight().beforeTransaction<void>(
          collection: SyncCollection.motivationResponses,
          payloadVersion: 1,
          payload: {'rawAnswer': 'must not enter transaction'},
          entityId: 'response:a',
          firebaseUid: 'uid',
          isDeleted: false,
          clientUpdatedAtUtcMs: 1000,
          researchMeasurementRollout: _rollout,
          authorizeResearchPush: () async => true,
          beginTransaction: () async {
            transactions++;
          },
        ),
        throwsA(isA<SyncFailure>()),
      );
      expect(transactions, 0);
    },
  );
  final occurred = DateTime.utc(2026, 9, 5, 12, 0, 0, 123);
  Map<String, dynamic> event(String type) {
    final payload = switch (type) {
      'TodayExperiencePresented' => <String, dynamic>{
        'entryAttemptId': '00000000-0000-4000-8000-000000000001',
        'catalogVersion': '1',
      },
      'TodayExperiencePresentationChanged' => <String, dynamic>{
        'fromPresentation': 'standard',
        'switchOrdinal': 1,
      },
      'TodayExperienceMissionStarted' => <String, dynamic>{
        'opportunityId': 'opportunity:a',
        'planId': 'plan:a',
        'mode': 'meaning-quiz',
      },
      _ => <String, dynamic>{
        'opportunityId': 'opportunity:a',
        'planId': 'plan:a',
        'terminalState': 'completed',
      },
    };
    final mission = type.startsWith('TodayExperienceMission');
    return EventEnvelopeV2(
      eventId: researchEventId('research:$type', occurred),
      eventType: type,
      eventVersion: 1,
      occurredAtUtc: occurred,
      recordedAtUtc: occurred,
      actorIdentity: 'owner:a',
      ownerIdentity: 'owner:a',
      aggregateType: mission ? 'LearningSession' : 'MeasurementOpportunity',
      aggregateId: mission ? 'session:a' : 'opportunity:a',
      correlationId: 'opportunity:a',
      idempotencyKey: 'research:$type',
      consentContext: const ConsentContext(
        researchConsentVersion: 1,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: 'motivation',
        variantId: 'adventure',
        assignedAtUtc: occurred,
      ),
      contentRevision: 'content1',
      policyVersion: 'policy1',
      appVersion: '1',
      buildId: 'test',
      privacyClassification: PrivacyClassification.ownerOnly,
      payload: {
        'assignedTreatment': 'adventure',
        'effectivePresentation': 'adventure',
        ...payload,
      },
    ).toJson();
  }

  for (final type in ResearchSyncContract.eventTypes) {
    test('frozen envelope accepts only bounded $type payload', () {
      final e = event(type);
      final payload = <String, Object?>{
        'permitId': 'permit:a',
        'permitPayloadSha256': List.filled(64, 'a').join(),
        'permitRevision': 1,
        'envelope': e,
      };
      void validate(Map<String, Object?> p) => ResearchSyncContract.validate(
        collection: SyncCollection.neutralEventsV2,
        entityId: e['eventId'] as String,
        payload: p,
        revision: 1,
        isDeleted: false,
      );
      expect(() => validate(payload), returnsNormally);
      for (final extra in ['score', 'freeText', 'ownerGateToken', 'permitId']) {
        expect(
          () => validate({
            ...payload,
            'envelope': {...e, extra: 'forged'},
          }),
          throwsA(isA<SyncFailure>()),
        );
      }
      expect(
        () => validate({
          ...payload,
          'envelope': {...e, 'eventType': 'QuizCompleted'},
        }),
        throwsA(isA<SyncFailure>()),
      );
    });
  }
  // Remaining gap: UUID occurrence must agree with the immutable envelope.
  test('event UUID timestamp cannot contradict occurrence', () {
    final e = event('TodayExperiencePresented');
    expect(
      () => ResearchSyncContract.validate(
        collection: SyncCollection.neutralEventsV2,
        entityId: e['eventId'] as String,
        revision: 1,
        isDeleted: false,
        payload: {
          'permitId': 'permit:a',
          'permitPayloadSha256': List.filled(64, 'a').join(),
          'permitRevision': 1,
          'envelope': {
            ...e,
            'occurredAtUtc': occurred
                .add(const Duration(milliseconds: 1))
                .toIso8601String(),
            'recordedAtUtc': occurred
                .add(const Duration(milliseconds: 1))
                .toIso8601String(),
          },
        },
      ),
      throwsA(isA<SyncFailure>()),
    );
  });
}
