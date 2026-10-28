import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_protocol_mode_catalog.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';
import 'package:vocab_learning_app/product/feature_contract/feature_contract_digest.dart';
import 'package:vocab_learning_app/runtime/registries/drift_consent_registry.dart';

void main() {
  test(
    'run id boundary keeps both canonical operation ids within 256 runes',
    () {
      final maxRunId = List<String>.filled(240, 'r').join();
      final maxNonIdPin = List<String>.filled(256, 'v').join();
      expect(_run(id: maxRunId).id, maxRunId);
      expect(
        _run(instrumentVersion: maxNonIdPin).instrumentVersion,
        maxNonIdPin,
        reason: 'the run-id budget must not narrow unrelated catalog pins',
      );

      for (final revision in const <int>[1, 2]) {
        final operationId =
            DriftAssessmentRepository.canonicalOutboxOperationId(
              runId: maxRunId,
              revision: revision,
            );
        expect(operationId, 'assessmentRun:$maxRunId:$revision');
        expect(operationId.runes.length, 256);
      }
    },
  );

  test('run id one rune over the operation budget is rejected', () {
    final oneOverRunId = List<String>.filled(241, 'r').join();

    expect(() => _run(id: oneOverRunId), throwsArgumentError);
    for (final revision in const <int>[1, 2]) {
      expect(
        () => DriftAssessmentRepository.canonicalOutboxOperationId(
          runId: oneOverRunId,
          revision: revision,
        ),
        throwsArgumentError,
        reason: 'revision $revision must keep operationId within 256 runes',
      );
    }
  });

  group('assessment run local sync evidence', () {
    late AppDatabase database;
    late DriftAssessmentRepository repository;

    setUp(() async {
      database = AppDatabase(NativeDatabase.memory());
      await _seedOwner(database);
      await _seedConsent(database);
      await _seedSession(database);
      await _seedAssignment(database);
      repository = DriftAssessmentRepository(database);
    });

    tearDown(() => database.close());

    test(
      'start and terminal replay emit two deterministic ordered v1 operations',
      () async {
        final active = _run();

        expect(await repository.start(active), active);
        expect(await repository.start(active), active);
        var operations = await _assessmentOperations(database);
        expect(operations, hasLength(1));
        expect(operations.single.operationId, _createOperationId);
        expect(operations.single.ownerId, _ownerId);
        expect(operations.single.entityType, 'assessmentRun');
        expect(operations.single.entityId, _runId);
        expect(operations.single.operationKind, 'upsert');
        expect(operations.single.payloadVersion, 1);
        expect(operations.single.baseRevision, 0);
        expect(
          operations.single.createdAtUtcMs,
          _startedAt.millisecondsSinceEpoch,
        );
        expect(operations.single.state, 'pending');

        final completed = await repository.complete(
          runId: _runId,
          completedAtUtc: _completedAt,
        );
        expect(completed.state, AssessmentRunState.completed);
        expect(
          await repository.complete(
            runId: _runId,
            completedAtUtc: _completedAt,
          ),
          completed,
        );

        operations = await _assessmentOperations(database);
        expect(operations, hasLength(2));
        expect(operations.map((row) => row.operationId), <String>[
          _createOperationId,
          _terminalOperationId,
        ]);
        expect(operations[1].entityId, _runId);
        expect(operations[1].operationKind, 'upsert');
        expect(operations[1].payloadVersion, 1);
        expect(operations[1].baseRevision, 1);
        expect(
          operations[1].createdAtUtcMs,
          _completedAt.millisecondsSinceEpoch,
        );
        expect(operations[1].state, 'pending');
      },
    );

    test(
      'abandon emits revision two once and terminal never reopens',
      () async {
        await repository.start(_run());

        final abandoned = await repository.abandon(
          runId: _runId,
          abandonedAtUtc: _abandonedAt,
        );
        expect(abandoned.state, AssessmentRunState.abandoned);
        expect(
          await repository.abandon(runId: _runId, abandonedAtUtc: _abandonedAt),
          abandoned,
        );
        await expectLater(
          repository.complete(runId: _runId, completedAtUtc: _completedAt),
          throwsA(isA<AssessmentRunConflict>()),
        );

        final operations = await _assessmentOperations(database);
        expect(operations, hasLength(2));
        expect(operations[1].operationId, _terminalOperationId);
        expect(operations[1].baseRevision, 1);
        expect(
          operations[1].createdAtUtcMs,
          _abandonedAt.millisecondsSinceEpoch,
        );
      },
    );

    test(
      'terminal outbox collision rolls back the state transition atomically',
      () async {
        await repository.start(_run());
        await database
            .into(database.outboxOperations)
            .insert(
              OutboxOperationsCompanion.insert(
                operationId: _terminalOperationId,
                ownerId: _ownerId,
                entityType: 'category',
                entityId: 'collision-entity',
                operationKind: SyncOperationKind.upsert.name,
                payloadVersion: const Value(1),
                baseRevision: const Value(0),
                createdAtUtcMs: _completedAt.millisecondsSinceEpoch,
              ),
            );

        await expectLater(
          repository.complete(runId: _runId, completedAtUtc: _completedAt),
          throwsA(isA<AssessmentRunConflict>()),
        );

        expect(await repository.getRun(_runId), _run());
        final operations = await database
            .select(database.outboxOperations)
            .get();
        expect(operations, hasLength(2));
        expect(
          operations
              .singleWhere((row) => row.operationId == _terminalOperationId)
              .entityType,
          'category',
        );
        expect(
          operations.where((row) => row.entityType == 'assessmentRun'),
          hasLength(1),
        );
      },
    );

    test(
      'research sync off rules mismatch and withdrawal keep work pending unleased',
      () async {
        await repository.start(_run());
        await repository.complete(runId: _runId, completedAtUtc: _completedAt);
        const gateToken = 'assessment-blocked-owner-gate';
        final gate = DriftOwnerOperationGate(database);
        expect(
          await gate.tryAcquire(
            token: gateToken,
            nowUtc: _claimAt,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );

        expect(
          await _claim(
            DriftSyncStore(database),
            ownerGateToken: gateToken,
            leaseToken: 'assessment-default-off',
          ),
          isEmpty,
        );
        expect(
          await _claim(
            _enabledStore(
              database,
              deployedRulesRevision: experimentAssignmentV1RulesRevision,
            ),
            ownerGateToken: gateToken,
            leaseToken: 'assessment-wrong-rules',
          ),
          isEmpty,
        );
        expect(
          await _claim(
            _enabledStore(database, protocolModeCatalog: _wrongProtocolCatalog),
            ownerGateToken: gateToken,
            leaseToken: 'assessment-unknown-protocol',
          ),
          isEmpty,
          reason:
              'a missing exact protocol mapping must not lease research work',
        );

        await database.customUpdate(
          'UPDATE research_consents SET withdrawn_at_utc_ms = ? '
          'WHERE owner_id = ? AND consent_version = ?',
          variables: [
            Variable<int>(_claimAt.millisecondsSinceEpoch - 1),
            const Variable<String>(_ownerId),
            const Variable<int>(_consentVersion),
          ],
        );
        expect(
          await _claim(
            _enabledStore(database),
            ownerGateToken: gateToken,
            leaseToken: 'assessment-withdrawn',
          ),
          isEmpty,
        );
        expect(
          await _claim(
            _enabledStore(database),
            ownerGateToken: gateToken,
            leaseToken: 'assessment-withdrawn-replay',
          ),
          isEmpty,
          reason: 'blocked research work must not enter a lease/retry loop',
        );

        final operations = await _assessmentOperations(database);
        expect(operations, hasLength(2));
        for (final operation in operations) {
          expect(operation.state, 'pending');
          expect(operation.attemptCount, 0);
          expect(operation.leaseToken, isNull);
          expect(operation.leaseExpiresAtUtcMs, isNull);
        }
        expect(await _runCount(database), 1);
      },
    );
  });

  test(
    'offline completion survives reopen and converges create before terminal once',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'lexiquest-assessment-sync-',
      );
      final file = File(
        '${temp.path}${Platform.pathSeparator}assessment.sqlite',
      );
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        await _seedOwner(database);
        await _seedConsent(database);
        await _seedSession(database);
        await _seedAssignment(database);
        final repository = DriftAssessmentRepository(database);
        await repository.start(_run());
        await repository.complete(runId: _runId, completedAtUtc: _completedAt);
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        const gateToken = 'assessment-reopen-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: _claimAt,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final store = _enabledStore(database);

        final createClaims = await _claim(
          store,
          ownerGateToken: gateToken,
          leaseToken: 'assessment-create-lease',
        );
        expect(createClaims, hasLength(1));
        expect(createClaims.single.localOperationId, _createOperationId);
        expect(createClaims.single.mutation.operationId, _createOperationId);
        expect(
          createClaims.single.mutation.collection,
          SyncCollection.assessmentRuns,
        );
        expect(createClaims.single.mutation.baseRevision, 0);
        expect(createClaims.single.mutation.localRevision, 1);
        expect(createClaims.single.mutation.payload['state'], 'active');
        expect(createClaims.single.mutation.payload['ownerId'], _firebaseUid);
        expect(
          createClaims.single.mutation.payload['assignmentId'],
          _cloudAssignmentId(),
        );
        final createPayload = Map<String, Object?>.from(
          createClaims.single.mutation.payload,
        );
        expect(
          (await DriftAssessmentRepository(
            database,
          ).getRun(_runId)).assignmentId,
          _localAssignmentId(_ownerId),
          reason: 'claim translation must not mutate the local owner-bound run',
        );
        await _acknowledge(
          store,
          claim: createClaims.single,
          ownerGateToken: gateToken,
          atUtc: _claimAt,
        );

        final terminalClaims = await _claim(
          store,
          ownerGateToken: gateToken,
          leaseToken: 'assessment-terminal-lease',
        );
        expect(terminalClaims, hasLength(1));
        expect(terminalClaims.single.localOperationId, _terminalOperationId);
        expect(
          terminalClaims.single.mutation.operationId,
          _terminalOperationId,
        );
        expect(terminalClaims.single.mutation.baseRevision, 1);
        expect(terminalClaims.single.mutation.localRevision, 2);
        expect(terminalClaims.single.mutation.payload['state'], 'completed');
        expect(terminalClaims.single.mutation.payload['ownerId'], _firebaseUid);
        expect(
          terminalClaims.single.mutation.payload['assignmentId'],
          _cloudAssignmentId(),
        );
        expect(
          terminalClaims.single.mutation.payload['completedAtUtcMs'],
          _completedAt.millisecondsSinceEpoch,
        );
        final terminalPayload = terminalClaims.single.mutation.payload;
        for (final key in createPayload.keys.where(
          (key) =>
              key != 'state' &&
              key != 'completedAtUtcMs' &&
              key != 'abandonedAtUtcMs',
        )) {
          expect(terminalPayload[key], createPayload[key], reason: key);
        }
        await _acknowledge(
          store,
          claim: terminalClaims.single,
          ownerGateToken: gateToken,
          atUtc: _claimAt.add(const Duration(seconds: 1)),
        );

        expect(
          await _claim(
            store,
            ownerGateToken: gateToken,
            leaseToken: 'assessment-no-duplicate-lease',
          ),
          isEmpty,
        );
        final operations = await _assessmentOperations(database);
        expect(operations.map((row) => row.state), <String>[
          'acknowledged',
          'acknowledged',
        ]);
      } finally {
        await database?.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  test(
    'pull translates assignment identity and replays terminal state without echo',
    () async {
      final temp = await Directory.systemTemp.createTemp(
        'lexiquest-assessment-pull-',
      );
      final file = File(
        '${temp.path}${Platform.pathSeparator}assessment.sqlite',
      );
      AppDatabase? database;
      try {
        database = AppDatabase(NativeDatabase(file));
        await _seedOwner(database, ownerId: _destinationOwnerId);
        await _seedConsent(database, ownerId: _destinationOwnerId);
        await _seedSession(database, ownerId: _destinationOwnerId);
        await _seedAssignment(database, ownerId: _destinationOwnerId);
        final store = DriftSyncStore(database);
        final destinationRun = _run(
          ownerId: _destinationOwnerId,
          assignmentId: _localAssignmentId(_destinationOwnerId),
        );
        final active = _cloudRunEntity(destinationRun, revision: 1);

        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.assessmentRuns,
            page: _page(active),
          ),
          isTrue,
        );
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.assessmentRuns,
            page: _page(active),
          ),
          isTrue,
        );
        final localActive = await DriftAssessmentRepository(
          database,
        ).getRun(_runId);
        expect(
          localActive.assignmentId,
          _localAssignmentId(_destinationOwnerId),
        );
        expect(localActive.state, AssessmentRunState.active);

        final completed = destinationRun.withTerminalState(
          state: AssessmentRunState.completed,
          terminalAtUtc: _completedAt,
        );
        final terminal = _cloudRunEntity(completed, revision: 2);
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.assessmentRuns,
            page: _page(terminal),
          ),
          isTrue,
        );
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.assessmentRuns,
            page: _page(terminal),
          ),
          isTrue,
        );
        await database.close();

        database = AppDatabase(NativeDatabase(file));
        final reopened = await DriftAssessmentRepository(
          database,
        ).getRun(_runId);
        expect(reopened, completed);
        expect(reopened.assignmentId, _localAssignmentId(_destinationOwnerId));
        expect(await _runCount(database), 1);
        expect(
          await (database.select(database.outboxOperations)..where(
                (row) =>
                    row.entityType.equals('assessmentRun') &
                    row.state.isIn(const <String>[
                      'pending',
                      'inFlight',
                      'retryWaiting',
                    ]),
              ))
              .get(),
          isEmpty,
          reason: 'remote assessment snapshots must not create pushable echo',
        );
      } finally {
        await database?.close();
        if (await temp.exists()) await temp.delete(recursive: true);
      }
    },
  );

  for (final terminalCase
      in <({String name, AssessmentRunState state, DateTime terminalAtUtc})>[
        (
          name: 'completed',
          state: AssessmentRunState.completed,
          terminalAtUtc: _completedAt,
        ),
        (
          name: 'abandoned',
          state: AssessmentRunState.abandoned,
          terminalAtUtc: _abandonedAt,
        ),
      ]) {
    test(
      'cold pulled Active then local ${terminalCase.name} claims only revision two',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwner(database, ownerId: _destinationOwnerId);
          await _seedConsent(database, ownerId: _destinationOwnerId);
          await _seedAssignment(database, ownerId: _destinationOwnerId);
          final active = _run(
            ownerId: _destinationOwnerId,
            assignmentId: _localAssignmentId(_destinationOwnerId),
          );
          final pullStore = DriftSyncStore(database);
          expect(
            await pullStore.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(_cloudRunEntity(active, revision: 1)),
            ),
            isTrue,
          );

          final gateToken = 'cold-terminal-${terminalCase.name}-gate';
          expect(
            await DriftOwnerOperationGate(database).tryAcquire(
              token: gateToken,
              nowUtc: _claimAt,
              leaseDuration: const Duration(minutes: 10),
            ),
            isTrue,
          );
          final store = _enabledStore(database);
          expect(
            await _claim(
              store,
              ownerId: _destinationOwnerId,
              ownerGateToken: gateToken,
              leaseToken: 'cold-terminal-before-local-change',
            ),
            isEmpty,
            reason:
                'the pulled Active revision must never echo as revision one',
          );

          final repository = DriftAssessmentRepository(database);
          final terminal = terminalCase.state == AssessmentRunState.completed
              ? await repository.complete(
                  runId: _runId,
                  completedAtUtc: terminalCase.terminalAtUtc,
                )
              : await repository.abandon(
                  runId: _runId,
                  abandonedAtUtc: terminalCase.terminalAtUtc,
                );
          expect(terminal.state, terminalCase.state);

          final claims = await _claim(
            store,
            ownerId: _destinationOwnerId,
            ownerGateToken: gateToken,
            leaseToken: 'cold-terminal-revision-two',
          );
          expect(claims, hasLength(1));
          expect(claims.single.localOperationId, _terminalOperationId);
          expect(claims.single.mutation.operationId, _terminalOperationId);
          expect(claims.single.mutation.baseRevision, 1);
          expect(claims.single.mutation.localRevision, 2);
          expect(
            claims.single.mutation.payload['state'],
            terminalCase.state.name,
          );
          await _acknowledge(
            store,
            claim: claims.single,
            ownerGateToken: gateToken,
            atUtc: _claimAt,
          );
          expect(
            await _claim(
              store,
              ownerId: _destinationOwnerId,
              ownerGateToken: gateToken,
              leaseToken: 'cold-terminal-no-replay',
            ),
            isEmpty,
          );
          expect(await database.select(database.syncConflicts).get(), isEmpty);
        } finally {
          await database.close();
        }
      },
    );
  }

  final coldDeviceCases =
      <
        ({
          String name,
          AssessmentRunState state,
          int revision,
          DateTime? completedAtUtc,
          DateTime? abandonedAtUtc,
        })
      >[
        (
          name: 'active',
          state: AssessmentRunState.active,
          revision: 1,
          completedAtUtc: null,
          abandonedAtUtc: null,
        ),
        (
          name: 'completed',
          state: AssessmentRunState.completed,
          revision: 2,
          completedAtUtc: _completedAt,
          abandonedAtUtc: null,
        ),
        (
          name: 'abandoned',
          state: AssessmentRunState.abandoned,
          revision: 2,
          completedAtUtc: null,
          abandonedAtUtc: _abandonedAt,
        ),
      ];
  for (final testCase in coldDeviceCases) {
    test(
      'cold device reconstructs canonical ${testCase.name} assessment state',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwner(database, ownerId: _destinationOwnerId);
          await _seedConsent(database, ownerId: _destinationOwnerId);
          await _seedAssignment(database, ownerId: _destinationOwnerId);
          expect(await _runCount(database), 0, reason: testCase.name);
          expect(
            await database.select(database.learningSessions).get(),
            isEmpty,
            reason: testCase.name,
          );
          final run = _run(
            ownerId: _destinationOwnerId,
            assignmentId: _localAssignmentId(_destinationOwnerId),
            state: testCase.state,
            completedAtUtc: testCase.completedAtUtc,
            abandonedAtUtc: testCase.abandonedAtUtc,
          );
          final entity = _cloudRunEntity(run, revision: testCase.revision);
          final store = DriftSyncStore(database);

          expect(
            await store.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(entity),
            ),
            isTrue,
            reason: testCase.name,
          );
          expect(
            await store.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(entity),
            ),
            isTrue,
            reason: '${testCase.name} replay',
          );

          expect(
            await DriftAssessmentRepository(database).getRun(_runId),
            run,
            reason: testCase.name,
          );
          expect(await _runCount(database), 1, reason: testCase.name);
          final sessions = await database
              .customSelect(
                'SELECT id, owner_id, activity_type, state, started_at_utc_ms, '
                'app_version, build_id FROM learning_sessions ORDER BY id',
              )
              .get();
          expect(sessions, hasLength(1), reason: testCase.name);
          expect(sessions.single.data, <String, Object?>{
            'id': _sessionId,
            'owner_id': _destinationOwnerId,
            'activity_type': 'assessment',
            'state': 'active',
            'started_at_utc_ms': _startedAt.millisecondsSinceEpoch,
            'app_version': '1.0.0',
            'build_id': 'task-12-sync',
          }, reason: testCase.name);
          expect(
            await database.select(database.syncConflicts).get(),
            isEmpty,
            reason: testCase.name,
          );
          expect(
            await (database.select(database.outboxOperations)..where(
                  (row) =>
                      row.entityType.equals('assessmentRun') &
                      row.state.isIn(const <String>[
                        'pending',
                        'inFlight',
                        'retryWaiting',
                      ]),
                ))
                .get(),
            isEmpty,
            reason: '${testCase.name} pull must not echo',
          );
        } finally {
          await database.close();
        }
      },
    );
  }

  test(
    'immutable revision and transition conflicts are durable and atomic',
    () async {
      final conflictCases = <_RunConflictCase>[
        _RunConflictCase(
          'immutable form checksum',
          payloadMutation: (payload) => <String, Object?>{
            ...payload,
            'formChecksumSha256':
                'cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc',
          },
        ),
        _RunConflictCase(
          'owner reassignment',
          payloadMutation: (payload) => <String, Object?>{
            ...payload,
            'ownerId': 'other-firebase-owner',
          },
        ),
        _RunConflictCase(
          'foreign assignment identity',
          payloadMutation: (payload) => <String, Object?>{
            ...payload,
            'assignmentId': 'foreign-local-assignment',
          },
        ),
        _RunConflictCase(
          'foreign learning session',
          payloadMutation: (payload) => <String, Object?>{
            ...payload,
            'learningSessionId': 'other-owner-session',
          },
        ),
        const _RunConflictCase('revision gap', revision: 3),
        _RunConflictCase(
          'terminal reopen',
          revision: 2,
          payloadMutation: (payload) => <String, Object?>{
            ...payload,
            'state': AssessmentRunState.active.name,
            'completedAtUtcMs': null,
          },
        ),
      ];

      for (final conflictCase in conflictCases) {
        final database = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwner(database, ownerId: _destinationOwnerId);
          await _seedConsent(database, ownerId: _destinationOwnerId);
          await _seedSession(database, ownerId: _destinationOwnerId);
          await _seedAssignment(database, ownerId: _destinationOwnerId);
          final store = DriftSyncStore(database);
          final run = _run(
            ownerId: _destinationOwnerId,
            assignmentId: _localAssignmentId(_destinationOwnerId),
          );
          final active = _cloudRunEntity(run, revision: 1);
          expect(
            await store.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(active),
            ),
            isTrue,
            reason: conflictCase.name,
          );

          final completed = run.withTerminalState(
            state: AssessmentRunState.completed,
            terminalAtUtc: _completedAt,
          );
          final canonicalPayload = _cloudRunPayload(completed);
          final conflicting = _cloudRunEntity(
            completed,
            revision: conflictCase.revision,
            payload:
                conflictCase.payloadMutation?.call(canonicalPayload) ??
                canonicalPayload,
          );
          expect(
            await store.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(conflicting),
            ),
            isTrue,
            reason: conflictCase.name,
          );
          expect(
            await store.applyPullPage(
              ownerId: _destinationOwnerId,
              collection: SyncCollection.assessmentRuns,
              page: _page(conflicting),
            ),
            isTrue,
            reason: '${conflictCase.name} replay',
          );

          final persisted = await DriftAssessmentRepository(
            database,
          ).getRun(_runId);
          expect(persisted, run, reason: conflictCase.name);
          final conflicts = await database.select(database.syncConflicts).get();
          expect(conflicts, hasLength(1), reason: conflictCase.name);
          expect(conflicts.single.entityType, 'assessmentRun');
          expect(conflicts.single.outcome, 'quarantined');
          final assessmentOperations = await (database.select(
            database.outboxOperations,
          )..where((row) => row.entityType.equals('assessmentRun'))).get();
          expect(assessmentOperations, hasLength(1), reason: conflictCase.name);
          expect(
            assessmentOperations.single.operationId,
            _createOperationId,
            reason: conflictCase.name,
          );
          expect(
            assessmentOperations.single.state,
            'conflictResolved',
            reason: conflictCase.name,
          );
          expect(
            assessmentOperations.single.attemptCount,
            0,
            reason: conflictCase.name,
          );
          expect(
            assessmentOperations.single.leaseToken,
            isNull,
            reason: conflictCase.name,
          );
        } finally {
          await database.close();
        }
      }
    },
  );

  test(
    'canonical assessment evidence conflict quarantines without mutating its run',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seedOwner(database, ownerId: _destinationOwnerId);
        await _seedConsent(database, ownerId: _destinationOwnerId);
        await _seedSession(database, ownerId: _destinationOwnerId);
        await _seedAssignment(database, ownerId: _destinationOwnerId);
        await _seedVocabulary(database, ownerId: _destinationOwnerId);
        final store = DriftSyncStore(
          database,
          payloadRollout: const SyncPayloadRollout.answerAttemptV2(),
          rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider(
            EvidencePolicyRolloutMode.enforced,
          ),
        );
        final run = _run(
          ownerId: _destinationOwnerId,
          assignmentId: _localAssignmentId(_destinationOwnerId),
        );
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.assessmentRuns,
            page: _page(_cloudRunEntity(run, revision: 1)),
          ),
          isTrue,
        );
        final exact = _cloudAssessmentAttemptEntity();
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.attempts,
            page: _page(exact),
          ),
          isTrue,
        );
        final conflicting = SyncEntity(
          collection: exact.collection,
          entityId: exact.entityId,
          revision: exact.revision,
          isDeleted: exact.isDeleted,
          payloadVersion: exact.payloadVersion,
          clientUpdatedAtUtc: exact.clientUpdatedAtUtc,
          serverUpdatedAtUtc: exact.serverUpdatedAtUtc.add(
            const Duration(seconds: 1),
          ),
          payload: <String, Object?>{...exact.payload, 'responseTimeMs': 451},
        );
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.attempts,
            page: _page(conflicting),
          ),
          isTrue,
        );
        expect(
          await store.applyPullPage(
            ownerId: _destinationOwnerId,
            collection: SyncCollection.attempts,
            page: _page(conflicting),
          ),
          isTrue,
        );

        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        expect(attempts.single.responseTimeMs, 450);
        expect(await DriftAssessmentRepository(database).getRun(_runId), run);
        final conflicts = await database.select(database.syncConflicts).get();
        expect(conflicts, hasLength(1));
        expect(conflicts.single.outcome, 'quarantined');
      } finally {
        await database.close();
      }
    },
  );

  test(
    'push conflict accepts exact cloud replay and quarantines immutable drift',
    () async {
      for (final differs in <bool>[false, true]) {
        final database = AppDatabase(NativeDatabase.memory());
        try {
          await _seedOwner(database);
          await _seedConsent(database);
          await _seedSession(database);
          await _seedAssignment(database);
          await DriftAssessmentRepository(database).start(_run());
          final store = _enabledStore(database);
          final gateToken = 'assessment-conflict-gate-$differs';
          expect(
            await DriftOwnerOperationGate(database).tryAcquire(
              token: gateToken,
              nowUtc: _claimAt,
              leaseDuration: const Duration(minutes: 10),
            ),
            isTrue,
          );
          final claims = await _claim(
            store,
            ownerGateToken: gateToken,
            leaseToken: 'assessment-conflict-lease-$differs',
          );
          expect(claims, hasLength(1));
          final claim = claims.single;
          final payload = differs
              ? <String, Object?>{
                  ...claim.mutation.payload,
                  'instrumentVersion': 'instrument-v2',
                }
              : claim.mutation.payload;
          final cloud = SyncEntity(
            collection: SyncCollection.assessmentRuns,
            entityId: claim.mutation.entityId,
            revision: claim.mutation.localRevision,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: claim.mutation.clientUpdatedAtUtc,
            serverUpdatedAtUtc: _claimAt,
            payload: payload,
          );

          expect(
            await store.resolvePushConflict(
              claim: claim,
              ownerGateToken: gateToken,
              cloudEntity: cloud,
              resolvedAtUtc: _claimAt,
            ),
            isTrue,
          );
          final operation = (await _assessmentOperations(database)).single;
          final conflicts = await database.select(database.syncConflicts).get();
          if (differs) {
            expect(operation.state, 'permanentFailure');
            expect(conflicts, hasLength(1));
            expect(conflicts.single.outcome, 'quarantined');
            expect(
              await _claim(
                store,
                ownerGateToken: gateToken,
                leaseToken: 'assessment-conflict-no-loop',
              ),
              isEmpty,
            );
          } else {
            expect(operation.state, 'conflictResolved');
            expect(operation.failureCode, 'identicalCloudEvidence');
            expect(conflicts, isEmpty);
          }
          expect(
            await DriftAssessmentRepository(database).getRun(_runId),
            _run(),
          );
        } finally {
          await database.close();
        }
      }
    },
  );

  test(
    'one engine run pulls assignment before assessment run before attempts',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seedOwner(database, ownerId: _destinationOwnerId);
        await _seedConsent(database, ownerId: _destinationOwnerId);
        await _seedSession(database, ownerId: _destinationOwnerId);
        await _seedVocabulary(database, ownerId: _destinationOwnerId);
        final destinationRun = _run(
          ownerId: _destinationOwnerId,
          assignmentId: _localAssignmentId(_destinationOwnerId),
        );
        final gateway = _PullOrderGateway(
          assignment: _cloudAssignmentEntity(),
          run: _cloudRunEntity(destinationRun, revision: 1),
          attempt: _cloudAssessmentAttemptEntity(),
          nowUtc: _claimAt,
        );
        var lease = 0;
        final engine = SyncEngine(
          owners: _OwnerRepository(
            identity.LocalOwner(
              id: _destinationOwnerId,
              firebaseUid: _firebaseUid,
              createdAtUtc: _assignedAt,
            ),
          ),
          store: DriftSyncStore(
            database,
            payloadRollout: const SyncPayloadRollout.answerAttemptV2(),
            rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider(
              EvidencePolicyRolloutMode.enforced,
            ),
          ),
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: _claimAt,
            expiresAtUtc: _claimAt.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(database),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => _claimAt,
          generateLeaseToken: () => 'assessment-pull-lease-${++lease}',
        );

        final result = await engine.run();

        expect(result.status, SyncRunStatus.completed);
        expect(result.pulled, 3);
        final assignmentIndex = gateway.pulled.indexOf(
          SyncCollection.experimentAssignments,
        );
        final runIndex = gateway.pulled.indexOf(SyncCollection.assessmentRuns);
        final attemptIndex = gateway.pulled.indexOf(SyncCollection.attempts);
        expect(assignmentIndex, greaterThanOrEqualTo(0));
        expect(runIndex, greaterThan(assignmentIndex));
        expect(attemptIndex, greaterThan(runIndex));
        expect(
          await DriftAssessmentRepository(database).getRun(_runId),
          destinationRun,
        );
        expect(
          await database.select(database.experimentAssignments).get(),
          hasLength(1),
        );
        final attempts = await database.select(database.answerAttempts).get();
        expect(attempts, hasLength(1));
        final storedContext = EvidenceContext.fromJson(
          (jsonDecode(attempts.single.evidenceContextJson) as Map)
              .cast<String, Object?>(),
        );
        expect(storedContext.evidenceClass, EvidenceClass.assessment);
        expect(
          storedContext.assignmentId,
          _localAssignmentId(_destinationOwnerId),
        );
        expect(
          await (database.select(database.outboxOperations)..where(
                (row) => row.state.isIn(const <String>[
                  'pending',
                  'inFlight',
                  'retryWaiting',
                ]),
              ))
              .get(),
          isEmpty,
          reason: 'remote assignment, run, and evidence pulls must not echo',
        );
      } finally {
        await database.close();
      }
    },
  );

  test('assessment responses remain canonical AnswerAttempts only', () async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      final tables = await database
          .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
          .map((row) => row.read<String>('name'))
          .get();
      expect(tables, contains('assessment_runs'));
      expect(tables, isNot(contains('assessment_attempts')));
      expect(tables, isNot(contains('assessment_responses')));
      expect(tables, isNot(contains('assessment_scores')));
      expect(SyncCollection.values, contains(SyncCollection.attempts));
      expect(SyncCollection.values, contains(SyncCollection.assessmentRuns));
      expect(
        SyncCollection.values.map((collection) => collection.wireName),
        isNot(contains('assessment_attempts')),
      );
    } finally {
      await database.close();
    }
  });
}

const _ownerId = 'local-assessment-owner';
const _destinationOwnerId = 'local-assessment-owner-device-b';
const _firebaseUid = 'firebase-assessment-owner';
const _sessionId = 'assessment-session-pre';
const _runId = 'assessment-run-pre';
const _studyCycleId = 'study-cycle-2026';
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1';
const _experimentId = 'study-a';
const _experimentVersion = 1;
const _cohort = 'intervention';
const _consentVersion = 1;
const _instrumentChecksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
const _formChecksum =
    'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb';
const _createOperationId = 'assessmentRun:assessment-run-pre:1';
const _terminalOperationId = 'assessmentRun:assessment-run-pre:2';
final _consentAt = DateTime.utc(2026, 8, 14, 7, 55);
final _assignedAt = DateTime.utc(2026, 8, 14, 8);
final _startedAt = DateTime.utc(2026, 8, 14, 9);
final _completedAt = DateTime.utc(2026, 8, 14, 9, 30);
final _abandonedAt = DateTime.utc(2026, 8, 14, 9, 20);
final _claimAt = DateTime.utc(2026, 8, 14, 10);

const _researchCatalog = ResearchProtocolModeCatalog(
  mappings: <ResearchProtocolModeMapping>[
    ResearchProtocolModeMapping(
      protocolId: _protocolId,
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
      protocolVersion: _protocolVersion,
      consentVersion: _consentVersion,
      mode: EvidencePolicyRolloutMode.enforced,
    ),
  ],
);

const _wrongProtocolCatalog = ResearchProtocolModeCatalog(
  mappings: <ResearchProtocolModeMapping>[
    ResearchProtocolModeMapping(
      protocolId: 'other-assessment-protocol',
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
      protocolVersion: _protocolVersion,
      consentVersion: _consentVersion,
      mode: EvidencePolicyRolloutMode.enforced,
    ),
  ],
);

String _localAssignmentId(String ownerId) =>
    DriftExperimentAssignmentRepository.canonicalAssignmentId(
      ownerId: ownerId,
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
    );

String _cloudAssignmentId() =>
    DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
      firebaseUid: _firebaseUid,
      experimentId: _experimentId,
      experimentVersion: _experimentVersion,
    );

AssessmentRun _run({
  String id = _runId,
  String ownerId = _ownerId,
  String? assignmentId,
  String instrumentVersion = 'instrument-v1',
  AssessmentRunState state = AssessmentRunState.active,
  DateTime? completedAtUtc,
  DateTime? abandonedAtUtc,
}) => AssessmentRun(
  id: id,
  ownerId: ownerId,
  learningSessionId: _sessionId,
  studyCycleId: _studyCycleId,
  phase: AssessmentPhase.pre,
  state: state,
  protocolId: _protocolId,
  protocolVersion: _protocolVersion,
  experimentId: _experimentId,
  experimentVersion: _experimentVersion,
  assignmentId: assignmentId ?? _localAssignmentId(ownerId),
  cohort: _cohort,
  consentVersion: _consentVersion,
  consentDecidedAtUtc: _consentAt,
  instrumentId: 'instrument-core',
  instrumentVersion: instrumentVersion,
  formId: 'form-a',
  formVersion: 'form-v1',
  instrumentChecksumSha256: _instrumentChecksum,
  formChecksumSha256: _formChecksum,
  appVersion: '1.0.0',
  buildId: 'task-12-sync',
  databaseSchemaVersion: 15,
  contentRevision: 'assessment-content-v1',
  evidencePolicyVersion: 'learning-evidence-v1',
  featureContractRevision: currentFeatureContractIdentity.revision,
  featureContractHash: currentFeatureContractIdentity.semanticHash,
  startedAtUtc: _startedAt,
  completedAtUtc: completedAtUtc,
  abandonedAtUtc: abandonedAtUtc,
);

Map<String, Object?> _cloudRunPayload(AssessmentRun run) => <String, Object?>{
  'runId': run.id,
  'ownerId': _firebaseUid,
  'learningSessionId': run.learningSessionId,
  'studyCycleId': run.studyCycleId,
  'phase': run.phase.name,
  'state': run.state.name,
  'protocolId': run.protocolId,
  'protocolVersion': run.protocolVersion,
  'experimentId': run.experimentId,
  'experimentVersion': run.experimentVersion,
  'assignmentId': _cloudAssignmentId(),
  'cohort': run.cohort,
  'consentVersion': run.consentVersion,
  'consentDecidedAtUtcMs': run.consentDecidedAtUtc.millisecondsSinceEpoch,
  'instrumentId': run.instrumentId,
  'instrumentVersion': run.instrumentVersion,
  'formId': run.formId,
  'formVersion': run.formVersion,
  'instrumentChecksumSha256': run.instrumentChecksumSha256,
  'formChecksumSha256': run.formChecksumSha256,
  'appVersion': run.appVersion,
  'buildId': run.buildId,
  'databaseSchemaVersion': run.databaseSchemaVersion,
  'contentRevision': run.contentRevision,
  'evidencePolicyVersion': run.evidencePolicyVersion,
  'featureContractRevision': run.featureContractRevision,
  'featureContractHash': run.featureContractHash,
  'startedAtUtcMs': run.startedAtUtc.millisecondsSinceEpoch,
  'completedAtUtcMs': run.completedAtUtc?.millisecondsSinceEpoch,
  'abandonedAtUtcMs': run.abandonedAtUtc?.millisecondsSinceEpoch,
};

SyncEntity _cloudRunEntity(
  AssessmentRun run, {
  required int revision,
  Map<String, Object?>? payload,
}) => SyncEntity(
  collection: SyncCollection.assessmentRuns,
  entityId: run.id,
  revision: revision,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc:
      run.completedAtUtc ?? run.abandonedAtUtc ?? run.startedAtUtc,
  serverUpdatedAtUtc: _claimAt.add(Duration(seconds: revision)),
  payload: payload ?? _cloudRunPayload(run),
);

SyncEntity _cloudAssignmentEntity() => SyncEntity(
  collection: SyncCollection.experimentAssignments,
  entityId: _cloudAssignmentId(),
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: _assignedAt,
  serverUpdatedAtUtc: _claimAt,
  payload: <String, Object?>{
    'assignmentId': _cloudAssignmentId(),
    'ownerId': _firebaseUid,
    'experimentId': _experimentId,
    'experimentVersion': _experimentVersion,
    'cohort': _cohort,
    'protocolVersion': _protocolVersion,
    'assignedAtUtcMs': _assignedAt.millisecondsSinceEpoch,
  },
);

SyncEntity _cloudAssessmentAttemptEntity() {
  final occurredAt = _startedAt.add(const Duration(minutes: 5));
  final context = EvidenceContext.forNewEvidence(
    evidenceClass: EvidenceClass.assessment,
    skillId: 'word-assessment-1',
    hintLevel: 0,
    contentRevision: 'assessment-content-v1',
    rolloutMode: EvidencePolicyRolloutMode.enforced,
    protocolId: _protocolId,
    protocolVersion: _protocolVersion,
    experimentId: _experimentId,
    experimentVersion: _experimentVersion,
    assignmentId: _cloudAssignmentId(),
    cohort: _cohort,
    researchConsentVersion: _consentVersion,
    instrumentId: 'instrument-core',
    instrumentVersion: 'instrument-v1',
    formId: 'form-a',
    formVersion: 'form-v1',
    assessmentItemId: 'item-assessment-1',
    assessmentResponseCode: 'correct',
    scoringRuleVersion: 'score-v1',
    engagementAllowed: false,
  );
  return SyncEntity(
    collection: SyncCollection.attempts,
    entityId: 'assessment-evidence-1',
    revision: 1,
    isDeleted: false,
    payloadVersion: 2,
    clientUpdatedAtUtc: occurredAt,
    serverUpdatedAtUtc: _claimAt.add(const Duration(seconds: 3)),
    payload: <String, Object?>{
      'sessionId': _sessionId,
      'wordId': 'word-assessment-1',
      'promptMode': 'assessmentResponse',
      'isCorrect': true,
      'responseTimeMs': 450,
      'attemptNumber': 1,
      'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
      'providerProvenance': null,
      'evidenceClass': EvidenceClass.assessment.name,
      'evidenceContext': context.toJson(),
    },
  );
}

PullPage _page(SyncEntity entity) => PullPage(
  changes: <SyncEntity>[entity],
  nextCursor: SyncCursor(
    serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
    documentId: entity.entityId,
  ),
  hasMore: false,
);

DriftSyncStore _enabledStore(
  AppDatabase database, {
  String deployedRulesRevision = assessmentRunV1RulesRevision,
  ResearchProtocolModeCatalog protocolModeCatalog = _researchCatalog,
}) => DriftSyncStore(
  database,
  researchSyncRollout: ResearchCollectionSyncRollout.researchAssessmentV1(
    deployedExperimentAssignmentRulesRevision:
        experimentAssignmentV1RulesRevision,
    deployedAssessmentRunRulesRevision: deployedRulesRevision,
    protocolModeCatalog: protocolModeCatalog,
  ),
  consentRegistry: DriftConsentRegistry(database),
);

Future<List<ClaimedSyncOperation>> _claim(
  DriftSyncStore store, {
  String ownerId = _ownerId,
  required String ownerGateToken,
  required String leaseToken,
}) => store.claimPending(
  ownerId: ownerId,
  firebaseUid: _firebaseUid,
  limit: 10,
  leaseToken: leaseToken,
  ownerGateToken: ownerGateToken,
  leaseDuration: const Duration(minutes: 5),
  nowUtc: _claimAt,
);

Future<void> _acknowledge(
  DriftSyncStore store, {
  required ClaimedSyncOperation claim,
  required String ownerGateToken,
  required DateTime atUtc,
}) async {
  final begun = await store.beginAttempt(
    claim: claim,
    ownerGateToken: ownerGateToken,
    nowUtc: atUtc,
  );
  expect(begun, isNotNull);
  final exact = begun!;
  expect(
    await store.acknowledge(
      operationId: exact.localOperationId,
      leaseToken: exact.leaseToken,
      ownerGateToken: ownerGateToken,
      nowUtc: atUtc,
      acknowledgement: PushAcknowledged(
        operationId: exact.mutation.operationId,
        resultingRevision: exact.mutation.localRevision,
        acknowledgedAtUtc: atUtc,
      ),
    ),
    isTrue,
  );
}

Future<void> _seedOwner(AppDatabase database, {String ownerId = _ownerId}) =>
    database.customInsert(
      'INSERT INTO local_owners('
      'id, firebase_uid, account_state, created_at_utc_ms) VALUES (?, ?, ?, ?)',
      variables: [
        Variable<String>(ownerId),
        const Variable<String>(_firebaseUid),
        const Variable<String>('firebaseBound'),
        Variable<int>(_assignedAt.millisecondsSinceEpoch),
      ],
    );

Future<void> _seedConsent(AppDatabase database, {String ownerId = _ownerId}) =>
    database.customInsert(
      'INSERT INTO research_consents('
      'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
      'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, NULL)',
      variables: [
        Variable<String>('consent:$ownerId:$_consentVersion'),
        Variable<String>(ownerId),
        const Variable<int>(_consentVersion),
        const Variable<String>('accepted'),
        Variable<int>(_consentAt.millisecondsSinceEpoch),
      ],
    );

Future<void> _seedSession(
  AppDatabase database, {
  String ownerId = _ownerId,
}) => database.customInsert(
  'INSERT INTO learning_sessions('
  'id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id'
  ') VALUES (?, ?, ?, ?, ?, ?, ?)',
  variables: [
    const Variable<String>(_sessionId),
    Variable<String>(ownerId),
    const Variable<String>('assessment'),
    const Variable<String>('active'),
    Variable<int>(_startedAt.millisecondsSinceEpoch),
    const Variable<String>('1.0.0'),
    const Variable<String>('task-12-sync'),
  ],
);

Future<void> _seedAssignment(
  AppDatabase database, {
  String ownerId = _ownerId,
}) => database.customInsert(
  'INSERT INTO experiment_assignments('
  'id, owner_id, experiment_id, experiment_version, cohort, '
  'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)',
  variables: [
    Variable<String>(_localAssignmentId(ownerId)),
    Variable<String>(ownerId),
    const Variable<String>(_experimentId),
    const Variable<int>(_experimentVersion),
    const Variable<String>(_cohort),
    const Variable<String>(_protocolVersion),
    Variable<int>(_assignedAt.millisecondsSinceEpoch),
  ],
);

Future<void> _seedVocabulary(
  AppDatabase database, {
  required String ownerId,
}) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'assessment-category-1',
          ownerId: ownerId,
          name: 'Assessment',
          normalizedName: 'assessment',
          createdAtUtcMs: _startedAt.millisecondsSinceEpoch,
          updatedAtUtcMs: _startedAt.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-assessment-1',
          ownerId: ownerId,
          categoryId: 'assessment-category-1',
          spelling: 'assessment',
          normalizedSpelling: 'assessment',
          meaning: 'assessment',
          normalizedMeaning: 'assessment',
          partOfSpeech: 'noun',
          createdAtUtcMs: _startedAt.millisecondsSinceEpoch,
          updatedAtUtcMs: _startedAt.millisecondsSinceEpoch,
        ),
      );
}

Future<List<OutboxOperation>> _assessmentOperations(AppDatabase database) =>
    (database.select(database.outboxOperations)
          ..where((row) => row.entityType.equals('assessmentRun'))
          ..orderBy([(row) => OrderingTerm.asc(row.createdAtUtcMs)]))
        .get();

Future<int> _runCount(AppDatabase database) => database
    .customSelect('SELECT COUNT(*) AS count FROM assessment_runs')
    .map((row) => row.read<int>('count'))
    .getSingle();

final class _RunConflictCase {
  const _RunConflictCase(this.name, {this.revision = 2, this.payloadMutation});

  final String name;
  final int revision;
  final Map<String, Object?> Function(Map<String, Object?>)? payloadMutation;
}

final class _OwnerRepository implements LocalOwnerRepository {
  _OwnerRepository(this.owner);

  identity.LocalOwner owner;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async {
    owner = identity.LocalOwner(
      id: owner.id,
      firebaseUid: firebaseUid,
      createdAtUtc: owner.createdAtUtc,
      upgradedAtUtc: owner.upgradedAtUtc,
    );
    return owner;
  }
}

final class _PullOrderGateway implements SyncGateway {
  _PullOrderGateway({
    required this.assignment,
    required this.run,
    required this.attempt,
    required this.nowUtc,
  });

  final SyncEntity assignment;
  final SyncEntity run;
  final SyncEntity attempt;
  final DateTime nowUtc;
  final List<SyncCollection> pulled = <SyncCollection>[];

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );

  @override
  Future<PushResult> push(PushMutation mutation) async => PushAcknowledged(
    operationId: mutation.operationId,
    resultingRevision: mutation.localRevision,
    acknowledgedAtUtc: nowUtc,
  );

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    pulled.add(collection);
    final entity = switch (collection) {
      SyncCollection.experimentAssignments => assignment,
      SyncCollection.assessmentRuns => run,
      SyncCollection.attempts => attempt,
      _ => null,
    };
    if (entity == null || after != null) {
      return PullPage(
        changes: const <SyncEntity>[],
        nextCursor: after,
        hasMore: false,
      );
    }
    return _page(entity);
  }
}
