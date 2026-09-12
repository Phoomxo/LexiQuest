import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart' as cloud;
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:firebase_auth/firebase_auth.dart' as auth;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_event_identity.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/research/domain/research_session_proof.dart';
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
const _uid = 'synthetic-proof-transport-uid';
const _gate = 'synthetic-proof-transport-gate';
const _rollout = ResearchMeasurementSyncRollout.localEmulatorV1(
  deployedRulesRevision: researchMeasurementV1RulesRevision,
);
SyncCollection get _proofs => ResearchSyncContract.collections.singleWhere(
  (collection) => collection.wireName == 'research_session_proofs',
);

// Real SQLite source/receiver, repositories, adapter, authorizer and gateway.
// Only issuer/signature/receipt policy and the in-process Firestore SDK driver
// are synthetic. This does not execute server rules or claim external approval.
void main() {
  late bool previousMultipleDatabaseWarning;
  setUpAll(() {
    previousMultipleDatabaseWarning =
        driftRuntimeOptions.dontWarnAboutMultipleDatabases;
    driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  });
  tearDownAll(() {
    driftRuntimeOptions.dontWarnAboutMultipleDatabases =
        previousMultipleDatabaseWarning;
  });
  late _Server server;
  late _Device sender;
  late _Device receiver;
  setUp(() async {
    server = _Server();
    sender = await _Device.create(server);
    receiver = await _Device.create(server);
  });

  test(
    'gateway transports Started before first answer and restores mission authority without learning effects',
    () async {
      sender.f.now = sender.f.now.add(const Duration(milliseconds: 123));
      receiver.f.now = sender.f.now;
      final opportunity = await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      final before = await receiver.learningEffects();
      final page = await receiver.page(_proofs);
      expect(page.changes, hasLength(1));
      final entity = page.changes.single;
      expect(
        ResearchSessionProof.decode(entity.payload).toJson(),
        entity.payload,
      );
      expect(entity.payload['proofRevision'], 1);
      expect(
        entity.serverReadProvenance!.matchesEntity(
          firebaseUid: _uid,
          entity: entity,
        ),
        isTrue,
      );
      expect(await receiver.apply(page, _proofs), isTrue);
      final proof = (await receiver.rows('research_session_proofs')).single;
      expect(proof['learning_session_id'], opportunity.learningSessionId);
      expect(proof['session_state'], 'active');
      expect(proof['ended_at_utc_ms'], isNull);
      expect(await receiver.learningEffects(), before);
      await receiver.pull(SyncCollection.measurementOpportunities);
      await receiver.pull(SyncCollection.neutralEventsV2);
      final restored = (await receiver.rows(
        'measurement_opportunities',
      )).single;
      expect(restored['started_event_id'], opportunity.startedEventId);
      expect(restored['learning_session_id'], opportunity.learningSessionId);
      final started =
          await (receiver.f.database.select(receiver.f.database.eventsV2)
                ..where(
                  (row) => row.eventId.equals(opportunity.startedEventId!),
                ))
              .getSingle();
      expect(
        researchEventOccurrence(started.eventId, started.occurredAtUtc.toUtc()),
        sender.f.now,
      );
      expect(await receiver.learningEffects(), before);
      expect(await sender.rows('answer_attempts'), isEmpty);
      expect(server.proofTransactionWrites, 1);
      expect(server.serverQueries, greaterThanOrEqualTo(5));
    },
  );

  test(
    'Completed-first then matching Started stays two phases with zero-answer completion',
    () async {
      final opportunity = await sender.accepted();
      await sender.finish(opportunity);
      receiver.f.now = sender.f.now;
      await sender.upload(completedFirst: true);
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      final before = await receiver.learningEffects();
      final completedPage = await receiver.page(_proofs, limit: 1);
      expect(completedPage.changes.single.payload['proofRevision'], 2);
      expect(await receiver.apply(completedPage, _proofs), isTrue);
      final original = (await receiver.rows('research_session_proofs')).single;
      expect(original['session_state'], 'completed');
      final startedPage = await receiver.page(_proofs, limit: 1);
      expect(startedPage.changes.single.payload['proofRevision'], 1);
      expect(await receiver.apply(startedPage, _proofs), isTrue);
      final rows = await receiver.rows('research_session_proofs');
      expect(rows, hasLength(2));
      expect(rows.singleWhere((row) => row['proof_revision'] == 2), original);
      await receiver.pull(SyncCollection.measurementOpportunities);
      await receiver.pull(SyncCollection.neutralEventsV2);
      expect(
        (await receiver.rows(
          'measurement_opportunities',
        )).single['completed_event_id'],
        isNotNull,
      );
      expect(await receiver.learningEffects(), before);
      expect(await sender.rows('answer_attempts'), isEmpty);
      expect(server.proofTransactionWrites, 2);
    },
  );

  for (final placeholder in [true, false]) {
    test(
      'gateway proof ${placeholder ? 'leaves syncedEvidence untouched' : 'rejects contradictory canonical source'}',
      () async {
        final opportunity = await sender.accepted();
        await sender.upload();
        await receiver.pull(SyncCollection.motivationMeasurementRuns);
        await receiver.f.database.customStatement(
          'INSERT INTO learning_sessions(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES(?,?,?,?,?,?,?)',
          [
            opportunity.learningSessionId,
            _owner,
            placeholder ? 'syncedEvidence' : 'quiz',
            placeholder ? 'syncedEvidence' : 'active',
            receiver.f.now.millisecondsSinceEpoch + 25,
            placeholder ? 'unknown' : '1',
            placeholder ? 'synced' : 'test',
          ],
        );
        // This is the exact SQL shape produced by the existing answer importer.
        // Its timestamp is an answer occurrence, never an invented session start.
        final before = await receiver.learningEffects();
        final page = await receiver.page(_proofs);
        if (placeholder) {
          expect(await receiver.apply(page, _proofs), isTrue);
          expect(await receiver.rows('research_session_proofs'), hasLength(1));
          await receiver.pull(SyncCollection.measurementOpportunities);
        } else {
          await expectLater(
            receiver.apply(page, _proofs),
            throwsA(isA<SyncFailure>()),
          );
          expect(await receiver.rows('research_session_proofs'), isEmpty);
          expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
        }
        expect(await receiver.learningEffects(), before);
      },
    );
  }

  test(
    'two-opportunity page rolls back first insert and cursor until second session proof arrives',
    () async {
      await sender.accepted();
      await sender.upload();
      await sender.accepted(
        sessionId: 'session:second-source',
        entryAttemptId: '22222222-2222-4222-8222-222222222222',
      );
      await sender.upload();
      // Driver cursor ordering reflects the actual gateway's timestamp/id query.
      // Both entries share their authentic canonical run, whose identity is
      // deterministic per owner/permit. Only the first session proof is admitted.
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      await receiver.pull(_proofs, limit: 1);
      final before = await receiver.learningEffects();
      final page = await receiver.page(SyncCollection.measurementOpportunities);
      expect(page.changes, hasLength(2));
      final firstSession = (await receiver.rows(
        'research_session_proofs',
      )).single['learning_session_id'];
      expect(page.changes.first.payload['learningSessionId'], firstSession);
      expect(
        page.changes.last.payload['learningSessionId'],
        isNot(firstSession),
      );
      await expectLater(
        receiver.apply(page, SyncCollection.measurementOpportunities),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.rows('measurement_opportunities'), isEmpty);
      expect(
        await receiver.store.readCheckpoint(
          _owner,
          SyncCollection.measurementOpportunities,
        ),
        isNull,
      );
      expect(await receiver.learningEffects(), before);
      await receiver.pull(_proofs);
      expect(
        await receiver.apply(page, SyncCollection.measurementOpportunities),
        isTrue,
      );
      expect(await receiver.rows('measurement_opportunities'), hasLength(2));
      expect(
        await receiver.store.readCheckpoint(
          _owner,
          SyncCollection.measurementOpportunities,
        ),
        page.nextCursor,
      );
      expect(await receiver.learningEffects(), before);
    },
  );

  test(
    'same proof ID changed to renewed permit pins is rejected without delivery acknowledgement',
    () async {
      await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(_proofs);
      final before = await receiver.rows('research_session_proofs');
      final checkpoint = await receiver.store.readCheckpoint(_owner, _proofs);
      final effects = await receiver.learningEffects();
      final previous = receiver.f.permit();
      var renewed = ResearchParticipationPermit(
        id: previous.id,
        ownerId: previous.ownerId,
        participantClass: previous.participantClass,
        ageBandCode: previous.ageBandCode,
        assignmentId: previous.assignmentId,
        assignedTreatment: previous.assignedTreatment,
        consentReceiptId: previous.consentReceiptId,
        guardianPermissionReceiptRef: previous.guardianPermissionReceiptRef,
        learnerAssentReceiptRef: previous.learnerAssentReceiptRef,
        protocolId: previous.protocolId,
        protocolVersion: previous.protocolVersion,
        issuedAtUtc: previous.issuedAtUtc,
        expiresAtUtc: DateTime.utc(2026, 9, 9),
        revokedAtUtc: previous.revokedAtUtc,
        issuerKeyId: previous.issuerKeyId,
        payloadSha256: '',
        signature: previous.signature,
        localRevision: 2,
        cloudRevision: 2,
        isDeleted: previous.isDeleted,
      );
      renewed = renewed.copyWith(
        payloadSha256: sha256
            .convert(utf8.encode(renewed.canonicalPayload()))
            .toString(),
      );
      await receiver.f.participation.importPermit(renewed);
      final id = before.single['id']! as String;
      // Deliberately contradictory server document, read through the gateway.
      // Current permit validity alone must not turn new pins into the same fact.
      final path = 'field_users/$_uid/research_session_proofs/$id';
      final document = _copyMap(server.documents[path]!);
      document['payload'] = {
        ...Map<String, dynamic>.from(document['payload'] as Map),
        'permitPayloadSha256': renewed.payloadSha256,
        'permitRevision': 2,
      };
      document['serverUpdatedAt'] = server.tick();
      server.documents[path] = document;
      final page = await receiver.page(_proofs);
      expect(page.changes.single.entityId, id);
      expect(page.changes.single.serverReadProvenance, isNotNull);
      await expectLater(
        receiver.apply(page, _proofs),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.rows('research_session_proofs'), before);
      expect(await receiver.store.readCheckpoint(_owner, _proofs), checkpoint);
      expect(await receiver.learningEffects(), effects);
    },
  );

  for (final changedPayload in [false, true]) {
    test(
      'retained proof tombstone ${changedPayload ? 'rejects changed immutable replay without cursor advance' : 'ignores exact replay without renewed authority or acknowledgement'}',
      () async {
        await sender.accepted();
        await sender.upload();
        await receiver.pull(SyncCollection.motivationMeasurementRuns);
        await receiver.pull(_proofs);
        final id =
            (await receiver.rows('research_session_proofs')).single['id']!
                as String;
        await receiver.f.database.customStatement(
          'UPDATE research_session_proofs SET is_deleted = 1 WHERE id = ? AND owner_id = ?',
          [id, _owner],
        );
        final retained = await receiver.rows('research_session_proofs');
        expect(retained.single['is_deleted'], 1);
        final operations = await receiver.rows('outbox_operations');
        final checkpoint = await receiver.store.readCheckpoint(_owner, _proofs);
        final effects = await receiver.learningEffects();
        final path = 'field_users/$_uid/research_session_proofs/$id';
        final document = _copyMap(server.documents[path]!);
        if (changedPayload) {
          // Explicit synthetic server contradiction, still a valid codec shape.
          document['payload'] = {
            ...Map<String, dynamic>.from(document['payload'] as Map),
            'buildId': 'synthetic-contradictory-build',
          };
        }
        document['serverUpdatedAt'] = server.tick();
        server.documents[path] = document;
        final page = await receiver.page(_proofs);
        expect(page.changes, hasLength(1));
        expect(page.nextCursor, isNot(checkpoint));
        expect(
          page.changes.single.serverReadProvenance!.matchesEntity(
            firebaseUid: _uid,
            entity: page.changes.single,
          ),
          isTrue,
        );
        expect(ResearchSessionProof.decode(page.changes.single.payload).id, id);
        if (changedPayload) {
          await expectLater(
            receiver.apply(page, _proofs),
            throwsA(isA<SyncFailure>()),
          );
          expect(
            await receiver.store.readCheckpoint(_owner, _proofs),
            checkpoint,
          );
        } else {
          // Ignoring this exact historical tombstone must not require granting
          // current participation again, or overwrite its first delivery ACK.
          receiver.f.authority.validSignature = false;
          try {
            expect(await receiver.apply(page, _proofs), isTrue);
          } finally {
            receiver.f.authority.validSignature = true;
          }
          expect(
            await receiver.store.readCheckpoint(_owner, _proofs),
            page.nextCursor,
          );
        }
        expect(await receiver.rows('research_session_proofs'), retained);
        expect(await receiver.rows('outbox_operations'), operations);
        expect(await receiver.learningEffects(), effects);
      },
    );
  }

  test(
    'standalone decode of a current-pin proof has no gateway provenance and cannot be imported',
    () async {
      await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      final gatewayPage = await receiver.page(_proofs);
      final actual = gatewayPage.changes.single;
      final decoded = FirestoreSyncCodec.decodeEntity(
        collection: _proofs,
        documentId: actual.entityId,
        data: server
            .documents['field_users/$_uid/research_session_proofs/${actual.entityId}']!,
        expectedFirebaseUid: _uid,
      );
      expect(decoded.serverReadProvenance, isNull);
      final untrusted = PullPage(
        changes: [decoded],
        nextCursor: gatewayPage.nextCursor,
        hasMore: false,
      );
      final before = await receiver.learningEffects();
      await expectLater(
        receiver.apply(untrusted, _proofs),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.rows('research_session_proofs'), isEmpty);
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
      expect(await receiver.apply(gatewayPage, _proofs), isTrue);
      expect(await receiver.learningEffects(), before);
    },
  );

  test(
    'lost source ACK retries existing gateway receipt without rewriting immutable proof',
    () async {
      await sender.accepted();
      final claims = await sender.claims();
      final proof = claims.singleWhere(
        (claim) => claim.mutation.collection == _proofs,
      );
      await sender.uploadClaims(
        claims.where((claim) => claim != proof).toList(),
      );
      final attempt = await sender.store.beginAttempt(
        claim: proof,
        ownerGateToken: _gate,
        nowUtc: sender.f.now,
      );
      expect(attempt, isNotNull);
      final first =
          await sender.gateway.push(attempt!.mutation) as PushAcknowledged;
      final path =
          'field_users/$_uid/research_session_proofs/${proof.mutation.entityId}';
      final original = _copyMap(server.documents[path]!);
      final second =
          await sender.gateway.push(attempt.mutation) as PushAcknowledged;
      expect(second.operationId, first.operationId);
      expect(second.acknowledgedAtUtc, first.acknowledgedAtUtc);
      expect(server.documents[path], original);
      expect(server.proofTransactionWrites, 1);
      expect(
        await sender.store.acknowledge(
          operationId: proof.localOperationId,
          leaseToken: proof.leaseToken,
          ownerGateToken: _gate,
          nowUtc: sender.f.now,
          acknowledgement: second,
        ),
        isTrue,
      );
    },
  );

  Future<void> expectPullAllowed(SyncEntity entity) async {
    expect(entity.serverReadProvenance, isNotNull);
    expect(
      await receiver.authority.authorize(
        ResearchSyncRequest(
          phase: ResearchSyncPhase.pull,
          ownerId: _owner,
          firebaseUid: _uid,
          collection: entity.collection,
          entityId: entity.entityId,
          payload: entity.payload,
          evaluatedAtUtc: receiver.f.now,
          ownerGateToken: _gate,
          serverReadProvenance: entity.serverReadProvenance,
        ),
      ),
      isTrue,
      reason: 'genuine gateway candidate must pass before race injection',
    );
  }

  test(
    'actual atomic Pair learning travels through gateway without receiver canonical hydration',
    () async {
      const operation = 'transport-pair-learning';
      final session = pairSessionId(_owner, operation);
      final opportunity = await sender.accepted(
        sessionId: session,
        startActivity: () => sender.startPair(operation),
      );
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      final before = await receiver.learningEffects();
      final page = await receiver.page(_proofs);
      expect(page.changes, hasLength(1));
      final proof = ResearchSessionProof.decode(page.changes.single.payload);
      expect(proof.toJson(), page.changes.single.payload);
      expect(proof.activityType, 'matching');
      expect(proof.learningSessionId, session);
      expect(proof.pairOwnerLineage, hasLength(1));
      expect(proof.pairOwnerLineage!.single.keys.toSet(), {
        'ownerId',
        'createdAtUtcMs',
        'upgradedAtUtcMs',
        'mergedIntoOwnerId',
      });
      expect(proof.pairOwnerLineage!.single['ownerId'], _owner);
      final start = PairMatchingStartOperation.fromStableSerialization(
        proof.pairStartOperation!,
      );
      expect(start.plan.sessionPurpose, PairSessionPurpose.learning);
      await expectPullAllowed(page.changes.single);
      expect(await receiver.apply(page, _proofs), isTrue);
      await receiver.pull(SyncCollection.measurementOpportunities);
      await receiver.pull(SyncCollection.neutralEventsV2);
      expect(
        (await receiver.rows(
          'measurement_opportunities',
        )).single['learning_session_id'],
        session,
      );
      expect(
        (await receiver.rows(
          'measurement_opportunities',
        )).single['started_event_id'],
        opportunity.startedEventId,
      );
      expect(await receiver.learningEffects(), before);
      expect(await receiver.rows('research_session_proofs'), hasLength(1));
      expect(server.proofTransactionWrites, 1);
    },
  );

  for (final corruption in ['invalid start JSON', 'valid replay operation']) {
    test('gateway refuses compact Pair proof with $corruption', () async {
      const operation = 'transport-pair-learning';
      await sender.accepted(
        sessionId: pairSessionId(_owner, operation),
        startActivity: () => sender.startPair(operation),
      );
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      final validPage = await receiver.page(_proofs);
      final entity = validPage.changes.single;
      await expectPullAllowed(entity);
      final path =
          'field_users/$_uid/research_session_proofs/${entity.entityId}';
      final original = _copyMap(server.documents[path]!);
      final altered = _copyMap(original);
      final payload = Map<String, dynamic>.from(altered['payload'] as Map);
      if (corruption == 'invalid start JSON') {
        payload['pairStartOperation'] = '{}';
      } else {
        final start = PairMatchingStartOperation.fromStableSerialization(
          payload['pairStartOperation'] as String,
        );
        final plan = start.plan;
        final replay = PairMatchingStartOperation(
          plan: PairMatchingPlanV1(
            ownerId: plan.ownerId,
            orderedLexicalItems: plan.orderedLexicalItems,
            direction: plan.direction,
            density: plan.density,
            shuffleSeed: plan.shuffleSeed,
            timerPreset: plan.timerPreset,
            allowlistVersion: plan.allowlistVersion,
            learningSessionId: plan.learningSessionId,
            entryKind: plan.entryKind,
            sourceSnapshotId: plan.sourceSnapshotId,
            createdAtUtc: plan.createdAtUtc,
            sessionPurpose: PairSessionPurpose.practiceReplay,
            sourceSessionId: 'synthetic-prior-terminal',
          ),
          launchOperationId: start.launchOperationId,
          appVersion: start.appVersion,
          buildId: start.buildId,
          configuration: start.configuration,
        );
        // Valid domain serialization, intentionally forbidden research purpose.
        expect(
          PairMatchingStartOperation.fromStableSerialization(
            replay.stableSerialization,
          ).plan.sessionPurpose,
          PairSessionPurpose.practiceReplay,
        );
        payload['pairStartOperation'] = replay.stableSerialization;
      }
      altered['payload'] = payload;
      altered['serverUpdatedAt'] = server.tick();
      server.documents[path] = altered;
      final before = await receiver.learningEffects();
      await expectLater(receiver.pull(_proofs), throwsA(isA<SyncFailure>()));
      expect(await receiver.rows('research_session_proofs'), isEmpty);
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
      expect(await receiver.learningEffects(), before);
      // Restore only the synthetic server attack; genuine gateway provenance
      // must again admit the original content.
      server.documents[path] = original;
      await receiver.pull(_proofs);
      expect(await receiver.rows('research_session_proofs'), hasLength(1));
    });
  }

  for (final race in [
    'insert canonical conflict',
    'withdraw consent',
    'remove proof authority',
    'tombstone sibling',
  ]) {
    test('receipt await tracks receiver $race and rolls back the page', () async {
      final opportunity = await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      SyncCollection collection = _proofs;
      if (race == 'remove proof authority' || race == 'tombstone sibling') {
        await receiver.pull(_proofs);
      }
      if (race == 'remove proof authority') {
        collection = SyncCollection.measurementOpportunities;
      } else if (race == 'tombstone sibling') {
        await sender.finish(opportunity);
        receiver.f.now = sender.f.now;
        await sender.upload();
      }
      final page = await receiver.page(collection);
      expect(page.changes, hasLength(1));
      await expectPullAllowed(page.changes.single);
      final effects = await receiver.learningEffects();
      final proofs = await receiver.rows('research_session_proofs');
      final consents = await receiver.rows('research_consents');
      final operations = await receiver.rows('outbox_operations');
      final checkpoint = await receiver.store.readCheckpoint(
        _owner,
        collection,
      );
      var changed = false;
      receiver.f.authority.onRead = () async {
        receiver.f.authority.onRead = null;
        changed = true;
        switch (race) {
          case 'insert canonical conflict':
            await receiver.f.database.customStatement(
              'INSERT INTO learning_sessions(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) VALUES(?,?,?,?,?,?,?)',
              [
                opportunity.learningSessionId,
                _owner,
                'quiz',
                'active',
                receiver.f.now.millisecondsSinceEpoch + 25,
                '1',
                'test',
              ],
            );
          case 'withdraw consent':
            await DriftResearchConsentRepository(receiver.f.database).decide(
              ownerId: _owner,
              version: 1,
              accepted: false,
              decidedAtUtc: receiver.f.now,
            );
          case 'remove proof authority':
            await receiver.f.database.customStatement(
              'DELETE FROM research_session_proofs WHERE owner_id = ?',
              [_owner],
            );
          case 'tombstone sibling':
            await receiver.f.database.customStatement(
              'UPDATE research_session_proofs SET is_deleted = 1 WHERE owner_id = ? AND proof_revision = 1',
              [_owner],
            );
        }
      };
      try {
        await expectLater(
          receiver.apply(page, collection),
          throwsA(isA<SyncFailure>()),
        );
      } finally {
        receiver.f.authority.onRead = null;
      }
      expect(
        changed,
        isTrue,
        reason: 'race must execute within real receipt lookup',
      );
      expect(await receiver.learningEffects(), effects);
      expect(await receiver.rows('research_session_proofs'), proofs);
      expect(await receiver.rows('research_consents'), consents);
      expect(await receiver.rows('outbox_operations'), operations);
      expect(
        await receiver.store.readCheckpoint(_owner, collection),
        checkpoint,
      );
      expect(await receiver.apply(page, collection), isTrue);
    });
  }

  test(
    'gateway-admitted mirrors cannot authorize source enqueue claim or push',
    () async {
      final opportunity = await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      final before = await receiver.learningEffects();
      final proofPage = await receiver.page(_proofs);
      expect(await receiver.apply(proofPage, _proofs), isTrue);
      final opportunityPage = await receiver.page(
        SyncCollection.measurementOpportunities,
      );
      expect(
        await receiver.apply(
          opportunityPage,
          SyncCollection.measurementOpportunities,
        ),
        isTrue,
      );
      final eventPage = await receiver.page(SyncCollection.neutralEventsV2);
      expect(
        await receiver.apply(eventPage, SyncCollection.neutralEventsV2),
        isTrue,
      );
      final entities = [
        proofPage.changes.single,
        opportunityPage.changes.single,
        eventPage.changes.singleWhere(
          (entity) => entity.entityId == opportunity.startedEventId,
        ),
      ];
      expect(await receiver.rows('learning_sessions'), isEmpty);
      final operationsBefore = await receiver.rows('outbox_operations');
      final serverBefore = {
        for (final entry in server.documents.entries)
          entry.key: _copyMap(entry.value),
      };
      for (final entity in entities) {
        await expectPullAllowed(entity);
        for (final phase in [
          ResearchSyncPhase.enqueue,
          ResearchSyncPhase.claim,
          ResearchSyncPhase.push,
        ]) {
          for (final includeProvenance in [false, true]) {
            expect(
              await receiver.authority.authorize(
                ResearchSyncRequest(
                  phase: phase,
                  ownerId: _owner,
                  firebaseUid: _uid,
                  collection: entity.collection,
                  entityId: entity.entityId,
                  payload: entity.payload,
                  evaluatedAtUtc: receiver.f.now,
                  ownerGateToken: _gate,
                  serverReadProvenance: includeProvenance
                      ? entity.serverReadProvenance
                      : null,
                ),
              ),
              isFalse,
              reason:
                  '${entity.collection.name} $phase cannot reuse mirror authority, provenance=$includeProvenance',
            );
          }
        }
        // Even an already-existing server receipt is not an outbound permit.
        await expectLater(
          receiver.gateway.push(
            PushMutation(
              operationId: ResearchSyncContract.operationIdFor(
                collection: entity.collection,
                entityId: entity.entityId,
                payload: entity.payload,
                revision: entity.revision,
              ),
              firebaseUid: _uid,
              collection: entity.collection,
              entityId: entity.entityId,
              operationKind: SyncOperationKind.upsert,
              payloadVersion: entity.payloadVersion,
              baseRevision: entity.revision - 1,
              localRevision: entity.revision,
              clientUpdatedAtUtc: entity.clientUpdatedAtUtc,
              payload: entity.payload,
              ownerGateToken: _gate,
            ),
          ),
          throwsA(isA<PermissionDeniedSyncFailure>()),
        );
      }
      await receiver.store.enqueueResearchChanges(
        ownerId: _owner,
        firebaseUid: _uid,
        ownerGateToken: _gate,
        nowUtc: receiver.f.now,
      );
      final claims = await receiver.store.claimPending(
        ownerId: _owner,
        firebaseUid: _uid,
        limit: 50,
        leaseToken: 'mirror-must-not-be-claimed',
        ownerGateToken: _gate,
        leaseDuration: const Duration(minutes: 1),
        nowUtc: receiver.f.now,
      );
      final sourceCollections = {
        _proofs,
        SyncCollection.measurementOpportunities,
        SyncCollection.neutralEventsV2,
      };
      expect(
        claims.where(
          (claim) => sourceCollections.contains(claim.mutation.collection),
        ),
        isEmpty,
      );
      final sourceIds = entities.map((entity) => entity.entityId).toSet();
      expect(
        (await receiver.rows(
          'outbox_operations',
        )).where((row) => sourceIds.contains(row['entity_id'])).toList(),
        operationsBefore
            .where((row) => sourceIds.contains(row['entity_id']))
            .toList(),
      );
      expect(server.documents, serverBefore);
      expect(await receiver.learningEffects(), before);
    },
  );

  test(
    'renewed current permit admits old gateway proof and exact durable recovery only',
    () async {
      await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      await receiver.pull(SyncCollection.motivationResponses);
      final previous = receiver.f.permit();
      var renewed = ResearchParticipationPermit(
        id: previous.id,
        ownerId: previous.ownerId,
        participantClass: previous.participantClass,
        ageBandCode: previous.ageBandCode,
        assignmentId: previous.assignmentId,
        assignedTreatment: previous.assignedTreatment,
        consentReceiptId: previous.consentReceiptId,
        guardianPermissionReceiptRef: previous.guardianPermissionReceiptRef,
        learnerAssentReceiptRef: previous.learnerAssentReceiptRef,
        protocolId: previous.protocolId,
        protocolVersion: previous.protocolVersion,
        issuedAtUtc: previous.issuedAtUtc,
        expiresAtUtc: DateTime.utc(2026, 9, 9),
        revokedAtUtc: previous.revokedAtUtc,
        issuerKeyId: previous.issuerKeyId,
        payloadSha256: '',
        signature: previous.signature,
        localRevision: 2,
        cloudRevision: 2,
        isDeleted: previous.isDeleted,
      );
      renewed = renewed.copyWith(
        payloadSha256: sha256
            .convert(utf8.encode(renewed.canonicalPayload()))
            .toString(),
      );
      await receiver.f.participation.importPermit(renewed);
      expect(
        (await receiver.rows(
          'research_participation_permits',
        )).single['local_revision'],
        2,
      );
      final page = await receiver.page(_proofs);
      final entity = page.changes.single;
      expect(entity.payload['permitRevision'], 1);
      expect(entity.payload['permitPayloadSha256'], previous.payloadSha256);
      final document = server
          .documents['field_users/$_uid/research_session_proofs/${entity.entityId}']!;
      final unmarked = FirestoreSyncCodec.decodeEntity(
        collection: _proofs,
        documentId: entity.entityId,
        data: document,
        expectedFirebaseUid: _uid,
      );
      expect(unmarked.serverReadProvenance, isNull);
      final unmarkedPage = PullPage(
        changes: [unmarked],
        nextCursor: page.nextCursor,
        hasMore: false,
      );
      final effects = await receiver.learningEffects();
      await expectLater(
        receiver.apply(unmarkedPage, _proofs),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.rows('research_session_proofs'), isEmpty);
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);

      // Trusted server provenance never bypasses current permit authentication.
      receiver.f.authority.validSignature = false;
      try {
        await expectLater(
          receiver.apply(page, _proofs),
          throwsA(isA<SyncFailure>()),
        );
      } finally {
        receiver.f.authority.validSignature = true;
      }
      expect(await receiver.rows('research_session_proofs'), isEmpty);
      expect(await receiver.apply(page, _proofs), isTrue);
      final proofRows = await receiver.rows('research_session_proofs');
      final exactOperation = ResearchSyncContract.operationIdFor(
        collection: _proofs,
        entityId: entity.entityId,
        payload: entity.payload,
        revision: 1,
      );
      final delivery = (await receiver.rows(
        'outbox_operations',
      )).singleWhere((row) => row['operation_id'] == exactOperation);
      expect(delivery['state'], 'acknowledged');
      expect(delivery['owner_id'], _owner);
      expect(delivery['entity_id'], entity.entityId);
      expect(delivery['entity_type'], 'researchSessionProof');
      expect(proofRows.single['permit_revision'], 1);
      expect(proofRows.single['permit_payload_sha256'], previous.payloadSha256);
      Future<void> loseOnlyProofCheckpoint() async {
        final unrelated = (await receiver.rows('sync_checkpoints'))
            .where(
              (row) =>
                  row['owner_id'] != _owner ||
                  row['collection_name'] != _proofs.wireName,
            )
            .toList();
        await receiver.f.database.customStatement(
          'DELETE FROM sync_checkpoints WHERE owner_id = ? AND collection_name = ?',
          [_owner, _proofs.wireName],
        );
        expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
        expect(await receiver.rows('sync_checkpoints'), unrelated);
        expect(await receiver.rows('research_session_proofs'), proofRows);
      }

      // The exact local admission and real pull ACK now support lost-marker
      // recovery after loss of ONLY the local collection checkpoint. Keeping
      // the consumed cursor would correctly short-circuit page application.
      await loseOnlyProofCheckpoint();
      var recoveryReceiptReads = 0;
      receiver.f.authority.onRead = () async {
        recoveryReceiptReads++;
      };
      try {
        expect(await receiver.apply(unmarkedPage, _proofs), isTrue);
      } finally {
        receiver.f.authority.onRead = null;
      }
      expect(recoveryReceiptReads, greaterThan(0));
      expect(
        await receiver.store.readCheckpoint(_owner, _proofs),
        page.nextCursor,
      );
      expect(await receiver.rows('research_session_proofs'), proofRows);
      expect(
        (await receiver.rows(
          'outbox_operations',
        )).singleWhere((row) => row['operation_id'] == exactOperation),
        delivery,
      );

      final changed = _copyMap(document);
      changed['payload'] = {
        ...Map<String, dynamic>.from(changed['payload'] as Map),
        'permitPayloadSha256': renewed.payloadSha256,
        'permitRevision': 2,
      };
      final contradictory = FirestoreSyncCodec.decodeEntity(
        collection: _proofs,
        documentId: entity.entityId,
        data: changed,
        expectedFirebaseUid: _uid,
      );
      await loseOnlyProofCheckpoint();
      await expectLater(
        receiver.apply(
          PullPage(
            changes: [contradictory],
            nextCursor: page.nextCursor,
            hasMore: false,
          ),
          _proofs,
        ),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
      expect(await receiver.rows('research_session_proofs'), proofRows);
      expect(
        (await receiver.rows(
          'outbox_operations',
        )).singleWhere((row) => row['operation_id'] == exactOperation),
        delivery,
      );
      // Removing only the actual durable admission is a negative disk-state
      // fixture. A known mirror alone must not grant unmarked historical pull.
      await receiver.f.database.customStatement(
        'DELETE FROM outbox_operations WHERE operation_id = ?',
        [exactOperation],
      );
      await loseOnlyProofCheckpoint();
      // Exercise the real authorizer explicitly as well: without the ACK,
      // adapter preflight may deny before invoking external receipt authority.
      expect(
        await receiver.authority.authorize(
          ResearchSyncRequest(
            phase: ResearchSyncPhase.pull,
            ownerId: _owner,
            firebaseUid: _uid,
            collection: _proofs,
            entityId: unmarked.entityId,
            payload: unmarked.payload,
            evaluatedAtUtc: receiver.f.now,
            ownerGateToken: _gate,
          ),
        ),
        isFalse,
      );
      await expectLater(
        receiver.apply(unmarkedPage, _proofs),
        throwsA(isA<SyncFailure>()),
      );
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
      expect(await receiver.rows('research_session_proofs'), proofRows);
      expect(
        (await receiver.rows(
          'outbox_operations',
        )).where((row) => row['operation_id'] == exactOperation),
        isEmpty,
      );
      expect(await receiver.learningEffects(), effects);
    },
  );

  test(
    'newer different-version withdrawal during receipt denies gateway proof admission',
    () async {
      await sender.accepted();
      await sender.upload();
      await receiver.pull(SyncCollection.motivationMeasurementRuns);
      final page = await receiver.page(_proofs);
      await expectPullAllowed(page.changes.single);
      final beforeConsents = await receiver.rows('research_consents');
      final beforeOperations = await receiver.rows('outbox_operations');
      final effects = await receiver.learningEffects();
      var changed = false;
      receiver.f.authority.onRead = () async {
        receiver.f.authority.onRead = null;
        // Persist a newer-version withdrawal while retaining the accepted
        // configured-version row and live run, isolating latest-consent policy.
        await receiver.f.database
            .into(receiver.f.database.researchConsents)
            .insert(
              ResearchConsentsCompanion.insert(
                id: 'synthetic:receiver-newer-withdrawal',
                ownerId: _owner,
                consentVersion: 2,
                consentState: 'withdrawn',
                decidedAtUtcMs: receiver.f.now.millisecondsSinceEpoch,
                withdrawnAtUtcMs: Value(receiver.f.now.millisecondsSinceEpoch),
              ),
            );
        final consents = await receiver.rows('research_consents');
        expect(
          consents.singleWhere(
            (row) => row['consent_version'] == 1,
          )['consent_state'],
          'accepted',
        );
        expect(
          consents.singleWhere(
            (row) => row['consent_version'] == 2,
          )['consent_state'],
          'withdrawn',
        );
        expect(
          (await receiver.rows('motivation_measurement_runs')).single['state'],
          'started',
        );
        changed = true;
      };
      try {
        await expectLater(
          receiver.apply(page, _proofs),
          throwsA(isA<SyncFailure>()),
        );
      } finally {
        receiver.f.authority.onRead = null;
      }
      expect(changed, isTrue);
      expect(await receiver.rows('research_session_proofs'), isEmpty);
      expect(await receiver.rows('research_consents'), beforeConsents);
      expect(await receiver.rows('outbox_operations'), beforeOperations);
      expect(await receiver.store.readCheckpoint(_owner, _proofs), isNull);
      expect(await receiver.learningEffects(), effects);
      expect(await receiver.apply(page, _proofs), isTrue);
    },
  );

  for (final enrolled in [false, true]) {
    test(
      '${enrolled ? 'off rollout accepted' : 'nonparticipant ordinary'} session produces no proof transport',
      () async {
        final device = await _Device.create(
          server,
          enrolled: enrolled,
          enabled: !enrolled,
        );
        if (enrolled) {
          await device.accepted();
        } else {
          await device.start('session:ordinary');
        }
        final before = await device.learningEffects();
        await device.store.enqueueResearchChanges(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _gate,
          nowUtc: device.f.now,
        );
        expect(await device.rows('research_session_proofs'), isEmpty);
        expect(await device.rows('outbox_operations'), isEmpty);
        expect(await device.learningEffects(), before);
        expect(server.proofTransactionWrites, 0);
      },
    );
  }
}

Map<String, dynamic> _copyMap(Map source) => {
  for (final entry in source.entries)
    entry.key as String: switch (entry.value) {
      Map value => _copyMap(value),
      List value => [
        for (final item in value) item is Map ? _copyMap(item) : item,
      ],
      final value => value,
    },
};

final class _Auth implements auth.FirebaseAuth {
  @override
  auth.User get currentUser => _User();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _User implements auth.User {
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// Narrow SDK driver: gateway code owns encoding, transaction ordering,
// conflict/receipt parsing, server reads and provenance creation. This is not a
// Firestore security-rules emulator. All staged writes commit atomically.
final class _Server implements cloud.FirebaseFirestore {
  final documents = <String, Map<String, dynamic>>{};
  var _sequence = 0;
  var proofTransactionWrites = 0;
  var serverQueries = 0;
  cloud.Timestamp tick() => cloud.Timestamp.fromDate(
    DateTime.utc(2026, 9, 5, 12, 0, 5).add(Duration(milliseconds: _sequence++)),
  );
  @override
  cloud.Settings get settings =>
      const cloud.Settings(host: 'localhost:8080', sslEnabled: false);
  @override
  cloud.CollectionReference<Map<String, dynamic>> collection(String path) =>
      _Collection(this, path);
  @override
  Future<T> runTransaction<T>(
    cloud.TransactionHandler<T> handler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    final transaction = _Transaction(this);
    final result = await handler(transaction);
    for (final entry in transaction.pending.entries) {
      documents[entry.key] = _copyMap(entry.value);
      if (entry.key.contains('/research_session_proofs/'))
        proofTransactionWrites++;
    }
    return result;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _Collection
    implements cloud.CollectionReference<Map<String, dynamic>> {
  _Collection(this.server, this.path, {this.after, this.maximum = 50});
  final _Server server;
  @override
  final String path;
  final List<Object?>? after;
  final int maximum;
  @override
  cloud.DocumentReference<Map<String, dynamic>> doc([String? id]) =>
      _Document(server, '$path/$id');
  @override
  cloud.Query<Map<String, dynamic>> orderBy(
    Object field, {
    bool descending = false,
  }) {
    expect(descending, isFalse);
    return this;
  }

  @override
  cloud.Query<Map<String, dynamic>> limit(int limit) =>
      _Collection(server, path, after: after, maximum: limit);
  @override
  cloud.Query<Map<String, dynamic>> startAfter(Iterable<Object?> values) =>
      _Collection(server, path, after: values.toList(), maximum: maximum);
  @override
  Future<cloud.QuerySnapshot<Map<String, dynamic>>> get([
    cloud.GetOptions? options,
  ]) async {
    expect(options?.source, cloud.Source.server);
    server.serverQueries++;
    final records =
        server.documents.entries
            .where(
              (entry) =>
                  entry.key.startsWith('$path/') &&
                  !entry.key.substring(path.length + 1).contains('/'),
            )
            .toList()
          ..sort(
            (a, b) => _compare(
              a.value['serverUpdatedAt'] as cloud.Timestamp,
              a.key.split('/').last,
              b.value['serverUpdatedAt'] as cloud.Timestamp,
              b.key.split('/').last,
            ),
          );
    final cursor = after;
    final selected = records
        .where(
          (entry) =>
              cursor == null ||
              _compare(
                    entry.value['serverUpdatedAt'] as cloud.Timestamp,
                    entry.key.split('/').last,
                    cursor[0]! as cloud.Timestamp,
                    cursor[1]! as String,
                  ) >
                  0,
        )
        .take(maximum)
        .toList();
    return _QuerySnapshot([
      for (final entry in selected)
        _QueryDocument(entry.key.split('/').last, _copyMap(entry.value)),
    ]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

int _compare(cloud.Timestamp a, String aId, cloud.Timestamp b, String bId) {
  final time = a.compareTo(b);
  return time != 0 ? time : aId.compareTo(bId);
}

// ignore: subtype_of_sealed_class
final class _Document implements cloud.DocumentReference<Map<String, dynamic>> {
  _Document(this.server, this.path);
  final _Server server;
  @override
  final String path;
  @override
  String get id => path.split('/').last;
  @override
  cloud.CollectionReference<Map<String, dynamic>> collection(String child) =>
      _Collection(server, '$path/$child');
  @override
  Future<cloud.DocumentSnapshot<Map<String, dynamic>>> get([
    cloud.GetOptions? options,
  ]) async {
    expect(options?.source, cloud.Source.server);
    final data = server.documents[path];
    return _DocumentSnapshot(id, data == null ? null : _copyMap(data));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Transaction implements cloud.Transaction {
  _Transaction(this.server);
  final _Server server;
  final pending = <String, Map<String, dynamic>>{};
  cloud.Timestamp? _commitTime;
  @override
  Future<cloud.DocumentSnapshot<T>> get<T extends Object?>(
    cloud.DocumentReference<T> document,
  ) async {
    expect(
      pending,
      isEmpty,
      reason: 'Gateway must finish reads before staging writes.',
    );
    final data = server.documents[document.path];
    return _DocumentSnapshot<T>(
      document.id,
      data == null ? null : _copyMap(data) as T,
    );
  }

  @override
  cloud.Transaction set<T>(
    cloud.DocumentReference<T> document,
    T data, [
    cloud.SetOptions? options,
  ]) {
    final time = _commitTime ??= server.tick();
    pending[document.path] = _copyMap({
      for (final entry in (data as Map<String, dynamic>).entries)
        entry.key: entry.value is cloud.FieldValue ? time : entry.value,
    });
    return this;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _Metadata extends Fake implements cloud.SnapshotMetadata {
  @override
  bool get isFromCache => false;
  @override
  bool get hasPendingWrites => false;
}

// ignore: subtype_of_sealed_class
final class _DocumentSnapshot<T> implements cloud.DocumentSnapshot<T> {
  _DocumentSnapshot(this.id, this.value);
  @override
  final String id;
  final T? value;
  @override
  bool get exists => value != null;
  @override
  T? data() => value;
  @override
  cloud.SnapshotMetadata get metadata => _Metadata();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

// ignore: subtype_of_sealed_class
final class _QuerySnapshot extends Fake
    implements cloud.QuerySnapshot<Map<String, dynamic>> {
  _QuerySnapshot(this.docs);
  @override
  final List<cloud.QueryDocumentSnapshot<Map<String, dynamic>>> docs;
  @override
  cloud.SnapshotMetadata get metadata => _Metadata();
}

// ignore: subtype_of_sealed_class
final class _QueryDocument extends Fake
    implements cloud.QueryDocumentSnapshot<Map<String, dynamic>> {
  _QueryDocument(this.id, this.value);
  @override
  final String id;
  final Map<String, dynamic> value;
  @override
  bool get exists => true;
  @override
  Map<String, dynamic> data() => value;
  @override
  cloud.SnapshotMetadata get metadata => _Metadata();
}

final class _Device {
  _Device(this.server, {required this.enabled});
  final _Server server;
  final bool enabled;
  final f = MotivationResearchFixture();
  late final learning = DriftLearningRepository(f.database);
  late final opportunities = DriftMeasurementOpportunityRepository(
    f.database,
    measurements: f.measurements,
    nowUtc: () => f.now,
  );
  late final authority = DriftResearchSyncAuthorizer(
    database: f.database,
    study: f.study,
    validator: f.participation.validator,
    nowUtc: () => f.now,
  );
  late final store = DriftSyncStore(
    f.database,
    researchMeasurementRollout: enabled
        ? _rollout
        : const ResearchMeasurementSyncRollout.off(),
    researchAuthorizer: authority.authorize,
    researchNowUtc: () => f.now,
  );
  late final gateway = FirestoreSyncGateway(
    firestore: server,
    auth: _Auth(),
    utcClock: () => f.now,
    researchMeasurementRollout: _rollout,
    researchAuthorizer: authority.authorize,
  );
  var lease = 0;

  static Future<_Device> create(
    _Server server, {
    bool enrolled = true,
    bool enabled = true,
  }) async {
    final device = _Device(server, enabled: enabled);
    addTearDown(() async {
      try {
        await DriftOwnerOperationGate(device.f.database).release(token: _gate);
      } finally {
        await device.f.database.close();
      }
    });
    await device.f.initialize(enroll: enrolled);
    await (device.f.database.update(device.f.database.localOwners)
          ..where((row) => row.id.equals(_owner)))
        .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
    expect(
      await DriftOwnerOperationGate(device.f.database).tryAcquire(
        token: _gate,
        nowUtc: device.f.now,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );
    return device;
  }

  Future<void> startPair(String operationId) async {
    final items = [
      for (var index = 0; index < 4; index++)
        PairLexicalItem(
          wordId: 'pair-word:$index',
          contentRevision: 1,
          checksum: ContentQualityPolicy.vocabularyChecksumSha256(
            categoryId: 'pair-category',
            spelling: 'word$index',
            normalizedSpelling: 'word$index',
            meaning: 'คำ$index',
            normalizedMeaning: 'คำ$index',
            partOfSpeech: 'noun',
            cefrLevel: null,
            source: 'manual',
            isGlobal: false,
          ),
          spelling: 'word$index',
          meaning: 'คำ$index',
          sourceLocale: 'en',
          targetLocale: 'th',
          sourceReasons: {PairSourceReason.dueSrs},
        ),
    ];
    await f.database
        .into(f.database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'pair-category',
            ownerId: _owner,
            name: 'Synthetic',
            normalizedName: 'synthetic',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    for (final item in items) {
      await f.database
          .into(f.database.vocabularyWords)
          .insert(
            VocabularyWordsCompanion.insert(
              id: item.wordId,
              ownerId: _owner,
              categoryId: 'pair-category',
              spelling: item.spelling,
              normalizedSpelling: item.spelling,
              meaning: item.meaning,
              normalizedMeaning: item.meaning,
              partOfSpeech: 'noun',
              contentRevision: Value(item.contentRevision),
              contentChecksumSha256: Value(item.checksum),
              createdAtUtcMs: 1,
              updatedAtUtcMs: 1,
            ),
          );
    }
    final configuration = SessionConfiguration.validated(
      schemaVersion: 1,
      policyVersion: sessionConfigurationPolicyVersion,
      ownerId: _owner,
      mode: LessonMode.matching,
      itemCount: 4,
      direction: SessionDirection.forward,
      difficulty: SessionDifficulty.standard,
      hintBudget: 0,
      timing: const SessionTiming.timed(Duration(minutes: 2)),
      packIdentity: null,
      protocolId: 'standard',
      protocolVersion: '1',
      protocolLimitsIdentity: 'standard',
    );
    final plan = PairMatchingPlanV1(
      ownerId: _owner,
      orderedLexicalItems: items,
      direction: PairDirection.enToTh,
      density: PairDensity.compact4,
      shuffleSeed: 52,
      timerPreset: PairTimerPreset.off,
      allowlistVersion: 'synthetic',
      learningSessionId: pairSessionId(_owner, operationId),
      entryKind: PairSourceSurface.learn,
      sourceSnapshotId: 'synthetic',
      createdAtUtc: f.now,
      sessionPurpose: PairSessionPurpose.learning,
    );
    await PairMatchingAtomicStartAdapter(
      repository: learning,
      capability: InternalPairMatchingCapability(
        allowlist: PairCuratedAllowlist(version: 'synthetic', items: items),
        isEnabled: () => true,
      ),
    ).start(
      PairMatchingStartOperation(
        plan: plan,
        launchOperationId: operationId,
        appVersion: f.study.appVersion,
        buildId: f.study.buildId,
        configuration: configuration,
      ),
    );
  }

  Future<void> start(String sessionId) => learning.startSession(
    LearningSessionDraft(
      id: sessionId,
      ownerId: _owner,
      activityType: 'quiz',
      startedAtUtc: f.now,
      appVersion: f.study.appVersion,
      buildId: f.study.buildId,
      sessionConfiguration: SessionConfiguration.validated(
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
      ),
    ),
  );

  Future<MeasurementOpportunity> accepted({
    String sessionId = 'session:proof-source',
    String entryAttemptId = '11111111-1111-4111-8111-111111111111',
    Future<void> Function()? startActivity,
  }) async {
    final run = await f.measurements.start(
      const MotivationMeasurementStart(ownerId: _owner, permitId: 'permit:a'),
    );
    await f.measurements.record(
      MotivationResponse(
        ownerId: _owner,
        runId: run.id,
        itemId: 'baseline',
        responseCode: 'high',
      ),
    );
    final opened = await opportunities.open(
      ownerId: _owner,
      measurementRunId: run.id,
      entryAttemptId: entryAttemptId,
      effectivePresentation: TodayExperiencePresentation.adventure,
    );
    await opportunities.recordPresented(_owner, opened.id);
    await (startActivity?.call() ?? start(sessionId));
    final accepted = await opportunities.attachAcceptedSession(
      ownerId: _owner,
      opportunityId: opened.id,
      learningSessionId: sessionId,
      planId: 'plan:proof-transport',
      mode: startActivity == null
          ? LessonMode.meaningQuiz
          : LessonMode.matching,
    );
    expect(accepted.startedEventId, isNotNull);
    expect(await rows('answer_attempts'), isEmpty);
    return accepted;
  }

  Future<void> finish(MeasurementOpportunity opportunity) async {
    f.now = f.now.add(const Duration(seconds: 1));
    await learning.finishSession(
      ownerId: _owner,
      sessionId: opportunity.learningSessionId!,
      endedAtUtc: f.now,
    );
    await opportunities.completeAcceptedSession(_owner, opportunity.id);
  }

  Future<List<ClaimedSyncOperation>> claims() async {
    await store.enqueueResearchChanges(
      ownerId: _owner,
      firebaseUid: _uid,
      ownerGateToken: _gate,
      nowUtc: f.now,
    );
    final claimed = await store.claimPending(
      ownerId: _owner,
      firebaseUid: _uid,
      limit: 50,
      leaseToken: 'proof-send-${lease++}',
      ownerGateToken: _gate,
      leaseDuration: const Duration(minutes: 1),
      nowUtc: f.now,
    );
    expect(
      claimed.where((claim) => claim.mutation.collection == _proofs),
      isNotEmpty,
    );
    return claimed;
  }

  Future<void> upload({bool completedFirst = false}) async =>
      uploadClaims(await claims(), completedFirst: completedFirst);
  Future<void> uploadClaims(
    List<ClaimedSyncOperation> claims, {
    bool completedFirst = false,
  }) async {
    final ordered = [...claims]
      ..sort((a, b) {
        final order = ResearchSyncContract.collections
            .indexOf(a.mutation.collection)
            .compareTo(
              ResearchSyncContract.collections.indexOf(b.mutation.collection),
            );
        if (order != 0) return order;
        if (a.mutation.collection == _proofs && completedFirst)
          return (b.mutation.payload['proofRevision']! as int).compareTo(
            a.mutation.payload['proofRevision']! as int,
          );
        return a.mutation.entityId.compareTo(b.mutation.entityId);
      });
    for (final claim in ordered) {
      if (claim.mutation.collection ==
          SyncCollection.researchParticipationPermits) {
        // Only the explicitly synthetic issuer fixture seeds a server permit.
        server.documents.putIfAbsent(
          'field_users/$_uid/research_participation_permits/${claim.mutation.entityId}',
          () => _copyMap(
            FirestoreSyncCodec.encodeEntity(
              claim.mutation,
              serverTimestamp: server.tick(),
            ),
          ),
        );
      }
      final attempt = await store.beginAttempt(
        claim: claim,
        ownerGateToken: _gate,
        nowUtc: f.now,
      );
      expect(attempt, isNotNull);
      final ack = await gateway.push(attempt!.mutation);
      expect(ack, isA<PushAcknowledged>());
      expect(
        await store.acknowledge(
          operationId: claim.localOperationId,
          leaseToken: claim.leaseToken,
          ownerGateToken: _gate,
          nowUtc: f.now,
          acknowledgement: ack as PushAcknowledged,
        ),
        isTrue,
      );
    }
  }

  Future<PullPage> page(SyncCollection collection, {int limit = 50}) async =>
      gateway.pull(
        firebaseUid: _uid,
        collection: collection,
        after: await store.readCheckpoint(_owner, collection),
        limit: limit,
      );
  Future<bool> apply(PullPage page, SyncCollection collection) =>
      store.applyPullPage(
        ownerId: _owner,
        collection: collection,
        page: page,
        ownerGateToken: _gate,
        nowUtc: f.now,
      );
  Future<void> pull(SyncCollection collection, {int limit = 50}) async {
    expect(
      await apply(await page(collection, limit: limit), collection),
      isTrue,
    );
  }

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await f.database
            .customSelect('SELECT * FROM $table ORDER BY 1')
            .get())
      Map<String, Object?>.from(row.data),
  ];
  Future<Map<String, Object?>> learningEffects() async => {
    for (final table in [
      'learning_sessions',
      'session_configurations',
      'answer_attempts',
      'srs_states',
      'points_ledger_entries',
      'reward_transactions',
      'owned_reward_items',
      'equipped_reward_items',
      'runtime_flags',
    ])
      table: await rows(table),
    // Research mission events are permitted; ordinary learning events and the
    // checkpoint namespace in runtime_flags must not be hydrated from a mirror.
    'ordinary_events': [
      for (final row
          in await f.database
              .customSelect(
                "SELECT * FROM events_v2 WHERE event_type NOT IN ('TodayExperiencePresented','TodayExperiencePresentationChanged','TodayExperienceMissionStarted','TodayExperienceMissionCompleted') ORDER BY event_id",
              )
              .get())
        Map<String, Object?>.from(row.data),
    ],
  };
}
