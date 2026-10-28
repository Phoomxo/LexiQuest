import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
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
  test('only the combined rollout can enable assessment run claims', () {
    const assignmentOnly =
        ResearchCollectionSyncRollout.experimentAssignmentsV1(
          deployedRulesRevision: experimentAssignmentV1RulesRevision,
          protocolModeCatalog: _catalog,
        );
    const assessmentOnly = ResearchCollectionSyncRollout.assessmentRunsV1(
      deployedRulesRevision: assessmentRunV1RulesRevision,
      protocolModeCatalog: _catalog,
    );
    const combined = ResearchCollectionSyncRollout.researchAssessmentV1(
      deployedExperimentAssignmentRulesRevision:
          experimentAssignmentV1RulesRevision,
      deployedAssessmentRunRulesRevision: assessmentRunV1RulesRevision,
      protocolModeCatalog: _catalog,
    );
    const staleAssessmentRules =
        ResearchCollectionSyncRollout.researchAssessmentV1(
          deployedExperimentAssignmentRulesRevision:
              experimentAssignmentV1RulesRevision,
          deployedAssessmentRunRulesRevision: 'assessment-run-v1-r1',
          protocolModeCatalog: _catalog,
        );

    expect(assignmentOnly.allowsExperimentAssignmentClaims, isTrue);
    expect(assignmentOnly.allowsAssessmentRunClaims, isFalse);
    expect(assessmentOnly.allowsExperimentAssignmentClaims, isFalse);
    expect(
      assessmentOnly.allowsAssessmentRunClaims,
      isFalse,
      reason: 'standalone assessment rollout cannot prove cloud assignment',
    );
    expect(combined.allowsExperimentAssignmentClaims, isTrue);
    expect(combined.allowsAssessmentRunClaims, isTrue);
    expect(
      staleAssessmentRules.allowsAssessmentRunClaims,
      isFalse,
      reason:
          'the pre-f39 rules token cannot authorize the widened v15-v22 '
          'assessment payload contract',
    );
  });

  test(
    'one shared research rollout delivers assignment before assessment run',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seedOwner(database);
        await _seedConsent(database);
        await _seedSession(database);
        final assignment = await DriftExperimentAssignmentRepository(database)
            .assignIfAbsent(
              ownerId: _ownerId,
              experimentId: _experimentId,
              experimentVersion: _experimentVersion,
              cohort: _cohort,
              protocolVersion: _protocolVersion,
              assignedAtUtc: _assignedAtUtc,
            );
        await DriftAssessmentRepository(database).start(
          AssessmentRun(
            id: _runId,
            ownerId: _ownerId,
            learningSessionId: _sessionId,
            studyCycleId: 'cycle-1',
            phase: AssessmentPhase.pre,
            state: AssessmentRunState.active,
            protocolId: _protocolId,
            protocolVersion: assignment.protocolVersion,
            experimentId: assignment.experimentId,
            experimentVersion: assignment.experimentVersion,
            assignmentId: assignment.id,
            cohort: assignment.cohort,
            consentVersion: _consentVersion,
            consentDecidedAtUtc: _consentAtUtc,
            instrumentId: 'instrument-core',
            instrumentVersion: 'instrument-v1',
            formId: 'form-a',
            formVersion: 'form-v1',
            instrumentChecksumSha256: _instrumentChecksum,
            formChecksumSha256: _formChecksum,
            appVersion: '1.0.0',
            buildId: 'task-12-shared-rollout',
            databaseSchemaVersion: AppDatabase.currentSchemaVersion,
            contentRevision: 'assessment-content-v1',
            evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
            featureContractRevision: currentFeatureContractIdentity.revision,
            featureContractHash: currentFeatureContractIdentity.semanticHash,
            startedAtUtc: _startedAtUtc,
            completedAtUtc: null,
            abandonedAtUtc: null,
          ),
        );

        const gateToken = 'shared-research-rollout-owner-gate';
        expect(
          await DriftOwnerOperationGate(database).tryAcquire(
            token: gateToken,
            nowUtc: _claimAtUtc,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        expect(
          await _claim(
            DriftSyncStore(database),
            gateToken: gateToken,
            leaseToken: 'shared-research-default-off',
          ),
          isEmpty,
          reason: 'production default must keep both collections pending',
        );

        final assessmentOnly = DriftSyncStore(
          database,
          researchSyncRollout:
              const ResearchCollectionSyncRollout.assessmentRunsV1(
                deployedRulesRevision: assessmentRunV1RulesRevision,
                protocolModeCatalog: _catalog,
              ),
          consentRegistry: DriftConsentRegistry(database),
        );
        expect(
          await _claim(
            assessmentOnly,
            gateToken: gateToken,
            leaseToken: 'standalone-assessment-must-stay-pending',
          ),
          isEmpty,
          reason: 'assessment cannot upload before its cloud assignment',
        );
        final afterStandalone = await database
            .select(database.outboxOperations)
            .get();
        expect(afterStandalone, hasLength(2));
        expect(
          afterStandalone.map((row) => row.state),
          everyElement('pending'),
        );
        expect(afterStandalone.map((row) => row.attemptCount), everyElement(0));
        expect(
          afterStandalone.map((row) => row.leaseToken),
          everyElement(isNull),
        );
        expect(
          afterStandalone.map((row) => row.leaseExpiresAtUtcMs),
          everyElement(isNull),
        );

        final wrongRules = DriftSyncStore(
          database,
          researchSyncRollout:
              ResearchCollectionSyncRollout.researchAssessmentV1(
                deployedExperimentAssignmentRulesRevision:
                    experimentAssignmentV1RulesRevision,
                deployedAssessmentRunRulesRevision:
                    experimentAssignmentV1RulesRevision,
                protocolModeCatalog: _catalog,
              ),
          consentRegistry: DriftConsentRegistry(database),
        );
        expect(
          await _claim(
            wrongRules,
            gateToken: gateToken,
            leaseToken: 'shared-research-wrong-rules',
          ),
          isEmpty,
          reason: 'either mismatched deployed revision must fail closed',
        );
        final stillPending = await database
            .select(database.outboxOperations)
            .get();
        expect(stillPending, hasLength(2));
        expect(stillPending.map((row) => row.state), everyElement('pending'));
        expect(stillPending.map((row) => row.attemptCount), everyElement(0));

        final store = DriftSyncStore(
          database,
          researchSyncRollout:
              ResearchCollectionSyncRollout.researchAssessmentV1(
                deployedExperimentAssignmentRulesRevision:
                    experimentAssignmentV1RulesRevision,
                deployedAssessmentRunRulesRevision:
                    assessmentRunV1RulesRevision,
                protocolModeCatalog: _catalog,
              ),
          consentRegistry: DriftConsentRegistry(database),
        );
        final assignmentClaims = await _claim(
          store,
          gateToken: gateToken,
          leaseToken: 'shared-research-assignment',
        );
        expect(assignmentClaims, hasLength(1));
        expect(
          assignmentClaims.single.mutation.collection,
          SyncCollection.experimentAssignments,
        );
        await _acknowledge(
          store,
          assignmentClaims.single,
          gateToken: gateToken,
          atUtc: _claimAtUtc,
        );

        final assessmentClaims = await _claim(
          store,
          gateToken: gateToken,
          leaseToken: 'shared-research-assessment',
        );
        expect(assessmentClaims, hasLength(1));
        expect(
          assessmentClaims.single.mutation.collection,
          SyncCollection.assessmentRuns,
        );
        expect(assessmentClaims.single.mutation.entityId, _runId);
        expect(assessmentClaims.single.mutation.localRevision, 1);
        await _acknowledge(
          store,
          assessmentClaims.single,
          gateToken: gateToken,
          atUtc: _claimAtUtc.add(const Duration(seconds: 1)),
        );

        final acknowledged = await database
            .select(database.outboxOperations)
            .get();
        expect(acknowledged, hasLength(2));
        expect(
          acknowledged.map((row) => row.state),
          everyElement('acknowledged'),
        );
        expect(acknowledged.map((row) => row.attemptCount), everyElement(1));
      } finally {
        await database.close();
      }
    },
  );

  test(
    'assignment pagination defers assessment pull until the required assignment lands',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      try {
        await _seedOwner(database);
        await _seedConsent(database);
        final localAssignmentId =
            DriftExperimentAssignmentRepository.canonicalAssignmentId(
              ownerId: _ownerId,
              experimentId: _experimentId,
              experimentVersion: _experimentVersion,
            );
        final expectedRun = _assessmentRun(
          ownerId: _ownerId,
          assignmentId: localAssignmentId,
        );
        final gateway = _PaginatedResearchGateway(
          firstAssignment: _cloudAssignmentEntity(
            experimentId: 'study-before',
            serverUpdatedAtUtc: _claimAtUtc.subtract(
              const Duration(seconds: 2),
            ),
          ),
          requiredAssignment: _cloudAssignmentEntity(
            serverUpdatedAtUtc: _claimAtUtc.subtract(
              const Duration(seconds: 1),
            ),
          ),
          run: _cloudRunEntity(expectedRun),
          nowUtc: _claimAtUtc,
        );
        var lease = 0;
        final store = DriftSyncStore(database);
        final engine = SyncEngine(
          owners: _ResearchOwnerRepository(
            identity.LocalOwner(
              id: _ownerId,
              firebaseUid: _firebaseUid,
              createdAtUtc: _consentAtUtc,
            ),
          ),
          store: store,
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: _claimAtUtc,
            expiresAtUtc: _claimAtUtc.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(database),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => _claimAtUtc,
          generateLeaseToken: () => 'research-pagination-${++lease}',
        );

        final firstPullStart = gateway.pulled.length;
        final first = await engine.run();
        final firstPulls = gateway.pulled.sublist(firstPullStart);
        expect(first.status, SyncRunStatus.completed);
        expect(first.retryRecommended, isTrue);
        expect(first.pulled, 1);
        expect(
          firstPulls,
          isNot(contains(SyncCollection.assessmentRuns)),
          reason: 'dependent runs must wait while assignment hasMore is true',
        );
        expect(
          await store.readCheckpoint(_ownerId, SyncCollection.assessmentRuns),
          isNull,
        );
        expect(await database.select(database.assessmentRuns).get(), isEmpty);
        expect(await database.select(database.syncConflicts).get(), isEmpty);

        final secondPullStart = gateway.pulled.length;
        final second = await engine.run();
        final secondPulls = gateway.pulled.sublist(secondPullStart);
        expect(second.status, SyncRunStatus.completed);
        expect(second.retryRecommended, isFalse);
        expect(second.pulled, 2);
        expect(
          secondPulls.indexOf(SyncCollection.assessmentRuns),
          greaterThan(
            secondPulls.indexOf(SyncCollection.experimentAssignments),
          ),
        );
        expect(
          await DriftAssessmentRepository(database).getRun(_runId),
          expectedRun,
        );
        expect(await database.select(database.syncConflicts).get(), isEmpty);
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
          reason: 'pulled research state must not create pushable echo',
        );
      } finally {
        await database.close();
      }
    },
  );
}

Future<List<ClaimedSyncOperation>> _claim(
  DriftSyncStore store, {
  required String gateToken,
  required String leaseToken,
}) => store.claimPending(
  ownerId: _ownerId,
  firebaseUid: _firebaseUid,
  limit: 1,
  leaseToken: leaseToken,
  ownerGateToken: gateToken,
  leaseDuration: const Duration(minutes: 5),
  nowUtc: _claimAtUtc,
);

Future<void> _acknowledge(
  DriftSyncStore store,
  ClaimedSyncOperation claim, {
  required String gateToken,
  required DateTime atUtc,
}) async {
  final begun = await store.beginAttempt(
    claim: claim,
    ownerGateToken: gateToken,
    nowUtc: atUtc,
  );
  expect(begun, isNotNull);
  final attempted = begun!;
  expect(
    await store.acknowledge(
      operationId: attempted.localOperationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: gateToken,
      nowUtc: atUtc,
      acknowledgement: PushAcknowledged(
        operationId: attempted.localOperationId,
        resultingRevision: attempted.mutation.localRevision,
        acknowledgedAtUtc: atUtc,
      ),
    ),
    isTrue,
  );
}

Future<void> _seedOwner(AppDatabase database) => database.customInsert(
  'INSERT INTO local_owners('
  'id, firebase_uid, account_state, created_at_utc_ms) VALUES (?, ?, ?, ?)',
  variables: [
    const Variable<String>(_ownerId),
    const Variable<String>(_firebaseUid),
    const Variable<String>('firebaseBound'),
    Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
  ],
);

Future<void> _seedConsent(AppDatabase database) => database.customInsert(
  'INSERT INTO research_consents('
  'id, owner_id, consent_version, consent_state, decided_at_utc_ms, '
  'withdrawn_at_utc_ms) VALUES (?, ?, ?, ?, ?, NULL)',
  variables: [
    const Variable<String>('consent:owner-a:7'),
    const Variable<String>(_ownerId),
    const Variable<int>(_consentVersion),
    const Variable<String>('accepted'),
    Variable<int>(_consentAtUtc.millisecondsSinceEpoch),
  ],
);

Future<void> _seedSession(AppDatabase database) => database.customInsert(
  'INSERT INTO learning_sessions('
  'id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id'
  ') VALUES (?, ?, ?, ?, ?, ?, ?)',
  variables: [
    const Variable<String>(_sessionId),
    const Variable<String>(_ownerId),
    const Variable<String>('assessment'),
    const Variable<String>('active'),
    Variable<int>(
      _startedAtUtc.subtract(const Duration(minutes: 1)).millisecondsSinceEpoch,
    ),
    const Variable<String>('1.0.0'),
    const Variable<String>('task-12-shared-rollout'),
  ],
);

AssessmentRun _assessmentRun({
  required String ownerId,
  required String assignmentId,
}) => AssessmentRun(
  id: _runId,
  ownerId: ownerId,
  learningSessionId: _sessionId,
  studyCycleId: 'cycle-1',
  phase: AssessmentPhase.pre,
  state: AssessmentRunState.active,
  protocolId: _protocolId,
  protocolVersion: _protocolVersion,
  experimentId: _experimentId,
  experimentVersion: _experimentVersion,
  assignmentId: assignmentId,
  cohort: _cohort,
  consentVersion: _consentVersion,
  consentDecidedAtUtc: _consentAtUtc,
  instrumentId: 'instrument-core',
  instrumentVersion: 'instrument-v1',
  formId: 'form-a',
  formVersion: 'form-v1',
  instrumentChecksumSha256: _instrumentChecksum,
  formChecksumSha256: _formChecksum,
  appVersion: '1.0.0',
  buildId: 'task-12-shared-rollout',
  databaseSchemaVersion: AppDatabase.currentSchemaVersion,
  contentRevision: 'assessment-content-v1',
  evidencePolicyVersion: EvidenceContext.currentPolicyVersion,
  featureContractRevision: currentFeatureContractIdentity.revision,
  featureContractHash: currentFeatureContractIdentity.semanticHash,
  startedAtUtc: _startedAtUtc,
  completedAtUtc: null,
  abandonedAtUtc: null,
);

SyncEntity _cloudAssignmentEntity({
  String experimentId = _experimentId,
  required DateTime serverUpdatedAtUtc,
}) {
  final cloudId =
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: _firebaseUid,
        experimentId: experimentId,
        experimentVersion: _experimentVersion,
      );
  return SyncEntity(
    collection: SyncCollection.experimentAssignments,
    entityId: cloudId,
    revision: 1,
    isDeleted: false,
    payloadVersion: 1,
    clientUpdatedAtUtc: _assignedAtUtc,
    serverUpdatedAtUtc: serverUpdatedAtUtc,
    payload: <String, Object?>{
      'assignmentId': cloudId,
      'ownerId': _firebaseUid,
      'experimentId': experimentId,
      'experimentVersion': _experimentVersion,
      'cohort': _cohort,
      'protocolVersion': _protocolVersion,
      'assignedAtUtcMs': _assignedAtUtc.millisecondsSinceEpoch,
    },
  );
}

SyncEntity _cloudRunEntity(AssessmentRun run) {
  final cloudAssignmentId =
      DriftExperimentAssignmentRepository.canonicalCloudAssignmentId(
        firebaseUid: _firebaseUid,
        experimentId: run.experimentId,
        experimentVersion: run.experimentVersion,
      );
  return SyncEntity(
    collection: SyncCollection.assessmentRuns,
    entityId: run.id,
    revision: 1,
    isDeleted: false,
    payloadVersion: 1,
    clientUpdatedAtUtc: run.startedAtUtc,
    serverUpdatedAtUtc: _claimAtUtc,
    payload: <String, Object?>{
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
      'assignmentId': cloudAssignmentId,
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
      'completedAtUtcMs': null,
      'abandonedAtUtcMs': null,
    },
  );
}

final class _ResearchOwnerRepository implements LocalOwnerRepository {
  _ResearchOwnerRepository(this.owner);

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

final class _PaginatedResearchGateway implements SyncGateway {
  _PaginatedResearchGateway({
    required this.firstAssignment,
    required this.requiredAssignment,
    required this.run,
    required this.nowUtc,
  });

  final SyncEntity firstAssignment;
  final SyncEntity requiredAssignment;
  final SyncEntity run;
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
    if (collection == SyncCollection.experimentAssignments) {
      if (after == null) return _page(firstAssignment, hasMore: true);
      if (after.documentId == firstAssignment.entityId) {
        return _page(requiredAssignment, hasMore: false);
      }
    } else if (collection == SyncCollection.assessmentRuns && after == null) {
      return _page(run, hasMore: false);
    }
    return PullPage(
      changes: const <SyncEntity>[],
      nextCursor: after,
      hasMore: false,
    );
  }

  PullPage _page(SyncEntity entity, {required bool hasMore}) => PullPage(
    changes: <SyncEntity>[entity],
    nextCursor: SyncCursor(
      serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
      documentId: entity.entityId,
    ),
    hasMore: hasMore,
  );
}

const _ownerId = 'owner-a';
const _firebaseUid = 'firebase-owner-a';
const _experimentId = 'study-a';
const _experimentVersion = 1;
const _protocolId = 'assessment-protocol';
const _protocolVersion = 'protocol-1';
const _cohort = 'intervention';
const _consentVersion = 7;
const _runId = 'assessment-run-shared-rollout';
const _sessionId = 'assessment-session-shared-rollout';
const _instrumentChecksum =
    '1111111111111111111111111111111111111111111111111111111111111111';
const _formChecksum =
    '2222222222222222222222222222222222222222222222222222222222222222';
final _consentAtUtc = DateTime.utc(2026, 8, 14, 8);
final _assignedAtUtc = DateTime.utc(2026, 8, 14, 8, 1);
final _startedAtUtc = DateTime.utc(2026, 8, 14, 9);
final _claimAtUtc = DateTime.utc(2026, 8, 14, 10);

const _catalog = ResearchProtocolModeCatalog(
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
