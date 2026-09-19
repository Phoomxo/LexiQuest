import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';

import '../../support/motivation_research_fixture.dart';
import '../../support/pair_purpose_fixture.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';

void main() {
  late MotivationResearchFixture f;
  late _Receipts receipts;
  late ResearchParticipationPermitValidator validator;
  late DriftResearchParticipationRepository participation;
  late DriftResearchSyncAuthorizer authorizer;
  late DriftOwnerOperationGate gate;
  late ResearchParticipationPermit permit;
  const token = 'synthetic-sync-gate';

  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize(enroll: false);
    receipts = _Receipts();
    validator = ResearchParticipationPermitValidator(
      protocolId: f.study.protocolId,
      protocolVersion: f.study.protocolVersion,
      signatures: _verifier,
      receipts: receipts,
    );
    participation = DriftResearchParticipationRepository(
      f.database,
      study: f.study,
      validator: validator,
      nowUtc: () => f.now,
    );
    authorizer = DriftResearchSyncAuthorizer(
      database: f.database,
      study: f.study,
      validator: validator,
      nowUtc: () => f.now,
    );
    permit = _signed(f.permit());
    await participation.importPermit(permit);
    await f.database.customUpdate(
      "UPDATE local_owners SET firebase_uid = 'uid-a', account_state = 'signedIn' WHERE id = 'owner:a'",
    );
    gate = DriftOwnerOperationGate(f.database);
    expect(
      await gate.tryAcquire(
        token: token,
        nowUtc: f.now,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );
  });
  tearDown(() => f.database.close());

  ResearchSyncRequest request({
    ResearchSyncPhase phase = ResearchSyncPhase.enqueue,
    SyncCollection collection = SyncCollection.researchParticipationPermits,
    Map<String, Object?>? payload,
    String? id,
    String owner = 'owner:a',
    String uid = 'uid-a',
    String? gateToken = token,
    SyncServerReadProvenance? serverReadProvenance,
  }) => ResearchSyncRequest(
    phase: phase,
    ownerId: owner,
    firebaseUid: uid,
    collection: collection,
    entityId: id ?? (payload?['id'] as String?) ?? permit.id,
    payload: payload ?? ResearchSyncContract.permitPayload(permit),
    evaluatedAtUtc: f.now,
    ownerGateToken: gateToken,
    serverReadProvenance: serverReadProvenance,
  );

  String runId() => f.measurements.runIdFor('owner:a', permit.id);
  Map<String, Object?> run([Map<String, Object?> changes = const {}]) => {
    ...ResearchSyncContract.reference(permit),
    'id': runId(),
    'ownerId': 'owner:a',
    'assignmentId': f.assignmentId,
    'consentVersion': 1,
    'consentDecidedAtUtcMs': DateTime.utc(
      2026,
      9,
      5,
      10,
    ).millisecondsSinceEpoch,
    'protocolId': f.study.protocolId,
    'protocolVersion': f.study.protocolVersion,
    'treatment': 'adventure',
    'instrumentId': f.instrument.instrumentId,
    'instrumentVersion': f.instrument.instrumentVersion,
    'formId': f.instrument.formId,
    'formVersion': f.instrument.formVersion,
    'appVersion': f.study.appVersion,
    'buildId': f.study.buildId,
    'databaseSchemaVersion': AppDatabase.currentSchemaVersion,
    'contentRevision': f.study.contentRevision,
    'evidencePolicyVersion': f.study.evidencePolicyVersion,
    'state': 'started',
    'startedAtUtcMs': f.now.millisecondsSinceEpoch - 1000,
    'closedAtUtcMs': null,
    ...changes,
  };
  Map<String, Object?> response([Map<String, Object?> changes = const {}]) => {
    ...ResearchSyncContract.reference(permit),
    'id':
        'response:${sha256.convert(utf8.encode(jsonEncode([runId(), 'baseline'])))}',
    'ownerId': 'owner:a',
    'runId': runId(),
    'itemId': 'baseline',
    'itemCatalogVersion': f.instrument.itemCatalogVersion,
    'responseCode': 'low',
    'ordinalValue': 1,
    'answeredAtUtcMs': f.now.millisecondsSinceEpoch - 500,
    ...changes,
  };
  Future<void> seed(String table, Map<String, Object?> payload) =>
      _insert(f.database, table, {
        for (final e in payload.entries)
          if (!ResearchSyncContract.referenceKeys.contains(e.key))
            _snake(e.key): e.value,
      });
  Future<void> seedRun([Map<String, Object?> changes = const {}]) =>
      seed('motivation_measurement_runs', run(changes));
  Future<bool> pullPermit(ResearchParticipationPermit p) =>
      authorizer.authorize(
        request(
          phase: ResearchSyncPhase.pull,
          payload: ResearchSyncContract.permitPayload(p),
        ),
      );
  const attempt = '00000000-0000-4000-8000-000000000001';
  String opportunityId() =>
      'opportunity:${sha256.convert(utf8.encode(jsonEncode(['owner:a', runId(), permit.id, attempt])))}';
  Map<String, Object?> opportunity([Map<String, Object?> changes = const {}]) =>
      {
        ...ResearchSyncContract.reference(permit),
        'id': opportunityId(),
        'ownerId': 'owner:a',
        'measurementRunId': runId(),
        'entryAttemptId': attempt,
        'assignedTreatment': 'adventure',
        'effectivePresentation': 'standard',
        'presentedEventId': null,
        'learningSessionId': null,
        'startedEventId': null,
        'completedEventId': null,
        'lastSwitchOrdinal': 0,
        'suppressedSwitchCount': 0,
        'openedAtUtcMs': f.now.millisecondsSinceEpoch - 600,
        'closedAtUtcMs': null,
        ...changes,
      };
  Future<void> seedOpportunity([Map<String, Object?> changes = const {}]) =>
      _insert(f.database, 'measurement_opportunities', {
        for (final e in opportunity(changes).entries)
          if (!ResearchSyncContract.referenceKeys.contains(e.key))
            _snake(e.key): e.value,
        'permit_id': permit.id,
      });
  EventEnvelopeV2 event(String type) {
    final occurred = f.now.subtract(const Duration(milliseconds: 477));
    final ordinal = type == 'TodayExperiencePresentationChanged' ? 1 : 0;
    final identity =
        'research:${sha256.convert(utf8.encode(jsonEncode([opportunityId(), type, ordinal])))}';
    final mission = type.contains('Mission');
    return EventEnvelopeV2(
      eventId: researchEventId(identity, occurred),
      eventType: type,
      eventVersion: 1,
      occurredAtUtc: occurred,
      recordedAtUtc: f.now,
      actorIdentity: 'owner:a',
      ownerIdentity: 'owner:a',
      aggregateType: mission ? 'LearningSession' : 'MeasurementOpportunity',
      aggregateId: mission ? 'session:a' : opportunityId(),
      correlationId: opportunityId(),
      idempotencyKey: identity,
      consentContext: const ConsentContext(
        researchConsentVersion: 1,
        aiConsentGranted: false,
        voiceConsentGranted: false,
        socialConsentGranted: false,
      ),
      experimentContext: ExperimentContext(
        experimentId: f.study.experimentId,
        variantId: 'adventure',
        assignedAtUtc: DateTime.utc(2026, 9, 5, 10, 30),
      ),
      contentRevision: f.study.contentRevision,
      policyVersion: f.study.evidencePolicyVersion,
      appVersion: f.study.appVersion,
      buildId: f.study.buildId,
      privacyClassification: PrivacyClassification.ownerOnly,
      payload: {
        'assignedTreatment': 'adventure',
        'effectivePresentation': 'standard',
        ...switch (type) {
          'TodayExperiencePresented' => {
            'entryAttemptId': attempt,
            'catalogVersion': f.study.catalogVersion,
          },
          'TodayExperiencePresentationChanged' => {
            'fromPresentation': 'adventure',
            'switchOrdinal': 1,
          },
          'TodayExperienceMissionStarted' => {
            'opportunityId': opportunityId(),
            'planId': 'plan:a',
            'mode': 'meaning-quiz',
          },
          _ => {
            'opportunityId': opportunityId(),
            'planId': 'plan:a',
            'terminalState': 'completed',
          },
        },
      },
    );
  }

  Future<void> seedEvent(EventEnvelopeV2 e) async {
    await f.database
        .into(f.database.eventsV2)
        .insert(
          EventsV2Companion.insert(
            eventId: e.eventId,
            eventType: e.eventType,
            eventVersion: 1,
            occurredAtUtc: e.occurredAtUtc,
            recordedAtUtc: e.recordedAtUtc,
            actorIdentity: e.actorIdentity,
            ownerId: e.ownerIdentity,
            aggregateType: e.aggregateType,
            aggregateId: e.aggregateId,
            correlationId: Value(e.correlationId),
            idempotencyKey: e.idempotencyKey,
            consentContextJson: jsonEncode(e.consentContext.toJson()),
            experimentContextJson: Value(
              jsonEncode(e.experimentContext!.toJson()),
            ),
            contentRevision: Value(e.contentRevision),
            policyVersion: Value(e.policyVersion),
            appVersion: e.appVersion,
            buildId: e.buildId,
            privacyClassification: e.privacyClassification.name,
            payloadJson: jsonEncode(e.payload),
          ),
        );
  }

  Future<Map<String, Object?>> historical(SyncCollection collection) async {
    await seedRun();
    Map<String, Object?> payload;
    if (collection == SyncCollection.motivationMeasurementRuns) {
      payload = run();
    } else if (collection == SyncCollection.motivationResponses) {
      payload = response();
      await seed('motivation_responses', payload);
    } else if (collection == SyncCollection.measurementOpportunities) {
      await seedOpportunity();
      payload = opportunity();
    } else {
      final e = event('TodayExperiencePresented');
      await seedOpportunity({'presentedEventId': e.eventId});
      await seedEvent(e);
      payload = {
        ...ResearchSyncContract.reference(permit),
        'envelope': e.toJson(),
      };
    }
    final id = collection == SyncCollection.neutralEventsV2
        ? (payload['envelope']! as Map)['eventId']! as String
        : payload['id']! as String;
    // Synthetic durable history of the exact wrapper previously authorized for
    // enqueue. Integration tests below use the real enqueue path instead.
    final op =
        'research-sync:${ResearchSyncContract.fingerprint({'collection': collection.wireName, 'id': id, 'payload': payload})}:1';
    await f.database
        .into(f.database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: op,
            ownerId: 'owner:a',
            entityId: id,
            entityType: collection == SyncCollection.neutralEventsV2
                ? (payload['envelope']! as Map)['eventType']! as String
                : collection.entityType,
            operationKind: 'upsert',
            createdAtUtcMs: f.now.millisecondsSinceEpoch,
          ),
        );
    await participation.importPermit(
      _signed(permit, {
        'localRevision': 2,
        'cloudRevision': 2,
        'expiresAtUtc': permit.expiresAtUtc
            .add(const Duration(days: 1))
            .toIso8601String(),
      }),
    );
    return payload;
  }

  ResearchSyncRequest historicalRequest(
    SyncCollection c,
    Map<String, Object?> payload, {
    ResearchSyncPhase phase = ResearchSyncPhase.pull,
    SyncServerReadProvenance? serverReadProvenance,
  }) => request(
    phase: phase,
    collection: c,
    payload: payload,
    serverReadProvenance: serverReadProvenance,
    id: c == SyncCollection.neutralEventsV2
        ? (payload['envelope']! as Map)['eventId']! as String
        : payload['id']! as String,
  );

  // Explicit synthetic authenticated-server boundary. Ordinary JSON decoding
  // and direct document import do not produce this process-local marker.
  SyncServerReadProvenance serverRead(
    SyncCollection c,
    Map<String, Object?> payload, {
    String uid = 'uid-a',
    String? id,
  }) => SyncEntity(
    collection: c,
    entityId:
        id ??
        (c == SyncCollection.neutralEventsV2
            ? (payload['envelope']! as Map)['eventId']! as String
            : payload['id']! as String),
    revision: 1,
    isDeleted: false,
    payloadVersion: 1,
    clientUpdatedAtUtc: f.now,
    serverUpdatedAtUtc: f.now,
    payload: payload,
  ).withServerReadProvenance(firebaseUid: uid).serverReadProvenance!;

  for (final c in [
    SyncCollection.motivationMeasurementRuns,
    SyncCollection.motivationResponses,
    SyncCollection.measurementOpportunities,
    SyncCollection.neutralEventsV2,
  ]) {
    test(
      'P2 authenticated same-UID server history restores unknown ${c.name}',
      () async {
        final old = await historical(c);
        await f.database.delete(f.database.outboxOperations).go();
        final table = switch (c) {
          SyncCollection.motivationMeasurementRuns =>
            'motivation_measurement_runs',
          SyncCollection.motivationResponses => 'motivation_responses',
          SyncCollection.measurementOpportunities =>
            'measurement_opportunities',
          _ => 'events_v2',
        };
        await f.database.customUpdate('DELETE FROM $table');
        expect(
          await authorizer.authorize(
            historicalRequest(c, old, serverReadProvenance: serverRead(c, old)),
          ),
          isTrue,
        );
      },
    );
  }
  test(
    'P2 server-admitted old hash is transport metadata not a fact signature',
    () async {
      final old = await historical(SyncCollection.motivationResponses);
      await f.database.delete(f.database.outboxOperations).go();
      await f.database.delete(f.database.motivationResponses).go();
      final admitted = {...old, 'permitPayloadSha256': 'a' * 64};
      expect(
        await authorizer.authorize(
          historicalRequest(
            SyncCollection.motivationResponses,
            admitted,
            serverReadProvenance: serverRead(
              SyncCollection.motivationResponses,
              admitted,
            ),
          ),
        ),
        isTrue,
      );
    },
  );
  for (final mismatch in ['uid', 'collection', 'id', 'payload']) {
    test('P2 server provenance rejects $mismatch mismatch', () async {
      final old = await historical(SyncCollection.motivationResponses);
      await f.database.delete(f.database.outboxOperations).go();
      final marker = serverRead(
        mismatch == 'collection'
            ? SyncCollection.motivationMeasurementRuns
            : SyncCollection.motivationResponses,
        mismatch == 'payload' ? {...old, 'permitPayloadSha256': 'b' * 64} : old,
        uid: mismatch == 'uid' ? 'other-uid' : 'uid-a',
        id: mismatch == 'id' ? 'other-id' : null,
      );
      expect(
        await authorizer.authorize(
          historicalRequest(
            SyncCollection.motivationResponses,
            old,
            serverReadProvenance: marker,
          ),
        ),
        isFalse,
      );
    });
  }
  for (final phase in [
    ResearchSyncPhase.enqueue,
    ResearchSyncPhase.claim,
    ResearchSyncPhase.push,
  ]) {
    test(
      'P2 server provenance never permits historical ${phase.name}',
      () async {
        final old = await historical(SyncCollection.motivationResponses);
        expect(
          await authorizer.authorize(
            historicalRequest(
              SyncCollection.motivationResponses,
              old,
              phase: phase,
              serverReadProvenance: serverRead(
                SyncCollection.motivationResponses,
                old,
              ),
            ),
          ),
          isFalse,
        );
      },
    );
  }
  for (final change in <Map<String, Object?>>[
    {'permitPayloadSha256': 'malformed'},
    {'permitRevision': 0},
    {'permitRevision': 3},
    {'permitId': 'different'},
    {'itemId': 'unknown'},
    {'ordinalValue': 5},
    {'itemCatalogVersion': 'wrong'},
    {'runId': 'other-run'},
    {'answeredAtUtcMs': 1},
    {'responseCode': 'high', 'ordinalValue': 5},
  ]) {
    test(
      'P2 trusted marker still rejects invalid or conflicting ${change.keys.first}',
      () async {
        final old = await historical(SyncCollection.motivationResponses);
        await f.database.delete(f.database.outboxOperations).go();
        final invalid = {...old, ...change};
        expect(
          await authorizer.authorize(
            historicalRequest(
              SyncCollection.motivationResponses,
              invalid,
              serverReadProvenance: serverRead(
                SyncCollection.motivationResponses,
                invalid,
              ),
            ),
          ),
          isFalse,
        );
      },
    );
  }
  for (final race in [
    'owner',
    'receipt',
    'withdrawn',
    'permit',
    'fence',
    'expiry',
  ]) {
    test(
      'P2 marked history rechecks current $race authority after await',
      () async {
        final old = await historical(SyncCollection.motivationResponses);
        await f.database.delete(f.database.outboxOperations).go();
        final marker = serverRead(SyncCollection.motivationResponses, old);
        receipts.onRead = () async {
          receipts.onRead = null;
          switch (race) {
            case 'owner':
              await f.database.customUpdate(
                "UPDATE local_owners SET firebase_uid = 'other'",
              );
            case 'receipt':
              receipts.active = false;
            case 'withdrawn':
              await f.database.customUpdate(
                "UPDATE research_consents SET consent_state = 'withdrawn'",
              );
            case 'permit':
              await f.database.customUpdate(
                "UPDATE research_participation_permits SET signature = 'forged'",
              );
            case 'fence':
              await gate.beginOwnerFence(
                ownerId: 'owner:a',
                token: token,
                nowUtc: f.now,
              );
            case 'expiry':
              f.now = f.now.add(const Duration(minutes: 5));
          }
        };
        expect(
          await authorizer.authorize(
            historicalRequest(
              SyncCollection.motivationResponses,
              old,
              serverReadProvenance: marker,
            ),
          ),
          isFalse,
        );
      },
    );
  }

  for (final c in [
    SyncCollection.motivationMeasurementRuns,
    SyncCollection.motivationResponses,
    SyncCollection.measurementOpportunities,
    SyncCollection.neutralEventsV2,
  ]) {
    test(
      'P2 known identical historical ${c.name} pull survives authentic renewal',
      () async {
        final old = await historical(c);
        expect(await authorizer.authorize(historicalRequest(c, old)), isTrue);
        final current = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(current.localRevision, 2);
        expect(current.payloadSha256, isNot(old['permitPayloadSha256']));
      },
    );
  }
  for (final phase in [
    ResearchSyncPhase.enqueue,
    ResearchSyncPhase.claim,
    ResearchSyncPhase.push,
  ]) {
    test('P2 historical refs never authorize new ${phase.name}', () async {
      final old = await historical(SyncCollection.motivationResponses);
      expect(
        await authorizer.authorize(
          historicalRequest(
            SyncCollection.motivationResponses,
            old,
            phase: phase,
          ),
        ),
        isFalse,
      );
    });
  }
  for (final change in <Map<String, Object?>>[
    {'permitPayloadSha256': '0' * 64},
    {'permitPayloadSha256': 'malformed'},
    {'permitRevision': 0},
    {'permitRevision': 3},
    {'permitId': 'different'},
    {'responseCode': 'high', 'ordinalValue': 5},
  ]) {
    test('P2 historical pull rejects forged ${change.keys.first}', () async {
      final old = await historical(SyncCollection.motivationResponses);
      expect(
        await authorizer.authorize(
          historicalRequest(SyncCollection.motivationResponses, {
            ...old,
            ...change,
          }),
        ),
        isFalse,
      );
    });
  }
  test(
    'P2 unmarked history without local admission proof stays denied',
    () async {
      final old = await historical(SyncCollection.motivationResponses);
      await f.database.delete(f.database.outboxOperations).go();
      expect(
        await authorizer.authorize(
          historicalRequest(SyncCollection.motivationResponses, old),
        ),
        isFalse,
      );
    },
  );
  test(
    'P2 known old refs without matching local fact cannot restore historical data',
    () async {
      final old = await historical(SyncCollection.motivationResponses);
      await f.database.delete(f.database.motivationResponses).go();
      expect(
        await authorizer.authorize(
          historicalRequest(SyncCollection.motivationResponses, old),
        ),
        isFalse,
      );
    },
  );
  for (final race in ['owner', 'receipt', 'withdrawn', 'permit']) {
    test(
      'P2 historical pull rechecks current $race authority after await',
      () async {
        final old = await historical(SyncCollection.motivationResponses);
        receipts.onRead = () async {
          receipts.onRead = null;
          switch (race) {
            case 'owner':
              await f.database.customUpdate(
                "UPDATE local_owners SET firebase_uid = 'other'",
              );
            case 'receipt':
              receipts.active = false;
            case 'withdrawn':
              await f.database.customUpdate(
                "UPDATE research_consents SET consent_state = 'withdrawn'",
              );
            case 'permit':
              await f.database.customUpdate(
                "UPDATE research_participation_permits SET signature = 'forged'",
              );
          }
        };
        expect(
          await authorizer.authorize(
            historicalRequest(SyncCollection.motivationResponses, old),
          ),
          isFalse,
        );
      },
    );
  }

  for (final phase in ResearchSyncPhase.values) {
    test(
      'ordinary owned Sync gate allows authentic permit at ${phase.name}',
      () async {
        expect(await authorizer.authorize(request(phase: phase)), isTrue);
      },
    );
    test('true owner-transition fence denies ${phase.name}', () async {
      await gate.beginOwnerFence(
        ownerId: 'owner:a',
        token: token,
        nowUtc: f.now,
      );
      expect(await authorizer.authorize(request(phase: phase)), isFalse);
    });
  }
  test(
    'gateway push with null token requires real active gate snapshot',
    () async {
      expect(
        await authorizer.authorize(
          request(phase: ResearchSyncPhase.push, gateToken: null),
        ),
        isTrue,
      );
      await gate.release(token: token);
      expect(
        await authorizer.authorize(
          request(phase: ResearchSyncPhase.push, gateToken: null),
        ),
        isFalse,
      );
    },
  );
  for (final phase in [
    ResearchSyncPhase.enqueue,
    ResearchSyncPhase.claim,
    ResearchSyncPhase.pull,
  ]) {
    test('missing supplied token denies ${phase.name}', () async {
      expect(
        await authorizer.authorize(request(phase: phase, gateToken: null)),
        isFalse,
      );
    });
  }
  test('token text alone and wrong token do not authorize', () async {
    expect(await authorizer.authorize(request(gateToken: 'wrong')), isFalse);
    await gate.release(token: token);
    expect(await authorizer.authorize(request()), isFalse);
  });
  test(
    'stale marker from another lease does not block ordinary Sync',
    () async {
      await gate.beginOwnerFence(
        ownerId: 'owner:a',
        token: token,
        nowUtc: f.now,
      );
      await gate.release(token: token);
      await gate.tryAcquire(
        token: 'next-gate',
        nowUtc: f.now,
        leaseDuration: const Duration(minutes: 5),
      );
      expect(
        await authorizer.authorize(request(gateToken: 'next-gate')),
        isTrue,
      );
    },
  );
  test(
    'owner Firebase uid and exactly-one-active-owner are mandatory',
    () async {
      expect(await authorizer.authorize(request(uid: 'uid-b')), isFalse);
      expect(await authorizer.authorize(request(owner: 'owner:b')), isFalse);
      await f.database
          .into(f.database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner:b', createdAtUtcMs: 1),
          );
      expect(await authorizer.authorize(request()), isFalse);
    },
  );

  for (final change in [
    'gateExpiry',
    'gateReplacement',
    'ownerFence',
    'ownerChange',
    'consentWithdrawal',
    'consentReaccept',
    'assignmentChange',
    'permitChange',
    'receiptLoss',
  ]) {
    test('rechecks $change after asynchronous authority lookup', () async {
      receipts.onRead = () async {
        receipts.onRead = null;
        switch (change) {
          case 'gateExpiry':
            f.now = f.now.add(const Duration(minutes: 5));
          case 'gateReplacement':
            await gate.release(token: token);
            await gate.tryAcquire(
              token: 'replacement',
              nowUtc: f.now,
              leaseDuration: const Duration(minutes: 5),
            );
          case 'ownerFence':
            await gate.beginOwnerFence(
              ownerId: 'owner:a',
              token: token,
              nowUtc: f.now,
            );
          case 'ownerChange':
            await f.database.customUpdate(
              "UPDATE local_owners SET firebase_uid = 'uid-b'",
            );
          case 'consentWithdrawal':
            await f.database.customUpdate(
              "UPDATE research_consents SET consent_state = 'withdrawn', withdrawn_at_utc_ms = ${f.now.millisecondsSinceEpoch}",
            );
          case 'consentReaccept':
            await f.database.customUpdate(
              'UPDATE research_consents SET decided_at_utc_ms = ${f.now.millisecondsSinceEpoch}',
            );
          case 'assignmentChange':
            await f.database.customUpdate(
              "UPDATE experiment_assignments SET cohort = 'standard'",
            );
          case 'permitChange':
            await f.database.customUpdate(
              "UPDATE research_participation_permits SET signature = 'forged'",
            );
          case 'receiptLoss':
            receipts.active = false;
        }
      };
      expect(await authorizer.authorize(request()), isFalse);
    });
  }
  test(
    'permit expiry crossing async lookup is denied even inside live gate',
    () async {
      await gate.release(token: token);
      permit = _signed(permit, {
        'expiresAtUtc': f.now.add(const Duration(seconds: 1)).toIso8601String(),
        'localRevision': 2,
        'cloudRevision': 2,
      });
      // Direct synthetic replacement avoids renewal policy: tests the boundary clock.
      await _replacePermit(f.database, permit);
      await gate.tryAcquire(
        token: token,
        nowUtc: f.now,
        leaseDuration: const Duration(minutes: 5),
      );
      receipts.onRead = () async {
        receipts.onRead = null;
        f.now = f.now.add(const Duration(seconds: 1));
      };
      expect(await authorizer.authorize(request()), isFalse);
    },
  );
  for (final version in <Object>[
    24,
    25,
    26,
    23,
    27,
    28,
    29,
    '27',
    27.0,
    '28',
    28.0,
    '25',
    25.0,
    25.5,
    '26',
    26.0,
    26.5,
  ]) {
    test(
      'research schema transport keeps explicit version $version (${version.runtimeType})',
      () {
        final payload = run({'databaseSchemaVersion': version});
        void validate() => ResearchSyncContract.validate(
          collection: SyncCollection.motivationMeasurementRuns,
          entityId: runId(),
          payload: payload,
          revision: 1,
          isDeleted: false,
        );
        expect(
          validate,
          version is int && const {24, 25, 26, 27, 28}.contains(version)
              ? returnsNormally
              : throwsA(isA<SyncFailure>()),
        );
        expect(payload['databaseSchemaVersion'], version);
      },
    );
  }
  test(
    'historical schema remains pinned and cannot authorize a current run',
    () async {
      final payload = run({'databaseSchemaVersion': 24});
      await seed('motivation_measurement_runs', payload);
      expect(
        await authorizer.authorize(
          request(
            collection: SyncCollection.motivationMeasurementRuns,
            payload: payload,
          ),
        ),
        isFalse,
      );
      expect(payload['databaseSchemaVersion'], 24);
      final stored = await f.database
          .customSelect(
            'SELECT database_schema_version FROM motivation_measurement_runs WHERE id = ?',
            variables: [Variable(runId())],
          )
          .getSingle();
      expect(stored.read<int>('database_schema_version'), 24);
    },
  );
  for (final state in ['started', 'completed', 'skipped', 'abandoned']) {
    test(
      'upload accepts $state run without requiring capture-active run',
      () async {
        final p = run({
          'state': state,
          'closedAtUtcMs': state == 'started'
              ? null
              : f.now.millisecondsSinceEpoch,
        });
        await seed('motivation_measurement_runs', p);
        expect(
          await authorizer.authorize(
            request(
              collection: SyncCollection.motivationMeasurementRuns,
              payload: p,
            ),
          ),
          isTrue,
        );
      },
    );
  }
  for (final pin in [
    'id',
    'assignmentId',
    'consentVersion',
    'consentDecidedAtUtcMs',
    'instrumentId',
    'instrumentVersion',
    'formId',
    'formVersion',
    'appVersion',
    'buildId',
    'contentRevision',
    'evidencePolicyVersion',
    'permitPayloadSha256',
    'permitRevision',
  ]) {
    test(
      'rejects run $pin conflict including otherwise canonical values',
      () async {
        await seedRun();
        final original = run()[pin];
        final p = run({
          pin: original is int
              ? original + 1
              : pin == 'permitPayloadSha256'
              ? '0' * 64
              : 'different',
        });
        expect(
          await authorizer.authorize(
            request(
              phase: ResearchSyncPhase.pull,
              collection: SyncCollection.motivationMeasurementRuns,
              payload: p,
            ),
          ),
          isFalse,
        );
      },
    );
  }
  test('withdrawn run cannot upload or be resurrected by pull', () async {
    await seedRun({
      'state': 'withdrawn',
      'closedAtUtcMs': f.now.millisecondsSinceEpoch,
    });
    for (final phase in ResearchSyncPhase.values) {
      expect(
        await authorizer.authorize(
          request(
            phase: phase,
            collection: SyncCollection.motivationMeasurementRuns,
            payload: run(),
          ),
        ),
        isFalse,
      );
    }
  });
  test('tombstoned parent denies child upload and pull', () async {
    await seedRun();
    await seed('motivation_responses', response());
    await f.database.customUpdate(
      'UPDATE motivation_measurement_runs SET is_deleted = 1',
    );
    for (final phase in [ResearchSyncPhase.push, ResearchSyncPhase.pull]) {
      expect(
        await authorizer.authorize(
          request(
            phase: phase,
            collection: SyncCollection.motivationResponses,
            payload: response(),
          ),
        ),
        isFalse,
      );
    }
  });
  test('valid actual coded response and ordinal upload', () async {
    await seedRun();
    await seed('motivation_responses', response());
    expect(
      await authorizer.authorize(
        request(
          collection: SyncCollection.motivationResponses,
          payload: response(),
        ),
      ),
      isTrue,
    );
  });
  for (final change in <Map<String, Object?>>[
    {'itemId': 'unknown'},
    {'responseCode': 'unknown'},
    {'ordinalValue': 5},
    {'itemCatalogVersion': 'unknown'},
    {'ownerId': 'owner:b'},
    {'runId': 'missing'},
    {'answeredAtUtcMs': 1},
    {'id': 'nondeterministic'},
  ]) {
    test('rejects invalid response ${change.keys.single}', () async {
      await seedRun();
      expect(
        await authorizer.authorize(
          request(
            phase: ResearchSyncPhase.pull,
            collection: SyncCollection.motivationResponses,
            payload: response(change),
          ),
        ),
        isFalse,
      );
    });
  }
  test('local run withdrawal during receipt lookup denies response', () async {
    await seedRun();
    await seed('motivation_responses', response());
    receipts.onRead = () async {
      receipts.onRead = null;
      await f.database.customUpdate(
        "UPDATE motivation_measurement_runs SET state = 'withdrawn', closed_at_utc_ms = ${f.now.millisecondsSinceEpoch}",
      );
    };
    expect(
      await authorizer.authorize(
        request(
          collection: SyncCollection.motivationResponses,
          payload: response(),
        ),
      ),
      isFalse,
    );
  });
  test(
    'new active signed pull authorizes enrollment with local consent only',
    () async {
      await f.database.delete(f.database.researchParticipationPermits).go();
      expect(await pullPermit(permit), isTrue);
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        isEmpty,
      );
    },
  );
  for (final deleted in [false, true]) {
    test(
      'unknown signed ${deleted ? 'deletion' : 'revocation'} never enrolls',
      () async {
        await f.database.delete(f.database.researchParticipationPermits).go();
        expect(
          await pullPermit(
            _signed(permit, {
              'localRevision': 2,
              'cloudRevision': 2,
              if (deleted)
                'isDeleted': true
              else
                'revokedAtUtc': f.now.toIso8601String(),
            }),
          ),
          isFalse,
        );
      },
    );
    test(
      'known newer signed ${deleted ? 'deletion' : 'revocation'} learns cutoff after withdrawal and expiry',
      () async {
        await seedRun({
          'state': 'withdrawn',
          'closedAtUtcMs': f.now.millisecondsSinceEpoch,
        });
        await f.database.customUpdate(
          "UPDATE research_consents SET consent_state = 'withdrawn', withdrawn_at_utc_ms = ${f.now.millisecondsSinceEpoch}",
        );
        receipts.active = false;
        await gate.release(token: token);
        f.now = permit.expiresAtUtc.add(const Duration(seconds: 1));
        await gate.tryAcquire(
          token: token,
          nowUtc: f.now,
          leaseDuration: const Duration(minutes: 5),
        );
        final cutoff = _signed(permit, {
          'localRevision': 2,
          'cloudRevision': 2,
          if (deleted)
            'isDeleted': true
          else
            'revokedAtUtc': permit.expiresAtUtc.toIso8601String(),
        });
        expect(await pullPermit(cutoff), isTrue);
      },
    );
  }
  test(
    'newer active renewal preserves immutable pins and requires receipts',
    () async {
      final next = _signed(permit, {
        'localRevision': 2,
        'cloudRevision': 2,
        'expiresAtUtc': permit.expiresAtUtc
            .add(const Duration(days: 1))
            .toIso8601String(),
      });
      expect(await pullPermit(next), isTrue);
      receipts.active = false;
      expect(await pullPermit(next), isFalse);
    },
  );
  for (final change in <Map<String, Object?>>[
    {'consentReceiptId': 'other'},
    {'issuedAtUtc': DateTime.utc(2026, 9, 5, 11, 1).toIso8601String()},
    {'ageBandCode': 'other'},
    {'assignmentId': 'other'},
    {'assignedTreatment': 'standard'},
    {'ownerId': 'owner:b'},
    {'protocolVersion': '2'},
  ]) {
    test(
      'genuine signed update cannot alter immutable ${change.keys.single}',
      () async {
        expect(
          await pullPermit(
            _signed(permit, {
              'localRevision': 2,
              'cloudRevision': 2,
              'revokedAtUtc': f.now.toIso8601String(),
              ...change,
            }),
          ),
          isFalse,
        );
      },
    );
  }
  test(
    'revocation replay safe, stale update denied, signed state cannot resurrect',
    () async {
      final revoked = _signed(permit, {
        'localRevision': 2,
        'cloudRevision': 2,
        'revokedAtUtc': f.now.toIso8601String(),
      });
      await _replacePermit(f.database, revoked);
      expect(await pullPermit(revoked), isTrue);
      expect(await pullPermit(permit), isFalse);
      expect(
        await pullPermit(
          _signed(permit, {'localRevision': 3, 'cloudRevision': 3}),
        ),
        isFalse,
      );
    },
  );
  test(
    'forged signature and non-positive or mismatched signed revisions deny',
    () async {
      for (final p in <Map<String, Object?>>[
        {
          ...ResearchSyncContract.permitPayload(permit),
          'signature': base64Encode(List.filled(64, 0)),
        },
        {...ResearchSyncContract.permitPayload(permit), 'localRevision': 0},
        {...ResearchSyncContract.permitPayload(permit), 'cloudRevision': 2},
        {...ResearchSyncContract.permitPayload(permit), 'unexpected': 'field'},
        {
          ...ResearchSyncContract.permitPayload(permit),
          'signature': 'x' * 17000,
        },
      ]) {
        expect(
          await authorizer.authorize(
            request(phase: ResearchSyncPhase.pull, payload: p),
          ),
          isFalse,
        );
      }
    },
  );
  test(
    'minor pull requires independently active guardian and assent',
    () async {
      await f.database.delete(f.database.researchParticipationPermits).go();
      final minor = _signed(permit, {
        'participantClass': 'minor',
        'ageBandCode': 'minor',
        'guardianPermissionReceiptRef': 'guardian:a',
        'learnerAssentReceiptRef': 'assent:a',
      });
      expect(await pullPermit(minor), isTrue);
      receipts.deniedKind = ResearchReceiptKind.learnerAssent;
      expect(await pullPermit(minor), isFalse);
      receipts.deniedKind = ResearchReceiptKind.guardianPermission;
      expect(await pullPermit(minor), isFalse);
    },
  );
  test(
    'missing trusted issuer cannot enroll even with valid mathematical signature',
    () async {
      await f.database.delete(f.database.researchParticipationPermits).go();
      final unknownIssuer = _signed(permit, {
        'issuerKeyId': 'untrusted-issuer',
      });
      expect(await pullPermit(unknownIssuer), isFalse);
    },
  );
  test('asynchronous receipt authority outage denies without writes', () async {
    receipts.onRead = () async {
      throw StateError('Synthetic authority unavailable');
    };
    expect(await authorizer.authorize(request()), isFalse);
  });
  test(
    'equal revision signed conflicting cutoff and revoked cutoff extension deny',
    () async {
      expect(
        await pullPermit(
          _signed(permit, {'revokedAtUtc': f.now.toIso8601String()}),
        ),
        isFalse,
      );
      final revoked = _signed(permit, {
        'localRevision': 2,
        'cloudRevision': 2,
        'revokedAtUtc': f.now.toIso8601String(),
      });
      await _replacePermit(f.database, revoked);
      expect(
        await pullPermit(
          _signed(revoked, {
            'localRevision': 3,
            'cloudRevision': 3,
            'revokedAtUtc': f.now
                .add(const Duration(seconds: 1))
                .toIso8601String(),
          }),
        ),
        isFalse,
      );
    },
  );
  test(
    'local response replacement during receipt lookup denies stale push',
    () async {
      await seedRun();
      await seed('motivation_responses', response());
      receipts.onRead = () async {
        receipts.onRead = null;
        await f.database.customUpdate(
          "UPDATE motivation_responses SET response_code = 'high', ordinal_value = 5",
        );
      };
      expect(
        await authorizer.authorize(
          request(
            collection: SyncCollection.motivationResponses,
            payload: response(),
          ),
        ),
        isFalse,
      );
    },
  );
  test(
    'withdrawal/reaccept cannot reimport old permit or restore old capture',
    () async {
      await seedRun({
        'state': 'withdrawn',
        'closedAtUtcMs': f.now.millisecondsSinceEpoch,
      });
      await f.database.customUpdate(
        'UPDATE research_consents SET decided_at_utc_ms = ${f.now.millisecondsSinceEpoch}',
      );
      expect(await pullPermit(permit), isFalse);
    },
  );
  test(
    'authorizer performs no writes even on valid and invalid requests',
    () async {
      final before =
          (await f.database
                  .customSelect('SELECT total_changes() AS n')
                  .getSingle())
              .read<int>('n');
      expect(await authorizer.authorize(request()), isTrue);
      expect(await authorizer.authorize(request(uid: 'different')), isFalse);
      final after =
          (await f.database
                  .customSelect('SELECT total_changes() AS n')
                  .getSingle())
              .read<int>('n');
      expect(after, before);
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );
  test(
    'nonparticipant denial creates zero research rows events or queue jobs',
    () async {
      await f.database.delete(f.database.researchParticipationPermits).go();
      final before =
          (await f.database
                  .customSelect('SELECT total_changes() AS n')
                  .getSingle())
              .read<int>('n');
      expect(await authorizer.authorize(request()), isFalse);
      final after =
          (await f.database
                  .customSelect('SELECT total_changes() AS n')
                  .getSingle())
              .read<int>('n');
      expect(after, before);
      expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
      expect(
        await f.database.select(f.database.motivationMeasurementRuns).get(),
        isEmpty,
      );
    },
  );
  test('valid unexposed denominator opportunity uploads', () async {
    await seedRun();
    await seedOpportunity();
    expect(
      await authorizer.authorize(
        request(
          collection: SyncCollection.measurementOpportunities,
          payload: opportunity(),
        ),
      ),
      isTrue,
    );
  });
  for (final change in <Map<String, Object?>>[
    {'measurementRunId': 'missing'},
    {'id': 'wrong-id'},
    {'assignedTreatment': 'standard'},
    {'ownerId': 'owner:b'},
    {'openedAtUtcMs': 1},
    {'learningSessionId': 'missing'},
    {'permitRevision': 2},
  ]) {
    test(
      'opportunity validates ${change.keys.single} parent and immutable pins',
      () async {
        await seedRun();
        await seedOpportunity();
        expect(
          await authorizer.authorize(
            request(
              phase: ResearchSyncPhase.pull,
              collection: SyncCollection.measurementOpportunities,
              payload: opportunity(change),
            ),
          ),
          isFalse,
        );
      },
    );
  }
  test('opportunity closed locally cannot reopen on pull', () async {
    await seedRun();
    await seedOpportunity({'closedAtUtcMs': f.now.millisecondsSinceEpoch});
    expect(
      await authorizer.authorize(
        request(
          phase: ResearchSyncPhase.pull,
          collection: SyncCollection.measurementOpportunities,
          payload: opportunity(),
        ),
      ),
      isFalse,
    );
  });
  for (final mutation in ['none', 'payload', 'insert', 'delete-all']) {
    test(
      'tracked normal Pair mission checkpoints across external await: $mutation',
      () async {
        await seedRun();
        final base = event('TodayExperienceMissionStarted');
        final id = await seedSyntheticReplayPurpose(
          f.database,
          owner: 'owner:a',
          at: base.occurredAtUtc,
          appVersion: f.study.appVersion,
          buildId: f.study.buildId,
          purpose: PairSessionPurpose.learning,
        );
        final e = EventEnvelopeV2.fromJson({
          ...base.toJson(),
          'aggregateId': id,
        });
        final presented = event('TodayExperiencePresented');
        await seedOpportunity({
          'presentedEventId': presented.eventId,
          'learningSessionId': id,
          'startedEventId': e.eventId,
        });
        await seedEvent(presented);
        await seedEvent(e);
        var observed = false;
        receipts.onRead = () async {
          receipts.onRead = null;
          observed = true;
          if (mutation == 'payload') {
            await f.database.customStatement(
              "UPDATE events_v2 SET payload_json='{}' WHERE event_type='LearningActivityCheckpoint'",
            );
          }
          if (mutation == 'delete-all') {
            await f.database.customStatement(
              "DELETE FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
            );
          }
          if (mutation == 'insert') {
            await f.database.customStatement(
              "INSERT INTO events_v2 (event_id,event_type,event_version,occurred_at_utc,recorded_at_utc,actor_identity,owner_id,aggregate_type,aggregate_id,idempotency_key,consent_context_json,app_version,build_id,privacy_classification,payload_json) SELECT 'learning-activity-checkpoint:synthetic-insertion',event_type,event_version,occurred_at_utc,recorded_at_utc,actor_identity,owner_id,aggregate_type,aggregate_id,'synthetic-insertion',consent_context_json,app_version,build_id,privacy_classification,payload_json FROM events_v2 WHERE event_type='LearningActivityCheckpoint'",
            );
          }
        };
        expect(
          await authorizer.authorize(
            request(
              collection: SyncCollection.neutralEventsV2,
              id: e.eventId,
              payload: {
                ...ResearchSyncContract.reference(permit),
                'envelope': e.toJson(),
              },
            ),
          ),
          mutation == 'none',
        );
        expect(
          observed,
          true,
          reason: 'must cross genuine external authority await',
        );
      },
    );
  }
  test(
    'seeded replay mission event cannot upload despite valid permit and linkage',
    () async {
      await seedRun();
      final base = event('TodayExperienceMissionStarted');
      final id = await seedSyntheticReplayPurpose(
        f.database,
        owner: 'owner:a',
        at: base.occurredAtUtc,
        appVersion: f.study.appVersion,
        buildId: f.study.buildId,
      );
      final e = EventEnvelopeV2.fromJson({...base.toJson(), 'aggregateId': id});
      final presented = event('TodayExperiencePresented');
      await seedOpportunity({
        'presentedEventId': presented.eventId,
        'learningSessionId': id,
        'startedEventId': e.eventId,
      });
      await seedEvent(presented);
      await seedEvent(e);
      expect(
        await authorizer.authorize(
          request(
            collection: SyncCollection.neutralEventsV2,
            id: e.eventId,
            payload: {
              ...ResearchSyncContract.reference(permit),
              'envelope': e.toJson(),
            },
          ),
        ),
        isFalse,
      );
    },
  );
  for (final type in ResearchSyncContract.eventTypes) {
    test(
      'actual neutral event $type uploads with UUIDv7 exact milliseconds',
      () async {
        await seedRun();
        final e = event(type);
        final mission = type.contains('Mission');
        final presented = event('TodayExperiencePresented');
        final started = event('TodayExperienceMissionStarted');
        if (mission) {
          await f.database
              .into(f.database.learningSessions)
              .insert(
                LearningSessionsCompanion.insert(
                  id: 'session:a',
                  ownerId: 'owner:a',
                  activityType: 'meaning-quiz',
                  state: type.endsWith('Completed') ? 'completed' : 'active',
                  startedAtUtcMs: e.occurredAtUtc.millisecondsSinceEpoch,
                  endedAtUtcMs: type.endsWith('Completed')
                      ? Value(e.occurredAtUtc.millisecondsSinceEpoch)
                      : const Value.absent(),
                  appVersion: f.study.appVersion,
                  buildId: f.study.buildId,
                ),
              );
        }
        await seedOpportunity({
          'presentedEventId': presented.eventId,
          if (type == 'TodayExperiencePresentationChanged')
            'lastSwitchOrdinal': 1,
          if (mission) 'learningSessionId': 'session:a',
          if (mission) 'startedEventId': started.eventId,
          if (type.endsWith('Completed')) 'completedEventId': e.eventId,
          if (type.endsWith('Completed'))
            'closedAtUtcMs': e.occurredAtUtc.millisecondsSinceEpoch,
        });
        if (type != 'TodayExperiencePresented') await seedEvent(presented);
        if (type.endsWith('Completed')) await seedEvent(started);
        await seedEvent(e);
        final stored = await (f.database.select(
          f.database.eventsV2,
        )..where((row) => row.eventId.equals(e.eventId))).getSingle();
        expect(stored.occurredAtUtc.millisecondsSinceEpoch % 1000, 0);
        expect(
          await authorizer.authorize(
            request(
              collection: SyncCollection.neutralEventsV2,
              id: e.eventId,
              payload: {
                ...ResearchSyncContract.reference(permit),
                'envelope': e.toJson(),
              },
            ),
          ),
          isTrue,
        );
      },
    );
  }
  for (final field in [
    'catalogVersion',
    'contentRevision',
    'policyVersion',
    'experimentContext',
    'occurredAtUtc',
    'correlationId',
    'eventType',
  ]) {
    test(
      'neutral event rejects $field conflict without relaxing frozen envelope',
      () async {
        await seedRun();
        final e = event('TodayExperiencePresented');
        await seedOpportunity({'presentedEventId': e.eventId});
        await seedEvent(e);
        final envelope = e.toJson();
        if (field == 'catalogVersion') {
          envelope['payload'] = {...e.payload, 'catalogVersion': 'wrong'};
        } else if (field == 'experimentContext') {
          envelope[field] = {
            ...e.experimentContext!.toJson(),
            'variantId': 'standard',
          };
        } else if (field == 'occurredAtUtc') {
          envelope[field] = e.occurredAtUtc
              .add(const Duration(milliseconds: 1))
              .toIso8601String();
        } else {
          envelope[field] = 'wrong';
        }
        expect(
          await authorizer.authorize(
            request(
              phase: ResearchSyncPhase.pull,
              collection: SyncCollection.neutralEventsV2,
              id: e.eventId,
              payload: {
                ...ResearchSyncContract.reference(permit),
                'envelope': envelope,
              },
            ),
          ),
          isFalse,
        );
      },
    );
  }
}

// Public, deterministic NON-PRODUCTION P-256 key, confined to this test file.
final _curve = ECCurve_secp256r1();
final _private = ECPrivateKey(BigInt.one, _curve);
final _verifier = ResearchP256SignatureVerifier(
  publicKeysSec1Hex: {
    'sync-synthetic': _curve.G
        .getEncoded(false)
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join(),
  },
);
ResearchParticipationPermit _signed(
  ResearchParticipationPermit source, [
  Map<String, Object?> changes = const {},
]) {
  final canonical = <String, Object?>{
    ...jsonDecode(source.canonicalPayload()) as Map<String, dynamic>,
    'issuerKeyId': 'sync-synthetic',
    ...changes,
  };
  final bytes = utf8.encode(jsonEncode(canonical));
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
  final s = signer.generateSignature(bytes) as ECSignature;
  final hex =
      '${s.r.toRadixString(16).padLeft(64, '0')}${s.s.toRadixString(16).padLeft(64, '0')}';
  return ResearchSyncContract.permitFromPayload({
    ...canonical,
    'payloadSha256': sha256.convert(bytes).toString(),
    'signature': base64Encode([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]),
  });
}

final class _Receipts implements ResearchReceiptAuthority {
  bool active = true;
  ResearchReceiptKind? deniedKind;
  Future<void> Function()? onRead;
  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    final captured = active && kind != deniedKind && ownerId == 'owner:a';
    await onRead?.call();
    return captured;
  }
}

String _snake(String key) =>
    key.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');
Future<void> _insert(
  AppDatabase db,
  String table,
  Map<String, Object?> data,
) async {
  await db.customInsert(
    'INSERT INTO $table (${data.keys.join(',')}) VALUES (${List.filled(data.length, '?').join(',')})',
    variables: [
      for (final value in data.values)
        switch (value) {
          String v => Variable<String>(v),
          int v => Variable<int>(v),
          bool v => Variable<int>(v ? 1 : 0),
          null => const Variable<String>(null),
          _ => throw StateError('Synthetic fixture scalar expected'),
        },
    ],
  );
}

Future<void> _replacePermit(
  AppDatabase db,
  ResearchParticipationPermit p,
) async {
  await db.customUpdate(
    'UPDATE research_participation_permits SET expires_at_utc_ms = ?, revoked_at_utc_ms = ?, is_deleted = ?, local_revision = ?, cloud_revision = ?, payload_sha256 = ?, signature = ? WHERE id = ?',
    variables: [
      Variable(p.expiresAtUtc.millisecondsSinceEpoch),
      Variable(p.revokedAtUtc?.millisecondsSinceEpoch),
      Variable(p.isDeleted ? 1 : 0),
      Variable(p.localRevision),
      Variable(p.cloudRevision),
      Variable(p.payloadSha256),
      Variable(p.signature),
      Variable(p.id),
    ],
  );
}
