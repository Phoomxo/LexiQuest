import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/research/application/assigned_learning_event_context_provider.dart';
import 'package:vocab_learning_app/features/research/application/experiment_assignment_use_cases.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/data/firestore_sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';

void main() {
  final decidedAt = DateTime.utc(2026, 8, 14, 8);
  final assignedAt = DateTime.utc(2026, 8, 14, 8, 1);
  final now = DateTime.utc(2026, 8, 14, 9);

  group('experiment assignment local outbox', () {
    late AppDatabase database;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _insertOwner(database, 'owner-a');
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
    });

    tearDown(() => database.close());

    test(
      'explicit assignment creates one deterministic immutable v1 upsert',
      () async {
        final useCases = _useCases(database);
        final assignment = await _assign(useCases, assignedAt: assignedAt);
        final replay = await _assign(useCases, assignedAt: assignedAt);

        expect(replay, assignment);
        final operations = await database
            .select(database.outboxOperations)
            .get();
        expect(operations, hasLength(1));
        final operation = operations.single;
        expect(
          operation.operationId,
          'experimentAssignment:${assignment.id}:1',
        );
        expect(operation.ownerId, assignment.ownerId);
        expect(operation.entityType, 'experimentAssignment');
        expect(operation.entityId, assignment.id);
        expect(operation.operationKind, 'upsert');
        expect(operation.payloadVersion, 1);
        expect(operation.baseRevision, 0);
        expect(operation.state, 'pending');
        expect(operation.createdAtUtcMs, assignedAt.millisecondsSinceEpoch);
      },
    );

    test(
      'research sync is off by default and requires the deployed rules revision',
      () async {
        final assignment = await _assign(
          _useCases(database),
          assignedAt: assignedAt,
        );
        const gateToken = 'research-rollout-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        expect(
          await _claimAssignments(
            DriftSyncStore(database),
            ownerGateToken: gateToken,
            leaseToken: 'default-off-lease',
            nowUtc: now,
          ),
          isEmpty,
        );
        expect(
          await _claimAssignments(
            _enabledStore(
              database,
              deployedRulesRevision: legacyFirestoreRulesRevision,
            ),
            ownerGateToken: gateToken,
            leaseToken: 'wrong-rules-lease',
            nowUtc: now,
          ),
          isEmpty,
        );

        final claims = await _claimAssignments(
          _enabledStore(
            database,
            deployedRulesRevision: experimentAssignmentV1RulesRevision,
          ),
          ownerGateToken: gateToken,
          leaseToken: 'exact-rules-lease',
          nowUtc: now,
        );
        expect(claims, hasLength(1));
        expect(
          claims.single.mutation.collection,
          SyncCollection.experimentAssignments,
        );
        expect(
          claims.single.mutation.entityId,
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: 'firebase-owner-a',
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          ),
        );
        expect(claims.single.mutation.payloadVersion, 1);
        expect(claims.single.mutation.operationKind, SyncOperationKind.upsert);
        expect(claims.single.mutation.payload, _assignmentPayload(assignment));
      },
    );
  });

  test(
    'claims each assignment only through its exact catalog consent mapping',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _insertOwner(database, 'owner-a');
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 1,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
          withdrawnAtUtcMs: decidedAt
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 2,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final repository = DriftExperimentAssignmentRepository(database);
        final versionOne = await repository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'study-consent-v1',
          experimentVersion: 1,
          cohort: 'control',
          protocolVersion: 'protocol-v1',
          assignedAtUtc: assignedAt,
        );
        final versionTwo = await repository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'study-consent-v2',
          experimentVersion: 2,
          cohort: 'intervention',
          protocolVersion: 'protocol-v2',
          assignedAtUtc: assignedAt.add(const Duration(milliseconds: 1)),
        );
        final unmapped = await repository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'study-unmapped',
          experimentVersion: 1,
          cohort: 'control',
          protocolVersion: 'protocol-unknown',
          assignedAtUtc: assignedAt.add(const Duration(milliseconds: 2)),
        );
        const catalog = ResearchProtocolModeCatalog(
          mappings: <ResearchProtocolModeMapping>[
            ResearchProtocolModeMapping(
              experimentId: 'study-consent-v1',
              experimentVersion: 1,
              protocolVersion: 'protocol-v1',
              consentVersion: 1,
              mode: EvidencePolicyRolloutMode.shadow,
            ),
            ResearchProtocolModeMapping(
              experimentId: 'study-consent-v2',
              experimentVersion: 2,
              protocolVersion: 'protocol-v2',
              consentVersion: 2,
              mode: EvidencePolicyRolloutMode.enforced,
            ),
          ],
        );
        expect(
          catalog
              .lookup(
                protocolId: null,
                experimentId: versionOne.experimentId,
                experimentVersion: versionOne.experimentVersion,
                protocolVersion: versionOne.protocolVersion,
                consentVersion: 1,
              )
              ?.consentVersion,
          1,
        );
        expect(
          catalog
              .lookup(
                protocolId: null,
                experimentId: versionTwo.experimentId,
                experimentVersion: versionTwo.experimentVersion,
                protocolVersion: versionTwo.protocolVersion,
                consentVersion: 2,
              )
              ?.consentVersion,
          2,
        );
        expect(
          catalog.lookup(
            protocolId: null,
            experimentId: unmapped.experimentId,
            experimentVersion: unmapped.experimentVersion,
            protocolVersion: unmapped.protocolVersion,
            consentVersion: 2,
          ),
          isNull,
        );
        const gateToken = 'per-assignment-consent-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        final claims = await _claimAssignments(
          DriftSyncStore(
            database,
            researchSyncRollout: _catalogBoundResearchRollout(catalog),
            consentRegistry: DriftConsentRegistry(database),
          ),
          ownerGateToken: gateToken,
          leaseToken: 'per-assignment-consent-lease',
          nowUtc: now,
        );

        expect(
          claims.map((claim) => claim.mutation.payload['experimentId']),
          <Object?>['study-consent-v2'],
        );
        final operations = await database
            .select(database.outboxOperations)
            .get();
        expect(
          operations.singleWhere((row) => row.entityId == versionOne.id).state,
          'pending',
        );
        expect(
          operations.singleWhere((row) => row.entityId == versionTwo.id).state,
          'inFlight',
        );
        expect(
          operations.singleWhere((row) => row.entityId == unmapped.id).state,
          'pending',
        );
      } finally {
        await database.close();
      }
    },
  );

  test('malformed catalog mapping leaves assignment sync pending', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await _insertOwner(database, 'owner-a');
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 2,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      final assignment = await DriftExperimentAssignmentRepository(database)
          .assignIfAbsent(
            ownerId: 'owner-a',
            experimentId: 'study-malformed-mapping',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol-v2',
            assignedAtUtc: assignedAt,
          );
      const malformedCatalog = ResearchProtocolModeCatalog(
        mappings: <ResearchProtocolModeMapping>[
          ResearchProtocolModeMapping(
            experimentId: ' study-malformed-mapping',
            experimentVersion: 1,
            protocolVersion: 'protocol-v2',
            consentVersion: 2,
            mode: EvidencePolicyRolloutMode.shadow,
          ),
        ],
      );
      expect(
        () => malformedCatalog.lookup(
          protocolId: null,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
          protocolVersion: assignment.protocolVersion,
          consentVersion: 2,
        ),
        throwsFormatException,
      );
      const gateToken = 'malformed-assignment-catalog-gate';
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: gateToken,
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      expect(
        await _claimAssignments(
          DriftSyncStore(
            database,
            researchSyncRollout: _catalogBoundResearchRollout(malformedCatalog),
            consentRegistry: DriftConsentRegistry(database),
          ),
          ownerGateToken: gateToken,
          leaseToken: 'malformed-assignment-catalog-lease',
          nowUtc: now,
        ),
        isEmpty,
      );
      final operation =
          (await database.select(database.outboxOperations).get()).single;
      expect(operation.entityId, assignment.id);
      expect(operation.state, 'pending');
    } finally {
      await database.close();
    }
  });

  test(
    'global consent cannot authorize an assignment without its catalog mapping',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _insertOwner(database, 'owner-a');
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 1,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
          withdrawnAtUtcMs: decidedAt
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
        );
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 2,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignment = await DriftExperimentAssignmentRepository(database)
            .assignIfAbsent(
              ownerId: 'owner-a',
              experimentId: 'study-global-bypass',
              experimentVersion: 1,
              cohort: 'control',
              protocolVersion: 'protocol-v1',
              assignedAtUtc: assignedAt,
            );
        const exactCatalog = ResearchProtocolModeCatalog(
          mappings: <ResearchProtocolModeMapping>[
            ResearchProtocolModeMapping(
              experimentId: 'study-global-bypass',
              experimentVersion: 1,
              protocolVersion: 'protocol-v1',
              consentVersion: 1,
              mode: EvidencePolicyRolloutMode.shadow,
            ),
          ],
        );
        expect(
          exactCatalog
              .lookupForAssignment(
                experimentId: assignment.experimentId,
                experimentVersion: assignment.experimentVersion,
                protocolVersion: assignment.protocolVersion,
              )
              ?.consentVersion,
          1,
        );
        final legacyGlobalRollout =
            ResearchCollectionSyncRollout.experimentAssignmentsV1(
              deployedRulesRevision: experimentAssignmentV1RulesRevision,
              consentVersion: 2,
            );
        const gateToken = 'global-consent-bypass-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        final claims = await _claimAssignments(
          DriftSyncStore(
            database,
            researchSyncRollout: legacyGlobalRollout,
            consentRegistry: DriftConsentRegistry(database),
          ),
          ownerGateToken: gateToken,
          leaseToken: 'global-consent-bypass-lease',
          nowUtc: now,
        );

        expect(claims, isEmpty);
        expect(
          legacyGlobalRollout.allowsExperimentAssignmentClaims,
          isFalse,
          reason: 'a non-null protocol catalog is required to enable claims',
        );
        final operation =
            (await database.select(database.outboxOperations).get()).single;
        expect(operation.entityId, assignment.id);
        expect(operation.state, 'pending');
      } finally {
        await database.close();
      }
    },
  );

  test(
    'claim translates local assignment identity to canonical Firebase identity',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        const localOwnerId = 'local-owner-a';
        const firebaseUid = 'firebase-shared-owner';
        await _insertOwner(database, localOwnerId, firebaseUid: firebaseUid);
        await _putConsent(
          database,
          ownerId: localOwnerId,
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignment = await DriftExperimentAssignmentRepository(database)
            .assignIfAbsent(
              ownerId: localOwnerId,
              experimentId: 'cross-device-study',
              experimentVersion: 3,
              cohort: 'intervention',
              protocolVersion: 'protocol-3',
              assignedAtUtc: assignedAt,
            );
        final localAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: localOwnerId,
              experimentId: assignment.experimentId,
              experimentVersion: assignment.experimentVersion,
            );
        final cloudAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: firebaseUid,
              experimentId: assignment.experimentId,
              experimentVersion: assignment.experimentVersion,
            );
        expect(assignment.id, localAssignmentId);
        expect(assignment.id, isNot(cloudAssignmentId));
        const gateToken = 'cross-device-push-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        final claims = await _claimAssignments(
          _enabledStore(database),
          ownerId: localOwnerId,
          firebaseUid: firebaseUid,
          ownerGateToken: gateToken,
          leaseToken: 'cross-device-push-lease',
          nowUtc: now,
        );
        expect(claims, hasLength(1));
        final mutation = claims.single.mutation;
        expect(mutation.entityId, cloudAssignmentId);
        expect(mutation.payload['assignmentId'], cloudAssignmentId);
        expect(mutation.payload['ownerId'], firebaseUid);
        final encoded = FirestoreSyncCodec.encodeOperation(
          mutation,
          acknowledgedAt: 'server-timestamp',
        );
        expect(encoded['entityId'], cloudAssignmentId);

        final localRow =
            (await database.select(database.experimentAssignments).get())
                .single;
        expect(localRow.id, localAssignmentId);
        expect(localRow.ownerId, localOwnerId);
      } finally {
        await database.close();
      }
    },
  );

  test(
    'cloud assignment pulls into each local owner identity without echo',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        const localOwnerId = 'second-device-owner';
        const firebaseUid = 'firebase-shared-owner';
        await _insertOwner(database, localOwnerId, firebaseUid: firebaseUid);
        final cloudAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: firebaseUid,
              experimentId: 'cross-device-study',
              experimentVersion: 3,
            );
        final localAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: localOwnerId,
              experimentId: 'cross-device-study',
              experimentVersion: 3,
            );
        final cloudAssignment = ExperimentAssignment(
          id: cloudAssignmentId,
          ownerId: localOwnerId,
          experimentId: 'cross-device-study',
          experimentVersion: 3,
          cohort: 'intervention',
          protocolVersion: 'protocol-3',
          assignedAtUtc: assignedAt,
        );
        final entity = _assignmentEntity(
          cloudAssignment,
          payload: _assignmentPayload(
            cloudAssignment,
            firebaseUid: firebaseUid,
          ),
          firebaseUid: firebaseUid,
          serverUpdatedAt: now,
        );
        final store = DriftSyncStore(database);

        await store.applyPullPage(
          ownerId: localOwnerId,
          collection: SyncCollection.experimentAssignments,
          page: _page(entity),
        );
        await store.applyPullPage(
          ownerId: localOwnerId,
          collection: SyncCollection.experimentAssignments,
          page: _page(
            _assignmentEntity(
              cloudAssignment,
              payload: _assignmentPayload(
                cloudAssignment,
                firebaseUid: firebaseUid,
              ),
              serverUpdatedAt: now.add(const Duration(milliseconds: 1)),
            ),
          ),
        );

        final persisted = await DriftExperimentAssignmentRepository(database)
            .getAssignment(
              ownerId: localOwnerId,
              experimentId: 'cross-device-study',
              experimentVersion: 3,
            );
        expect(persisted.id, localAssignmentId);
        expect(persisted.ownerId, localOwnerId);
        expect(persisted.cohort, cloudAssignment.cohort);
        expect(persisted.protocolVersion, cloudAssignment.protocolVersion);
        expect(persisted.assignedAtUtc, cloudAssignment.assignedAtUtc);
        expect(await _assignmentCount(database), 1);
        expect(await database.select(database.outboxOperations).get(), isEmpty);
        expect(await database.select(database.syncConflicts).get(), isEmpty);

        final wrongOwnerPayload = <String, Object?>{
          ..._assignmentPayload(cloudAssignment, firebaseUid: firebaseUid),
          'ownerId': 'another-firebase-owner',
        };
        await store.applyPullPage(
          ownerId: localOwnerId,
          collection: SyncCollection.experimentAssignments,
          page: _page(
            _assignmentEntity(
              cloudAssignment,
              payload: wrongOwnerPayload,
              firebaseUid: firebaseUid,
              serverUpdatedAt: now.add(const Duration(milliseconds: 2)),
            ),
          ),
        );
        expect(await _assignmentCount(database), 1);
        expect(
          await database.select(database.syncConflicts).get(),
          hasLength(1),
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    '401 blocked research operations cannot starve a later ordinary claim',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _insertOwner(database, 'owner-a');
        final repository = DriftExperimentAssignmentRepository(database);
        for (var index = 0; index < 401; index += 1) {
          await repository.assignIfAbsent(
            ownerId: 'owner-a',
            experimentId: 'blocked-study-$index',
            experimentVersion: 1,
            cohort: 'control',
            protocolVersion: 'protocol-blocked',
            assignedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              index + 1,
              isUtc: true,
            ),
          );
        }
        await _insertCategoryOperation(
          database,
          ownerId: 'owner-a',
          categoryId: 'category:allowed-after-research',
          createdAtUtcMs: 1000,
        );
        const gateToken = 'starvation-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        final claims = await DriftSyncStore(database).claimPending(
          ownerId: 'owner-a',
          firebaseUid: 'firebase-owner-a',
          limit: 1,
          leaseToken: 'starvation-lease',
          ownerGateToken: gateToken,
          leaseDuration: const Duration(minutes: 5),
          nowUtc: now,
        );

        expect(claims, hasLength(1));
        expect(claims.single.mutation.collection, SyncCollection.categories);
        expect(
          claims.single.mutation.entityId,
          'category:allowed-after-research',
        );
        final researchOperations =
            await (database.select(database.outboxOperations)..where(
                  (row) => row.entityType.equals(
                    SyncCollection.experimentAssignments.entityType,
                  ),
                ))
                .get();
        expect(researchOperations, hasLength(401));
        expect(
          researchOperations.map((row) => row.state),
          everyElement('pending'),
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'released local retry survives a file-backed reopen exactly once',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-assignment-sync-',
      );
      final file = File('${directory.path}${Platform.pathSeparator}app.sqlite');
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        await _insertOwner(database, 'owner-a');
        await _putConsent(
          database,
          ownerId: 'owner-a',
          version: 7,
          state: 'accepted',
          decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
        );
        final assignment = await _assign(
          _useCases(database),
          assignedAt: assignedAt,
        );
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        const firstGate = 'first-reopen-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: firstGate,
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final firstStore = _enabledStore(database);
        final firstClaims = await _claimAssignments(
          firstStore,
          ownerGateToken: firstGate,
          leaseToken: 'first-reopen-lease',
          nowUtc: now,
        );
        expect(firstClaims, hasLength(1));
        expect(
          firstClaims.single.mutation.entityId,
          DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
            firebaseUid: 'firebase-owner-a',
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
          ),
        );
        expect(
          await firstStore.releaseClaim(
            claim: firstClaims.single,
            ownerGateToken: firstGate,
            nowUtc: now,
          ),
          isTrue,
        );
        await DriftOwnerOperationGate(database).release(token: firstGate);
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        const secondGate = 'second-reopen-owner-gate';
        final later = now.add(const Duration(minutes: 1));
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: secondGate,
            nowUtc: later,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final secondClaims = await _claimAssignments(
          _enabledStore(database),
          ownerGateToken: secondGate,
          leaseToken: 'second-reopen-lease',
          nowUtc: later,
        );
        expect(secondClaims, hasLength(1));
        expect(
          secondClaims.single.mutation.operationId,
          firstClaims.single.mutation.operationId,
        );
        expect(
          await database.select(database.outboxOperations).get(),
          hasLength(1),
        );
      } finally {
        await database?.close();
        await directory.delete(recursive: true);
      }
    },
  );

  group('experiment assignment immutable pull', () {
    late AppDatabase database;
    late DriftExperimentAssignmentRepository repository;
    late DriftSyncStore store;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _insertOwner(database, 'owner-a');
      await _putConsent(
        database,
        ownerId: 'owner-a',
        version: 7,
        state: 'accepted',
        decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
      );
      repository = DriftExperimentAssignmentRepository(database);
      store = _enabledStore(database);
    });

    tearDown(() => database.close());

    test(
      'absent pull persists once and byte-equivalent replay is idempotent',
      () async {
        final assignment = _assignment(assignedAt: assignedAt);
        final first = _assignmentEntity(assignment, serverUpdatedAt: now);
        await store.applyPullPage(
          ownerId: 'owner-a',
          collection: SyncCollection.experimentAssignments,
          page: _page(first),
        );
        final replay = _assignmentEntity(
          assignment,
          serverUpdatedAt: now.add(const Duration(milliseconds: 1)),
        );
        await store.applyPullPage(
          ownerId: 'owner-a',
          collection: SyncCollection.experimentAssignments,
          page: _page(replay),
        );

        expect(
          await repository.getAssignment(
            ownerId: 'owner-a',
            experimentId: 'study-a',
            experimentVersion: 1,
          ),
          assignment,
        );
        expect(await _assignmentCount(database), 1);
        expect(await database.select(database.syncConflicts).get(), isEmpty);
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );

    final conflictCases = <_RemoteConflictCase>[
      _RemoteConflictCase(
        name: 'different cohort quarantines the immutable assignment',
        mutate: (assignment) => _copyAssignment(assignment, cohort: 'control'),
      ),
      _RemoteConflictCase(
        name: 'different protocol quarantines the immutable assignment',
        mutate: (assignment) =>
            _copyAssignment(assignment, protocolVersion: 'protocol-2'),
      ),
      _RemoteConflictCase(
        name: 'different assignment time quarantines the immutable assignment',
        mutate: (assignment) => _copyAssignment(
          assignment,
          assignedAtUtc: assignment.assignedAtUtc.add(
            const Duration(milliseconds: 1),
          ),
        ),
      ),
      _RemoteConflictCase(
        name: 'same entity with another experiment version is quarantined',
        mutate: (assignment) =>
            _copyAssignment(assignment, experimentVersion: 2),
      ),
      _RemoteConflictCase(
        name: 'same logical assignment under another entity id is quarantined',
        mutate: (assignment) => _copyAssignment(
          assignment,
          id: 'experiment-assignment:remote-collision',
        ),
      ),
      _RemoteConflictCase(
        name: 'owner mismatch is quarantined without replacing local audit',
        payloadMutation: (payload) => <String, Object?>{
          ...payload,
          'ownerId': 'owner-b',
        },
      ),
      _RemoteConflictCase(
        name: 'missing canonical payload key is quarantined fail closed',
        payloadMutation: (payload) =>
            <String, Object?>{...payload}..remove('protocolVersion'),
      ),
      _RemoteConflictCase(
        name: 'extra payload key is quarantined fail closed',
        payloadMutation: (payload) => <String, Object?>{
          ...payload,
          'runtimeEnabled': true,
        },
      ),
      _RemoteConflictCase(
        name: 'wrong payload type is quarantined fail closed',
        payloadMutation: (payload) => <String, Object?>{
          ...payload,
          'experimentVersion': '1',
        },
      ),
    ];

    for (final conflictCase in conflictCases) {
      test(conflictCase.name, () async {
        final local = await repository.assignIfAbsent(
          ownerId: 'owner-a',
          experimentId: 'study-a',
          experimentVersion: 1,
          cohort: 'intervention',
          protocolVersion: 'protocol-1',
          assignedAtUtc: assignedAt,
        );
        final remote = conflictCase.mutate?.call(local) ?? local;
        final payload =
            conflictCase.payloadMutation?.call(_assignmentPayload(remote)) ??
            _assignmentPayload(remote);
        final entity = _assignmentEntity(
          remote,
          payload: payload,
          serverUpdatedAt: now,
        );

        expect(
          await store.applyPullPage(
            ownerId: 'owner-a',
            collection: SyncCollection.experimentAssignments,
            page: _page(entity),
          ),
          isTrue,
        );

        final persisted = await database
            .select(database.experimentAssignments)
            .get();
        expect(persisted, hasLength(1));
        expect(persisted.single.id, local.id);
        expect(persisted.single.ownerId, local.ownerId);
        expect(persisted.single.experimentId, local.experimentId);
        expect(persisted.single.experimentVersion, local.experimentVersion);
        expect(persisted.single.cohort, local.cohort);
        expect(persisted.single.protocolVersion, local.protocolVersion);
        expect(
          persisted.single.assignedAtUtcMs,
          local.assignedAtUtc.millisecondsSinceEpoch,
        );
        final conflicts = await database.select(database.syncConflicts).get();
        expect(conflicts, hasLength(1));
        expect(conflicts.single.entityType, 'experimentAssignment');
        expect(conflicts.single.resolutionPolicy, 'immutableEventId');
        expect(conflicts.single.outcome, 'quarantined');
        await expectLater(
          DriftExperimentRegistry(repository).getAssignment(
            ownerId: 'owner-a',
            experimentId: 'study-a',
            experimentVersion: 1,
          ),
          throwsA(isA<ExperimentAssignmentConflict>()),
        );
        await _expectInterventionBlocked(
          database,
          assignment: local,
          occurredAtUtc: now.add(const Duration(minutes: 1)),
        );
      });
    }
  });

  group('consent withdrawal and denial', () {
    final cases = <_ConsentBlockCase>[
      _ConsentBlockCase(
        'withdrawn',
        withdrawalUtcMs: decidedAt
            .add(const Duration(minutes: 1))
            .millisecondsSinceEpoch,
      ),
      const _ConsentBlockCase('declined'),
      const _ConsentBlockCase('unknown', deleteRow: true),
    ];

    for (final blockCase in cases) {
      test(
        '${blockCase.name} blocks claims and intervention without erasing audit',
        () async {
          final database = AppDatabase(NativeDatabase.memory());
          try {
            await _insertOwner(database, 'owner-a');
            await _putConsent(
              database,
              ownerId: 'owner-a',
              version: 7,
              state: 'accepted',
              decidedAtUtcMs: decidedAt.millisecondsSinceEpoch,
            );
            final useCases = _useCases(database);
            final assignment = await _assign(useCases, assignedAt: assignedAt);
            await _blockConsent(database, blockCase);

            expect(
              await useCases.assignIfConsented(
                ownerId: 'owner-a',
                experimentId: 'study-b',
                experimentVersion: 1,
                cohort: 'intervention',
                protocolVersion: 'protocol-1',
                consentVersion: 7,
                assignedAtUtc: assignedAt.add(const Duration(minutes: 1)),
              ),
              isNull,
            );
            const gateToken = 'blocked-consent-owner-gate';
            expect(
              await DriftOwnerOperationGate(database).tryAcquire(
                token: gateToken,
                nowUtc: now,
                leaseDuration: const Duration(minutes: 10),
              ),
              isTrue,
            );
            expect(
              await _claimAssignments(
                _enabledStore(database),
                ownerGateToken: gateToken,
                leaseToken: 'blocked-consent-lease',
                nowUtc: now,
              ),
              isEmpty,
            );
            expect(await _assignmentCount(database), 1);
            final operations = await database
                .select(database.outboxOperations)
                .get();
            expect(operations, hasLength(1));
            expect(operations.single.state, 'pending');
            await _expectInterventionBlocked(
              database,
              assignment: assignment,
              occurredAtUtc: now.add(const Duration(minutes: 1)),
            );
          } finally {
            await database.close();
          }
        },
      );
    }
  });
}

ExperimentAssignmentUseCases _useCases(AppDatabase database) {
  return ExperimentAssignmentUseCases(
    repository: DriftExperimentAssignmentRepository(database),
    consentRegistry: DriftConsentRegistry(database),
  );
}

Future<ExperimentAssignment> _assign(
  ExperimentAssignmentUseCases useCases, {
  required DateTime assignedAt,
}) async {
  final assignment = await useCases.assignIfConsented(
    ownerId: 'owner-a',
    experimentId: 'study-a',
    experimentVersion: 1,
    cohort: 'intervention',
    protocolVersion: 'protocol-1',
    consentVersion: 7,
    assignedAtUtc: assignedAt,
  );
  expect(assignment, isNotNull);
  return assignment!;
}

DriftSyncStore _enabledStore(
  AppDatabase database, {
  String deployedRulesRevision = experimentAssignmentV1RulesRevision,
}) {
  return DriftSyncStore(
    database,
    researchSyncRollout: ResearchCollectionSyncRollout.experimentAssignmentsV1(
      deployedRulesRevision: deployedRulesRevision,
      protocolModeCatalog: _defaultResearchSyncCatalog,
    ),
    consentRegistry: DriftConsentRegistry(database),
  );
}

const _defaultResearchSyncCatalog = ResearchProtocolModeCatalog(
  mappings: <ResearchProtocolModeMapping>[
    ResearchProtocolModeMapping(
      experimentId: 'study-a',
      experimentVersion: 1,
      protocolVersion: 'protocol-1',
      consentVersion: 7,
      mode: EvidencePolicyRolloutMode.shadow,
    ),
    ResearchProtocolModeMapping(
      experimentId: 'cross-device-study',
      experimentVersion: 3,
      protocolVersion: 'protocol-3',
      consentVersion: 7,
      mode: EvidencePolicyRolloutMode.shadow,
    ),
  ],
);

ResearchCollectionSyncRollout _catalogBoundResearchRollout(
  ResearchProtocolModeCatalog catalog,
) {
  return ResearchCollectionSyncRollout.experimentAssignmentsV1(
    deployedRulesRevision: experimentAssignmentV1RulesRevision,
    protocolModeCatalog: catalog,
  );
}

Future<List<ClaimedSyncOperation>> _claimAssignments(
  DriftSyncStore store, {
  String ownerId = 'owner-a',
  String firebaseUid = 'firebase-owner-a',
  int limit = 10,
  required String ownerGateToken,
  required String leaseToken,
  required DateTime nowUtc,
}) {
  return store.claimPending(
    ownerId: ownerId,
    firebaseUid: firebaseUid,
    limit: limit,
    leaseToken: leaseToken,
    ownerGateToken: ownerGateToken,
    leaseDuration: const Duration(minutes: 5),
    nowUtc: nowUtc,
  );
}

ExperimentAssignment _assignment({required DateTime assignedAt}) {
  return ExperimentAssignment(
    id: DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: 'owner-a',
      experimentId: 'study-a',
      experimentVersion: 1,
    ),
    ownerId: 'owner-a',
    experimentId: 'study-a',
    experimentVersion: 1,
    cohort: 'intervention',
    protocolVersion: 'protocol-1',
    assignedAtUtc: assignedAt,
  );
}

ExperimentAssignment _copyAssignment(
  ExperimentAssignment source, {
  String? id,
  int? experimentVersion,
  String? cohort,
  String? protocolVersion,
  DateTime? assignedAtUtc,
}) {
  return ExperimentAssignment(
    id: id ?? source.id,
    ownerId: source.ownerId,
    experimentId: source.experimentId,
    experimentVersion: experimentVersion ?? source.experimentVersion,
    cohort: cohort ?? source.cohort,
    protocolVersion: protocolVersion ?? source.protocolVersion,
    assignedAtUtc: assignedAtUtc ?? source.assignedAtUtc,
  );
}

Map<String, Object?> _assignmentPayload(
  ExperimentAssignment assignment, {
  String firebaseUid = 'firebase-owner-a',
}) {
  return <String, Object?>{
    'assignmentId':
        DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
          firebaseUid: firebaseUid,
          experimentId: assignment.experimentId,
          experimentVersion: assignment.experimentVersion,
        ),
    'ownerId': firebaseUid,
    'experimentId': assignment.experimentId,
    'experimentVersion': assignment.experimentVersion,
    'cohort': assignment.cohort,
    'protocolVersion': assignment.protocolVersion,
    'assignedAtUtcMs': assignment.assignedAtUtc.millisecondsSinceEpoch,
  };
}

SyncEntity _assignmentEntity(
  ExperimentAssignment assignment, {
  Map<String, Object?>? payload,
  String firebaseUid = 'firebase-owner-a',
  required DateTime serverUpdatedAt,
}) {
  final localAssignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: assignment.ownerId,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      );
  final canonicalCloudAssignmentId =
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: firebaseUid,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
      );
  final entityId = assignment.id == localAssignmentId
      ? canonicalCloudAssignmentId
      : assignment.id;
  final resolvedPayload =
      payload ??
      <String, Object?>{
        ..._assignmentPayload(assignment, firebaseUid: firebaseUid),
        'assignmentId': entityId,
      };
  return SyncEntity(
    collection: SyncCollection.experimentAssignments,
    entityId: entityId,
    revision: 1,
    isDeleted: false,
    payloadVersion: 1,
    clientUpdatedAtUtc: assignment.assignedAtUtc,
    serverUpdatedAtUtc: serverUpdatedAt,
    payload: resolvedPayload,
  );
}

PullPage _page(SyncEntity entity) {
  return PullPage(
    changes: <SyncEntity>[entity],
    nextCursor: SyncCursor(
      serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
      documentId: entity.entityId,
    ),
    hasMore: false,
  );
}

Future<void> _expectInterventionBlocked(
  AppDatabase database, {
  required ExperimentAssignment assignment,
  required DateTime occurredAtUtc,
}) async {
  final provider = AssignedLearningEventContextProvider(
    experimentRegistry: DriftExperimentRegistry(
      DriftExperimentAssignmentRepository(database),
    ),
    consentRegistry: DriftConsentRegistry(database),
  );
  await expectLater(
    provider.resolve(
      ownerId: assignment.ownerId,
      evidenceContext: EvidenceContext.forNewEvidence(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'meaning-recall',
        hintLevel: 0,
        contentRevision: 'content-v1',
        rolloutMode: EvidencePolicyRolloutMode.shadow,
        protocolId: 'study-protocol',
        protocolVersion: assignment.protocolVersion,
        experimentId: assignment.experimentId,
        experimentVersion: assignment.experimentVersion,
        assignmentId: assignment.id,
        cohort: assignment.cohort,
        researchConsentVersion: 7,
        engagementAllowed: true,
      ),
      occurredAtUtc: occurredAtUtc,
    ),
    throwsStateError,
  );
}

Future<void> _insertOwner(
  AppDatabase database,
  String ownerId, {
  String firebaseUid = 'firebase-owner-a',
}) {
  return database.customInsert(
    'INSERT INTO local_owners('
    'id, firebase_uid, account_state, created_at_utc_ms) '
    'VALUES (?, ?, ?, ?)',
    variables: [
      Variable<String>(ownerId),
      Variable<String>(firebaseUid),
      const Variable<String>('firebaseBound'),
      const Variable<int>(1),
    ],
  );
}

Future<void> _insertCategoryOperation(
  AppDatabase database, {
  required String ownerId,
  required String categoryId,
  required int createdAtUtcMs,
}) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: categoryId,
          ownerId: ownerId,
          name: 'Allowed ordinary category',
          normalizedName: 'allowed ordinary category',
          createdAtUtcMs: createdAtUtcMs,
          updatedAtUtcMs: createdAtUtcMs,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: 'category:$categoryId:1',
          ownerId: ownerId,
          entityType: SyncCollection.categories.entityType,
          entityId: categoryId,
          operationKind: SyncOperationKind.upsert.name,
          createdAtUtcMs: createdAtUtcMs,
        ),
      );
}

Future<void> _putConsent(
  AppDatabase database, {
  required String ownerId,
  required int version,
  required String state,
  required int decidedAtUtcMs,
  int? withdrawnAtUtcMs,
}) async {
  await database.customInsert(
    'INSERT INTO research_consents('
    'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
    'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, '
    "${withdrawnAtUtcMs == null ? 'NULL' : '?'})",
    variables: [
      Variable<String>('consent:$ownerId:$version'),
      Variable<String>(ownerId),
      Variable<int>(version),
      Variable<String>(state),
      Variable<int>(decidedAtUtcMs),
      if (withdrawnAtUtcMs != null) Variable<int>(withdrawnAtUtcMs),
    ],
  );
}

Future<void> _blockConsent(
  AppDatabase database,
  _ConsentBlockCase blockCase,
) async {
  if (blockCase.deleteRow) {
    await database.customStatement(
      'DELETE FROM research_consents WHERE owner_id = ? AND consent_version = ?',
      <Object?>['owner-a', 7],
    );
    return;
  }
  final withdrawalUtcMs = blockCase.withdrawalUtcMs;
  await database.customUpdate(
    'UPDATE research_consents SET consent_state = ?, '
    'withdrawn_at_utc_ms = ${withdrawalUtcMs == null ? 'NULL' : '?'} '
    'WHERE owner_id = ? AND consent_version = ?',
    variables: [
      Variable<String>(blockCase.name),
      if (withdrawalUtcMs != null) Variable<int>(withdrawalUtcMs),
      const Variable<String>('owner-a'),
      const Variable<int>(7),
    ],
  );
}

Future<int> _assignmentCount(AppDatabase database) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM experiment_assignments')
      .map((row) => row.read<int>('count'))
      .getSingle();
}

final class _RemoteConflictCase {
  const _RemoteConflictCase({
    required this.name,
    this.mutate,
    this.payloadMutation,
  });

  final String name;
  final ExperimentAssignment Function(ExperimentAssignment)? mutate;
  final Map<String, Object?> Function(Map<String, Object?>)? payloadMutation;
}

final class _ConsentBlockCase {
  const _ConsentBlockCase(
    this.name, {
    this.withdrawalUtcMs,
    this.deleteRow = false,
  });

  final String name;
  final int? withdrawalUtcMs;
  final bool deleteRow;
}
