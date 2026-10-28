import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_session_proof_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_research_sync_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/research_session_proof.dart';
import 'package:vocab_learning_app/features/research/domain/research_participation_permit.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_research_sync_adapter.dart';
import 'package:vocab_learning_app/features/sync/domain/research_sync.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';

import '../../support/motivation_research_fixture.dart';
import '../../support/pair_purpose_fixture.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_atomic_start.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/application/pair_matching_source_composer.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_launch.dart';
import 'package:vocab_learning_app/features/learning/pair_matching/domain/pair_matching_plan.dart';

const _owner = 'owner:a';
const _uid = 'synthetic-proof-uid';
const _token = 'synthetic-proof-gate';
var _session = 'session:proof-source';
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
    _session = 'session:proof-source';
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

  Future<int> prepare(
    DriftResearchSessionProofRepository repository, {
    int limit = 10,
  }) => repository.prepareForOwner(
    ownerId: _owner,
    firebaseUid: _uid,
    ownerGateToken: _token,
    limit: limit,
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

  Future<MeasurementOpportunity> accepted({
    int index = 0,
    String? sessionId,
    Future<void> Function()? start,
  }) async {
    _session = sessionId ?? 'session:proof-source:$index';
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
      entryAttemptId:
          '11111111-1111-4111-8111-${(index + 1).toString().padLeft(12, '0')}',
      effectivePresentation: TodayExperiencePresentation.adventure,
    );
    await opportunities.recordPresented(_owner, opened.id);
    await (start?.call() ?? startLearning());
    // Current maintained API name for the actual accepted-session bind path.
    final bound = await opportunities.attachAcceptedSession(
      ownerId: _owner,
      opportunityId: opened.id,
      learningSessionId: _session,
      planId: 'plan:synthetic-proof',
      mode: start == null ? LessonMode.meaningQuiz : LessonMode.matching,
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

  Future<void> mutateEvent(String id, Map<String, Object?> values) async {
    await f.database.customStatement(
      'UPDATE events_v2 SET ${values.keys.map((key) => '$key = ?').join(', ')} WHERE event_id = ?',
      [...values.values, id],
    );
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

  test(
    'canonical completion prepares Completed before neutral completion event exists',
    () async {
      final opportunity = await accepted();
      f.now = f.now.add(const Duration(seconds: 1));
      await learning.finishSession(
        ownerId: _owner,
        sessionId: _session,
        endedAtUtc: f.now,
      );
      expect(
        (await opportunities.load(_owner, opportunity.id))!.completedEventId,
        isNull,
      );
      expect(await prepare(repository(composed)), 2);
      expect(
        (await rows(
          'research_session_proofs',
        )).map((row) => row['proof_revision']).toSet(),
        {1, 2},
      );
      expect(
        (await opportunities.load(_owner, opportunity.id))!.completedEventId,
        isNull,
      );
    },
  );

  for (final corruption in ['malformed payload', 'wrong session link']) {
    test('Started $corruption cannot supply source admission', () async {
      final opportunity = await accepted();
      final original = (await rows(
        'events_v2',
      )).singleWhere((row) => row['event_id'] == opportunity.startedEventId);
      await mutateEvent(
        opportunity.startedEventId!,
        corruption == 'malformed payload'
            ? {'payload_json': '{'}
            : {'aggregate_id': 'session:unrelated'},
      );
      expect(await prepare(repository(composed)), 0);
      await expectNoProofs();
      // Restore exact authentic source to establish a positive control.
      await mutateEvent(opportunity.startedEventId!, {
        'payload_json': original['payload_json'],
        'aggregate_id': original['aggregate_id'],
      });
      expect(await prepare(repository(composed)), 1);
    });
  }

  test(
    'linked event mutation after successful callback invalidates an unchanged compact proof',
    () async {
      final opportunity = await accepted();
      var calls = 0;
      expect(
        await prepare(
          repository((request) async {
            calls++;
            expect(await composed(request), isTrue);
            final event = (await rows('events_v2')).singleWhere(
              (row) => row['event_id'] == opportunity.startedEventId,
            );
            await mutateEvent(opportunity.startedEventId!, {
              'recorded_at_utc': (event['recorded_at_utc']! as int) + 1,
            });
            // This envelope field is outside the compact session proof.
            final after = ResearchSessionProof.fromCanonicalSnapshot(
              ownerId: _owner,
              permitId: 'permit:a',
              permitPayloadSha256: f.permit().payloadSha256,
              permitRevision: 1,
              measurementRunId: opportunity.measurementRunId,
              proofRevision: 1,
              session: (await rows('learning_sessions')).single,
            );
            expect(after.toJson(), request.payload);
            return true;
          }),
        ),
        0,
      );
      expect(calls, 1);
      await expectNoProofs();
    },
  );

  test(
    'canonical configuration change during approving callback invalidates capture',
    () async {
      await accepted();
      var calls = 0;
      expect(
        await prepare(
          repository((request) async {
            calls++;
            expect(await composed(request), isTrue);
            final config = SessionConfiguration.validated(
              schemaVersion: 1,
              policyVersion: sessionConfigurationPolicyVersion,
              ownerId: _owner,
              mode: LessonMode.meaningQuiz,
              itemCount: 2,
              direction: SessionDirection.forward,
              difficulty: SessionDifficulty.standard,
              hintBudget: 1,
              timing: const SessionTiming.timed(Duration(minutes: 2)),
              packIdentity: null,
              protocolId: 'standard',
              protocolVersion: '1',
              protocolLimitsIdentity: 'standard',
            );
            await f.database.customStatement(
              'UPDATE learning_sessions SET session_configuration_identity = ?, session_configuration_json = ? WHERE id = ?',
              [config.contentIdentity, config.stableSerialization, _session],
            );
            return true;
          }),
        ),
        0,
      );
      expect(calls, 1);
      await expectNoProofs();
    },
  );

  test(
    'actual Pair atomic learning start supplies an accepted proof',
    () async {
      const operation = 'source-integrity-pair';
      await accepted(
        sessionId: pairSessionId(_owner, operation),
        start: () => startPair(operation),
      );
      expect(await prepare(repository(composed)), 1);
      expect(requests, hasLength(1));
      final proof = ResearchSessionProof.decode(requests.single.payload);
      expect(proof.activityType, 'matching');
      expect(proof.pairStartOperation, isNotNull);
      expect(proof.pairOwnerLineage, hasLength(1));
      expect(await rows('answer_attempts'), isEmpty);
    },
  );

  test(
    'later malformed Pair checkpoint prevents deriving Started from valid initial',
    () async {
      const operation = 'source-integrity-pair';
      await accepted(
        sessionId: pairSessionId(_owner, operation),
        start: () => startPair(operation),
      );
      final initial = (await rows('events_v2')).singleWhere(
        (row) => row['event_type'] == 'LearningActivityCheckpoint',
      );
      // Deliberate post-capture disk corruption; never a valid terminal history.
      final corrupt = Map<String, Object?>.from(initial)
        ..['event_id'] = 'synthetic-corrupt-later'
        ..['idempotency_key'] = 'synthetic-corrupt-later'
        ..['payload_json'] = jsonEncode({
          'schemaVersion': 1,
          'activityType': 'matching',
          'sessionId': _session,
          'revision': 2,
          'state': <String, Object?>{},
        });
      await f.database.customStatement(
        'INSERT INTO events_v2 (${corrupt.keys.join(', ')}) VALUES (${List.filled(corrupt.length, '?').join(', ')})',
        corrupt.values.toList(),
      );
      expect(await prepare(repository(composed)), 0);
      await expectNoProofs();
      await f.database.customStatement(
        'DELETE FROM events_v2 WHERE event_id = ?',
        ['synthetic-corrupt-later'],
      );
      expect(await prepare(repository(composed)), 1);
    },
  );

  test(
    'replay substituted after genuine admission cannot produce learning proof',
    () async {
      final opportunity = await accepted();
      final original = (await rows(
        'events_v2',
      )).singleWhere((row) => row['event_id'] == opportunity.startedEventId);
      final replay = await seedSyntheticReplayPurpose(
        f.database,
        owner: _owner,
        at: f.now,
        appVersion: f.study.appVersion,
        buildId: f.study.buildId,
      );
      // Simulate a corrupted persisted binding, not a legitimate replay admission.
      // Keep the actual Started envelope linked to the substituted session.
      await f.database.customStatement(
        'UPDATE measurement_opportunities SET learning_session_id = ? WHERE id = ?',
        [replay, opportunity.id],
      );
      final payload = Map<String, Object?>.from(
        jsonDecode(original['payload_json']! as String) as Map,
      )..['mode'] = LessonMode.matching.id;
      await mutateEvent(opportunity.startedEventId!, {
        'aggregate_id': replay,
        'payload_json': jsonEncode(payload),
      });
      expect(await prepare(repository(composed)), 0);
      await expectNoProofs();
    },
  );

  test(
    'renewed permit defers new sibling and leaves original proof and ACK untouched',
    () async {
      final opportunity = await accepted();
      expect(await prepare(repository(composed)), 1);
      await f.database.customStatement(
        "UPDATE outbox_operations SET state = 'acknowledged', attempt_count = 2, acknowledged_at_utc_ms = ? WHERE entity_type = 'researchSessionProof'",
        [f.now.millisecondsSinceEpoch],
      );
      final proofBefore = await rows('research_session_proofs');
      final operationsBefore = await proofOperations();
      final prior = f.permit();
      final unsigned = ResearchParticipationPermit(
        id: prior.id,
        ownerId: prior.ownerId,
        participantClass: prior.participantClass,
        ageBandCode: prior.ageBandCode,
        assignmentId: prior.assignmentId,
        assignedTreatment: prior.assignedTreatment,
        consentReceiptId: prior.consentReceiptId,
        guardianPermissionReceiptRef: prior.guardianPermissionReceiptRef,
        learnerAssentReceiptRef: prior.learnerAssentReceiptRef,
        protocolId: prior.protocolId,
        protocolVersion: prior.protocolVersion,
        issuedAtUtc: prior.issuedAtUtc,
        expiresAtUtc: DateTime.utc(2026, 9, 9),
        issuerKeyId: prior.issuerKeyId,
        payloadSha256: '',
        signature: prior.signature,
        localRevision: 2,
        cloudRevision: 2,
        isDeleted: false,
      );
      final renewed = unsigned.copyWith(
        payloadSha256: sha256
            .convert(utf8.encode(unsigned.canonicalPayload()))
            .toString(),
      );
      await f.participation.importPermit(renewed);
      expect(
        (await rows('research_participation_permits')).single['local_revision'],
        2,
      );
      await finish(opportunity);
      expect(await prepare(repository(composed)), 0);
      expect(await rows('research_session_proofs'), proofBefore);
      expect(await proofOperations(), operationsBefore);
    },
  );

  test(
    'bounded candidate scan passes 50 ACKs and later failure preserves the prefix',
    () async {
      MeasurementOpportunity? last;
      for (var index = 0; index < 51; index++) {
        last = await accepted(index: index);
      }
      final repo = repository(composed);
      for (final limit in [0, 51]) {
        await expectLater(prepare(repo, limit: limit), throwsArgumentError);
      }
      await expectNoProofs();
      expect(await prepare(repo, limit: 50), 50);
      await f.database.customStatement(
        "UPDATE outbox_operations SET state = 'acknowledged', attempt_count = 2, acknowledged_at_utc_ms = ? WHERE entity_type = 'researchSessionProof'",
        [f.now.millisecondsSinceEpoch],
      );
      final prefix = await proofOperations();
      expect(prefix, hasLength(50));
      expect(await prepare(repo, limit: 1), 1);
      expect(await rows('research_session_proofs'), hasLength(51));
      for (final operation in prefix) {
        expect(
          (await proofOperations()).singleWhere(
            (row) => row['operation_id'] == operation['operation_id'],
          ),
          operation,
        );
      }
      final proofsBefore = await rows('research_session_proofs');
      final operationsBefore = await proofOperations();
      await finish(last!);
      await f.database.customStatement(
        "CREATE TEMP TRIGGER reject_later_proof BEFORE INSERT ON outbox_operations WHEN NEW.entity_type = 'researchSessionProof' BEGIN SELECT RAISE(ABORT, 'synthetic later proof failure'); END",
      );
      // The local bounded scan may revisit acknowledged phases before finding
      // this later completion. It must reach it within two finite cycles.
      Object? observedFailure;
      final maximumCalls = 2 * (proofsBefore.length + 1) + 2;
      for (var call = 0; call < maximumCalls; call++) {
        final beforeRequests = requests.length;
        try {
          expect(await prepare(repo, limit: 1), 0);
        } on Object catch (error) {
          observedFailure = error;
        }
        expect(requests.length - beforeRequests, lessThanOrEqualTo(1));
        expect(await rows('research_session_proofs'), proofsBefore);
        expect(await proofOperations(), operationsBefore);
        if (observedFailure != null) break;
      }
      expect(observedFailure, isNotNull);
      expect(
        observedFailure.toString(),
        contains('synthetic later proof failure'),
      );
    },
  );

  test(
    'different operation ID does not satisfy the exact proof upload intent',
    () async {
      await accepted();
      final repo = repository(composed);
      expect(await prepare(repo), 1);
      final originalProofs = await rows('research_session_proofs');
      final exact = (await proofOperations()).single;
      // Persisted malformed intent is deliberately not a valid delivery receipt.
      // Entity/type/kind agree, but its operation identity does not.
      await f.database.customStatement(
        "UPDATE outbox_operations SET operation_id = ?, state = 'acknowledged', attempt_count = 7, acknowledged_at_utc_ms = ? WHERE operation_id = ?",
        [
          'synthetic-wrong-proof-intent',
          f.now.millisecondsSinceEpoch,
          exact['operation_id'],
        ],
      );
      final malformed = (await proofOperations()).single;
      expect(await prepare(repo), 1);
      expect(await rows('research_session_proofs'), originalProofs);
      final repaired = await proofOperations();
      expect(repaired, hasLength(2));
      expect(
        repaired.singleWhere(
          (row) => row['operation_id'] == exact['operation_id'],
        ),
        exact,
      );
      expect(
        repaired.singleWhere(
          (row) => row['operation_id'] == malformed['operation_id'],
        ),
        malformed,
      );
      expect(await prepare(repo), 0);
      expect(await proofOperations(), repaired);
    },
  );

  test(
    'assignment quarantine after composed approval invalidates source admission',
    () async {
      await accepted();
      final assignment = (await rows('experiment_assignments')).single;
      var approvals = 0;
      expect(
        await prepare(
          repository((request) async {
            final approved = await composed(request);
            expect(approved, isTrue);
            approvals++;
            await f.database
                .into(f.database.syncConflicts)
                .insert(
                  SyncConflictsCompanion.insert(
                    id: 'synthetic:proof-assignment-quarantine',
                    ownerId: _owner,
                    entityType: 'experimentAssignment',
                    entityId: assignment['id']! as String,
                    localRevision: 1,
                    cloudRevision: 1,
                    resolutionPolicy: 'immutableAssignment',
                    outcome: 'quarantined',
                    localSnapshotJson: const Value(null),
                    resolvedAtUtcMs: f.now.millisecondsSinceEpoch,
                  ),
                );
            // Return the genuinely obtained approval after its local source
            // authority changed; the repository must recheck this dependency.
            return approved;
          }),
        ),
        0,
      );
      expect(approvals, 1);
      expect(requests, hasLength(1));
      final conflict = (await rows('sync_conflicts')).single;
      expect(conflict['outcome'], 'quarantined');
      expect(conflict['local_snapshot_json'], isNull);
      await expectNoProofs();
      expect(await rows('sync_checkpoints'), isEmpty);
    },
  );

  for (final throwAt in [1, 2]) {
    test(
      'unexpected source clock StateError at read $throwAt propagates',
      () async {
        await accepted();
        final failure = StateError('synthetic proof clock failure');
        var clockReads = 0;
        final repo = DriftResearchSessionProofRepository(
          f.database,
          rollout: _rollout,
          authorizeCandidate: composed,
          nowUtc: () {
            clockReads++;
            if (clockReads == throwAt) throw failure;
            return f.now;
          },
        );
        await expectLater(prepare(repo), throwsA(same(failure)));
        expect(clockReads, throwAt);
        expect(requests, hasLength(throwAt - 1));
        await expectNoProofs();
        expect(await rows('sync_checkpoints'), isEmpty);
      },
    );
  }

  for (final malformedClock in ['non-UTC', 'negative UTC']) {
    test(
      'malformed source clock $malformedClock denies without throwing',
      () async {
        await accepted();
        final repo = DriftResearchSessionProofRepository(
          f.database,
          rollout: _rollout,
          authorizeCandidate: composed,
          nowUtc: () => malformedClock == 'non-UTC'
              ? DateTime.fromMillisecondsSinceEpoch(
                  f.now.millisecondsSinceEpoch,
                )
              : DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
        );
        expect(await prepare(repo), 0);
        expect(requests, isEmpty);
        await expectNoProofs();
        expect(await rows('sync_checkpoints'), isEmpty);
        // The identical accepted source works with a well-formed current clock.
        expect(await prepare(repository(composed)), 1);
      },
    );
  }

  test(
    'denied proof prefix advances in bounded memory across repository recreation',
    () async {
      await accepted(index: 0);
      await accepted(index: 1);
      final candidates = await rows('measurement_opportunities');
      final deniedSession = candidates.first['learning_session_id'];
      final validSession = candidates.last['learning_session_id'];
      final sourceBefore = await rows('events_v2');
      final consentBefore = await rows('research_consents');
      var calls = 0;
      Future<bool> admit(ResearchSyncRequest request) async {
        calls++;
        if (request.payload['learningSessionId'] == deniedSession) return false;
        return composed(request);
      }

      var inserted = 0;
      for (var run = 0; run < 3 && inserted == 0; run++) {
        final before = calls;
        inserted += await prepare(repository(admit), limit: 1);
        expect(calls - before, lessThanOrEqualTo(1));
        if (run == 0) expect(await rows('sync_checkpoints'), isEmpty);
      }
      expect(inserted, 1);
      final proofs = await rows('research_session_proofs');
      expect(proofs, hasLength(1));
      expect(proofs.single['learning_session_id'], validSession);
      expect(await rows('events_v2'), sourceBefore);
      expect(await rows('research_consents'), consentBefore);
    },
  );

  test(
    'denied enqueue prefix reaches a later authorized opportunity after adapter recreation',
    () async {
      await accepted(index: 0);
      await accepted(index: 1);
      final candidates = await rows('measurement_opportunities');
      final validId = candidates.last['id'];
      final before = await rows('measurement_opportunities');
      Future<bool> admit(ResearchSyncRequest request) async =>
          request.collection == SyncCollection.measurementOpportunities &&
          request.entityId == validId &&
          await authority.authorize(request);
      var inserted = 0;
      for (var run = 0; run < 3 && inserted == 0; run++) {
        final recreated = DriftResearchSyncAdapter(
          f.database,
          rollout: _rollout,
          authorizer: admit,
          researchNowUtc: () => f.now,
        );
        inserted += await recreated.enqueue(
          ownerId: _owner,
          firebaseUid: _uid,
          ownerGateToken: _token,
          nowUtc: f.now,
          limit: 1,
        );
      }
      expect(inserted, 1);
      final operations = (await rows('outbox_operations'))
          .where((row) => row['entity_type'] == 'measurementOpportunity')
          .toList();
      expect(operations, hasLength(1));
      expect(operations.single['entity_id'], validId);
      expect(await rows('measurement_opportunities'), before);
      expect(await rows('sync_checkpoints'), isEmpty);
      await expectNoProofs();
    },
  );

  test(
    'all-denied proof scans wrap finitely without any persisted scheduling write',
    () async {
      for (var index = 0; index < 3; index++) {
        await accepted(index: index);
      }
      final before = {
        for (final table in [
          'research_consents',
          'events_v2',
          'outbox_operations',
          'research_session_proofs',
          'sync_checkpoints',
        ])
          table: await rows(table),
      };
      final seen = <String>[];
      for (var call = 0; call < 4; call++) {
        expect(
          await prepare(
            repository((request) async {
              seen.add(request.entityId);
              return false;
            }),
            limit: 1,
          ),
          0,
        );
        expect(seen, hasLength(call + 1));
      }
      expect(seen.take(3).toSet(), hasLength(3));
      expect(seen.last, seen.first);
      for (final entry in before.entries) {
        expect(await rows(entry.key), entry.value);
      }
    },
  );

  const localPreparation = 'local:research-session-proof-preparation:v1';

  Future<List<Map<String, Object?>>> preparationHints() async => [
    for (final row in await rows('sync_checkpoints'))
      if (row['owner_id'] == _owner &&
          row['collection_name'] == localPreparation)
        row,
  ];

  test(
    'local proof cursor survives repository restart and isolates pull cursors',
    () async {
      for (var index = 0; index < 3; index++) {
        await accepted(index: index);
      }
      await f.database
          .into(f.database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner:other-proof',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      for (final entry in [
        (_owner, 'research_session_proofs', 'synthetic-server-pull-cursor'),
        ('owner:other-proof', localPreparation, 'synthetic-other-owner-hint'),
      ]) {
        await f.database
            .into(f.database.syncCheckpoints)
            .insert(
              SyncCheckpointsCompanion.insert(
                id: 'synthetic:${entry.$1}:${entry.$2}',
                ownerId: entry.$1,
                collectionName: entry.$2,
                serverCursor: Value(entry.$3),
                lastSuccessAtUtcMs: Value(
                  entry.$2 == localPreparation ? null : 7,
                ),
              ),
            );
      }
      final unrelated = await rows('sync_checkpoints');
      final seen = <String>{};
      List<Map<String, Object?>>? acknowledged;
      for (var call = 0; call < 3; call++) {
        final beforeRequests = requests.length;
        // No in-memory cursor state survives this reconstruction.
        expect(await prepare(repository(composed), limit: 1), 1);
        expect(requests.length - beforeRequests, 1);
        expect(seen.add(requests.last.entityId), isTrue);
        final hint = (await preparationHints()).single;
        expect(hint['server_cursor'], isA<String>());
        expect(jsonDecode(hint['server_cursor']! as String), isA<Map>());
        expect(hint['last_success_at_utc_ms'], isNull);
        if (call == 0) {
          await f.database.customStatement(
            "UPDATE outbox_operations SET state = 'acknowledged', attempt_count = 3, acknowledged_at_utc_ms = ? WHERE entity_type = 'researchSessionProof'",
            [f.now.millisecondsSinceEpoch],
          );
          acknowledged = await proofOperations();
        }
        for (final existing in unrelated) {
          expect(
            (await rows(
              'sync_checkpoints',
            )).singleWhere((row) => row['id'] == existing['id']),
            existing,
          );
        }
      }
      expect(await rows('research_session_proofs'), hasLength(3));
      final original = acknowledged!.single;
      expect(
        (await proofOperations()).singleWhere(
          (row) => row['operation_id'] == original['operation_id'],
        ),
        original,
      );
      final beforeRequests = requests.length;
      expect(await prepare(repository(composed), limit: 3), 0);
      final wrapped = requests
          .skip(beforeRequests)
          .map((request) => request.entityId)
          .toList();
      expect(wrapped, hasLength(3));
      expect(wrapped.toSet(), hasLength(3));
      expect(wrapped.toSet(), seen);
    },
  );

  test(
    'local proof cursor wraps to later completion and newly inserted lower key',
    () async {
      final original = await accepted();
      expect(await prepare(repository(composed), limit: 1), 1);
      final started = (await rows('research_session_proofs')).single;
      final originalOperation = (await proofOperations()).single;
      await finish(original);
      var inserted = 0;
      for (var call = 0; call < 6 && inserted == 0; call++) {
        final beforeRequests = requests.length;
        inserted += await prepare(repository(composed), limit: 1);
        expect(requests.length - beforeRequests, lessThanOrEqualTo(1));
      }
      expect(inserted, 1);
      expect(await rows('research_session_proofs'), hasLength(2));

      int? lowerIndex;
      String? lowerId;
      for (var index = 1; index <= 4096; index++) {
        final entry =
            '11111111-1111-4111-8111-${(index + 1).toString().padLeft(12, '0')}';
        final id =
            'opportunity:${sha256.convert(utf8.encode(jsonEncode([_owner, original.measurementRunId, original.permitId, entry])))}';
        if (id.compareTo(original.id) < 0) {
          lowerIndex = index;
          lowerId = id;
          break;
        }
      }
      expect(lowerIndex, isNotNull);
      final lower = await accepted(index: lowerIndex!);
      expect(lower.id, lowerId);
      expect(lower.id.compareTo(original.id), lessThan(0));
      inserted = 0;
      for (var call = 0; call < 8 && inserted == 0; call++) {
        final beforeRequests = requests.length;
        inserted += await prepare(repository(composed), limit: 1);
        expect(requests.length - beforeRequests, lessThanOrEqualTo(1));
      }
      expect(inserted, 1);
      expect(await rows('research_session_proofs'), hasLength(3));
      expect(
        (await rows(
          'research_session_proofs',
        )).singleWhere((row) => row['id'] == started['id']),
        started,
      );
      expect(
        (await proofOperations()).singleWhere(
          (row) => row['operation_id'] == originalOperation['operation_id'],
        ),
        originalOperation,
      );
    },
  );

  test(
    'malformed local proof cursor resets only after genuine admission',
    () async {
      await accepted();
      expect(await prepare(repository(composed), limit: 1), 1);
      final hint = (await preparationHints()).single;
      final proofBefore = await rows('research_session_proofs');
      final operationsBefore = await proofOperations();
      for (final malformed in ['{', '"not-a-cursor"', '{"unexpected":true}']) {
        await f.database.customStatement(
          'UPDATE sync_checkpoints SET server_cursor = ? WHERE id = ?',
          [malformed, hint['id']],
        );
        final malformedRows = await rows('sync_checkpoints');
        var deniedCalls = 0;
        expect(
          await prepare(
            repository((_) async {
              deniedCalls++;
              return false;
            }),
            limit: 1,
          ),
          0,
        );
        expect(deniedCalls, 1);
        expect(await rows('sync_checkpoints'), malformedRows);
        final beforeRequests = requests.length;
        expect(await prepare(repository(composed), limit: 1), 0);
        expect(requests.length - beforeRequests, 1);
        final repaired = (await preparationHints()).single;
        expect(repaired['server_cursor'], isNot(malformed));
        expect(jsonDecode(repaired['server_cursor']! as String), isA<Map>());
        expect(repaired['last_success_at_utc_ms'], isNull);
        expect(await rows('research_session_proofs'), proofBefore);
        expect(await proofOperations(), operationsBefore);
      }
    },
  );

  for (final reason in ['off', 'null authority', 'nonparticipant', 'denied']) {
    test('local proof cursor is absent for $reason preparation', () async {
      if (reason == 'nonparticipant') {
        await startLearning();
      } else {
        await accepted();
      }
      var calls = 0;
      final repo = repository(
        reason == 'null authority'
            ? null
            : (_) async {
                calls++;
                return reason != 'denied';
              },
        rollout: reason == 'off'
            ? const ResearchMeasurementSyncRollout.off()
            : _rollout,
      );
      expect(await prepare(repo, limit: 1), 0);
      expect(calls, reason == 'denied' ? 1 : 0);
      await expectNoProofs();
      expect(await rows('sync_checkpoints'), isEmpty);
    });
  }

  test(
    'local proof cursor storage failure rolls back proof and exact outbox',
    () async {
      await accepted();
      final checkpointsBefore = await rows('sync_checkpoints');
      await f.database.customStatement(
        "CREATE TEMP TRIGGER reject_proof_hint BEFORE INSERT ON sync_checkpoints WHEN NEW.collection_name = 'local:research-session-proof-preparation:v1' BEGIN SELECT RAISE(ABORT, 'synthetic proof hint failure'); END",
      );
      await expectLater(
        prepare(repository(composed), limit: 1),
        throwsA(
          predicate<Object>(
            (error) =>
                error.toString().contains('synthetic proof hint failure'),
          ),
        ),
      );
      expect(requests, hasLength(1));
      await expectNoProofs();
      expect(await rows('sync_checkpoints'), checkpointsBefore);
      await f.database.customStatement('DROP TRIGGER reject_proof_hint');
      expect(await prepare(repository(composed), limit: 1), 1);
      expect(await rows('research_session_proofs'), hasLength(1));
      expect(await proofOperations(), hasLength(1));
      expect(await preparationHints(), hasLength(1));
    },
  );
}
