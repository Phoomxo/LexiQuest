import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_event_store.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_eligibility_policy.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/srs_operation_identity.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore store;
  final now = DateTime.utc(2026, 7, 30, 10);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    await _seedVocabulary(database);
  });

  tearDown(() => database.close());

  test('sync store forwards the identical evidence policy pair', () {
    expect(
      store.projections.evidenceDecisions.rolloutModeProvider,
      isA<FixedEvidencePolicyRolloutModeProvider>().having(
        (provider) => provider.mode,
        'mode',
        EvidencePolicyRolloutMode.legacy,
      ),
    );
    final policy = EvidenceEligibilityPolicySet();
    final rollout = FixedEvidencePolicyRolloutModeProvider.legacy();

    final injected = DriftSyncStore(
      database,
      evidencePolicy: policy,
      rolloutModeProvider: rollout,
    );

    expect(
      identical(injected.projections.evidenceDecisions.evidencePolicy, policy),
      isTrue,
    );
    expect(
      identical(
        injected.projections.evidenceDecisions.rolloutModeProvider,
        rollout,
      ),
      isTrue,
    );
  });

  test('attempt outbox reconstructs an immutable cloud mutation', () async {
    final learning = DriftLearningRepository(database);
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-1',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: now,
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
        evidenceContext: _frozenV13LegacyEvidence(),
      ),
    );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'attempt-claim-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );

    final claim = (await store.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-1',
      ownerGateToken: 'attempt-claim-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
      // Phase 0 W12-13: recordAnswer also enqueues srsState outbox.
    )).firstWhere((c) => c.mutation.collection == SyncCollection.attempts);

    expect(claim.mutation.collection, SyncCollection.attempts);
    expect(claim.mutation.localRevision, 1);
    expect(claim.mutation.baseRevision, 0);
    expect(claim.mutation.payload['wordId'], 'word-1');
    expect(claim.mutation.payload['isCorrect'], isTrue);
    expect(claim.mutation.payloadVersion, 1);
    expect(claim.mutation.payload, isNot(contains('evidenceContext')));
  });

  test(
    'attempt payload v2 preserves the complete declared evidence context',
    () async {
      final context = _declaredEvidence();
      await _insertAttemptForSync(
        database,
        id: 'attempt-v2',
        sessionId: 'session-v2',
        occurredAt: now,
        evidenceContext: context,
      );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'attempt-v2-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final v2Store = DriftSyncStore(
        database,
        payloadRollout: const SyncPayloadRollout.answerAttemptV2(),
      );

      final claim = (await v2Store.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'attempt-v2-lease',
        ownerGateToken: 'attempt-v2-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      )).single;

      expect(claim.mutation.payloadVersion, 2);
      expect(
        claim.mutation.payload['evidenceClass'],
        context.evidenceClass.name,
      );
      expect(claim.mutation.payload['evidenceContext'], context.toJson());
    },
  );

  test('payload v1 refuses to down-convert declared evidence', () async {
    await _insertAttemptForSync(
      database,
      id: 'attempt-declared-v1',
      sessionId: 'session-declared-v1',
      occurredAt: now,
      evidenceContext: _declaredEvidence(),
    );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'attempt-declared-v1-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );

    await expectLater(
      store.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'attempt-declared-v1-lease',
        ownerGateToken: 'attempt-declared-v1-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      ),
      throwsA(isA<InvalidSyncPayloadFailure>()),
    );
  });

  test(
    'pulled attempt is set-union idempotent and rebuilds projections',
    () async {
      final entity = SyncEntity(
        collection: SyncCollection.attempts,
        entityId: 'attempt-remote',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now.add(const Duration(seconds: 1)),
        payload: <String, Object?>{
          'sessionId': 'session-remote',
          'wordId': 'word-1',
          'promptMode': 'meaningChoice',
          'isCorrect': true,
          'responseTimeMs': 300,
          'attemptNumber': 1,
          'occurredAtUtcMs': now.millisecondsSinceEpoch,
          'providerProvenance': null,
        },
      );
      final page = PullPage(
        changes: [entity],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
          documentId: entity.entityId,
        ),
        hasMore: false,
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: page,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: page,
      );

      final attempts = await database.select(database.answerAttempts).get();
      expect(attempts, hasLength(1));
      final evidence = EvidenceContext.fromJson(
        (jsonDecode(attempts.single.evidenceContextJson) as Map)
            .cast<String, Object?>(),
      );
      expect(
        attempts.single.evidenceClass,
        EvidenceClass.independentRecall.name,
      );
      expect(
        evidence.toJson(),
        EvidenceContext.legacyCompatibility(
          evidenceClass: EvidenceClass.independentRecall,
          skillId: 'legacy-unspecified',
          hintLevel: 0,
          contentRevision: 'legacy-unknown',
          engagementAllowed: true,
        ).toJson(),
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
    },
  );

  test(
    'pulled attempt payload v2 preserves declared evidence exactly',
    () async {
      final context = _declaredEvidence();
      final v2Store = DriftSyncStore(
        database,
        rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider(
          EvidencePolicyRolloutMode.shadow,
        ),
      );
      final entity = _attemptEntity(
        id: 'attempt-remote-v2',
        sessionId: 'session-remote-v2',
        occurredAt: now,
        payloadVersion: 2,
        evidenceContext: context,
      );

      await v2Store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(entity),
      );
      await v2Store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(_laterServerReplay(entity)),
      );

      final attempt = await database
          .select(database.answerAttempts)
          .getSingle();
      expect(attempt.evidenceClass, context.evidenceClass.name);
      expect(
        EvidenceContext.fromJson(
          (jsonDecode(attempt.evidenceContextJson) as Map)
              .cast<String, Object?>(),
        ).toJson(),
        context.toJson(),
      );
    },
  );

  test(
    'pulled attempt payload v2 rejects top-level context mismatch',
    () async {
      final context = _declaredEvidence();
      final v2Store = DriftSyncStore(
        database,
        rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider(
          EvidencePolicyRolloutMode.shadow,
        ),
      );
      final entity = _attemptEntity(
        id: 'attempt-remote-v2-mismatch',
        sessionId: 'session-remote-v2-mismatch',
        occurredAt: now,
        payloadVersion: 2,
        evidenceContext: context,
      );
      final malformed = SyncEntity(
        collection: entity.collection,
        entityId: entity.entityId,
        revision: entity.revision,
        isDeleted: entity.isDeleted,
        payloadVersion: entity.payloadVersion,
        clientUpdatedAtUtc: entity.clientUpdatedAtUtc,
        serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
        payload: <String, Object?>{
          ...entity.payload,
          'evidenceClass': EvidenceClass.recognition.name,
        },
      );

      await expectLater(
        v2Store.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.attempts,
          page: _page(malformed),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await database.select(database.answerAttempts).get(), isEmpty);
    },
  );

  test('pulled attempt payload v2 rejects unknown payload keys', () async {
    final context = _declaredEvidence();
    final entity = _attemptEntity(
      id: 'attempt-remote-v2-extra',
      sessionId: 'session-remote-v2-extra',
      occurredAt: now,
      payloadVersion: 2,
      evidenceContext: context,
    );
    final malformed = SyncEntity(
      collection: entity.collection,
      entityId: entity.entityId,
      revision: entity.revision,
      isDeleted: entity.isDeleted,
      payloadVersion: entity.payloadVersion,
      clientUpdatedAtUtc: entity.clientUpdatedAtUtc,
      serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
      payload: <String, Object?>{...entity.payload, 'rawAudio': 'not allowed'},
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(malformed),
      ),
      throwsA(isA<InvalidSyncPayloadFailure>()),
    );
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  test(
    'historical attempt remains valid after its word is soft deleted',
    () async {
      await (database.update(database.vocabularyWords)
            ..where((row) => row.id.equals('word-1')))
          .write(const VocabularyWordsCompanion(isDeleted: Value(true)));
      final entity = _attemptEntity(
        id: 'attempt-deleted-word',
        sessionId: 'session-deleted-word',
        occurredAt: now,
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(entity),
      );

      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
    },
  );

  test('pulled attempt rejects a session id owned by another owner', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2));
    await database
        .into(database.learningSessions)
        .insert(
          LearningSessionsCompanion.insert(
            id: 'shared-session',
            ownerId: 'owner-2',
            activityType: 'quiz',
            state: 'active',
            startedAtUtcMs: 1,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
    final entity = _attemptEntity(
      id: 'attempt-cross-owner',
      sessionId: 'shared-session',
      occurredAt: now,
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(entity),
      ),
      throwsA(isA<Object>()),
    );

    final foreignSession = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals('shared-session'))).getSingle();
    expect(foreignSession.correctCount, 0);
    expect(await database.select(database.answerAttempts).get(), isEmpty);
  });

  test('identical attempt pull repairs a missing SRS projection', () async {
    final entity = _attemptEntity(
      id: 'attempt-repair',
      sessionId: 'session-repair',
      occurredAt: now,
    );
    final page = _page(entity);
    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.attempts,
      page: page,
    );
    await database.delete(database.srsStates).go();

    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.attempts,
      page: _page(_laterServerReplay(entity)),
    );

    expect(await database.select(database.srsStates).get(), hasLength(1));
  });

  test(
    'reading projection rebuild uses monotonic position and latest time',
    () async {
      final later = _readingEntity(
        id: 'reading-later',
        position: 80,
        occurredAt: now.add(const Duration(minutes: 10)),
      );
      final earlier = _readingEntity(
        id: 'reading-earlier',
        position: 20,
        occurredAt: now,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.readingEvents,
        page: _page(earlier),
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.readingEvents,
        page: _page(later),
      );

      final progress = await database
          .select(database.readingProgressEntries)
          .getSingle();
      expect(progress.lastPosition, 80);
      expect(
        progress.updatedAtUtcMs,
        now.add(const Duration(minutes: 10)).millisecondsSinceEpoch,
      );
    },
  );

  test('identical reading pull repairs a missing projection', () async {
    final entity = _readingEntity(
      id: 'reading-repair',
      position: 40,
      occurredAt: now,
    );
    final page = _page(entity);
    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.readingEvents,
      page: page,
    );
    await database.delete(database.readingProgressEntries).go();

    await store.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.readingEvents,
      page: _page(_laterServerReplay(entity)),
    );

    expect(
      await database.select(database.readingProgressEntries).get(),
      hasLength(1),
    );
  });

  test('malformed attempt payload rolls back its pull checkpoint', () async {
    final valid = _attemptEntity(
      id: 'attempt-malformed',
      sessionId: 'session-malformed',
      occurredAt: now,
    );
    final malformed = SyncEntity(
      collection: valid.collection,
      entityId: valid.entityId,
      revision: valid.revision,
      isDeleted: valid.isDeleted,
      payloadVersion: valid.payloadVersion,
      clientUpdatedAtUtc: valid.clientUpdatedAtUtc,
      serverUpdatedAtUtc: valid.serverUpdatedAtUtc,
      payload: <String, Object?>{...valid.payload, 'promptMode': 'x' * 61},
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(malformed),
      ),
      throwsA(isA<Object>()),
    );

    expect(await database.select(database.answerAttempts).get(), isEmpty);
    expect(await database.select(database.syncCheckpoints).get(), isEmpty);
  });

  test(
    'conflicting immutable attempt is quarantined without overwrite',
    () async {
      final original = _attemptEntity(
        id: 'attempt-conflict',
        sessionId: 'session-conflict',
        occurredAt: now,
      );
      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(original),
      );
      final conflicting = SyncEntity(
        collection: original.collection,
        entityId: original.entityId,
        revision: original.revision,
        isDeleted: original.isDeleted,
        payloadVersion: original.payloadVersion,
        clientUpdatedAtUtc: original.clientUpdatedAtUtc,
        serverUpdatedAtUtc: original.serverUpdatedAtUtc.add(
          const Duration(seconds: 1),
        ),
        payload: <String, Object?>{...original.payload, 'isCorrect': false},
      );

      await store.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(conflicting),
      );

      final attempt = await database
          .select(database.answerAttempts)
          .getSingle();
      expect(attempt.isCorrect, isTrue);
      final conflict = await database
          .select(database.syncConflicts)
          .getSingle();
      expect(conflict.outcome, 'quarantined');
      expect(conflict.entityId, original.entityId);
    },
  );

  test('attempt acknowledgement is replay safe', () async {
    final learning = DriftLearningRepository(database);
    await learning.startSession(
      LearningSessionDraft(
        id: 'session-ack',
        ownerId: 'owner-1',
        activityType: 'quiz',
        startedAtUtc: now,
        appVersion: 'test',
        buildId: 'test',
      ),
    );
    await learning.recordAnswer(
      RecordAnswerCommand.frozenV13LegacyIngress(
        id: 'attempt-ack',
        ownerId: 'owner-1',
        sessionId: 'session-ack',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
        evidenceContext: _frozenV13LegacyEvidence(),
      ),
    );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'attempt-ack-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );
    final claim = (await store.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-ack',
      ownerGateToken: 'attempt-ack-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
      // Phase 0 W12-13: recordAnswer now also enqueues a srsState outbox op.
      // Filter to the attempt operation specifically.
    )).firstWhere((c) => c.mutation.collection == SyncCollection.attempts);
    final attempted = (await store.beginAttempt(
      claim: claim,
      ownerGateToken: 'attempt-ack-gate',
      nowUtc: now,
    ))!;
    final acknowledgement = PushAcknowledged(
      operationId: attempted.mutation.operationId,
      resultingRevision: 1,
      acknowledgedAtUtc: now.add(const Duration(seconds: 1)),
    );

    await store.acknowledge(
      operationId: attempted.mutation.operationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: 'attempt-ack-gate',
      nowUtc: now,
      acknowledgement: acknowledgement,
    );
    await store.acknowledge(
      operationId: attempted.mutation.operationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: 'attempt-ack-gate',
      nowUtc: now,
      acknowledgement: acknowledgement,
    );

    final outbox =
        await (database.select(database.outboxOperations)..where(
              (r) => r.operationId.equals(attempted.mutation.operationId),
            ))
            .getSingle();
    expect(outbox.state, 'acknowledged');
    expect(
      outbox.acknowledgedAtUtcMs,
      acknowledgement.acknowledgedAtUtc.millisecondsSinceEpoch,
    );
  });

  test(
    'two acknowledged SRS reviews upload distinct revisions after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-srs-reviews-',
      );
      final path = '${directory.path}${Platform.pathSeparator}learning.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _seedVocabulary(firstDatabase);
        final learning = DriftLearningRepository(firstDatabase);
        await learning.startSession(
          LearningSessionDraft(
            id: 'session-srs',
            ownerId: 'owner-1',
            activityType: 'quiz',
            startedAtUtc: now,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
        await _recordSrsReview(
          learning,
          id: 'attempt-srs-1',
          attemptNumber: 1,
          occurredAtUtc: now,
        );
        expect(
          await DriftOwnerOperationGate(firstDatabase).tryAcquire(
            token: 'run-first',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final firstStore = DriftSyncStore(firstDatabase);
        final firstSrs =
            (await firstStore.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-1',
              limit: 10,
              leaseToken: 'lease-first',
              ownerGateToken: 'run-first',
              leaseDuration: const Duration(minutes: 5),
              nowUtc: now,
            )).singleWhere(
              (claim) => claim.mutation.collection == SyncCollection.srsStates,
            );
        expect(
          firstSrs.mutation.operationId,
          _srsOperationId('attempt-srs-1', 1),
        );
        expect(firstSrs.mutation.baseRevision, 0);
        expect(firstSrs.mutation.localRevision, 1);
        final firstAttempt = (await firstStore.beginAttempt(
          claim: firstSrs,
          ownerGateToken: 'run-first',
          nowUtc: now,
        ))!;
        expect(
          await firstStore.acknowledge(
            operationId: firstAttempt.mutation.operationId,
            leaseToken: firstAttempt.leaseToken,
            ownerGateToken: 'run-first',
            nowUtc: now,
            acknowledgement: PushAcknowledged(
              operationId: firstAttempt.mutation.operationId,
              resultingRevision: 1,
              acknowledgedAtUtc: now,
            ),
          ),
          isTrue,
        );
        await DriftOwnerOperationGate(
          firstDatabase,
        ).release(token: 'run-first');
      } finally {
        await firstDatabase.close();
      }

      final secondNow = now.add(const Duration(minutes: 1));
      final secondDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await secondDatabase.customSelect('SELECT 1').getSingle();
        await _recordSrsReview(
          DriftLearningRepository(secondDatabase),
          id: 'attempt-srs-2',
          attemptNumber: 2,
          occurredAtUtc: secondNow,
        );
        await _recordSrsReview(
          DriftLearningRepository(secondDatabase),
          id: 'attempt-srs-2',
          attemptNumber: 2,
          occurredAtUtc: secondNow,
        );
        final srsOperationsBeforeClaim = await (secondDatabase.select(
          secondDatabase.outboxOperations,
        )..where((row) => row.entityType.equals('srsState'))).get();
        expect(srsOperationsBeforeClaim, hasLength(2));
        expect(
          await DriftOwnerOperationGate(secondDatabase).tryAcquire(
            token: 'run-second',
            nowUtc: secondNow,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final secondStore = DriftSyncStore(secondDatabase);
        final secondSrs =
            (await secondStore.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-1',
              limit: 10,
              leaseToken: 'lease-second',
              ownerGateToken: 'run-second',
              leaseDuration: const Duration(minutes: 5),
              nowUtc: secondNow,
            )).singleWhere(
              (claim) => claim.mutation.collection == SyncCollection.srsStates,
            );

        expect(
          secondSrs.mutation.operationId,
          _srsOperationId('attempt-srs-2', 2),
        );
        expect(secondSrs.mutation.baseRevision, 1);
        expect(secondSrs.mutation.localRevision, 2);
        expect(secondSrs.mutation.payload['repetitions'], 2);
        final secondAttempt = (await secondStore.beginAttempt(
          claim: secondSrs,
          ownerGateToken: 'run-second',
          nowUtc: secondNow,
        ))!;
        await secondStore.acknowledge(
          operationId: secondAttempt.mutation.operationId,
          leaseToken: secondAttempt.leaseToken,
          ownerGateToken: 'run-second',
          nowUtc: secondNow,
          acknowledgement: PushAcknowledged(
            operationId: secondAttempt.mutation.operationId,
            resultingRevision: 2,
            acknowledgedAtUtc: secondNow,
          ),
        );
        await DriftOwnerOperationGate(
          secondDatabase,
        ).release(token: 'run-second');
      } finally {
        await secondDatabase.close();
      }

      final finalDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await finalDatabase.customSelect('SELECT 1').getSingle();
        final srsOperations = await (finalDatabase.select(
          finalDatabase.outboxOperations,
        )..where((row) => row.entityType.equals('srsState'))).get();

        expect(srsOperations.map((row) => row.operationId).toSet(), {
          _srsOperationId('attempt-srs-1', 1),
          _srsOperationId('attempt-srs-2', 2),
        });
        expect(srsOperations.map((row) => row.state).toSet(), {'acknowledged'});
      } finally {
        await finalDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );

  test('opaque legacy SRS ids derive revision from the durable base', () async {
    await database
        .into(database.srsStates)
        .insert(
          SrsStatesCompanion.insert(
            id: 'srs-opaque',
            ownerId: 'owner-1',
            wordId: 'word-1',
            stability: const Value(1),
            difficulty: const Value(5),
            intervalDays: const Value(1),
            repetitions: const Value(1),
            lapses: const Value(0),
            dueAtUtcMs: 10,
            algorithmVersion: 1,
          ),
        );
    await database
        .into(database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: 'opaque:srs:99:token',
            ownerId: 'owner-1',
            entityType: 'srsState',
            entityId: 'word-1',
            operationKind: 'upsert',
            baseRevision: const Value(4),
            createdAtUtcMs: 1,
          ),
        );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'opaque-srs-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    final claim = (await store.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'opaque-srs-lease',
      ownerGateToken: 'opaque-srs-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
    )).single;

    expect(claim.mutation.baseRevision, 4);
    expect(claim.mutation.localRevision, 5);
  });

  test(
    'lost SRS acknowledgement replays older id before second review',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-srs-lost-ack-',
      );
      final path = '${directory.path}${Platform.pathSeparator}learning.sqlite';
      final cloud = _SrsIdempotentFakeCloud();
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _seedVocabulary(firstDatabase);
        final learning = DriftLearningRepository(firstDatabase);
        await learning.startSession(
          LearningSessionDraft(
            id: 'session-srs',
            ownerId: 'owner-1',
            activityType: 'quiz',
            startedAtUtc: now,
            appVersion: 'test',
            buildId: 'test',
          ),
        );
        await _recordSrsReview(
          learning,
          id: 'attempt-srs-1',
          attemptNumber: 1,
          occurredAtUtc: now,
        );
        expect(
          await DriftOwnerOperationGate(firstDatabase).tryAcquire(
            token: 'run-first',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final firstStore = DriftSyncStore(firstDatabase);
        final firstSrs =
            (await firstStore.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-1',
              limit: 10,
              leaseToken: 'lease-first',
              ownerGateToken: 'run-first',
              leaseDuration: const Duration(minutes: 5),
              nowUtc: now,
            )).singleWhere(
              (claim) => claim.mutation.collection == SyncCollection.srsStates,
            );
        final firstAttempt = (await firstStore.beginAttempt(
          claim: firstSrs,
          ownerGateToken: 'run-first',
          nowUtc: now,
        ))!;
        await cloud.push(firstAttempt.mutation);
      } finally {
        await firstDatabase.close();
      }

      final reopenedAt = now.add(const Duration(minutes: 5));
      final reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopenedDatabase.customSelect('SELECT 1').getSingle();
        await _recordSrsReview(
          DriftLearningRepository(reopenedDatabase),
          id: 'attempt-srs-2',
          attemptNumber: 2,
          occurredAtUtc: reopenedAt,
        );
        expect(
          await DriftOwnerOperationGate(reopenedDatabase).tryAcquire(
            token: 'run-reopened',
            nowUtc: reopenedAt,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final reopenedStore = DriftSyncStore(reopenedDatabase);
        final replayLease =
            (await reopenedStore.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-1',
              limit: 10,
              leaseToken: 'lease-replay',
              ownerGateToken: 'run-reopened',
              leaseDuration: const Duration(minutes: 5),
              nowUtc: reopenedAt,
            )).singleWhere(
              (claim) => claim.mutation.collection == SyncCollection.srsStates,
            );

        expect(
          replayLease.mutation.operationId,
          _srsOperationId('attempt-srs-1', 1),
        );
        expect(replayLease.mutation.localRevision, 2);
        expect(replayLease.mutation.payload['repetitions'], 2);
        final replayAttempt = (await reopenedStore.beginAttempt(
          claim: replayLease,
          ownerGateToken: 'run-reopened',
          nowUtc: reopenedAt,
        ))!;
        final oldAcknowledgement = await cloud.push(replayAttempt.mutation);
        expect(oldAcknowledgement.resultingRevision, 1);
        await reopenedStore.acknowledge(
          operationId: replayAttempt.mutation.operationId,
          leaseToken: replayAttempt.leaseToken,
          ownerGateToken: 'run-reopened',
          nowUtc: reopenedAt,
          acknowledgement: oldAcknowledgement,
        );

        final laterLease =
            (await reopenedStore.claimPending(
              ownerId: 'owner-1',
              firebaseUid: 'firebase-1',
              limit: 10,
              leaseToken: 'lease-later',
              ownerGateToken: 'run-reopened',
              leaseDuration: const Duration(minutes: 5),
              nowUtc: reopenedAt,
            )).singleWhere(
              (claim) => claim.mutation.collection == SyncCollection.srsStates,
            );

        expect(
          laterLease.mutation.operationId,
          _srsOperationId('attempt-srs-2', 2),
        );
        expect(laterLease.mutation.baseRevision, 1);
        expect(laterLease.mutation.localRevision, 2);
        expect(
          cloud.requestsFor('firebase-1', _srsOperationId('attempt-srs-1', 1)),
          2,
        );
        expect(
          cloud.appliesFor('firebase-1', _srsOperationId('attempt-srs-1', 1)),
          1,
        );
      } finally {
        await reopenedDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );

  test(
    'independent devices use distinct SRS ids at the same base revision',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-srs-multi-device-',
      );
      final firstDatabase = AppDatabase(
        NativeDatabase(
          File('${directory.path}${Platform.pathSeparator}first.sqlite'),
        ),
      );
      final secondDatabase = AppDatabase(
        NativeDatabase(
          File('${directory.path}${Platform.pathSeparator}second.sqlite'),
        ),
      );
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await secondDatabase.customSelect('SELECT 1').getSingle();
        await _seedSrsDeviceAtRevisionFive(
          firstDatabase,
          newAnswerId: 'answer-device-a',
          isCorrect: true,
          occurredAtUtc: now.add(const Duration(minutes: 1)),
        );
        await _seedSrsDeviceAtRevisionFive(
          secondDatabase,
          newAnswerId: 'answer-device-b',
          isCorrect: false,
          occurredAtUtc: now.add(const Duration(minutes: 2)),
        );
        final firstAttempt = await _claimAndReserveSrs(
          firstDatabase,
          token: 'device-a',
          nowUtc: now.add(const Duration(minutes: 3)),
        );
        final secondAttempt = await _claimAndReserveSrs(
          secondDatabase,
          token: 'device-b',
          nowUtc: now.add(const Duration(minutes: 3)),
        );
        final cloud = _RevisionedSrsCloud(
          initialRevision: 5,
          nowUtc: now.add(const Duration(minutes: 4)),
        );

        final firstResult = await cloud.push(firstAttempt.mutation);
        final secondResult = await cloud.push(secondAttempt.mutation);

        expect(firstAttempt.mutation.baseRevision, 5);
        expect(secondAttempt.mutation.baseRevision, 5);
        expect(firstAttempt.mutation.localRevision, 6);
        expect(secondAttempt.mutation.localRevision, 6);
        expect(
          secondAttempt.mutation.operationId,
          isNot(firstAttempt.mutation.operationId),
        );
        expect(
          firstAttempt.mutation.operationId,
          matches(RegExp(r'^srsState:v2:[0-9a-f]{64}:r6$')),
        );
        expect(
          secondAttempt.mutation.operationId,
          matches(RegExp(r'^srsState:v2:[0-9a-f]{64}:r6$')),
        );
        expect(firstAttempt.mutation.operationId, isNot(contains('device')));
        expect(secondAttempt.mutation.operationId, isNot(contains('device')));
        expect(firstResult, isA<PushAcknowledged>());
        expect(secondResult, isA<PushConflict>());
        expect(cloud.rawRequests, hasLength(2));
        expect(
          cloud.rawRequests.map((mutation) => mutation.operationId).toSet(),
          hasLength(2),
        );

        final conflict = secondResult as PushConflict;
        final secondStore = DriftSyncStore(secondDatabase);
        final localSrsBeforeConflict = await (secondDatabase.select(
          secondDatabase.srsStates,
        )..where((row) => row.wordId.equals('word-1'))).getSingle();
        expect(
          await secondStore.resolvePushConflict(
            claim: secondAttempt,
            cloudEntity: conflict.cloudEntity,
            ownerGateToken: 'device-b',
            resolvedAtUtc: now.add(const Duration(minutes: 4)),
          ),
          isTrue,
        );
        final conflictRows = await (secondDatabase.select(
          secondDatabase.syncConflicts,
        )..where((row) => row.ownerId.equals('owner-1'))).get();
        expect(conflictRows, hasLength(1));
        expect(conflictRows.single.outcome, 'localEvidenceWins');
        expect(conflictRows.single.entityId, secondAttempt.mutation.entityId);
        final secondOperation =
            await (secondDatabase.select(secondDatabase.outboxOperations)
                  ..where(
                    (row) => row.operationId.equals(
                      secondAttempt.mutation.operationId,
                    ),
                  ))
                .getSingle();
        expect(secondOperation.state, 'conflictResolved');
        expect(
          await (secondDatabase.select(
            secondDatabase.srsStates,
          )..where((row) => row.wordId.equals('word-1'))).getSingle(),
          localSrsBeforeConflict,
          reason:
              'durable answer evidence remains the SRS projection authority',
        );
        expect(
          await (secondDatabase.select(secondDatabase.answerAttempts)
                ..where((row) => row.id.equals('answer-device-b')))
              .getSingleOrNull(),
          isNotNull,
          reason: 'the immutable answer remains durable after SRS cloud-wins',
        );
      } finally {
        await secondDatabase.close();
        await firstDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test(
    'file-backed legacy SRS gap normalizes once under the owner gate',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-srs-legacy-normalization-',
      );
      final path = '${directory.path}${Platform.pathSeparator}legacy.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _seedLegacySrsGap(firstDatabase, now);
      } finally {
        await firstDatabase.close();
      }

      final reopened = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopened.customSelect('SELECT 1').getSingle();
        final store = DriftSyncStore(reopened);
        expect(
          await store.claimPending(
            ownerId: 'owner-1',
            firebaseUid: 'firebase-legacy',
            limit: 10,
            leaseToken: 'unowned-lease',
            ownerGateToken: 'unowned-gate',
            leaseDuration: const Duration(minutes: 5),
            nowUtc: now,
          ),
          isEmpty,
        );
        expect(await _srsOutboxRows(reopened), hasLength(1));
        final gate = DriftOwnerOperationGate(reopened);
        expect(
          await gate.tryAcquire(
            token: 'normalize-gate',
            nowUtc: now,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims = await store.claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-legacy',
          limit: 10,
          leaseToken: 'normalize-lease',
          ownerGateToken: 'normalize-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: now,
        );
        final normalized = claims.singleWhere(
          (claim) => claim.mutation.collection == SyncCollection.srsStates,
        );

        expect(
          normalized.mutation.operationId,
          _srsOperationId('legacy-answer-3', 3),
        );
        expect(normalized.mutation.baseRevision, 2);
        expect(normalized.mutation.localRevision, 3);
        final attempted = (await store.beginAttempt(
          claim: normalized,
          ownerGateToken: 'normalize-gate',
          nowUtc: now,
        ))!;
        expect(
          await store.acknowledge(
            operationId: attempted.mutation.operationId,
            leaseToken: attempted.leaseToken,
            ownerGateToken: 'normalize-gate',
            nowUtc: now,
            acknowledgement: PushAcknowledged(
              operationId: attempted.mutation.operationId,
              resultingRevision: 3,
              acknowledgedAtUtc: now,
            ),
          ),
          isTrue,
        );
        await gate.release(token: 'normalize-gate');
      } finally {
        await reopened.close();
      }

      final finalDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await finalDatabase.customSelect('SELECT 1').getSingle();
        final finalGate = DriftOwnerOperationGate(finalDatabase);
        final finalNow = now.add(const Duration(minutes: 1));
        expect(
          await finalGate.tryAcquire(
            token: 'final-gate',
            nowUtc: finalNow,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims = await DriftSyncStore(finalDatabase).claimPending(
          ownerId: 'owner-1',
          firebaseUid: 'firebase-legacy',
          limit: 10,
          leaseToken: 'final-lease',
          ownerGateToken: 'final-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: finalNow,
        );
        final rows = await _srsOutboxRows(finalDatabase);

        expect(
          claims.where(
            (claim) => claim.mutation.collection == SyncCollection.srsStates,
          ),
          isEmpty,
        );
        expect(rows, hasLength(2));
        expect(
          rows
              .singleWhere(
                (row) =>
                    row.operationId == _srsOperationId('legacy-answer-3', 3),
              )
              .state,
          'acknowledged',
        );
      } finally {
        await finalDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );
}

String _srsOperationId(String answerAttemptId, int revision) {
  return SrsOperationIdentity.create(
    ownerId: 'owner-1',
    wordId: 'word-1',
    answerAttemptId: answerAttemptId,
    revision: revision,
  );
}

SyncEntity _attemptEntity({
  required String id,
  required String sessionId,
  required DateTime occurredAt,
  int payloadVersion = 1,
  EvidenceContext? evidenceContext,
}) => SyncEntity(
  collection: SyncCollection.attempts,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: payloadVersion,
  clientUpdatedAtUtc: occurredAt,
  serverUpdatedAtUtc: occurredAt.add(const Duration(seconds: 1)),
  payload: <String, Object?>{
    'sessionId': sessionId,
    'wordId': 'word-1',
    'promptMode': 'meaningChoice',
    'isCorrect': true,
    'responseTimeMs': 300,
    'attemptNumber': 1,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
    'providerProvenance': null,
    if (payloadVersion == 2) ...<String, Object?>{
      'evidenceClass': evidenceContext!.evidenceClass.name,
      'evidenceContext': evidenceContext.toJson(),
    },
  },
);

EvidenceContext _declaredEvidence() => EvidenceContext.forNewEvidence(
  evidenceClass: EvidenceClass.independentRecall,
  skillId: 'meaning-recall',
  hintLevel: 0,
  contentRevision: 'built-in-v1',
  rolloutMode: EvidencePolicyRolloutMode.shadow,
  protocolId: 'evidence-pilot',
  protocolVersion: '1.0.0',
  experimentId: 'evidence-eligibility',
  experimentVersion: 1,
  assignmentId: 'assignment-1',
  cohort: 'shadow',
  researchConsentVersion: 1,
  engagementAllowed: true,
);

Future<void> _insertAttemptForSync(
  AppDatabase database, {
  required String id,
  required String sessionId,
  required DateTime occurredAt,
  required EvidenceContext evidenceContext,
}) async {
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: sessionId,
          ownerId: 'owner-1',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: occurredAt.millisecondsSinceEpoch,
          appVersion: 'test',
          buildId: 'test',
        ),
      );
  await database
      .into(database.answerAttempts)
      .insert(
        AnswerAttemptsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          sessionId: sessionId,
          wordId: 'word-1',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: const Value(300),
          attemptNumber: 1,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          evidenceClass: Value(evidenceContext.evidenceClass.name),
          evidenceContextJson: Value(jsonEncode(evidenceContext.toJson())),
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: LearningEvidenceContract.answerAttemptOutboxOperationId(
            id,
          ),
          ownerId: 'owner-1',
          entityType: 'attempt',
          entityId: id,
          operationKind: 'upsert',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
      );
}

SyncEntity _readingEntity({
  required String id,
  required int position,
  required DateTime occurredAt,
}) => SyncEntity(
  collection: SyncCollection.readingEvents,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: occurredAt,
  serverUpdatedAtUtc: occurredAt.add(const Duration(seconds: 1)),
  payload: <String, Object?>{
    'documentId': 'document-1',
    'documentRevision': 1,
    'eventType': 'checkpoint',
    'position': position,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
  },
);

PullPage _page(SyncEntity entity) => PullPage(
  changes: [entity],
  nextCursor: SyncCursor(
    serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
    documentId: entity.entityId,
  ),
  hasMore: false,
);

SyncEntity _laterServerReplay(SyncEntity entity) => SyncEntity(
  collection: entity.collection,
  entityId: entity.entityId,
  revision: entity.revision,
  isDeleted: entity.isDeleted,
  payloadVersion: entity.payloadVersion,
  clientUpdatedAtUtc: entity.clientUpdatedAtUtc,
  serverUpdatedAtUtc: entity.serverUpdatedAtUtc.add(
    const Duration(microseconds: 1),
  ),
  payload: entity.payload,
);

Future<void> _seedVocabulary(AppDatabase database) async {
  await database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category-1',
          ownerId: 'owner-1',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
  await database
      .into(database.vocabularyWords)
      .insert(
        VocabularyWordsCompanion.insert(
          id: 'word-1',
          ownerId: 'owner-1',
          categoryId: 'category-1',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          createdAtUtcMs: 1,
          updatedAtUtcMs: 1,
        ),
      );
}

Future<void> _recordSrsReview(
  DriftLearningRepository learning, {
  required String id,
  required int attemptNumber,
  bool isCorrect = true,
  required DateTime occurredAtUtc,
}) {
  return learning.recordAnswer(
    RecordAnswerCommand.frozenV13LegacyIngress(
      id: id,
      ownerId: 'owner-1',
      sessionId: 'session-srs',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: isCorrect,
      responseTimeMs: 250,
      attemptNumber: attemptNumber,
      occurredAtUtc: occurredAtUtc,
      evidenceContext: _frozenV13LegacyEvidence(),
    ),
  );
}

EvidenceContext _frozenV13LegacyEvidence() =>
    LearningEvidenceContract.frozenV13LegacyEvidenceContext();

Future<void> _seedSrsDeviceAtRevisionFive(
  AppDatabase database, {
  required String newAnswerId,
  required bool isCorrect,
  required DateTime occurredAtUtc,
}) async {
  await _seedVocabulary(database);
  await (database.update(
    database.localOwners,
  )..where((row) => row.id.equals('owner-1'))).write(
    const LocalOwnersCompanion(
      firebaseUid: Value('firebase-shared'),
      accountState: Value('firebaseBound'),
    ),
  );
  final learning = DriftLearningRepository(database);
  await learning.startSession(
    LearningSessionDraft(
      id: 'session-srs',
      ownerId: 'owner-1',
      activityType: 'quiz',
      startedAtUtc: occurredAtUtc.subtract(const Duration(minutes: 10)),
      appVersion: 'test',
      buildId: 'test',
    ),
  );
  for (var revision = 1; revision <= 5; revision++) {
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'base-answer-$revision',
            ownerId: 'owner-1',
            sessionId: 'session-srs',
            wordId: 'word-1',
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: const Value(250),
            attemptNumber: revision,
            occurredAtUtcMs: occurredAtUtc
                .subtract(Duration(minutes: 6 - revision))
                .millisecondsSinceEpoch,
          ),
        );
  }
  await _recordSrsReview(
    learning,
    id: newAnswerId,
    attemptNumber: 6,
    isCorrect: isCorrect,
    occurredAtUtc: occurredAtUtc,
  );
}

Future<void> _seedLegacySrsGap(AppDatabase database, DateTime nowUtc) async {
  await _seedVocabulary(database);
  await (database.update(
    database.localOwners,
  )..where((row) => row.id.equals('owner-1'))).write(
    const LocalOwnersCompanion(
      firebaseUid: Value('firebase-legacy'),
      accountState: Value('firebaseBound'),
    ),
  );
  await database
      .into(database.learningSessions)
      .insert(
        LearningSessionsCompanion.insert(
          id: 'legacy-session',
          ownerId: 'owner-1',
          activityType: 'quiz',
          state: 'completed',
          startedAtUtcMs: nowUtc.millisecondsSinceEpoch - 1000,
          endedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
          appVersion: 'legacy',
          buildId: 'legacy',
        ),
      );
  for (var revision = 1; revision <= 3; revision++) {
    await database
        .into(database.answerAttempts)
        .insert(
          AnswerAttemptsCompanion.insert(
            id: 'legacy-answer-$revision',
            ownerId: 'owner-1',
            sessionId: 'legacy-session',
            wordId: 'word-1',
            promptMode: 'meaningChoice',
            isCorrect: true,
            responseTimeMs: const Value(250),
            attemptNumber: revision,
            occurredAtUtcMs: nowUtc.millisecondsSinceEpoch - (4 - revision),
          ),
        );
  }
  await database
      .into(database.srsStates)
      .insert(
        SrsStatesCompanion.insert(
          id: 'legacy-srs',
          ownerId: 'owner-1',
          wordId: 'word-1',
          stability: const Value(3),
          difficulty: const Value(4),
          intervalDays: const Value(3),
          repetitions: const Value(3),
          lapses: const Value(0),
          lastReviewAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
          dueAtUtcMs: nowUtc.millisecondsSinceEpoch + 1000,
          algorithmVersion: 1,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: 'srsState:word-1:1',
          ownerId: 'owner-1',
          entityType: 'srsState',
          entityId: 'word-1',
          operationKind: 'upsert',
          state: const Value('acknowledged'),
          attemptCount: const Value(1),
          baseRevision: const Value(0),
          createdAtUtcMs: nowUtc.millisecondsSinceEpoch - 1000,
          acknowledgedAtUtcMs: Value(nowUtc.millisecondsSinceEpoch - 500),
        ),
      );
}

Future<List<OutboxOperation>> _srsOutboxRows(AppDatabase database) {
  return (database.select(
    database.outboxOperations,
  )..where((row) => row.entityType.equals('srsState'))).get();
}

Future<ClaimedSyncOperation> _claimAndReserveSrs(
  AppDatabase database, {
  required String token,
  required DateTime nowUtc,
}) async {
  final gate = DriftOwnerOperationGate(database);
  expect(
    await gate.tryAcquire(
      token: token,
      nowUtc: nowUtc,
      leaseDuration: const Duration(minutes: 10),
    ),
    isTrue,
  );
  final store = DriftSyncStore(database);
  final claims = await store.claimPending(
    ownerId: 'owner-1',
    firebaseUid: 'firebase-shared',
    limit: 10,
    leaseToken: '$token-lease',
    ownerGateToken: token,
    leaseDuration: const Duration(minutes: 5),
    nowUtc: nowUtc,
  );
  final srs = claims.singleWhere(
    (claim) => claim.mutation.collection == SyncCollection.srsStates,
  );
  for (final claim in claims.where((claim) => !identical(claim, srs))) {
    expect(
      await store.releaseClaim(
        claim: claim,
        ownerGateToken: token,
        nowUtc: nowUtc,
      ),
      isTrue,
    );
  }
  return (await store.beginAttempt(
    claim: srs,
    ownerGateToken: token,
    nowUtc: nowUtc,
  ))!;
}

final class _RevisionedSrsCloud {
  _RevisionedSrsCloud({required int initialRevision, required this.nowUtc})
    : _revision = initialRevision;

  final DateTime nowUtc;
  final List<PushMutation> rawRequests = <PushMutation>[];
  final Map<String, PushAcknowledged> _receipts = <String, PushAcknowledged>{};
  int _revision;
  SyncEntity? _remote;

  Future<PushResult> push(PushMutation mutation) async {
    rawRequests.add(mutation);
    final key = '${mutation.firebaseUid}\u001f${mutation.operationId}';
    final receipt = _receipts[key];
    if (receipt != null) return receipt;
    if (mutation.baseRevision != _revision) {
      return PushConflict(_remote!);
    }
    _revision = mutation.localRevision;
    _remote = SyncEntity(
      collection: mutation.collection,
      entityId: mutation.entityId,
      revision: mutation.localRevision,
      isDeleted: false,
      payloadVersion: mutation.payloadVersion,
      clientUpdatedAtUtc: mutation.clientUpdatedAtUtc,
      serverUpdatedAtUtc: nowUtc,
      payload: mutation.payload,
    );
    final acknowledgement = PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: nowUtc,
    );
    _receipts[key] = acknowledgement;
    return acknowledgement;
  }
}

final class _SrsIdempotentFakeCloud {
  final Map<String, PushAcknowledged> _acknowledgements =
      <String, PushAcknowledged>{};
  final Map<String, int> _requests = <String, int>{};
  final Map<String, int> _applies = <String, int>{};

  Future<PushAcknowledged> push(PushMutation mutation) async {
    final key = '${mutation.firebaseUid}\u001f${mutation.operationId}';
    _requests[key] = (_requests[key] ?? 0) + 1;
    return _acknowledgements.putIfAbsent(key, () {
      _applies[key] = (_applies[key] ?? 0) + 1;
      return PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: mutation.clientUpdatedAtUtc,
      );
    });
  }

  int requestsFor(String uid, String operationId) =>
      _requests['$uid\u001f$operationId'] ?? 0;

  int appliesFor(String uid, String operationId) =>
      _applies['$uid\u001f$operationId'] ?? 0;
}
