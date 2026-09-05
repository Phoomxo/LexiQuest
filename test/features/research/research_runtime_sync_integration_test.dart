import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:pointycastle/api.dart';
import 'package:pointycastle/digests/sha256.dart';
import 'package:pointycastle/ecc/api.dart';
import 'package:pointycastle/ecc/curves/secp256r1.dart';
import 'package:pointycastle/macs/hmac.dart';
import 'package:pointycastle/signers/ecdsa_signer.dart';
import 'package:vocab_learning_app/config/adventure_research_runtime_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/research/application/adventure_research_runtime.dart';
import 'package:vocab_learning_app/features/research/application/research_participation_permit_validator.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_participation_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/data/research_p256_signature_verifier.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';

import '../../support/motivation_research_fixture.dart';

const _owner = 'owner:a';
const _uid = 'runtime-sync-synthetic-uid';
const _token = 'runtime-sync-integration-gate';
const _attempt = '11111111-1111-4111-8111-111111111111';
const _rollout = ResearchMeasurementSyncRollout.localEmulatorV1(
  deployedRulesRevision: researchMeasurementV1RulesRevision,
);

// New integration evidence against existing production components, not a claim
// of preimplementation RED. Only receipt/network boundaries are synthetic.
void main() {
  late MotivationResearchFixture f;
  late _SyntheticReceipts receipts;
  late AdventureResearchRuntime runtime;
  late DriftResearchSyncAuthorizer authorizer;
  late DriftSyncStore store;
  late DriftOwnerOperationGate gate;
  late ResearchParticipationPermit permit;
  final notifications = <int>[];

  DriftSyncStore newStore() => DriftSyncStore(
    f.database,
    researchMeasurementRollout: _rollout,
    researchAuthorizer: authorizer.authorize,
  );

  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize(enroll: false);
    await (f.database.update(f.database.localOwners)
          ..where((row) => row.id.equals(_owner)))
        .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
    receipts = _SyntheticReceipts();
    notifications.clear();
    runtime = AdventureResearchRuntime.fromConfig(
      f.database,
      AdventureResearchRuntimeConfig.configured(
        study: f.study,
        issuerPublicKeys: _publicKeys,
        receipts: receipts,
      ),
      nowUtc: () => f.now,
      onLocalMutation: (ownerId) async {
        expect(ownerId, _owner);
        notifications.add(
          await store.enqueueResearchForOwner(ownerId: ownerId, nowUtc: f.now),
        );
      },
    )!;
    authorizer = DriftResearchSyncAuthorizer(
      database: f.database,
      study: f.study,
      validator: runtime.participation.validator,
      nowUtc: () => f.now,
    );
    store = newStore();
    gate = DriftOwnerOperationGate(f.database);
    permit = _signed(f.permit());
  });
  tearDown(() => f.database.close());

  void tick([int milliseconds = 137]) {
    f.now = f.now.add(Duration(milliseconds: milliseconds));
  }

  Future<void> importPermit([ResearchParticipationPermit? value]) =>
      runtime.importDocument(
        _owner,
        jsonEncode(ResearchSyncContract.permitPayload(value ?? permit)),
      );
  Future<List<ClaimedSyncOperation>> claim({
    bool acquire = true,
    DriftSyncStore? from,
  }) async {
    if (acquire) {
      expect(
        await gate.tryAcquire(
          token: _token,
          nowUtc: f.now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
    }
    return (from ?? store).claimPending(
      ownerId: _owner,
      firebaseUid: _uid,
      limit: 50,
      leaseToken: 'integration-claims',
      ownerGateToken: _token,
      leaseDuration: const Duration(minutes: 2),
      nowUtc: f.now,
    );
  }

  Future<({String runId, String opportunityId})> capture({
    TodayExperiencePresentation presentation =
        TodayExperiencePresentation.adventure,
  }) async {
    await importPermit();
    tick();
    final run = await runtime.useCases.prepare(
      ownerId: _owner,
      permitId: permit.id,
    );
    expect(
      run,
      isNotNull,
      reason: 'real signed config must allow runtime prepare',
    );
    tick();
    await runtime.useCases.record(
      MotivationResponse(
        ownerId: _owner,
        runId: run!.id,
        itemId: 'baseline',
        responseCode: 'high',
      ),
    );
    tick();
    final opened = await runtime.useCases.open(
      ownerId: _owner,
      runId: run.id,
      entryAttemptId: _attempt,
      presentation: presentation,
    );
    expect(opened, isNotNull);
    tick();
    await runtime.useCases.recordPresented(_owner, opened!.id);
    return (runId: run.id, opportunityId: opened.id);
  }

  Future<bool> authorizePush(PushMutation mutation) => authorizer.authorize(
    ResearchSyncRequest(
      phase: ResearchSyncPhase.push,
      ownerId: _owner,
      firebaseUid: mutation.firebaseUid,
      collection: mutation.collection,
      entityId: mutation.entityId,
      payload: mutation.payload,
      ownerGateToken: mutation.ownerGateToken,
      evaluatedAtUtc: f.now,
    ),
  );
  Future<void> checkDelivery(
    List<ClaimedSyncOperation> claims, {
    ResearchParticipationPermit? expectedPermit,
  }) async {
    final p = expectedPermit ?? permit;
    expect(
      claims.map((c) => c.mutation.collection).toSet(),
      ResearchSyncContract.collections.toSet(),
    );
    for (final c in claims) {
      final mutation = c.mutation;
      expect(mutation.firebaseUid, _uid);
      expect(mutation.ownerGateToken, _token);
      if (mutation.collection == SyncCollection.researchParticipationPermits) {
        expect(mutation.payload, ResearchSyncContract.permitPayload(p));
      } else {
        for (final ref in ResearchSyncContract.reference(p).entries) {
          expect(mutation.payload[ref.key], ref.value);
        }
      }
      final reserved = await store.beginAttempt(
        claim: c,
        ownerGateToken: _token,
        nowUtc: f.now,
      );
      expect(
        reserved,
        isNotNull,
        reason: 'real claim revalidation: ${mutation.collection.name}',
      );
      expect(reserved!.attemptCount, 1);
      var transactions = 0;
      // Exercise the real gateway preflight without constructing Firebase or
      // sending network traffic. The transaction sentinel is not authorization.
      final result = await const FirestoreSyncPreflight().beforeTransaction(
        collection: mutation.collection,
        payloadVersion: mutation.payloadVersion,
        payload: mutation.payload,
        entityId: mutation.entityId,
        firebaseUid: _uid,
        isDeleted: mutation.operationKind == SyncOperationKind.delete,
        clientUpdatedAtUtcMs:
            mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
        researchRevision: mutation.localRevision,
        researchMeasurementRollout: _rollout,
        authorizeResearchPush: () => authorizePush(mutation),
        beginTransaction: () async {
          transactions++;
          return 'local-preflight-only';
        },
      );
      expect(result, 'local-preflight-only');
      expect(transactions, 1);
      final wire = FirestoreSyncCodec.encodeEntity(
        mutation,
        serverTimestamp: Timestamp.fromDate(f.now),
      );
      expect(wire['payload'], mutation.payload);
    }
  }

  Future<ResearchParticipationPermitRow> storedPermit() =>
      f.database.select(f.database.researchParticipationPermits).getSingle();

  test(
    'configured factory uses genuine verifier and missing enrollment writes no research',
    () async {
      expect(
        runtime.participation.validator.signatures,
        isA<ResearchP256SignatureVerifier>(),
      );
      expect(
        AdventureResearchRuntime.fromConfig(
          f.database,
          const AdventureResearchRuntimeConfig.off(),
          nowUtc: () => f.now,
        ),
        isNull,
      );
      expect(
        await runtime.useCases.prepare(ownerId: _owner, permitId: permit.id),
        isNull,
      );
      expect(
        await store.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
        0,
      );
      expect(await claim(), isEmpty);
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        isEmpty,
      );
      expect(
        await f.database.select(f.database.motivationMeasurementRuns).get(),
        isEmpty,
      );
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        isEmpty,
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        isEmpty,
      );
      expect(await f.database.select(f.database.eventsV2).get(), isEmpty);
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
    },
  );

  test(
    'signed import and committed capture enqueue and deliver all five real payload collections',
    () async {
      final captured = await capture();
      expect(
        notifications,
        hasLength(5),
        reason: 'every runtime mutation reached real after-commit queue hook',
      );
      expect(
        notifications.fold<int>(0, (a, b) => a + b),
        greaterThanOrEqualTo(5),
      );
      final jobs = await f.database.select(f.database.outboxOperations).get();
      final pending = jobs.where((row) => row.state == 'pending');
      expect(
        pending
            .map(
              (row) =>
                  ResearchSyncContract.collectionForEntityType(row.entityType),
            )
            .toSet(),
        ResearchSyncContract.collections.toSet(),
        reason: 'must be queued before claim recovery scan',
      );
      final claims = await claim();
      expect(claims, hasLength(5));
      final response = claims.singleWhere(
        (c) => c.mutation.collection == SyncCollection.motivationResponses,
      );
      expect(response.mutation.payload['runId'], captured.runId);
      expect(response.mutation.payload['responseCode'], 'high');
      expect(response.mutation.payload['ordinalValue'], 5);
      final opportunity = claims.singleWhere(
        (c) => c.mutation.collection == SyncCollection.measurementOpportunities,
      );
      expect(opportunity.mutation.entityId, captured.opportunityId);
      expect(opportunity.mutation.payload['measurementRunId'], captured.runId);
      final event = claims.singleWhere(
        (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
      );
      final envelope = event.mutation.payload['envelope']! as Map;
      expect(envelope['correlationId'], captured.opportunityId);
      expect(envelope.keys, isNot(contains('permitId')));
      final localEvent = await f.database
          .select(f.database.eventsV2)
          .getSingle();
      expect(localEvent.occurredAtUtc.millisecondsSinceEpoch % 1000, 0);
      expect(
        envelope['occurredAtUtc'],
        researchEventOccurrence(
          localEvent.eventId,
          localEvent.occurredAtUtc,
        ).toIso8601String(),
      );
      await checkDelivery(claims);
      expect(
        ResearchSyncContract.permitPayload(permitFromRow(await storedPermit())),
        ResearchSyncContract.permitPayload(permit),
      );
    },
  );

  for (final presentation in TodayExperiencePresentation.values) {
    test(
      '${presentation.name} canonical completion and post deliver four neutral events with completed run',
      () async {
        final captured = await capture(presentation: presentation);
        var opportunity = await runtime.opportunities.load(
          _owner,
          captured.opportunityId,
        );
        tick();
        opportunity = await runtime.useCases.changePresentation(
          ownerId: _owner,
          opportunityId: captured.opportunityId,
          presentation: presentation == TodayExperiencePresentation.adventure
              ? TodayExperiencePresentation.standard
              : TodayExperiencePresentation.adventure,
          expectedRevision: opportunity!.localRevision,
        );
        tick();
        final config = SessionConfiguration.validated(
          schemaVersion: 1,
          policyVersion: sessionConfigurationPolicyVersion,
          ownerId: _owner,
          mode: LessonMode.meaningQuiz,
          itemCount: 2,
          direction: SessionDirection.forward,
          difficulty: SessionDifficulty.standard,
          hintBudget: 0,
          timing: const SessionTiming.timed(Duration(minutes: 2)),
          packIdentity: null,
          protocolId: 'standard',
          protocolVersion: '1',
          protocolLimitsIdentity: 'standard',
        );
        // Synthetic canonical learning input, not research-generated learning.
        await f.database
            .into(f.database.learningSessions)
            .insert(
              LearningSessionsCompanion.insert(
                id: 'session:canonical',
                ownerId: _owner,
                activityType: 'quiz',
                state: 'active',
                startedAtUtcMs: f.now.millisecondsSinceEpoch,
                appVersion: f.study.appVersion,
                buildId: f.study.buildId,
                sessionConfigurationIdentity: Value(config.contentIdentity),
                sessionConfigurationJson: Value(config.stableSerialization),
              ),
            );
        await runtime.useCases.reconcile(_owner);
        tick(60000);
        await (f.database.update(
          f.database.learningSessions,
        )..where((row) => row.id.equals('session:canonical'))).write(
          LearningSessionsCompanion(
            state: const Value('completed'),
            endedAtUtcMs: Value(f.now.millisecondsSinceEpoch),
          ),
        );
        final canonical = await f.database
            .select(f.database.learningSessions)
            .getSingle();
        await runtime.useCases.reconcile(_owner);
        tick();
        await runtime.useCases.record(
          MotivationResponse(
            ownerId: _owner,
            runId: captured.runId,
            itemId: 'post',
            responseCode: 'low',
          ),
        );
        await runtime.useCases.close(
          MotivationMeasurementClose(
            ownerId: _owner,
            runId: captured.runId,
            state: MotivationMeasurementRunState.completed,
          ),
        );
        final claims = await claim();
        final events = claims.where(
          (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
        );
        expect(
          events
              .map((c) => (c.mutation.payload['envelope']! as Map)['eventType'])
              .toSet(),
          ResearchSyncContract.eventTypes,
        );
        expect(
          claims.where(
            (c) => c.mutation.collection == SyncCollection.motivationResponses,
          ),
          hasLength(2),
        );
        expect(
          claims
              .singleWhere(
                (c) =>
                    c.mutation.collection ==
                    SyncCollection.motivationMeasurementRuns,
              )
              .mutation
              .payload['state'],
          'completed',
        );
        expect(claims, hasLength(9));
        await checkDelivery(claims);
        expect(
          await f.database.select(f.database.learningSessions).getSingle(),
          canonical,
        );
        expect(
          await f.database.select(f.database.answerAttempts).get(),
          isEmpty,
        );
        expect(
          await f.database.select(f.database.rewardTransactions).get(),
          isEmpty,
        );
      },
    );
  }

  test(
    'runtime withdrawal while all claims held blocks attempts and preserves signed evidence',
    () async {
      await capture();
      final claims = await claim();
      expect(claims, hasLength(5));
      final signedBefore = ResearchSyncContract.permitPayload(
        permitFromRow(await storedPermit()),
      );
      final responses = await f.database
          .select(f.database.motivationResponses)
          .get();
      final events = await f.database.select(f.database.eventsV2).get();
      tick();
      await runtime.withdraw(
        _owner,
      ); // ordinary owned Sync gate is not owner transition
      expect(
        notifications.last,
        0,
        reason:
            'busy gate postpones denial marker enqueue, never local withdrawal',
      );
      for (final c in claims) {
        expect(
          await store.beginAttempt(
            claim: c,
            ownerGateToken: _token,
            nowUtc: f.now,
          ),
          isNull,
        );
        expect(await authorizePush(c.mutation), isFalse);
        final op =
            await (f.database.select(f.database.outboxOperations)
                  ..where((row) => row.operationId.equals(c.localOperationId)))
                .getSingle();
        expect(op.attemptCount, 0);
      }
      expect(
        (await f.database
                .select(f.database.motivationMeasurementRuns)
                .getSingle())
            .state,
        'withdrawn',
      );
      expect(
        (await f.database
                .select(f.database.measurementOpportunities)
                .getSingle())
            .closedAtUtcMs,
        isNotNull,
      );
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        responses,
      );
      expect(await f.database.select(f.database.eventsV2).get(), events);
      expect(
        ResearchSyncContract.permitPayload(permitFromRow(await storedPermit())),
        signedBefore,
      );
      expect(await runtime.currentPermit(_owner), isNull);
      await gate.release(token: _token);
      receipts.active = false;
      f.now = permit.expiresAtUtc.add(const Duration(seconds: 1));
      final restarted = newStore();
      final readsBeforeRecovery = receipts.reads;
      expect(
        await restarted.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
        1,
      );
      expect(
        await restarted.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
        0,
      );
      final recovered = await claim(from: restarted);
      expect(recovered, hasLength(1));
      final denial = recovered.single;
      expect(denial.mutation.collection, SyncCollection.researchWithdrawals);
      expect(denial.mutation.payload, {
        'permitId': permit.id,
        'ownerId': _owner,
      });
      expect(
        receipts.reads,
        readsBeforeRecovery,
        reason: 'deny-only recovery must not require active authority',
      );
      final reserved = await restarted.beginAttempt(
        claim: denial,
        ownerGateToken: _token,
        nowUtc: f.now,
      );
      expect(reserved, isNotNull);
      expect(
        await restarted.markRetry(
          operationId: denial.localOperationId,
          leaseToken: denial.leaseToken,
          ownerGateToken: _token,
          nowUtc: f.now,
          nextAttemptAtUtc: f.now,
          failure: const OfflineSyncFailure(),
        ),
        isTrue,
      );
      final retry = (await claim(acquire: false, from: newStore())).single;
      expect(retry.localOperationId, denial.localOperationId);
      final ack = acknowledgeResearchWithdrawal(retry.mutation, {
        'schemaVersion': 1,
        'permitId': permit.id,
        'ownerId': _owner,
        'withdrawnAt': Timestamp.fromDate(f.now),
      });
      // Synthetic remote receipt only; no Firestore transaction was sent.
      expect(
        await restarted.acknowledge(
          operationId: retry.localOperationId,
          leaseToken: retry.leaseToken,
          ownerGateToken: _token,
          nowUtc: f.now,
          acknowledgement: ack,
        ),
        isTrue,
      );
      expect(await claim(acquire: false, from: restarted), isEmpty);
      expect(
        ResearchSyncContract.permitPayload(permitFromRow(await storedPermit())),
        signedBefore,
      );
    },
  );

  test(
    'real receipt loss after capture denies claim without erasing answer or denominator',
    () async {
      await capture();
      final queued = await f.database.select(f.database.outboxOperations).get();
      expect(queued, isNotEmpty);
      receipts.active = false;
      expect(await claim(), isEmpty);
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        hasLength(1),
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      expect(await f.database.select(f.database.eventsV2).get(), hasLength(1));
    },
  );

  test(
    'genuinely signed renewal invalidates held wrappers then requeues current refs without duplicating evidence',
    () async {
      await capture();
      final original = await claim();
      final envelope = original
          .singleWhere(
            (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
          )
          .mutation
          .payload['envelope'];
      final renewed = _signed(permit, {
        'localRevision': 2,
        'cloudRevision': 2,
        'expiresAtUtc': permit.expiresAtUtc
            .add(const Duration(days: 1))
            .toIso8601String(),
      });
      await importPermit(renewed);
      for (final c in original) {
        expect(
          await store.beginAttempt(
            claim: c,
            ownerGateToken: _token,
            nowUtc: f.now,
          ),
          isNull,
        );
      }
      await gate.release(token: _token);
      await store.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now);
      final current = await claim();
      expect(current, hasLength(5));
      expect(
        current
            .singleWhere(
              (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
            )
            .mutation
            .payload['envelope'],
        envelope,
      );
      await checkDelivery(current, expectedPermit: renewed);
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        hasLength(1),
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      expect(await f.database.select(f.database.eventsV2).get(), hasLength(1));
    },
  );

  test(
    'raw +321us system clock composes genuine runtime capture queue and authorizer',
    () async {
      DateTime systemClock() => f.now.add(const Duration(microseconds: 321));
      // Additional integration evidence for MAIN's already-tested clock fix.
      // As in bootstrap, the real authorizer shares runtime's canonical clock.
      runtime = AdventureResearchRuntime.fromConfig(
        f.database,
        AdventureResearchRuntimeConfig.configured(
          study: f.study,
          issuerPublicKeys: _publicKeys,
          receipts: receipts,
        ),
        nowUtc: systemClock,
        onLocalMutation: (owner) async => notifications.add(
          await store.enqueueResearchForOwner(
            ownerId: owner,
            nowUtc: systemClock(),
          ),
        ),
      )!;
      authorizer = DriftResearchSyncAuthorizer(
        database: f.database,
        study: f.study,
        validator: runtime.participation.validator,
        nowUtc: runtime.participation.nowUtc,
      );
      store = newStore();
      await capture();
      expect(systemClock().microsecondsSinceEpoch % 1000, 321);
      expect(runtime.participation.nowUtc(), f.now);
      expect(notifications, hasLength(5));
      expect(
        await gate.tryAcquire(
          token: _token,
          nowUtc: systemClock(),
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final claims = await store.claimPending(
        ownerId: _owner,
        firebaseUid: _uid,
        limit: 50,
        leaseToken: 'raw-clock-claim',
        ownerGateToken: _token,
        leaseDuration: const Duration(minutes: 2),
        nowUtc: systemClock(),
      );
      expect(
        claims.map((c) => c.mutation.collection).toSet(),
        ResearchSyncContract.collections.toSet(),
      );
      for (final c in claims) {
        expect(
          await store.beginAttempt(
            claim: c,
            ownerGateToken: _token,
            nowUtc: systemClock(),
          ),
          isNotNull,
        );
        final gatewayRequest = ResearchSyncRequest(
          phase: ResearchSyncPhase.push,
          ownerId: _owner,
          firebaseUid: _uid,
          collection: c.mutation.collection,
          entityId: c.mutation.entityId,
          payload: c.mutation.payload,
          evaluatedAtUtc: systemClock(),
        );
        expect(gatewayRequest.evaluatedAtUtc, f.now);
        expect(await authorizer.authorize(gatewayRequest), isTrue);
        expect(c.mutation.clientUpdatedAtUtc.microsecondsSinceEpoch % 1000, 0);
      }
      expect(
        ResearchSyncContract.permitPayload(permitFromRow(await storedPermit())),
        ResearchSyncContract.permitPayload(permit),
        reason: 'canonicalize process clock, never signed inputs',
      );
    },
  );

  for (final recovery in ['conflict', 'pull']) {
    test(
      'P2 committed E1 with lost ACK then signed renewal reconciles via $recovery once',
      () async {
        await capture();
        final first = await claim();
        final e1 = first.singleWhere(
          (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
        );
        final reserved = await store.beginAttempt(
          claim: e1,
          ownerGateToken: _token,
          nowUtc: f.now,
        );
        expect(reserved, isNotNull);
        expect(await authorizePush(e1.mutation), isTrue);
        // Atomic synthetic server commit boundary using the production codecs:
        // both immutable entity and operation receipt exist, only local ACK lost.
        final remoteEntities = {
          e1.mutation.entityId: FirestoreSyncCodec.encodeEntity(
            e1.mutation,
            serverTimestamp: Timestamp.fromDate(f.now),
          ),
        };
        final remoteOperations = {
          e1.mutation.operationId: FirestoreSyncCodec.encodeOperation(
            e1.mutation,
            acknowledgedAt: Timestamp.fromDate(f.now),
          ),
        };
        final remoteFact = FirestoreSyncCodec.decodeEntity(
          collection: e1.mutation.collection,
          documentId: e1.mutation.entityId,
          data: remoteEntities.values.single,
          expectedFirebaseUid: _uid,
        );
        await store.markRetry(
          operationId: e1.localOperationId,
          leaseToken: e1.leaseToken,
          ownerGateToken: _token,
          nowUtc: f.now,
          nextAttemptAtUtc: f.now,
          failure: const OfflineSyncFailure(),
        );
        for (final other in first.where(
          (c) => c.localOperationId != e1.localOperationId,
        )) {
          await store.releaseClaim(
            claim: other,
            ownerGateToken: _token,
            nowUtc: f.now,
          );
        }
        final renewed = _signed(permit, {
          'localRevision': 2,
          'cloudRevision': 2,
          'expiresAtUtc': permit.expiresAtUtc
              .add(const Duration(days: 1))
              .toIso8601String(),
        });
        final trustedRemotePermit = ResearchSyncContract.permitPayload(renewed);
        await importPermit(renewed);
        expect(
          ResearchSyncContract.permitPayload(
            permitFromRow(await storedPermit()),
          ),
          trustedRemotePermit,
        );
        final current = await claim(acquire: false);
        final e2 = current.singleWhere(
          (c) => c.mutation.collection == SyncCollection.neutralEventsV2,
        );
        expect(e2.localOperationId, isNot(e1.localOperationId));
        expect(e2.mutation.payload['permitRevision'], 2);
        expect(
          e2.mutation.payload['envelope'],
          e1.mutation.payload['envelope'],
        );
        expect(await authorizePush(e1.mutation), isFalse);
        expect(await authorizePush(e2.mutation), isTrue);
        if (recovery == 'conflict') {
          expect(
            await store.resolvePushConflict(
              claim: e2,
              ownerGateToken: _token,
              cloudEntity: PushConflict(remoteFact).cloudEntity,
              resolvedAtUtc: f.now,
            ),
            isTrue,
          );
        } else {
          final cursor = SyncCursor(
            serverUpdatedAtUtc: remoteFact.serverUpdatedAtUtc,
            documentId: remoteFact.entityId,
          );
          expect(
            await store.applyPullPage(
              ownerId: _owner,
              collection: remoteFact.collection,
              page: PullPage(
                changes: [remoteFact],
                nextCursor: cursor,
                hasMore: false,
              ),
              ownerGateToken: _token,
              nowUtc: f.now,
            ),
            isTrue,
          );
          expect(
            await store.readCheckpoint(_owner, remoteFact.collection),
            cursor,
          );
        }
        final delivered =
            await (f.database.select(f.database.outboxOperations)
                  ..where((row) => row.operationId.equals(e2.localOperationId)))
                .getSingle();
        expect(
          delivered.state,
          'acknowledged',
          reason:
              'verified same immutable fact is delivered, not merely conflictResolved',
        );
        expect(delivered.acknowledgedAtUtcMs, isNotNull);
        expect(
          (await claim(
            acquire: false,
          )).where((c) => c.mutation.entityId == remoteFact.entityId),
          isEmpty,
        );
        expect(
          await f.database.select(f.database.eventsV2).get(),
          hasLength(1),
        );
        expect(remoteEntities, hasLength(1));
        expect(remoteOperations, hasLength(1));
        expect(
          remoteEntities.values.single['payload'],
          e1.mutation.payload,
          reason:
              'do not rewrite immutable admitted cloud wrapper to new authority',
        );
        expect(
          ResearchSyncContract.permitPayload(
            permitFromRow(await storedPermit()),
          ),
          trustedRemotePermit,
        );
      },
    );
  }
  test(
    'P2 all known historical fact collection pulls advance checkpoints after signed renewal',
    () async {
      await capture();
      final first = await claim();
      final historical = [
        for (final c in first)
          if (c.mutation.collection !=
              SyncCollection.researchParticipationPermits)
            FirestoreSyncCodec.decodeEntity(
              collection: c.mutation.collection,
              documentId: c.mutation.entityId,
              data: FirestoreSyncCodec.encodeEntity(
                c.mutation,
                serverTimestamp: Timestamp.fromDate(f.now),
              ),
              expectedFirebaseUid: _uid,
            ),
      ];
      await importPermit(
        _signed(permit, {
          'localRevision': 2,
          'cloudRevision': 2,
          'expiresAtUtc': permit.expiresAtUtc
              .add(const Duration(days: 1))
              .toIso8601String(),
        }),
      );
      for (final entity in historical) {
        final cursor = SyncCursor(
          serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
          documentId: entity.entityId,
        );
        expect(
          await store.applyPullPage(
            ownerId: _owner,
            collection: entity.collection,
            page: PullPage(
              changes: [entity],
              nextCursor: cursor,
              hasMore: false,
            ),
            ownerGateToken: _token,
            nowUtc: f.now,
          ),
          isTrue,
        );
        expect(await store.readCheckpoint(_owner, entity.collection), cursor);
      }
      expect((await storedPermit()).localRevision, 2);
      expect(
        await f.database.select(f.database.motivationResponses).get(),
        hasLength(1),
      );
      expect(
        await f.database.select(f.database.measurementOpportunities).get(),
        hasLength(1),
      );
      expect(await f.database.select(f.database.eventsV2).get(), hasLength(1));
    },
  );
  test(
    'P2 conflicting historical response cannot acknowledge local fact or advance checkpoint',
    () async {
      await capture();
      final first = await claim();
      final old = first.singleWhere(
        (c) => c.mutation.collection == SyncCollection.motivationResponses,
      );
      await importPermit(
        _signed(permit, {'localRevision': 2, 'cloudRevision': 2}),
      );
      final conflicting = SyncEntity(
        collection: old.mutation.collection,
        entityId: old.mutation.entityId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: old.mutation.clientUpdatedAtUtc,
        serverUpdatedAtUtc: f.now,
        payload: {
          ...old.mutation.payload,
          'responseCode': 'low',
          'ordinalValue': 1,
        },
      );
      await expectLater(
        store.applyPullPage(
          ownerId: _owner,
          collection: conflicting.collection,
          page: PullPage(
            changes: [conflicting],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: f.now,
              documentId: conflicting.entityId,
            ),
            hasMore: false,
          ),
          ownerGateToken: _token,
          nowUtc: f.now,
        ),
        throwsA(isA<SyncFailure>()),
      );
      expect(
        await store.readCheckpoint(_owner, conflicting.collection),
        isNull,
      );
      expect(
        (await f.database.select(f.database.motivationResponses).getSingle())
            .responseCode,
        'high',
      );
      expect(
        (await (f.database.select(
                  f.database.outboxOperations,
                )..where((row) => row.operationId.equals(old.localOperationId)))
                .getSingle())
            .state,
        isNot('acknowledged'),
      );
    },
  );

  for (final trustedServer in [true, false]) {
    test(
      'P2 new-device parent-first historical pull with server provenance $trustedServer',
      () async {
        await capture();
        final originalClaims = await claim();
        final remote = [
          for (final collection in ResearchSyncContract.collections.skip(1))
            FirestoreSyncCodec.decodeEntity(
              collection: collection,
              documentId: originalClaims
                  .singleWhere((c) => c.mutation.collection == collection)
                  .mutation
                  .entityId,
              data: FirestoreSyncCodec.encodeEntity(
                originalClaims
                    .singleWhere((c) => c.mutation.collection == collection)
                    .mutation,
                serverTimestamp: Timestamp.fromDate(f.now),
              ),
              expectedFirebaseUid: _uid,
            ),
        ];
        final renewed = _signed(permit, {
          'localRevision': 2,
          'cloudRevision': 2,
          'expiresAtUtc': permit.expiresAtUtc
              .add(const Duration(days: 1))
              .toIso8601String(),
        });
        await importPermit(renewed);
        // Device B is a separate empty database, not deletion of device A evidence.
        final originalWarning =
            driftRuntimeOptions.dontWarnAboutMultipleDatabases;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        addTearDown(
          () => driftRuntimeOptions.dontWarnAboutMultipleDatabases =
              originalWarning,
        );
        final device = MotivationResearchFixture();
        addTearDown(device.database.close);
        await device.initialize(enroll: false);
        device.now = f.now;
        await (device.database.update(device.database.localOwners)
              ..where((r) => r.id.equals(_owner)))
            .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
        final deviceRuntime = AdventureResearchRuntime.fromConfig(
          device.database,
          AdventureResearchRuntimeConfig.configured(
            study: device.study,
            issuerPublicKeys: _publicKeys,
            receipts: receipts,
          ),
          nowUtc: () => device.now,
        )!;
        await deviceRuntime.importDocument(
          _owner,
          jsonEncode(ResearchSyncContract.permitPayload(renewed)),
        );
        final deviceAuthorizer = DriftResearchSyncAuthorizer(
          database: device.database,
          study: device.study,
          validator: deviceRuntime.participation.validator,
          nowUtc: () => device.now,
        );
        DriftSyncStore reopened() => DriftSyncStore(
          device.database,
          researchMeasurementRollout: _rollout,
          researchAuthorizer: deviceAuthorizer.authorize,
        );
        final target = reopened();
        expect(
          await device.database
              .select(device.database.motivationMeasurementRuns)
              .get(),
          isEmpty,
        );
        expect(
          await device.database
              .select(device.database.motivationResponses)
              .get(),
          isEmpty,
        );
        expect(
          await device.database
              .select(device.database.measurementOpportunities)
              .get(),
          isEmpty,
        );
        expect(
          await device.database.select(device.database.eventsV2).get(),
          isEmpty,
        );
        expect(
          await device.database.select(device.database.outboxOperations).get(),
          isEmpty,
        );
        expect(
          await DriftOwnerOperationGate(device.database).tryAcquire(
            token: _token,
            nowUtc: device.now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        for (final decoded in remote) {
          // Explicit authenticated-server fixture analogue of the gateway only.
          final entity = trustedServer
              ? decoded.withServerReadProvenance(firebaseUid: _uid)
              : decoded;
          final cursor = SyncCursor(
            serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
            documentId: entity.entityId,
          );
          final applied = target.applyPullPage(
            ownerId: _owner,
            collection: entity.collection,
            page: PullPage(
              changes: [entity],
              nextCursor: cursor,
              hasMore: false,
            ),
            ownerGateToken: _token,
            nowUtc: device.now,
          );
          if (!trustedServer) {
            await expectLater(applied, throwsA(isA<SyncFailure>()));
            expect(
              await target.readCheckpoint(_owner, entity.collection),
              isNull,
            );
            expect(
              await device.database
                  .select(device.database.motivationMeasurementRuns)
                  .get(),
              isEmpty,
            );
            return;
          }
          expect(
            await applied,
            isTrue,
            reason: 'parent-first ${entity.collection.name}',
          );
          expect(
            await target.readCheckpoint(_owner, entity.collection),
            cursor,
          );
        }
        expect(
          (await device.database
                  .select(device.database.motivationResponses)
                  .getSingle())
              .responseCode,
          'high',
        );
        final opportunity = await device.database
            .select(device.database.measurementOpportunities)
            .getSingle();
        final event = await device.database
            .select(device.database.eventsV2)
            .getSingle();
        expect(opportunity.presentedEventId, event.eventId);
        expect(
          ResearchSyncContract.permitPayload(
            permitFromRow(
              await device.database
                  .select(device.database.researchParticipationPermits)
                  .getSingle(),
            ),
          ),
          ResearchSyncContract.permitPayload(renewed),
        );
        final reloaded = reopened();
        final afterRestart = await reloaded.claimPending(
          ownerId: _owner,
          firebaseUid: _uid,
          limit: 50,
          leaseToken: 'device-b-claim',
          ownerGateToken: _token,
          leaseDuration: const Duration(minutes: 2),
          nowUtc: device.now,
        );
        expect(
          afterRestart.where(
            (c) =>
                c.mutation.collection !=
                SyncCollection.researchParticipationPermits,
          ),
          isEmpty,
          reason: 'server-delivered immutable facts do not become new uploads',
        );
        final eventDelivery = await (device.database.select(
          device.database.outboxOperations,
        )..where((r) => r.entityId.equals(event.eventId))).get();
        expect(eventDelivery, hasLength(1));
        expect(eventDelivery.single.state, 'acknowledged');
        expect(eventDelivery.single.attemptCount, 0);
        expect(
          await f.database.select(f.database.eventsV2).get(),
          hasLength(1),
        );
      },
    );
  }

  for (final mismatch in [
    'revision',
    'serverTimestamp',
    'clientTimestamp',
    'uid',
  ]) {
    test(
      'P2 adapter rejects server marker $mismatch before forwarding despite local proof',
      () async {
        await capture();
        final original = (await claim()).singleWhere(
          (c) => c.mutation.collection == SyncCollection.motivationResponses,
        );
        final decoded =
            FirestoreSyncCodec.decodeEntity(
              collection: original.mutation.collection,
              documentId: original.mutation.entityId,
              data: FirestoreSyncCodec.encodeEntity(
                original.mutation,
                serverTimestamp: Timestamp.fromDate(f.now),
              ),
              expectedFirebaseUid: _uid,
            ).withServerReadProvenance(
              firebaseUid: mismatch == 'uid' ? 'wrong-uid' : _uid,
            );
        await importPermit(
          _signed(permit, {'localRevision': 2, 'cloudRevision': 2}),
        );
        final tampered = SyncEntity(
          collection: decoded.collection,
          entityId: decoded.entityId,
          revision: mismatch == 'revision' ? 2 : decoded.revision,
          isDeleted: decoded.isDeleted,
          payloadVersion: decoded.payloadVersion,
          clientUpdatedAtUtc: mismatch == 'clientTimestamp'
              ? decoded.clientUpdatedAtUtc.add(const Duration(milliseconds: 1))
              : decoded.clientUpdatedAtUtc,
          serverUpdatedAtUtc: mismatch == 'serverTimestamp'
              ? decoded.serverUpdatedAtUtc.add(const Duration(milliseconds: 1))
              : decoded.serverUpdatedAtUtc,
          payload: decoded.payload,
          serverReadProvenance: decoded.serverReadProvenance,
        );
        await expectLater(
          store.applyPullPage(
            ownerId: _owner,
            collection: tampered.collection,
            page: PullPage(
              changes: [tampered],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: tampered.serverUpdatedAtUtc,
                documentId: tampered.entityId,
              ),
              hasMore: false,
            ),
            ownerGateToken: _token,
            nowUtc: f.now,
          ),
          throwsA(isA<SyncFailure>()),
        );
        expect(await store.readCheckpoint(_owner, tampered.collection), isNull);
        expect(
          (await (f.database.select(f.database.outboxOperations)..where(
                    (r) => r.operationId.equals(original.localOperationId),
                  ))
                  .getSingle())
              .state,
          isNot('acknowledged'),
        );
      },
    );
  }

  test(
    'forged document is rejected before capture or queue despite active local consent',
    () async {
      final forged = {
        ...ResearchSyncContract.permitPayload(permit),
        'signature': base64Encode(List.filled(64, 0)),
      };
      await expectLater(
        runtime.importDocument(_owner, jsonEncode(forged)),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        isEmpty,
      );
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
      expect(notifications, isEmpty);
    },
  );
}

// NON-PRODUCTION, public deterministic test key. Never put this scalar in
// shipped configuration/assets. Production verification is the actual P-256
// verifier composed by AdventureResearchRuntime.fromConfig.
final _curve = ECCurve_secp256r1();
final _private = ECPrivateKey(BigInt.one, _curve);
final _publicKeys = <String, String>{
  'runtime-integration-synthetic': _curve.G
      .getEncoded(false)
      .map((b) => b.toRadixString(16).padLeft(2, '0'))
      .join(),
};
ResearchParticipationPermit _signed(
  ResearchParticipationPermit source, [
  Map<String, Object?> changes = const {},
]) {
  final canonical = <String, Object?>{
    ...jsonDecode(source.canonicalPayload()) as Map<String, dynamic>,
    'issuerKeyId': 'runtime-integration-synthetic',
    ...changes,
  };
  final bytes = utf8.encode(jsonEncode(canonical));
  final signer = ECDSASigner(SHA256Digest(), HMac(SHA256Digest(), 64))
    ..init(true, PrivateKeyParameter<ECPrivateKey>(_private));
  final signature = signer.generateSignature(bytes) as ECSignature;
  final hex =
      '${signature.r.toRadixString(16).padLeft(64, '0')}${signature.s.toRadixString(16).padLeft(64, '0')}';
  return ResearchSyncContract.permitFromPayload({
    ...canonical,
    'payloadSha256': sha256.convert(bytes).toString(),
    'signature': base64Encode([
      for (var i = 0; i < hex.length; i += 2)
        int.parse(hex.substring(i, i + 2), radix: 16),
    ]),
  });
}

final class _SyntheticReceipts implements ResearchReceiptAuthority {
  bool active = true;
  int reads = 0;
  @override
  Future<bool> isActive({
    required String ownerId,
    required String receiptId,
    required ResearchReceiptKind kind,
    required DateTime evaluatedAtUtc,
  }) async {
    reads++;
    return active &&
        ownerId == _owner &&
        receiptId == 'receipt:a' &&
        kind == ResearchReceiptKind.consent;
  }
}
