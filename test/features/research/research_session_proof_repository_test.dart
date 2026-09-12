import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_session_proof_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_session_proof.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_research_sync_adapter.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';

import '../../support/motivation_research_fixture.dart';

const _owner = 'owner:a';
const _uid = 'synthetic-proof-uid';
const _token = 'synthetic-proof-gate';
const _session = 'session:proof-source';
const _rollout = ResearchMeasurementSyncRollout.localEmulatorV1(
  deployedRulesRevision: researchMeasurementV1RulesRevision,
);

void main() {
  late MotivationResearchFixture f;
  late DriftLearningRepository learning;
  late DriftMeasurementOpportunityRepository opportunities;
  late DriftResearchSyncAuthorizer authority;
  late DriftResearchSyncAdapter adapter;
  final requests = <ResearchSyncRequest>[];

  setUp(() async {
    f = MotivationResearchFixture();
    await f.initialize(enroll: false);
    learning = DriftLearningRepository(f.database);
    opportunities = DriftMeasurementOpportunityRepository(
      f.database,
      measurements: f.measurements,
      nowUtc: () => f.now,
    );
    await (f.database.update(f.database.localOwners)
          ..where((row) => row.id.equals(_owner)))
        .write(const LocalOwnersCompanion(firebaseUid: Value(_uid)));
    expect(
      await DriftOwnerOperationGate(f.database).tryAcquire(
        token: _token,
        nowUtc: f.now,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );
    authority = DriftResearchSyncAuthorizer(
      database: f.database,
      study: f.study,
      validator: f.participation.validator,
      nowUtc: () => f.now,
    );
    adapter = DriftResearchSyncAdapter(
      f.database,
      rollout: _rollout,
      authorizer: authority.authorize,
      researchNowUtc: () => f.now,
    );
    requests.clear();
  });
  tearDown(() => f.database.close());

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row
        in await f.database
            .customSelect('SELECT * FROM $table ORDER BY 1')
            .get())
      row.data,
  ];

  Future<List<Map<String, Object?>>> proofOperations() async => [
    for (final row
        in await f.database
            .customSelect(
              "SELECT * FROM outbox_operations WHERE entity_type = 'researchSessionProof' ORDER BY operation_id",
            )
            .get())
      row.data,
  ];

  Future<void> expectNoProofs() async {
    expect(await rows('research_session_proofs'), isEmpty);
    expect(await proofOperations(), isEmpty);
  }

  Future<Map<String, Object?>> learningSnapshot() async => {
    for (final table in [
      'learning_sessions',
      'answer_attempts',
      'srs_states',
      'reward_transactions',
      'events_v2',
    ])
      table: await rows(table),
  };

  // This is the approved constructor composition through the ACTUAL adapter
  // policy, including latest-consent pre/post checks and the real authorizer.
  // Its signature/receipt fixture is synthetic; it is not an external issuer.
  Future<bool> composed(ResearchSyncRequest request) async {
    requests.add(request);
    final proof = ResearchSessionProof.decode(request.payload);
    final payload = proof.toJson();
    final at = payload['proofRevision'] == 1
        ? payload['startedAtUtcMs']! as int
        : payload['endedAtUtcMs']! as int;
    return adapter.allowed(
      ResearchSyncSnapshot(
        request.collection,
        request.ownerId,
        request.entityId,
        1,
        0,
        DateTime.fromMillisecondsSinceEpoch(at, isUtc: true),
        payload,
        phase: ResearchSyncPhase.enqueue,
      ),
      request.firebaseUid,
      request.ownerGateToken!,
      request.evaluatedAtUtc,
      ResearchSyncPhase.enqueue,
    );
  }

  DriftResearchSessionProofRepository repository(
    ResearchSyncAuthorizer? authorizeCandidate, {
    ResearchMeasurementSyncRollout rollout = _rollout,
  }) => DriftResearchSessionProofRepository(
    f.database,
    rollout: rollout,
    authorizeCandidate: authorizeCandidate,
    nowUtc: () => f.now,
  );

  Future<int> prepare(DriftResearchSessionProofRepository repository) =>
      repository.prepareForOwner(
        ownerId: _owner,
        firebaseUid: _uid,
        ownerGateToken: _token,
        limit: 10,
      );

  Future<void> startLearning() => learning.startSession(
    LearningSessionDraft(
      id: _session,
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

  Future<MeasurementOpportunity> accepted() async {
    await f.participation.importPermit(f.permit());
    final run = await f.measurements.start(
      const MotivationMeasurementStart(ownerId: _owner, permitId: 'permit:a'),
    );
    // Required research baseline is not a learning answer attempt.
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
      entryAttemptId: '11111111-1111-4111-8111-111111111111',
      effectivePresentation: TodayExperiencePresentation.adventure,
    );
    await opportunities.recordPresented(_owner, opened.id);
    await startLearning();
    // Current maintained API name for the actual accepted-session bind path.
    final bound = await opportunities.attachAcceptedSession(
      ownerId: _owner,
      opportunityId: opened.id,
      learningSessionId: _session,
      planId: 'plan:synthetic-proof',
      mode: LessonMode.meaningQuiz,
    );
    expect(bound.learningSessionId, _session);
    expect(bound.startedEventId, isNotNull);
    expect(await rows('answer_attempts'), isEmpty);
    return bound;
  }

  Future<void> finish(MeasurementOpportunity opportunity) async {
    f.now = f.now.add(const Duration(seconds: 1));
    await learning.finishSession(
      ownerId: _owner,
      sessionId: _session,
      endedAtUtc: f.now,
    );
    await opportunities.completeAcceptedSession(_owner, opportunity.id);
  }

  Future<void> newerWithdrawal() async {
    f.now = f.now.add(const Duration(seconds: 1));
    await DriftResearchConsentRepository(
      f.database,
    ).decide(ownerId: _owner, version: 2, accepted: false, decidedAtUtc: f.now);
    final old = await (f.database.select(
      f.database.researchConsents,
    )..where((row) => row.consentVersion.equals(1))).getSingle();
    expect(old.consentState, 'accepted');
  }

  test(
    'accepted canonical source prepares Started before its first answer',
    () async {
      final opportunity = await accepted();
      final before = await learningSnapshot();
      expect(await prepare(repository(composed)), 1);
      final proof = (await rows('research_session_proofs')).single;
      expect(
        proof['id'],
        ResearchSessionProof.identityFor(
          ownerId: _owner,
          permitId: 'permit:a',
          measurementRunId: opportunity.measurementRunId,
          learningSessionId: _session,
          proofRevision: 1,
        ),
      );
      expect(proof['proof_revision'], 1);
      expect(proof['session_state'], 'active');
      expect(proof['ended_at_utc_ms'], isNull);
      expect(proof['permit_payload_sha256'], f.permit().payloadSha256);
      expect(proof['permit_revision'], 1);
      expect(requests, hasLength(1));
      expect(requests.single.phase, ResearchSyncPhase.enqueue);
      final operation = (await proofOperations()).single;
      expect(
        operation['operation_id'],
        ResearchSyncContract.operationIdFor(
          collection: requests.single.collection,
          entityId: requests.single.entityId,
          payload: requests.single.payload,
          revision: 1,
        ),
      );
      expect(operation['entity_id'], proof['id']);
      expect(operation['attempt_count'], 0);
      expect(operation['state'], 'pending');
      expect(await learningSnapshot(), before);
    },
  );

  test('completed zero-answer source prepares two immutable phases', () async {
    final opportunity = await accepted();
    await finish(opportunity);
    final before = await learningSnapshot();
    expect(await prepare(repository(composed)), 2);
    final proofs = await rows('research_session_proofs');
    expect(proofs, hasLength(2));
    final started = proofs.singleWhere((row) => row['proof_revision'] == 1);
    final completed = proofs.singleWhere((row) => row['proof_revision'] == 2);
    expect(started['session_state'], 'active');
    expect(started['ended_at_utc_ms'], isNull);
    expect(completed['session_state'], 'completed');
    expect(completed['ended_at_utc_ms'], f.now.millisecondsSinceEpoch);
    expect(started['started_at_utc_ms'], completed['started_at_utc_ms']);
    expect(started['id'], isNot(completed['id']));
    expect(await proofOperations(), hasLength(2));
    expect(requests, hasLength(2));
    expect(
      ResearchSessionProof.decode(
        requests.first.payload,
      ).hasSameStartCore(ResearchSessionProof.decode(requests.last.payload)),
      isTrue,
    );
    expect(await rows('answer_attempts'), isEmpty);
    expect(await learningSnapshot(), before);
  });

  test('off rollout never invokes an approving candidate callback', () async {
    await accepted();
    var calls = 0;
    expect(
      await prepare(
        repository((_) async {
          calls++;
          return true;
        }, rollout: const ResearchMeasurementSyncRollout.off()),
      ),
      0,
    );
    expect(calls, 0);
    await expectNoProofs();
  });

  test('missing original authority remains null and creates nothing', () async {
    await accepted();
    // Deliberately pass null, not a wrapper around a missing authorizer.
    expect(await prepare(repository(null)), 0);
    await expectNoProofs();
  });

  test(
    'ordinary nonparticipant session does not become a proof candidate',
    () async {
      await startLearning();
      final before = await learningSnapshot();
      final researchBefore = {
        for (final table in [
          'research_consents',
          'research_participation_permits',
          'motivation_measurement_runs',
          'motivation_responses',
          'measurement_opportunities',
        ])
          table: await rows(table),
      };
      var calls = 0;
      expect(
        await prepare(
          repository((_) async {
            calls++;
            return true;
          }),
        ),
        0,
      );
      expect(calls, 0);
      await expectNoProofs();
      expect(await rows('outbox_operations'), isEmpty);
      expect(await learningSnapshot(), before);
      for (final entry in researchBefore.entries) {
        expect(await rows(entry.key), entry.value);
      }
    },
  );

  test('denied admission observes no provisional proof or outbox', () async {
    await accepted();
    final observedProofs = <Object?>[];
    final observedOperations = <Object?>[];
    var calls = 0;
    expect(
      await prepare(
        repository((_) async {
          calls++;
          observedProofs.add(await rows('research_session_proofs'));
          observedOperations.add(await proofOperations());
          return false;
        }),
      ),
      0,
    );
    expect(calls, 1);
    expect(observedProofs, everyElement(isEmpty));
    expect(observedOperations, everyElement(isEmpty));
    await expectNoProofs();
  });

  test('outbox insert failure atomically rolls back the new proof', () async {
    await accepted();
    final before = await learningSnapshot();
    await f.database.customStatement(
      "CREATE TEMP TRIGGER reject_proof_outbox BEFORE INSERT ON outbox_operations WHEN NEW.entity_type = 'researchSessionProof' BEGIN SELECT RAISE(ABORT, 'synthetic proof outbox failure'); END",
    );
    await expectLater(prepare(repository(composed)), throwsA(anything));
    expect(requests, hasLength(1));
    await expectNoProofs();
    expect(await learningSnapshot(), before);
  });

  test(
    'repeat preparation and Completed preserve Started acknowledgement metadata',
    () async {
      final opportunity = await accepted();
      expect(await prepare(repository(composed)), 1);
      final original = (await rows('research_session_proofs')).single;
      final operation = (await proofOperations()).single;
      // Synthetic persisted delivery state, not a claim of server acceptance.
      await f.database.customStatement(
        'UPDATE research_session_proofs SET cloud_revision = 1, last_acknowledged_at_utc_ms = ? WHERE id = ?',
        [f.now.millisecondsSinceEpoch, original['id']],
      );
      await f.database.customStatement(
        "UPDATE outbox_operations SET state = 'acknowledged', attempt_count = 2, last_attempt_at_utc_ms = ?, acknowledged_at_utc_ms = ? WHERE operation_id = ?",
        [
          f.now.millisecondsSinceEpoch,
          f.now.millisecondsSinceEpoch,
          operation['operation_id'],
        ],
      );
      final acknowledged = (await rows('research_session_proofs')).single;
      final acknowledgedOperation = (await proofOperations()).single;
      expect(await prepare(repository(composed)), 0);
      expect((await rows('research_session_proofs')).single, acknowledged);
      expect((await proofOperations()).single, acknowledgedOperation);
      await finish(opportunity);
      expect(await prepare(repository(composed)), 1);
      expect(
        (await rows(
          'research_session_proofs',
        )).singleWhere((row) => row['id'] == original['id']),
        acknowledged,
      );
      expect(
        (await proofOperations()).singleWhere(
          (row) => row['operation_id'] == operation['operation_id'],
        ),
        acknowledgedOperation,
      );
      expect(await rows('research_session_proofs'), hasLength(2));
      expect(await proofOperations(), hasLength(2));
    },
  );

  test(
    'owner deactivation during candidate await prevents atomic insertion',
    () async {
      await accepted();
      var calls = 0;
      expect(
        await prepare(
          repository((_) async {
            calls++;
            await (f.database.update(f.database.localOwners)
                  ..where((row) => row.id.equals(_owner)))
                .write(const LocalOwnersCompanion(isActive: Value(false)));
            return true; // Synthetic callback isolates the repository's own fence.
          }),
        ),
        0,
      );
      expect(calls, 1);
      await expectNoProofs();
    },
  );

  test(
    'time-only gate expiry during await rejects unchanged source rows',
    () async {
      await accepted();
      final before = await learningSnapshot();
      var calls = 0;
      expect(
        await prepare(
          repository((_) async {
            calls++;
            await Future<void>.value();
            f.now = f.now.add(const Duration(minutes: 6));
            return true; // A captured enqueue time would incorrectly keep this valid.
          }),
        ),
        0,
      );
      expect(calls, 1);
      await expectNoProofs();
      expect(await learningSnapshot(), before);
    },
  );

  test(
    'adapter composition denies newer withdrawn consent despite accepted study version',
    () async {
      await accepted();
      final session = (await rows('learning_sessions')).single;
      final opportunity = (await rows('measurement_opportunities')).single;
      final proof = ResearchSessionProof.fromCanonicalSnapshot(
        ownerId: _owner,
        permitId: f.permit().id,
        permitPayloadSha256: f.permit().payloadSha256,
        permitRevision: f.permit().localRevision,
        measurementRunId: opportunity['measurement_run_id']! as String,
        proofRevision: 1,
        session: session,
      );
      final collection = ResearchSyncContract.collections.singleWhere(
        (collection) => collection.wireName == 'research_session_proofs',
      );
      final request = ResearchSyncRequest(
        phase: ResearchSyncPhase.enqueue,
        ownerId: _owner,
        firebaseUid: _uid,
        collection: collection,
        entityId: proof.toJson()['id']! as String,
        payload: proof.toJson(),
        evaluatedAtUtc: f.now,
        ownerGateToken: _token,
      );
      // Positive control establishes this exact missing-row candidate is valid.
      expect(await composed(request), isTrue);
      await expectNoProofs();
      await newerWithdrawal();
      expect(await composed(request), isFalse);
      expect(await prepare(repository(composed)), 0);
      await expectNoProofs();
    },
  );

  test(
    'adapter postflight rejects newer consent withdrawal during receipt await',
    () async {
      await accepted();
      var changedDuringReceipt = false;
      f.authority.onRead = () async {
        if (changedDuringReceipt) return;
        changedDuringReceipt = true;
        await newerWithdrawal();
      };
      expect(await prepare(repository(composed)), 0);
      expect(changedDuringReceipt, isTrue);
      expect(requests, hasLength(1));
      await expectNoProofs();
      expect(
        (await rows('motivation_measurement_runs')).single['state'],
        'started',
      );
      // The independent StageA denial remains durable; absence is NOT expected.
      final denial = (await rows('outbox_operations')).single;
      expect(denial['entity_type'], 'researchWithdrawal');
      expect(denial['attempt_count'], 0);
    },
  );
}
