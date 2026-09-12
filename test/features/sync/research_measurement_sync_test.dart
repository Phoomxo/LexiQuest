import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:cloud_firestore/cloud_firestore.dart' as cloud;
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:firebase_core/firebase_core.dart' show FirebaseException;
import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_research_sync_adapter.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';

import '../../support/motivation_research_fixture.dart';

const _owner = 'owner:a';
const _uid = 'research-synthetic-uid';
const _gate = 'research-test-gate';
const _rollout = ResearchMeasurementSyncRollout.localEmulatorV1(
  deployedRulesRevision: researchMeasurementV1RulesRevision,
);

void main() {
  test('research rollout is separate, exact revision and default off', () {
    expect(const ResearchMeasurementSyncRollout.off().allowsSync, isFalse);
    expect(_rollout.allowsSync, isTrue);
    expect(
      const ResearchMeasurementSyncRollout.localEmulatorV1(
        deployedRulesRevision: 'research-measurement-v1-r0',
      ).allowsSync,
      isFalse,
    );
    expect(
      const ResearchCollectionSyncRollout.off().allowsAssessmentRunClaims,
      isFalse,
    );
    expect(ResearchSyncContract.collections.map((c) => c.wireName), [
      'research_participation_permits',
      'motivation_measurement_runs',
      'motivation_responses',
      'research_session_proofs',
      'measurement_opportunities',
      'neutral_events_v2',
    ]);
  });

  group('durable research sync under the existing owner gate', () {
    late MotivationResearchFixture f;
    late String runId;
    final seen = <ResearchSyncRequest>[];
    var allowed = true;
    Future<bool> authorize(ResearchSyncRequest r) async {
      seen.add(r);
      // Synthetic authority only. The production callback is supplied by MAIN.
      return allowed;
    }

    DriftSyncStore store({bool enabled = true, bool callback = true}) =>
        DriftSyncStore(
          f.database,
          researchMeasurementRollout: enabled
              ? _rollout
              : const ResearchMeasurementSyncRollout.off(),
          researchAuthorizer: callback ? authorize : null,
        );
    Future<List<ClaimedSyncOperation>> claim(DriftSyncStore s) =>
        s.claimPending(
          ownerId: _owner,
          firebaseUid: _uid,
          limit: 20,
          leaseToken: 'lease',
          ownerGateToken: _gate,
          leaseDuration: const Duration(minutes: 1),
          nowUtc: f.now,
        );
    setUp(() async {
      f = MotivationResearchFixture();
      seen.clear();
      allowed = true;
      await f.initialize();
      await (f.database.update(f.database.localOwners)
            ..where((r) => r.id.equals(_owner)))
          .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
      runId = (await f.measurements.start(
        const MotivationMeasurementStart(ownerId: _owner, permitId: 'permit:a'),
      )).id;
      expect(
        await DriftOwnerOperationGate(f.database).tryAcquire(
          token: _gate,
          nowUtc: f.now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
    });
    tearDown(() => f.database.close());

    test('default off or absent callback creates no research outbox', () async {
      expect(await claim(store(enabled: false)), isEmpty);
      expect(await claim(store(callback: false)), isEmpty);
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        isEmpty,
      );
      expect(seen, isEmpty);
    });
    test(
      'claim preserves signed owner and revisions and passes own gate token',
      () async {
        final claims = await claim(store());
        expect(claims, hasLength(2));
        final permit = claims.singleWhere(
          (c) =>
              c.mutation.collection ==
              SyncCollection.researchParticipationPermits,
        );
        expect(permit.mutation.payload, {
          ...jsonDecode(f.permit().canonicalPayload()) as Map<String, dynamic>,
          'payloadSha256': f.permit().payloadSha256,
          'signature': f.permit().signature,
        });
        expect(permit.mutation.payload['ownerId'], _owner);
        expect(permit.mutation.firebaseUid, _uid);
        expect(seen.map((r) => r.ownerGateToken), everyElement(_gate));
        expect(seen.any((r) => r.phase == ResearchSyncPhase.enqueue), isTrue);
        expect(seen.any((r) => r.phase == ResearchSyncPhase.claim), isTrue);
        expect(
          await store().acknowledge(
            operationId: permit.localOperationId,
            leaseToken: permit.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            acknowledgement: PushAcknowledged(
              operationId: permit.localOperationId,
              resultingRevision: permit.mutation.localRevision,
              acknowledgedAtUtc: f.now,
            ),
          ),
          isTrue,
        );
        final persisted = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(persisted.localRevision, 1);
        expect(persisted.cloudRevision, 1);
        expect(persisted.signature, f.permit().signature);
      },
    );
    test('repeated enqueue is idempotent', () async {
      final s = store();
      expect(
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
          limit: 20,
        ),
        2,
      );
      expect(
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
          limit: 20,
        ),
        0,
      );
      expect(
        await f.database.select(f.database.outboxOperations).get(),
        hasLength(2),
      );
    });
    test(
      'withdrawal between claim and reservation spends no attempt',
      () async {
        final s = store();
        final c = (await claim(s)).first;
        await (f.database.update(
          f.database.researchConsents,
        )..where((r) => r.ownerId.equals(_owner))).write(
          ResearchConsentsCompanion(
            consentState: const Value('withdrawn'),
            withdrawnAtUtcMs: Value(f.now.millisecondsSinceEpoch),
          ),
        );
        expect(
          await s.beginAttempt(claim: c, ownerGateToken: _gate, nowUtc: f.now),
          isNull,
        );
        final op = await (f.database.select(
          f.database.outboxOperations,
        )..where((r) => r.operationId.equals(c.localOperationId))).getSingle();
        expect(op.attemptCount, 0);
      },
    );
    test(
      'callback denial between enqueue and claim prevents delivery',
      () async {
        final s = store();
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
          limit: 20,
        );
        allowed = false;
        expect(await claim(s), isEmpty);
      },
    );
    test(
      'payload/pin changes after claim invalidate reserved mutation',
      () async {
        final s = store();
        final c = (await claim(s)).singleWhere(
          (c) =>
              c.mutation.collection == SyncCollection.motivationMeasurementRuns,
        );
        await (f.database.update(
          f.database.motivationMeasurementRuns,
        )..where((r) => r.id.equals(runId))).write(
          const MotivationMeasurementRunsCompanion(
            instrumentVersion: Value('2'),
          ),
        );
        expect(
          await s.beginAttempt(claim: c, ownerGateToken: _gate, nowUtc: f.now),
          isNull,
        );
      },
    );
    test('local withdrawal prevents download resurrection', () async {
      final s = store();
      final c = (await claim(s)).singleWhere(
        (c) =>
            c.mutation.collection == SyncCollection.motivationMeasurementRuns,
      );
      await (f.database.update(
        f.database.researchConsents,
      )..where((r) => r.ownerId.equals(_owner))).write(
        ResearchConsentsCompanion(
          consentState: const Value('withdrawn'),
          withdrawnAtUtcMs: Value(f.now.millisecondsSinceEpoch),
        ),
      );
      await (f.database.delete(
        f.database.motivationMeasurementRuns,
      )..where((r) => r.id.equals(runId))).go();
      final entity = SyncEntity(
        collection: c.mutation.collection,
        entityId: runId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: c.mutation.clientUpdatedAtUtc,
        serverUpdatedAtUtc: f.now,
        payload: c.mutation.payload,
      );
      await s.applyPullPage(
        ownerId: _owner,
        collection: entity.collection,
        page: PullPage(
          changes: [entity],
          nextCursor: SyncCursor(serverUpdatedAtUtc: f.now, documentId: runId),
          hasMore: false,
        ),
        ownerGateToken: _gate,
        nowUtc: f.now,
      );
      expect(
        await f.database.select(f.database.motivationMeasurementRuns).get(),
        isEmpty,
      );
    });

    Future<String> presentedEvent() async {
      await DriftOwnerOperationGate(f.database).release(token: _gate);
      await f.measurements.record(
        MotivationResponse(
          ownerId: _owner,
          runId: runId,
          itemId: 'baseline',
          responseCode: 'high',
        ),
      );
      final opportunities = DriftMeasurementOpportunityRepository(
        f.database,
        measurements: f.measurements,
        nowUtc: () => f.now,
      );
      final o = await opportunities.open(
        ownerId: _owner,
        measurementRunId: runId,
        entryAttemptId: '00000000-0000-4000-8000-000000000001',
        effectivePresentation: TodayExperiencePresentation.adventure,
      );
      final presented = await opportunities.recordPresented(_owner, o.id);
      await DriftOwnerOperationGate(f.database).tryAcquire(
        token: _gate,
        nowUtc: f.now,
        leaseDuration: const Duration(minutes: 10),
      );
      return presented.presentedEventId!;
    }

    Future<void> renewPermit() async {
      final signed = Map<String, dynamic>.from(
        jsonDecode(f.permit().canonicalPayload()) as Map,
      );
      signed['localRevision'] = 2;
      signed['cloudRevision'] = 2;
      signed['expiresAtUtc'] = DateTime.utc(2026, 9, 9).toIso8601String();
      final hash = sha256.convert(utf8.encode(jsonEncode(signed))).toString();
      await (f.database.update(
        f.database.researchParticipationPermits,
      )..where((r) => r.id.equals('permit:a'))).write(
        ResearchParticipationPermitsCompanion(
          localRevision: const Value(2),
          cloudRevision: const Value(2),
          payloadSha256: Value(hash),
          expiresAtUtcMs: Value(
            DateTime.utc(2026, 9, 9).millisecondsSinceEpoch,
          ),
        ),
      );
    }

    test(
      'all five research collections round trip bounded captured payloads without owner remapping',
      () async {
        await presentedEvent();
        final captured = await claim(store());
        expect(captured.map((c) => c.mutation.collection).toSet(), {
          SyncCollection.researchParticipationPermits,
          SyncCollection.motivationMeasurementRuns,
          SyncCollection.motivationResponses,
          SyncCollection.measurementOpportunities,
          SyncCollection.neutralEventsV2,
        });
        for (final c in captured) {
          final encoded = FirestoreSyncCodec.encodeEntity(
            c.mutation,
            serverTimestamp: Timestamp.fromDate(f.now),
          );
          final restored = FirestoreSyncCodec.decodeEntity(
            collection: c.mutation.collection,
            documentId: c.mutation.entityId,
            data: encoded,
            expectedFirebaseUid: _uid,
          );
          expect(restored.payload, c.mutation.payload);
          expect(restored.revision, c.mutation.localRevision);
          expect(restored.payloadVersion, 1);
          expect(
            ResearchSyncContract.ownerOf(restored.collection, restored.payload),
            _owner,
          );
          expect(
            jsonEncode(
              encoded,
              toEncodable: (value) =>
                  (value as Timestamp).toDate().toIso8601String(),
            ),
            isNot(contains(_gate)),
          );
          expect(
            () => FirestoreSyncCodec.decodeEntity(
              collection: c.mutation.collection,
              documentId: c.mutation.entityId,
              data: {
                ...encoded,
                'payload': {
                  ...c.mutation.payload,
                  'unboundedAnswer': 'not allowed',
                },
              },
            ),
            throwsA(isA<SyncFailure>()),
          );
        }
      },
    );
    // Meaningful RED queued before the source-authority renewal fix.
    test(
      'active permit renewal refreshes only undelivered event wrapper',
      () async {
        final eventId = await presentedEvent();
        final s = store();
        final initial = await claim(s);
        final eventClaim = initial.singleWhere(
          (c) => c.mutation.entityId == eventId,
        );
        final originalEnvelope = eventClaim.mutation.payload['envelope'];
        await renewPermit();
        expect(
          await s.beginAttempt(
            claim: eventClaim,
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          isNull,
        );
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
          limit: 20,
        );
        final jobs = await (f.database.select(
          f.database.outboxOperations,
        )..where((r) => r.entityId.equals(eventId))).get();
        expect(
          jobs,
          hasLength(2),
          reason: 'new current authority must not strand an undelivered event',
        );
        final refreshed = (await claim(
          s,
        )).singleWhere((c) => c.mutation.entityId == eventId);
        expect(refreshed.mutation.payload['envelope'], originalEnvelope);
        expect(refreshed.mutation.payload['permitRevision'], 2);
        expect(
          refreshed.mutation.operationId,
          isNot(eventClaim.mutation.operationId),
        );
        expect(
          await f.database.select(f.database.eventsV2).get(),
          hasLength(1),
        );
      },
    );
    test(
      'active permit renewal cannot enqueue an acknowledged event twice',
      () async {
        final eventId = await presentedEvent();
        final s = store();
        final eventClaim = (await claim(
          s,
        )).singleWhere((c) => c.mutation.entityId == eventId);
        await s.acknowledge(
          operationId: eventClaim.localOperationId,
          leaseToken: eventClaim.leaseToken,
          ownerGateToken: _gate,
          nowUtc: f.now,
          acknowledgement: PushAcknowledged(
            operationId: eventClaim.localOperationId,
            resultingRevision: 1,
            acknowledgedAtUtc: f.now,
          ),
        );
        await renewPermit();
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
          limit: 20,
        );
        expect(
          await (f.database.select(
            f.database.outboxOperations,
          )..where((r) => r.entityId.equals(eventId))).get(),
          hasLength(1),
        );
      },
    );

    Map<String, Object?> signedPermitUpdate({
      bool revoked = false,
      bool deleted = false,
      int revision = 2,
    }) {
      final canonical = Map<String, Object?>.from(
        jsonDecode(f.permit().canonicalPayload()) as Map,
      );
      canonical['localRevision'] = revision;
      canonical['cloudRevision'] = revision;
      canonical['expiresAtUtc'] = DateTime.utc(2026, 9, 9).toIso8601String();
      canonical['revokedAtUtc'] = revoked ? f.now.toIso8601String() : null;
      canonical['isDeleted'] = deleted;
      return {
        ...canonical,
        'payloadSha256': sha256
            .convert(utf8.encode(jsonEncode(canonical)))
            .toString(),
        'signature': 'synthetic-signature',
      };
    }

    Future<void> pullPermit(
      DriftSyncStore s,
      Map<String, Object?> payload, {
      int sequence = 1,
    }) async {
      final at = f.now.add(Duration(seconds: sequence));
      final entity = SyncEntity(
        collection: SyncCollection.researchParticipationPermits,
        entityId: payload['id']! as String,
        revision: payload['localRevision']! as int,
        isDeleted: payload['isDeleted']! as bool,
        payloadVersion: 1,
        clientUpdatedAtUtc: f.permit().issuedAtUtc,
        serverUpdatedAtUtc: at,
        payload: payload,
      );
      await s.applyPullPage(
        ownerId: _owner,
        collection: entity.collection,
        page: PullPage(
          changes: [entity],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: at,
            documentId: entity.entityId,
          ),
          hasMore: false,
        ),
        ownerGateToken: _gate,
        nowUtc: at,
      );
    }

    test(
      'authentic newer downloaded renewal preserves signed revisions',
      () async {
        final s = store();
        final incoming = signedPermitUpdate();
        await pullPermit(s, incoming);
        final p = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(p.localRevision, 2);
        expect(p.cloudRevision, 2);
        expect(p.payloadSha256, incoming['payloadSha256']);
        expect(p.signature, incoming['signature']);
      },
    );
    test(
      'downloaded signed revocation denies queued upload and stale cannot unrevoke',
      () async {
        final s = store();
        final claims = await claim(s);
        final revoked = signedPermitUpdate(revoked: true);
        await pullPermit(s, revoked);
        final p = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(p.revokedAtUtcMs, f.now.millisecondsSinceEpoch);
        expect(p.localRevision, 2);
        for (final c in claims) {
          expect(
            await s.beginAttempt(
              claim: c,
              ownerGateToken: _gate,
              nowUtc: f.now,
            ),
            isNull,
          );
        }
        await pullPermit(
          s,
          ResearchSyncContract.permitPayload(f.permit()),
          sequence: 2,
        );
        await pullPermit(s, revoked, sequence: 3);
        final after = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(after.revokedAtUtcMs, p.revokedAtUtcMs);
        expect(after.localRevision, 2);
        expect(after.signature, p.signature);
      },
    );
    test('unknown revoked permit pull cannot enroll a participant', () async {
      final s = store();
      await (f.database.delete(
        f.database.researchParticipationPermits,
      )..where((r) => r.id.equals('permit:a'))).go();
      await pullPermit(s, signedPermitUpdate(revoked: true));
      expect(
        await f.database.select(f.database.researchParticipationPermits).get(),
        isEmpty,
      );
    });
    test(
      'signed deletion of existing permit reaches authenticity callback and stays deleted',
      () async {
        final s = store();
        final claims = await claim(s);
        await (f.database.update(
          f.database.researchConsents,
        )..where((r) => r.ownerId.equals(_owner))).write(
          ResearchConsentsCompanion(
            consentState: const Value('withdrawn'),
            withdrawnAtUtcMs: Value(f.now.millisecondsSinceEpoch),
          ),
        );
        seen.clear();
        final incoming = signedPermitUpdate(deleted: true);
        await pullPermit(s, incoming);
        expect(
          seen.any(
            (r) =>
                r.phase == ResearchSyncPhase.pull &&
                r.payload['isDeleted'] == true &&
                r.ownerGateToken == _gate,
          ),
          isTrue,
          reason:
              'structural checks must not bypass the authenticity-only callback',
        );
        final deleted = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(deleted.isDeleted, isTrue);
        expect(deleted.localRevision, 2);
        expect(deleted.cloudRevision, 2);
        expect(deleted.payloadSha256, incoming['payloadSha256']);
        expect(deleted.signature, incoming['signature']);
        for (final c in claims) {
          expect(
            await s.beginAttempt(
              claim: c,
              ownerGateToken: _gate,
              nowUtc: f.now,
            ),
            isNull,
          );
        }
        await pullPermit(s, signedPermitUpdate(revision: 3), sequence: 2);
        await pullPermit(s, incoming, sequence: 3);
        final after = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(after.isDeleted, isTrue);
        expect(after.localRevision, 2);
        expect(after.payloadSha256, incoming['payloadSha256']);
      },
    );
    test(
      'unknown signed deleted permit cannot create local enrollment',
      () async {
        final s = store();
        await (f.database.delete(
          f.database.researchParticipationPermits,
        )..where((r) => r.id.equals('permit:a'))).go();
        await pullPermit(s, signedPermitUpdate(deleted: true));
        expect(
          await f.database
              .select(f.database.researchParticipationPermits)
              .get(),
          isEmpty,
        );
      },
    );
    test(
      'inactive permit pull still denies unavailable authenticity authority',
      () async {
        final s = store();
        allowed = false;
        try {
          await pullPermit(s, signedPermitUpdate(deleted: true, revoked: true));
        } on SyncFailure {
          /* Retriable authority denial is acceptable. */
        }
        final p = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(p.isDeleted, isFalse);
        expect(p.revokedAtUtcMs, isNull);
        expect(p.localRevision, 1);
        expect(
          await s.readCheckpoint(
            _owner,
            SyncCollection.researchParticipationPermits,
          ),
          isNull,
        );
      },
    );
    test(
      'signed revocation pull works after local consent withdrawal',
      () async {
        final s = store();
        await (f.database.update(
          f.database.researchConsents,
        )..where((r) => r.ownerId.equals(_owner))).write(
          ResearchConsentsCompanion(
            consentState: const Value('withdrawn'),
            withdrawnAtUtcMs: Value(f.now.millisecondsSinceEpoch),
          ),
        );
        final incoming = signedPermitUpdate(revoked: true);
        await pullPermit(s, incoming);
        final p = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        expect(p.revokedAtUtcMs, f.now.millisecondsSinceEpoch);
        expect(p.payloadSha256, incoming['payloadSha256']);
      },
    );
    test(
      'background recovery queues deny-only withdrawal after consent is withdrawn',
      () async {
        final s = store();
        await (f.database.update(
          f.database.researchConsents,
        )..where((r) => r.ownerId.equals(_owner))).write(
          ResearchConsentsCompanion(
            consentState: const Value('withdrawn'),
            withdrawnAtUtcMs: Value(f.now.millisecondsSinceEpoch),
          ),
        );
        allowed =
            false; // Active participation is no longer an authority to upload.
        final claims = await claim(s);
        expect(claims, hasLength(1));
        final op =
            await (f.database.select(f.database.outboxOperations)..where(
                  (r) => r.operationId.equals(claims.single.localOperationId),
                ))
                .getSingle();
        expect(op.entityType, 'researchWithdrawal');
        expect(claims.single.mutation.payload, {
          'permitId': 'permit:a',
          'ownerId': _owner,
        });
        expect(
          await s.beginAttempt(
            claim: claims.single,
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          isNotNull,
        );
      },
    );
    Future<void> withdrawLocally() => DriftResearchConsentRepository(
      f.database,
    ).decide(ownerId: _owner, version: 1, accepted: false, decidedAtUtc: f.now);

    String withdrawalId() =>
        'research-sync:${ResearchSyncContract.fingerprint({
          'collection': 'research_withdrawals',
          'id': 'permit:a',
          'payload': {'permitId': 'permit:a', 'ownerId': _owner},
        })}:1';

    for (final withRun in [false, true]) {
      test(
        'withdrawal persists denial before enqueue withRun=$withRun',
        () async {
          if (!withRun) {
            await f.database.delete(f.database.motivationMeasurementRuns).go();
          }
          await withdrawLocally();
          final intent =
              await (f.database.select(f.database.outboxOperations)..where(
                    (row) => row.entityType.equals('researchWithdrawal'),
                  ))
                  .getSingle();
          expect(intent.operationId, withdrawalId());
          expect(intent.entityId, 'permit:a');
          expect(intent.ownerId, _owner);
          expect(intent.payloadVersion, 1);
          expect(intent.state, 'pending');
          f.now = f.now.add(const Duration(seconds: 1));
          await DriftResearchConsentRepository(f.database).decide(
            ownerId: _owner,
            version: 1,
            accepted: true,
            decidedAtUtc: f.now,
          );
          final retained =
              await (f.database.select(
                    f.database.outboxOperations,
                  )..where((row) => row.operationId.equals(intent.operationId)))
                  .getSingle();
          expect(retained.toJson(), intent.toJson());
          expect(
            (await f.database.select(f.database.researchConsents).getSingle())
                .consentState,
            'accepted',
          );
          expect(
            seen,
            isEmpty,
            reason: 'local denial persistence needs no upload authority',
          );
        },
      );
    }

    test(
      'durable denial remains claimable after reaccept and acknowledged on repeat withdrawal',
      () async {
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        final s = store(callback: false);
        // Existing backfill makes the claim boundary independently testable on
        // the old implementation; the preceding tests require atomic insertion.
        await s.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        final restoredStore = store(callback: false);
        final denial = (await claim(restoredStore)).single;
        expect(denial.localOperationId, withdrawalId());
        expect(denial.mutation.payload, {
          'permitId': 'permit:a',
          'ownerId': _owner,
        });
        final attempt = (await restoredStore.beginAttempt(
          claim: denial,
          ownerGateToken: _gate,
          nowUtc: f.now,
        ))!;
        expect(
          await restoredStore.acknowledge(
            operationId: attempt.mutation.operationId,
            leaseToken: attempt.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            acknowledgement: PushAcknowledged(
              operationId: attempt.mutation.operationId,
              resultingRevision: 1,
              acknowledgedAtUtc: f.now,
            ),
          ),
          isTrue,
        );
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .consentState,
          'accepted',
        );
        final acknowledged = await (f.database.select(
          f.database.outboxOperations,
        )..where((row) => row.operationId.equals(withdrawalId()))).getSingle();
        expect(acknowledged.state, 'acknowledged');
        f.now = f.now.add(const Duration(seconds: 1));
        await withdrawLocally();
        final repeated =
            await (f.database.select(f.database.outboxOperations)
                  ..where((row) => row.entityType.equals('researchWithdrawal')))
                .getSingle();
        expect(repeated.toJson(), acknowledged.toJson());
        expect(await claim(restoredStore), isEmpty);
      },
    );

    for (final defect in ['operation-id', 'kind', 'version']) {
      test('durable denial rejects malformed $defect after reaccept', () async {
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        await store(callback: false).enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        final adapter = DriftResearchSyncAdapter(
          f.database,
          rollout: _rollout,
          authorizer: null,
        );
        final query = f.database.select(f.database.outboxOperations)
          ..where((row) => row.operationId.equals(withdrawalId()));
        final valid = await query.getSingle();
        expect(
          await adapter.claimAllowed(
            valid,
            firebaseUid: _uid,
            token: _gate,
            now: f.now,
          ),
          isTrue,
          reason:
              'A valid durable denial must first be admitted after reaccept.',
        );
        await (f.database.update(
          f.database.outboxOperations,
        )..where((row) => row.operationId.equals(valid.operationId))).write(
          OutboxOperationsCompanion(
            operationId: defect == 'operation-id'
                ? const Value('forged-denial')
                : const Value.absent(),
            operationKind: defect == 'kind'
                ? const Value('delete')
                : const Value.absent(),
            payloadVersion: defect == 'version'
                ? const Value(2)
                : const Value.absent(),
          ),
        );
        final malformed = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(
          await adapter.claimAllowed(
            malformed,
            firebaseUid: _uid,
            token: _gate,
            now: f.now,
          ),
          isFalse,
        );
        expect(malformed.attemptCount, valid.attemptCount);
      });
    }

    for (final loss in ['expired', 'released', 'owner']) {
      test('durable denial still requires current $loss authority', () async {
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        await store(callback: false).enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        final adapter = DriftResearchSyncAdapter(
          f.database,
          rollout: _rollout,
          authorizer: null,
        );
        final op = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(
          await adapter.claimAllowed(
            op,
            firebaseUid: _uid,
            token: _gate,
            now: f.now,
          ),
          isTrue,
        );
        if (loss == 'expired') {
          f.now = f.now.add(const Duration(minutes: 11));
        } else if (loss == 'released') {
          await DriftOwnerOperationGate(f.database).release(token: _gate);
        } else {
          await (f.database.update(f.database.localOwners)
                ..where((row) => row.id.equals(_owner)))
              .write(const LocalOwnersCompanion(isActive: Value(false)));
        }
        expect(
          await adapter.claimAllowed(
            op,
            firebaseUid: _uid,
            token: _gate,
            now: f.now,
          ),
          isFalse,
        );
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          op.toJson(),
        );
      });
    }

    test(
      'offline retry metadata survives reaccept and repeated withdrawal',
      () async {
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        final s = store(callback: false);
        final initial = (await claim(s)).single;
        expect(
          await s.beginAttempt(
            claim: initial,
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          isNotNull,
        );
        final retryAt = f.now.add(const Duration(minutes: 2));
        expect(
          await s.markRetry(
            operationId: initial.localOperationId,
            leaseToken: initial.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            nextAttemptAtUtc: retryAt,
            failure: const OfflineSyncFailure(),
          ),
          isTrue,
        );
        final before = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(before.state, 'retryWaiting');
        expect(before.attemptCount, 1);
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await withdrawLocally();
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          before.toJson(),
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        final restarted = store(callback: false);
        expect(
          await claim(restarted),
          isEmpty,
          reason: 'Retry time must not be reset by consent changes.',
        );
        f.now = retryAt;
        final retry = (await claim(restarted)).single;
        expect(retry.localOperationId, initial.localOperationId);
        expect(retry.mutation.payload, initial.mutation.payload);
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .consentState,
          'accepted',
        );
      },
    );

    test(
      'distinct persisted permit after reaccept does not inherit the old denial',
      () async {
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        await store(callback: false).enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        // The real import API correctly forbids two live permits for one protocol.
        // Retire the old synthetic permit through that API first.
        final revoked = Map<String, Object?>.from(
          jsonDecode(f.permit().canonicalPayload()) as Map,
        );
        revoked['revokedAtUtc'] = f.now.toIso8601String();
        revoked['localRevision'] = 2;
        revoked['cloudRevision'] = 2;
        await f.participation.importPermit(
          ResearchSyncContract.permitFromPayload({
            ...revoked,
            'payloadSha256': sha256
                .convert(utf8.encode(jsonEncode(revoked)))
                .toString(),
            'signature': 'synthetic-signature',
          }),
        );
        final newPayload = Map<String, Object?>.from(
          jsonDecode(f.permit(id: 'permit:b').canonicalPayload()) as Map,
        );
        newPayload['issuedAtUtc'] = f.now.toIso8601String();
        final newHash = sha256
            .convert(utf8.encode(jsonEncode(newPayload)))
            .toString();
        final newPermit = ResearchSyncContract.permitFromPayload({
          ...newPayload,
          'payloadSha256': newHash,
          'signature': 'synthetic-signature',
        });
        // The old immutable assignment predates reaccept. Re-enrollment is not
        // authorized by this test: prove that the real API retains that cutoff.
        await expectLater(
          f.participation.importPermit(newPermit),
          throwsA(
            isA<ResearchCaptureDenied>().having(
              (error) => error.reason,
              'reason',
              ResearchCaptureReason.identityConflict,
            ),
          ),
        );
        final original = await f.database
            .select(f.database.researchParticipationPermits)
            .getSingle();
        // Trusted SQL fixture for the transport's exact-ID denial boundary only.
        // It cannot authorize new collection (this store has no authorizer).
        await f.database
            .into(f.database.researchParticipationPermits)
            .insert(
              original
                  .toCompanion(true)
                  .copyWith(
                    id: const Value('permit:b'),
                    issuedAtUtcMs: Value(f.now.millisecondsSinceEpoch),
                    revokedAtUtcMs: const Value(null),
                    localRevision: const Value(1),
                    cloudRevision: const Value(1),
                    payloadSha256: Value(newHash),
                    signature: const Value('synthetic-signature'),
                  ),
            );
        final restarted = store(callback: false);
        await restarted.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        final claims = await claim(restarted);
        expect(claims.map((c) => c.mutation.entityId), ['permit:a']);
        expect(
          (await f.database.select(f.database.outboxOperations).get()).map(
            (o) => o.entityId,
          ),
          ['permit:a'],
        );
        expect(
          (await f.database
                  .select(f.database.researchParticipationPermits)
                  .get())
              .map((p) => p.id)
              .toSet(),
          {'permit:a', 'permit:b'},
        );
      },
    );

    test(
      'denial insert failure rolls back consent and run withdrawal together',
      () async {
        final beforeConsent = await f.database
            .select(f.database.researchConsents)
            .getSingle();
        final beforeRun = await f.database
            .select(f.database.motivationMeasurementRuns)
            .getSingle();
        await f.database.customStatement(
          "CREATE TEMP TRIGGER reject_denial BEFORE INSERT ON outbox_operations WHEN NEW.entity_type = 'researchWithdrawal' BEGIN SELECT RAISE(ABORT, 'synthetic denial persistence failure'); END",
        );
        await expectLater(withdrawLocally(), throwsA(anything));
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .toJson(),
          beforeConsent.toJson(),
        );
        expect(
          (await f.database
                  .select(f.database.motivationMeasurementRuns)
                  .getSingle())
              .toJson(),
          beforeRun.toJson(),
        );
        expect(
          await f.database.select(f.database.outboxOperations).get(),
          isEmpty,
        );
      },
    );

    test(
      'public hook preserves atomic denial and backfills legacy withdrawal without an active authorizer',
      () async {
        await withdrawLocally();
        await DriftOwnerOperationGate(f.database).release(token: _gate);
        final s = store(callback: false);
        final atomic = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(atomic.operationId, withdrawalId());
        expect(
          await s.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
          0,
        );
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          atomic.toJson(),
        );
        // Model a pre-patch withdrawn participant with no durable intent.
        // Delete only this synthetic permit's exact denial, retaining consent,
        // permit and withdrawn run so the public recovery hook must backfill.
        expect(
          await (f.database.delete(f.database.outboxOperations)..where(
                (row) =>
                    row.operationId.equals(withdrawalId()) &
                    row.ownerId.equals(_owner) &
                    row.entityType.equals('researchWithdrawal'),
              ))
              .go(),
          1,
        );
        expect(
          await f.database.select(f.database.outboxOperations).get(),
          isEmpty,
        );
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .consentState,
          'withdrawn',
        );
        expect(
          await s.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
          1,
        );
        expect(
          await s.enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
          0,
        );
        final op = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(op.entityType, 'researchWithdrawal');
        expect(op.entityId, 'permit:a');
        expect(op.ownerId, _owner);
        expect(op.payloadVersion, 1);
        expect(op.attemptCount, 0);
        expect(op.state, 'pending');
        expect(
          seen,
          isEmpty,
          reason: 'a deny-only request never asks for participation',
        );
      },
    );
    test(
      'withdrawal hook remains off by default and respects a busy owner gate',
      () async {
        await withdrawLocally();
        final intent = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(intent.attemptCount, 0);
        expect(
          await store().enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
          0,
        );
        expect(
          await store().claimPending(
            ownerId: _owner,
            firebaseUid: _uid,
            limit: 20,
            leaseToken: 'blocked-lease',
            ownerGateToken: 'competing-owner-token',
            leaseDuration: const Duration(minutes: 1),
            nowUtc: f.now,
          ),
          isEmpty,
        );
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          intent.toJson(),
        );
        expect(await claim(store(enabled: false)), isEmpty);
        await DriftOwnerOperationGate(f.database).release(token: _gate);
        expect(
          await store(
            enabled: false,
          ).enqueueResearchForOwner(ownerId: _owner, nowUtc: f.now),
          0,
        );
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          intent.toJson(),
        );
        expect(seen, isEmpty);
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .consentState,
          'withdrawn',
          reason:
              'network/rollout/gate conditions cannot roll back local withdrawal',
        );
      },
    );
    test(
      'withdrawal recovery rejects mismatched Firebase binding and actual owner fence',
      () async {
        await withdrawLocally();
        final intent = await f.database
            .select(f.database.outboxOperations)
            .getSingle();
        expect(intent.attemptCount, 0);
        final s = store(callback: false);
        expect(
          await s.enqueueResearchChanges(
            ownerId: _owner,
            firebaseUid: 'other-uid',
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          0,
        );
        expect(
          await s.enqueueResearchChanges(
            ownerId: _owner,
            firebaseUid: _uid,
            ownerGateToken: 'wrong-token',
            nowUtc: f.now,
          ),
          0,
        );
        final adapter = DriftResearchSyncAdapter(
          f.database,
          rollout: _rollout,
          authorizer: null,
        );
        for (final binding in [
          (uid: 'other-uid', token: _gate),
          (uid: _uid, token: 'wrong-token'),
        ]) {
          expect(
            await adapter.claimAllowed(
              intent,
              firebaseUid: binding.uid,
              token: binding.token,
              now: f.now,
            ),
            isFalse,
          );
        }
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          intent.toJson(),
        );
        await DriftOwnerOperationGate(
          f.database,
        ).beginOwnerFence(ownerId: _owner, token: _gate, nowUtc: f.now);
        expect(await claim(s), isEmpty);
        expect(
          (await f.database.select(f.database.outboxOperations).getSingle())
              .toJson(),
          intent.toJson(),
        );
        expect(
          (await f.database.select(f.database.researchConsents).getSingle())
              .consentState,
          'withdrawn',
        );
        expect(seen, isEmpty);
      },
    );
    test(
      'withdrawal recovery works for expired revoked and deleted local permits',
      () async {
        await withdrawLocally();
        final signed = signedPermitUpdate(revoked: true, deleted: true);
        await (f.database.update(
          f.database.researchParticipationPermits,
        )..where((r) => r.id.equals('permit:a'))).write(
          ResearchParticipationPermitsCompanion(
            localRevision: const Value(2),
            cloudRevision: const Value(2),
            isDeleted: const Value(true),
            revokedAtUtcMs: Value(f.now.millisecondsSinceEpoch),
            expiresAtUtcMs: Value(
              DateTime.utc(2026, 9, 9).millisecondsSinceEpoch,
            ),
            payloadSha256: Value(signed['payloadSha256']! as String),
            signature: Value(signed['signature']! as String),
          ),
        );
        f.now = DateTime.utc(2026, 9, 10);
        await DriftOwnerOperationGate(f.database).tryAcquire(
          token: _gate,
          nowUtc: f.now,
          leaseDuration: const Duration(minutes: 10),
        );
        final recovered = await claim(store(callback: false));
        expect(recovered, hasLength(1));
        expect(
          recovered.single.mutation.collection.wireName,
          'research_withdrawals',
        );
        expect(recovered.single.mutation.payload, {
          'permitId': 'permit:a',
          'ownerId': _owner,
        });
        expect(seen, isEmpty);
      },
    );
    test(
      'offline withdrawal retry preserves identity and acknowledgement prevents requeue',
      () async {
        await withdrawLocally();
        final s = store(callback: false);
        final initial = (await claim(s)).single;
        final reserved = await s.beginAttempt(
          claim: initial,
          ownerGateToken: _gate,
          nowUtc: f.now,
        );
        expect(reserved, isNotNull);
        expect(
          await s.markRetry(
            operationId: initial.localOperationId,
            leaseToken: initial.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            nextAttemptAtUtc: f.now,
            failure: const OfflineSyncFailure(),
          ),
          isTrue,
        );
        // A new store instance recovers solely from durable local state.
        final restarted = store(callback: false);
        final retry = (await claim(restarted)).single;
        expect(retry.localOperationId, initial.localOperationId);
        expect(retry.mutation.payload, initial.mutation.payload);
        expect(
          await restarted.acknowledge(
            operationId: retry.localOperationId,
            leaseToken: retry.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            acknowledgement: PushAcknowledged(
              operationId: retry.mutation.operationId,
              resultingRevision: 1,
              acknowledgedAtUtc: f.now,
            ),
          ),
          isTrue,
        );
        expect(await claim(store(callback: false)), isEmpty);
        expect(
          await f.database.select(f.database.outboxOperations).get(),
          hasLength(1),
        );
      },
    );
    test(
      'offline denial after reaccept blocks a second database through the real gateway',
      () async {
        final receiver = MotivationResearchFixture();
        addTearDown(receiver.database.close);
        await receiver.initialize();
        await (receiver.database.update(receiver.database.localOwners)
              ..where((row) => row.id.equals(_owner)))
            .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
        final receiverRun = await receiver.measurements.start(
          const MotivationMeasurementStart(
            ownerId: _owner,
            permitId: 'permit:a',
          ),
        );
        expect(
          await DriftOwnerOperationGate(receiver.database).tryAcquire(
            token: _gate,
            nowUtc: receiver.now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final receiverStore = DriftSyncStore(
          receiver.database,
          researchMeasurementRollout: _rollout,
          // Existing synthetic authority seam; server policy is modeled below.
          researchAuthorizer: (_) async => true,
        );
        Future<List<ClaimedSyncOperation>> receiverClaims() =>
            receiverStore.claimPending(
              ownerId: _owner,
              firebaseUid: _uid,
              limit: 20,
              leaseToken: 'receiver-lease',
              ownerGateToken: _gate,
              leaseDuration: const Duration(minutes: 1),
              nowUtc: receiver.now,
            );
        final server = _DenialServer(() => f.now);
        final senderGateway = FirestoreSyncGateway(
          firestore: server,
          auth: _DenialAuth(),
          utcClock: () => f.now,
          researchMeasurementRollout: _rollout,
        );
        final receiverGateway = FirestoreSyncGateway(
          firestore: server,
          auth: _DenialAuth(),
          utcClock: () => receiver.now,
          researchMeasurementRollout: _rollout,
          researchAuthorizer: (_) async => true,
        );
        final before = await receiverClaims();
        final permit = before.singleWhere(
          (claim) =>
              claim.mutation.collection ==
              SyncCollection.researchParticipationPermits,
        );
        final permitPath =
            'field_users/$_uid/research_participation_permits/permit:a';
        // Synthetic issuer fixture only; neither client is allowed to issue it.
        server.documents[permitPath] = Map<String, dynamic>.from(
          FirestoreSyncCodec.encodeEntity(
            permit.mutation,
            serverTimestamp: Timestamp.fromDate(f.now),
          ),
        );
        for (final initial in before) {
          expect(
            await receiverStore.beginAttempt(
              claim: initial,
              ownerGateToken: _gate,
              nowUtc: receiver.now,
            ),
            isNotNull,
          );
          final ack =
              await receiverGateway.push(initial.mutation) as PushAcknowledged;
          expect(
            await receiverStore.acknowledge(
              operationId: initial.localOperationId,
              leaseToken: initial.leaseToken,
              ownerGateToken: _gate,
              nowUtc: receiver.now,
              acknowledgement: ack,
            ),
            isTrue,
          );
        }
        final runPath =
            'field_users/$_uid/motivation_measurement_runs/${receiverRun.id}';
        expect(
          server.documents.containsKey(runPath),
          isTrue,
          reason: 'Receiver research succeeds before the targeted denial.',
        );
        final originalPermit = Map<String, dynamic>.from(
          server.documents[permitPath]!,
        );

        // No prior enqueue or retained run can backfill this denial after
        // reaccept. The source must preserve it inside the consent transaction.
        await f.database.delete(f.database.motivationMeasurementRuns).go();
        await withdrawLocally();
        expect(
          server.markerWrites,
          0,
          reason: 'Withdrawal is local while offline.',
        );
        f.now = f.now.add(const Duration(seconds: 1));
        await DriftResearchConsentRepository(f.database).decide(
          ownerId: _owner,
          version: 1,
          accepted: true,
          decidedAtUtc: f.now,
        );
        final senderStore = store(callback: false);
        final denial = (await claim(senderStore)).single;
        expect(denial.mutation.collection, SyncCollection.researchWithdrawals);
        expect(denial.mutation.operationId, withdrawalId());
        expect(denial.mutation.payload, {
          'permitId': 'permit:a',
          'ownerId': _owner,
        });
        expect(
          await senderStore.beginAttempt(
            claim: denial,
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          isNotNull,
        );
        final denialAck =
            await senderGateway.push(denial.mutation) as PushAcknowledged;
        final markerPath = 'field_users/$_uid/research_withdrawals/permit:a';
        final marker = server.documents[markerPath]!;
        expect(marker, {
          'schemaVersion': 1,
          'permitId': 'permit:a',
          'ownerId': _owner,
          'withdrawnAt': Timestamp.fromDate(f.now),
        });
        final retryAck =
            await senderGateway.push(denial.mutation) as PushAcknowledged;
        expect(retryAck.operationId, denialAck.operationId);
        expect(retryAck.acknowledgedAtUtc, denialAck.acknowledgedAtUtc);
        expect(
          server.markerWrites,
          1,
          reason: 'Lost ACK reuses the create-once marker.',
        );
        expect(
          await senderStore.acknowledge(
            operationId: denial.localOperationId,
            leaseToken: denial.leaseToken,
            ownerGateToken: _gate,
            nowUtc: f.now,
            acknowledgement: retryAck,
          ),
          isTrue,
        );

        receiver.now = f.now;
        await receiver.measurements.record(
          MotivationResponse(
            ownerId: _owner,
            runId: receiverRun.id,
            itemId: 'baseline',
            responseCode: 'high',
          ),
        );
        final attempted = (await receiverClaims()).singleWhere(
          (claim) =>
              claim.mutation.collection == SyncCollection.motivationResponses,
        );
        expect(
          await receiverStore.beginAttempt(
            claim: attempted,
            ownerGateToken: _gate,
            nowUtc: receiver.now,
          ),
          isNotNull,
        );
        final committedBefore = server.documents.map(
          (path, data) => MapEntry(path, Map<String, dynamic>.from(data)),
        );
        await expectLater(
          receiverGateway.push(attempted.mutation),
          throwsA(isA<PermissionDeniedSyncFailure>()),
        );
        expect(server.deniedResearchWrites, 1);
        expect(
          server.documents,
          committedBefore,
          reason: 'Neither entity nor acknowledgement may commit after denial.',
        );
        final pending =
            await (receiver.database.select(receiver.database.outboxOperations)
                  ..where(
                    (row) => row.operationId.equals(attempted.localOperationId),
                  ))
                .getSingle();
        expect(pending.state, isNot('acknowledged'));
        expect(server.documents[permitPath], originalPermit);
        for (final database in [f.database, receiver.database]) {
          expect(
            (await database.select(database.researchConsents).getSingle())
                .consentState,
            'accepted',
            reason: 'A denial marker is not a fabricated local consent update.',
          );
          expect(
            (await database
                    .select(database.researchParticipationPermits)
                    .getSingle())
                .revokedAtUtcMs,
            isNull,
          );
        }
        expect(
          ResearchSyncContract.collections,
          isNot(contains(SyncCollection.researchWithdrawals)),
        );
      },
    );

    test(
      'unavailable pull authority cannot advance checkpoint past undelivered facts',
      () async {
        final s = store();
        final c = (await claim(s)).singleWhere(
          (c) =>
              c.mutation.collection == SyncCollection.motivationMeasurementRuns,
        );
        final entity = SyncEntity(
          collection: c.mutation.collection,
          entityId: runId,
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: f.now,
          serverUpdatedAtUtc: f.now,
          payload: c.mutation.payload,
        );
        final page = PullPage(
          changes: [entity],
          nextCursor: SyncCursor(serverUpdatedAtUtc: f.now, documentId: runId),
          hasMore: false,
        );
        allowed = false;
        try {
          await s.applyPullPage(
            ownerId: _owner,
            collection: entity.collection,
            page: page,
            ownerGateToken: _gate,
            nowUtc: f.now,
          );
        } on SyncFailure {
          /* Retriable authority outage is acceptable. */
        }
        expect(await s.readCheckpoint(_owner, entity.collection), isNull);
        allowed = true;
        expect(
          await s.applyPullPage(
            ownerId: _owner,
            collection: entity.collection,
            page: page,
            ownerGateToken: _gate,
            nowUtc: f.now,
          ),
          isTrue,
        );
        expect(
          await s.readCheckpoint(_owner, entity.collection),
          page.nextCursor,
        );
      },
    );
    test(
      'actual owner lifecycle fence denies even an otherwise allowed research claim',
      () async {
        final s = store();
        await DriftOwnerOperationGate(
          f.database,
        ).beginOwnerFence(ownerId: _owner, token: _gate, nowUtc: f.now);
        expect(await claim(s), isEmpty);
      },
    );
  });

  test(
    'preflight missing research authority cannot begin transaction',
    () async {
      var began = false;
      await expectLater(
        const FirestoreSyncPreflight().beforeTransaction(
          collection: SyncCollection.motivationResponses,
          payloadVersion: 1,
          beginTransaction: () async {
            began = true;
          },
        ),
        throwsA(isA<SyncFailure>()),
      );
      expect(began, isFalse);
    },
  );
}

// Narrow SDK-shaped driver: production gateway performs serialization,
// transactions and acknowledgement parsing. The denial write policy below is
// explicitly modeled, not an execution of Firestore rules; emulator tests own
// that separate assertion. It does not alter issuer permits or receipt data.
final class _DenialServer implements cloud.FirebaseFirestore {
  _DenialServer(this.nowUtc);
  final DateTime Function() nowUtc;
  final documents = <String, Map<String, dynamic>>{};
  int markerWrites = 0;
  int deniedResearchWrites = 0;
  @override
  cloud.Settings get settings =>
      const cloud.Settings(host: 'localhost:8080', sslEnabled: false);
  @override
  cloud.CollectionReference<Map<String, dynamic>> collection(String path) =>
      _DenialCollection(this, path);
  @override
  Future<T> runTransaction<T>(
    cloud.TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _DenialTransaction(this);
    final result = await handler(transaction);
    for (final entry in transaction.pending.entries) {
      final parts = entry.key.split('/');
      final collection = parts[2];
      if (collection == 'research_withdrawals') {
        final permit =
            documents['field_users/${parts[1]}/research_participation_permits/${parts[3]}'];
        final payload = permit?['payload'] as Map?;
        if (documents.containsKey(entry.key) ||
            payload?['ownerId'] != entry.value['ownerId'] ||
            payload?['id'] != entry.value['permitId']) {
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
      } else if (collection == 'motivation_measurement_runs' ||
          collection == 'motivation_responses') {
        final payload = entry.value['payload'] as Map;
        if (documents.containsKey(
          'field_users/${parts[1]}/research_withdrawals/${payload['permitId']}',
        )) {
          deniedResearchWrites++;
          throw FirebaseException(
            plugin: 'cloud_firestore',
            code: 'permission-denied',
          );
        }
      }
    }
    markerWrites += transaction.pending.keys
        .where((path) => path.contains('/research_withdrawals/'))
        .length;
    documents.addAll(transaction.pending);
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DenialTransaction implements cloud.Transaction {
  _DenialTransaction(this.server);
  final _DenialServer server;
  final pending = <String, Map<String, dynamic>>{};
  @override
  Future<cloud.DocumentSnapshot<T>> get<T extends Object?>(
    cloud.DocumentReference<T> ref,
  ) async => _DenialSnapshot<T>(ref.id, server.documents[ref.path] as T?);
  @override
  cloud.Transaction set<T>(
    cloud.DocumentReference<T> ref,
    T data, [
    cloud.SetOptions? options,
  ]) {
    pending[ref.path] = {
      for (final entry in (data as Map<String, dynamic>).entries)
        entry.key: entry.value is cloud.FieldValue
            ? Timestamp.fromDate(server.nowUtc())
            : entry.value,
    };
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _DenialCollection
    implements cloud.CollectionReference<Map<String, dynamic>> {
  _DenialCollection(this.server, this.path);
  final _DenialServer server;
  @override
  final String path;
  @override
  cloud.DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _DenialDocument(server, '$path/$id');
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _DenialDocument
    implements cloud.DocumentReference<Map<String, dynamic>> {
  _DenialDocument(this.server, this.path);
  final _DenialServer server;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  cloud.CollectionReference<Map<String, dynamic>> collection(String child) =>
      _DenialCollection(server, '$path/$child');
  @override
  Future<cloud.DocumentSnapshot<Map<String, dynamic>>> get([
    cloud.GetOptions? options,
  ]) async {
    expect(options?.source, cloud.Source.server);
    return _DenialSnapshot(id, server.documents[path]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _DenialSnapshot<T> implements cloud.DocumentSnapshot<T> {
  _DenialSnapshot(this.id, this.value);
  @override
  final String id;
  final T? value;
  @override
  bool get exists => value != null;
  @override
  T? data() => value;
  @override
  cloud.SnapshotMetadata get metadata => _DenialMetadata();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DenialMetadata extends Fake implements cloud.SnapshotMetadata {
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

final class _DenialAuth implements auth.FirebaseAuth {
  @override
  auth.User get currentUser => _DenialUser();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _DenialUser implements auth.User {
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
