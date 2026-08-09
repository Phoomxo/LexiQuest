import 'dart:io';

import 'package:drift/drift.dart' show Value, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

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
      RecordAnswerCommand(
        id: 'attempt-1',
        ownerId: 'owner-1',
        sessionId: 'session-1',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
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

      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
    },
  );

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
      RecordAnswerCommand(
        id: 'attempt-ack',
        ownerId: 'owner-1',
        sessionId: 'session-ack',
        wordId: 'word-1',
        promptMode: 'meaningChoice',
        isCorrect: true,
        responseTimeMs: 250,
        attemptNumber: 1,
        occurredAtUtc: now,
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
        expect(firstSrs.mutation.operationId, 'srsState:word-1:1');
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

        expect(secondSrs.mutation.operationId, 'srsState:word-1:2');
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
          'srsState:word-1:1',
          'srsState:word-1:2',
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

        expect(replayLease.mutation.operationId, 'srsState:word-1:1');
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

        expect(laterLease.mutation.operationId, 'srsState:word-1:2');
        expect(laterLease.mutation.baseRevision, 1);
        expect(laterLease.mutation.localRevision, 2);
        expect(cloud.requestsFor('firebase-1', 'srsState:word-1:1'), 2);
        expect(cloud.appliesFor('firebase-1', 'srsState:word-1:1'), 1);
      } finally {
        await reopenedDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );
}

SyncEntity _attemptEntity({
  required String id,
  required String sessionId,
  required DateTime occurredAt,
}) => SyncEntity(
  collection: SyncCollection.attempts,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
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
  },
);

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
  required DateTime occurredAtUtc,
}) {
  return learning.recordAnswer(
    RecordAnswerCommand(
      id: id,
      ownerId: 'owner-1',
      sessionId: 'session-srs',
      wordId: 'word-1',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 250,
      attemptNumber: attemptNumber,
      occurredAtUtc: occurredAtUtc,
    ),
  );
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
