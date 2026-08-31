import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_quality_policy.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore store;
  late DateTime nowUtc;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    nowUtc = DateTime.utc(2026, 7, 30, 8);
    await _insertOwner(database, 'owner-a');
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'test-owner-gate',
        nowUtc: nowUtc,
        leaseDuration: const Duration(days: 1),
      ),
      isTrue,
    );
  });

  tearDown(() async {
    await database.close();
  });

  test(
    'claim coalesces consecutive entity revisions into latest state',
    () async {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:travel',
        name: 'Business travel',
        revision: 2,
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:travel:1:upsert',
        entityId: 'category:travel',
        baseRevision: 0,
        createdAtUtcMs: 1,
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:travel:2:upsert',
        entityId: 'category:travel',
        baseRevision: 1,
        createdAtUtcMs: 2,
      );

      final claimed = await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 10,
        leaseToken: 'lease-a',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      );
      expect(
        await store.releaseClaim(
          claim: claimed.single,
          ownerGateToken: 'test-owner-gate',
          nowUtc: nowUtc,
        ),
        isTrue,
      );
      final reclaimed = await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 10,
        leaseToken: 'lease-b',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      );
      final rows = await database.select(database.outboxOperations).get();

      expect(claimed, hasLength(1));
      expect(claimed.single.mutation.operationId, 'category:travel:2:upsert');
      expect(claimed.single.mutation.baseRevision, 0);
      expect(
        reclaimed.single.mutation.operationId,
        claimed.single.mutation.operationId,
      );
      expect(reclaimed.single.mutation.baseRevision, 0);
      expect(claimed.single.mutation.localRevision, 2);
      expect(claimed.single.mutation.payload['name'], 'Business travel');
      expect(
        rows
            .singleWhere((row) => row.operationId == 'category:travel:1:upsert')
            .state,
        'superseded',
      );
      expect(
        rows
            .singleWhere((row) => row.operationId == 'category:travel:2:upsert')
            .state,
        'inFlight',
      );
      expect(
        rows
            .singleWhere((row) => row.operationId == 'category:travel:2:upsert')
            .baseRevision,
        0,
      );
    },
  );

  test(
    'file-backed lost acknowledgement replays attempted id before later edit',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-lost-ack-barrier-',
      );
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      final cloud = _IdempotentFakeCloud();
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _insertOwner(firstDatabase, 'owner-file');
        await _insertCategory(
          firstDatabase,
          ownerId: 'owner-file',
          id: 'category:file',
          name: 'First edit',
        );
        await _insertOutbox(
          firstDatabase,
          ownerId: 'owner-file',
          operationId: 'category:category:file:1',
          entityId: 'category:file',
          baseRevision: 0,
          createdAtUtcMs: 1,
        );
        expect(
          await DriftOwnerOperationGate(firstDatabase).tryAcquire(
            token: 'run-first',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final firstStore = DriftSyncStore(firstDatabase);
        final firstLease = (await firstStore.claimPending(
          ownerId: 'owner-file',
          firebaseUid: 'firebase-file',
          limit: 1,
          leaseToken: 'lease-first',
          ownerGateToken: 'run-first',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: nowUtc,
        )).single;
        final firstAttempt = (await firstStore.beginAttempt(
          claim: firstLease,
          ownerGateToken: 'run-first',
          nowUtc: nowUtc,
        ))!;
        await cloud.push(firstAttempt.mutation);
      } finally {
        await firstDatabase.close();
      }

      final reopenedAt = nowUtc.add(const Duration(minutes: 5));
      final reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopenedDatabase.customSelect('SELECT 1').getSingle();
        await (reopenedDatabase.update(
          reopenedDatabase.vocabularyCategories,
        )..where((row) => row.id.equals('category:file'))).write(
          const VocabularyCategoriesCompanion(
            name: Value('Later edit'),
            normalizedName: Value('later edit'),
            localRevision: Value(2),
            updatedAtUtcMs: Value(2),
          ),
        );
        await _insertOutbox(
          reopenedDatabase,
          ownerId: 'owner-file',
          operationId: 'category:category:file:2',
          entityId: 'category:file',
          baseRevision: 1,
          createdAtUtcMs: 2,
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
        final replayLease = (await reopenedStore.claimPending(
          ownerId: 'owner-file',
          firebaseUid: 'firebase-file',
          limit: 1,
          leaseToken: 'lease-replay',
          ownerGateToken: 'run-reopened',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reopenedAt,
        )).single;

        expect(replayLease.mutation.operationId, 'category:category:file:1');
        final replayAttempt = (await reopenedStore.beginAttempt(
          claim: replayLease,
          ownerGateToken: 'run-reopened',
          nowUtc: reopenedAt,
        ))!;
        final existingAcknowledgement = await cloud.push(
          replayAttempt.mutation,
        );
        expect(existingAcknowledgement.resultingRevision, 1);
        expect(
          await reopenedStore.acknowledge(
            operationId: replayAttempt.mutation.operationId,
            leaseToken: replayAttempt.leaseToken,
            ownerGateToken: 'run-reopened',
            nowUtc: reopenedAt,
            acknowledgement: existingAcknowledgement,
          ),
          isTrue,
        );

        final laterLease = (await reopenedStore.claimPending(
          ownerId: 'owner-file',
          firebaseUid: 'firebase-file',
          limit: 1,
          leaseToken: 'lease-later',
          ownerGateToken: 'run-reopened',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reopenedAt,
        )).single;
        final rows = await reopenedDatabase
            .select(reopenedDatabase.outboxOperations)
            .get();

        expect(laterLease.mutation.operationId, 'category:category:file:2');
        expect(laterLease.mutation.baseRevision, 1);
        expect(laterLease.mutation.localRevision, 2);
        expect(laterLease.mutation.payload['name'], 'Later edit');
        expect(
          rows
              .singleWhere(
                (row) => row.operationId == 'category:category:file:1',
              )
              .state,
          'acknowledged',
        );
        expect(
          cloud.requestsFor('firebase-file', 'category:category:file:1'),
          2,
        );
        expect(
          cloud.appliesFor('firebase-file', 'category:category:file:1'),
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
    'new replay carrying latest revision retires later never-attempted edit',
    () async {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:barrier',
        name: 'First edit',
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:category:barrier:1',
        entityId: 'category:barrier',
        baseRevision: 0,
        createdAtUtcMs: 1,
      );
      final firstLease = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-first',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      )).single;
      await store.beginAttempt(
        claim: firstLease,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
      );
      await (database.update(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('category:barrier'))).write(
        const VocabularyCategoriesCompanion(
          name: Value('Latest edit'),
          normalizedName: Value('latest edit'),
          localRevision: Value(2),
          updatedAtUtcMs: Value(2),
        ),
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:category:barrier:2',
        entityId: 'category:barrier',
        baseRevision: 1,
        createdAtUtcMs: 2,
      );
      final replayAt = nowUtc.add(const Duration(minutes: 5));
      final replayLease = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-replay',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: replayAt,
      )).single;

      expect(replayLease.mutation.operationId, 'category:category:barrier:1');
      final replayAttempt = (await store.beginAttempt(
        claim: replayLease,
        ownerGateToken: 'test-owner-gate',
        nowUtc: replayAt,
      ))!;
      expect(replayAttempt.mutation.localRevision, 2);
      await store.acknowledge(
        operationId: replayAttempt.mutation.operationId,
        leaseToken: replayAttempt.leaseToken,
        ownerGateToken: 'test-owner-gate',
        nowUtc: replayAt,
        acknowledgement: PushAcknowledged(
          operationId: replayAttempt.mutation.operationId,
          resultingRevision: 2,
          acknowledgedAtUtc: replayAt,
        ),
      );

      final remaining = await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-none',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: replayAt,
      );
      final later =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('category:category:barrier:2'),
              ))
              .getSingle();

      expect(remaining, isEmpty);
      expect(later.state, 'superseded');
      expect(later.failureCode, 'includedInAcknowledgedReplay');
    },
  );

  test(
    'file-backed fifth reservation crash becomes terminal unknown delivery',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-fifth-crash-',
      );
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _insertOwner(firstDatabase, 'owner-file');
        await _insertCategory(
          firstDatabase,
          ownerId: 'owner-file',
          id: 'category:file',
          name: 'Crash boundary',
        );
        await _insertOutbox(
          firstDatabase,
          ownerId: 'owner-file',
          operationId: 'category:category:file:1',
          entityId: 'category:file',
          baseRevision: 0,
          createdAtUtcMs: 1,
        );
        await (firstDatabase.update(firstDatabase.outboxOperations)..where(
              (row) => row.operationId.equals('category:category:file:1'),
            ))
            .write(const OutboxOperationsCompanion(attemptCount: Value(4)));
        expect(
          await DriftOwnerOperationGate(firstDatabase).tryAcquire(
            token: 'run-first',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final firstStore = DriftSyncStore(firstDatabase);
        final leased = (await firstStore.claimPending(
          ownerId: 'owner-file',
          firebaseUid: 'firebase-file',
          limit: 1,
          leaseToken: 'lease-first',
          ownerGateToken: 'run-first',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: nowUtc,
        )).single;
        final fifth = await firstStore.beginAttempt(
          claim: leased,
          ownerGateToken: 'run-first',
          nowUtc: nowUtc,
        );
        expect(fifth, isNotNull);
        expect(fifth!.attemptCount, 5);
      } finally {
        await firstDatabase.close();
      }

      final reopenedAt = nowUtc.add(const Duration(minutes: 5));
      final reopenedDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await reopenedDatabase.customSelect('SELECT 1').getSingle();
        expect(
          await DriftOwnerOperationGate(reopenedDatabase).tryAcquire(
            token: 'run-reopened',
            nowUtc: reopenedAt,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        final claims = await DriftSyncStore(reopenedDatabase).claimPending(
          ownerId: 'owner-file',
          firebaseUid: 'firebase-file',
          limit: 1,
          leaseToken: 'lease-reopened',
          ownerGateToken: 'run-reopened',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: reopenedAt,
        );
        final operation = await reopenedDatabase
            .select(reopenedDatabase.outboxOperations)
            .getSingle();

        expect(claims, isEmpty);
        expect(operation.state, 'permanentFailure');
        expect(operation.failureCode, 'deliveryUnknownAfterReservationLimit');
        expect(operation.attemptCount, 5);
        expect(operation.leaseToken, isNull);
        expect(operation.leaseExpiresAtUtcMs, isNull);
      } finally {
        await reopenedDatabase.close();
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
        await directory.delete(recursive: true);
      }
    },
  );

  test('concurrent claimers never receive the same operation', () async {
    for (var index = 0; index < 2; index++) {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:$index',
        name: 'Category $index',
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'operation:$index',
        entityId: 'category:$index',
        baseRevision: 0,
        createdAtUtcMs: index,
      );
    }

    final claims = await Future.wait([
      store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-a',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      ),
      store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-b',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      ),
    ]);

    final operationIds = claims
        .expand((claim) => claim)
        .map((claim) => claim.mutation.operationId)
        .toSet();
    expect(operationIds, hasLength(2));
  });

  test(
    'run lease is atomic, token-owned, and reclaimable after expiry',
    () async {
      final otherStore = DriftSyncStore(database);
      await DriftOwnerOperationGate(database).release(token: 'test-owner-gate');
      final results = await Future.wait([
        store.tryAcquireRunLease(
          ownerId: 'owner-a',
          leaseToken: 'run-a',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 10),
        ),
        otherStore.tryAcquireRunLease(
          ownerId: 'owner-a',
          leaseToken: 'run-b',
          nowUtc: nowUtc,
          leaseDuration: const Duration(minutes: 10),
        ),
      ]);
      expect(results.where((acquired) => acquired), hasLength(1));

      await store.releaseRunLease(
        ownerId: 'owner-a',
        leaseToken: 'not-the-owner',
      );
      expect(
        await otherStore.tryAcquireRunLease(
          ownerId: 'owner-a',
          leaseToken: 'run-c',
          nowUtc: nowUtc.add(const Duration(minutes: 9)),
          leaseDuration: const Duration(minutes: 10),
        ),
        isFalse,
      );
      expect(
        await otherStore.tryAcquireRunLease(
          ownerId: 'owner-a',
          leaseToken: 'run-c',
          nowUtc: nowUtc.add(const Duration(minutes: 10)),
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
    },
  );

  test(
    'owner-operation lease is one global gate across file-backed handles',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-owner-operation-gate-',
      );
      final path = '${directory.path}${Platform.pathSeparator}gate.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      final secondDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await secondDatabase.customSelect('SELECT 1').getSingle();
        final firstGate = DriftOwnerOperationGate(firstDatabase);
        final secondGate = DriftOwnerOperationGate(secondDatabase);

        expect(
          await firstGate.tryAcquire(
            token: 'token-a',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 10),
          ),
          isTrue,
        );
        expect(
          await secondGate.tryAcquire(
            token: 'token-b',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 10),
          ),
          isFalse,
          reason: 'all sync and owner transitions share one fixed gate',
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
    'owner-operation gate renews and fences stale tokens across reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-owner-operation-renew-',
      );
      final path = '${directory.path}${Platform.pathSeparator}gate.sqlite';
      var firstDatabase = AppDatabase(NativeDatabase(File(path)));
      var secondDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await secondDatabase.customSelect('SELECT 1').getSingle();
        var firstGate = DriftOwnerOperationGate(firstDatabase);
        var secondGate = DriftOwnerOperationGate(secondDatabase);

        expect(
          await firstGate.tryAcquire(
            token: 'token-a',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 9),
          ),
          isTrue,
        );
        await secondGate.release(token: 'wrong-token');
        expect(
          await firstGate.isOwned(token: 'token-a', nowUtc: nowUtc),
          isTrue,
        );
        expect(
          await firstGate.renew(
            token: 'token-a',
            nowUtc: nowUtc.add(const Duration(minutes: 3)),
            leaseDuration: const Duration(minutes: 9),
          ),
          isTrue,
        );
        expect(
          await secondGate.tryAcquire(
            token: 'token-b',
            nowUtc: nowUtc.add(const Duration(minutes: 9)),
            leaseDuration: const Duration(minutes: 9),
          ),
          isFalse,
          reason: 'renewal extends ownership beyond the original expiry',
        );

        await secondDatabase.close();
        await firstDatabase.close();
        firstDatabase = AppDatabase(NativeDatabase(File(path)));
        secondDatabase = AppDatabase(NativeDatabase(File(path)));
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await secondDatabase.customSelect('SELECT 1').getSingle();
        firstGate = DriftOwnerOperationGate(firstDatabase);
        secondGate = DriftOwnerOperationGate(secondDatabase);
        final renewedExpiry = nowUtc.add(const Duration(minutes: 12));

        expect(
          await secondGate.tryAcquire(
            token: 'token-b',
            nowUtc: renewedExpiry,
            leaseDuration: const Duration(minutes: 9),
          ),
          isTrue,
          reason: 'a crash-stale gate is reclaimable exactly at expiry',
        );
        expect(
          await firstGate.renew(
            token: 'token-a',
            nowUtc: renewedExpiry,
            leaseDuration: const Duration(minutes: 9),
          ),
          isFalse,
        );
        await firstGate.release(token: 'token-a');
        expect(
          await secondGate.isOwned(token: 'token-b', nowUtc: renewedExpiry),
          isTrue,
          reason: 'stale renew and release cannot affect the new owner',
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

  test('claims remain isolated to the requested local owner', () async {
    await _seedOneCategoryOperation(database);
    await _insertOwner(database, 'owner-b');
    await _insertCategory(
      database,
      ownerId: 'owner-b',
      id: 'category:private',
      name: 'Private',
    );
    await _insertOutbox(
      database,
      ownerId: 'owner-b',
      operationId: 'operation:private',
      entityId: 'category:private',
      baseRevision: 0,
      createdAtUtcMs: 2,
    );

    final claimed = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 10,
      leaseToken: 'lease-a',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    );
    final privateOperation = await (database.select(
      database.outboxOperations,
    )..where((row) => row.operationId.equals('operation:private'))).getSingle();

    expect(claimed, hasLength(1));
    expect(claimed.single.mutation.entityId, 'category:travel');
    expect(privateOperation.state, 'pending');
  });

  test('owner gate loss prevents stale claim acquisition', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    final staleClaims = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: lostAt,
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(staleClaims, isEmpty);
    expect(row.state, 'pending');
  });

  test('only an expired lease is reclaimable', () async {
    await _seedOneCategoryOperation(database);
    await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-a',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    );

    final early = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc.add(const Duration(minutes: 4)),
    );
    final recovered = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc.add(const Duration(minutes: 5)),
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(early, isEmpty);
    expect(recovered, hasLength(1));
    expect(recovered.single.leaseToken, 'lease-b');
    expect(row.attemptCount, 0);
  });

  test(
    'claim and reclaim preserve reservation count and retry metadata',
    () async {
      await _seedOneCategoryOperation(database);
      await (database.update(
            database.outboxOperations,
          )..where((row) => row.operationId.equals('category:travel:1:upsert')))
          .write(
            OutboxOperationsCompanion(
              state: const Value('retryWaiting'),
              attemptCount: const Value(2),
              nextAttemptAtUtcMs: Value(nowUtc.millisecondsSinceEpoch),
              failureCode: Value(SyncFailureCode.offline.name),
            ),
          );

      final first = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-a',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      )).single;
      final reclaimed = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-b',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc.add(const Duration(minutes: 5)),
      )).single;
      final row = await database.select(database.outboxOperations).getSingle();

      expect(first.attemptCount, 2);
      expect(reclaimed.attemptCount, 2);
      expect(reclaimed.mutation.operationId, 'category:travel:1:upsert');
      expect(row.attemptCount, 2);
      expect(row.nextAttemptAtUtcMs, nowUtc.millisecondsSinceEpoch);
      expect(row.failureCode, SyncFailureCode.offline.name);
    },
  );

  test('owner gate loss prevents a send reservation', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final leased = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    final attempted = await store.beginAttempt(
      claim: leased,
      ownerGateToken: 'owner-token-a',
      nowUtc: lostAt,
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(attempted, isNull);
    expect(row.attemptCount, 0);
    expect(row.lastAttemptAtUtcMs, isNull);
  });

  test(
    'duplicate acknowledgement cannot regress entity or later-row rebase',
    () async {
      await _seedOneCategoryOperation(database);
      final claim = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-a',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      )).single;
      final attempted = (await store.beginAttempt(
        claim: claim,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
      ))!;
      await (database.update(
        database.vocabularyCategories,
      )..where((row) => row.id.equals('category:travel'))).write(
        const VocabularyCategoriesCompanion(
          name: Value('Later edit'),
          normalizedName: Value('later edit'),
          localRevision: Value(2),
          updatedAtUtcMs: Value(2),
        ),
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:travel:2:upsert',
        entityId: 'category:travel',
        baseRevision: 0,
        createdAtUtcMs: 2,
      );
      final acknowledgement = PushAcknowledged(
        operationId: attempted.mutation.operationId,
        resultingRevision: 1,
        acknowledgedAtUtc: nowUtc.add(const Duration(seconds: 1)),
      );

      await store.acknowledge(
        operationId: acknowledgement.operationId,
        leaseToken: attempted.leaseToken,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        acknowledgement: acknowledgement,
      );
      await store.acknowledge(
        operationId: acknowledgement.operationId,
        leaseToken: attempted.leaseToken,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        acknowledgement: PushAcknowledged(
          operationId: acknowledgement.operationId,
          resultingRevision: 0,
          acknowledgedAtUtc: nowUtc,
        ),
      );

      final operations = await database.select(database.outboxOperations).get();
      final operation = operations.singleWhere(
        (row) => row.operationId == 'category:travel:1:upsert',
      );
      final later = operations.singleWhere(
        (row) => row.operationId == 'category:travel:2:upsert',
      );
      final category = await database
          .select(database.vocabularyCategories)
          .getSingle();
      expect(operation.state, 'acknowledged');
      expect(
        operation.acknowledgedAtUtcMs,
        nowUtc.millisecondsSinceEpoch + 1000,
      );
      expect(category.cloudRevision, 1);
      expect(category.localRevision, 2);
      expect(
        category.lastAcknowledgedAtUtcMs,
        nowUtc.millisecondsSinceEpoch + 1000,
      );
      expect(later.state, 'pending');
      expect(later.baseRevision, 1);
    },
  );

  test(
    'owner gate token fences late acknowledgement with a matching operation lease',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-stale-ack-',
      );
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      final firstDatabase = AppDatabase(NativeDatabase(File(path)));
      final secondDatabase = AppDatabase(NativeDatabase(File(path)));
      try {
        await firstDatabase.customSelect('SELECT 1').getSingle();
        await _insertOwner(firstDatabase, 'owner-a');
        await _seedOneCategoryOperation(firstDatabase);
        await secondDatabase.customSelect('SELECT 1').getSingle();
        final firstStore = DriftSyncStore(firstDatabase);
        final firstGate = DriftOwnerOperationGate(firstDatabase);
        final secondGate = DriftOwnerOperationGate(secondDatabase);
        expect(
          await firstGate.tryAcquire(
            token: 'owner-token-a',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 1),
          ),
          isTrue,
        );
        final leased = (await firstStore.claimPending(
          ownerId: 'owner-a',
          firebaseUid: 'firebase-a',
          limit: 1,
          leaseToken: 'operation-token-a',
          ownerGateToken: 'owner-token-a',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: nowUtc,
        )).single;
        final attempted = (await firstStore.beginAttempt(
          claim: leased,
          ownerGateToken: 'owner-token-a',
          nowUtc: nowUtc,
        ))!;
        await (firstDatabase.update(
          firstDatabase.vocabularyCategories,
        )..where((row) => row.id.equals('category:travel'))).write(
          const VocabularyCategoriesCompanion(
            name: Value('Later edit'),
            normalizedName: Value('later edit'),
            localRevision: Value(2),
            updatedAtUtcMs: Value(2),
          ),
        );
        await _insertOutbox(
          firstDatabase,
          ownerId: 'owner-a',
          operationId: 'category:travel:2:upsert',
          entityId: 'category:travel',
          baseRevision: 0,
          createdAtUtcMs: 2,
        );
        final reclaimedAt = nowUtc.add(const Duration(minutes: 1));
        expect(
          await secondGate.tryAcquire(
            token: 'owner-token-b',
            nowUtc: reclaimedAt,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );

        final applied = await firstStore.acknowledge(
          operationId: attempted.mutation.operationId,
          leaseToken: attempted.leaseToken,
          ownerGateToken: 'owner-token-a',
          nowUtc: reclaimedAt,
          acknowledgement: PushAcknowledged(
            operationId: attempted.mutation.operationId,
            resultingRevision: 1,
            acknowledgedAtUtc: reclaimedAt,
          ),
        );

        final rows = await firstDatabase
            .select(firstDatabase.outboxOperations)
            .get();
        final row = rows.singleWhere(
          (candidate) => candidate.operationId == 'category:travel:1:upsert',
        );
        final later = rows.singleWhere(
          (candidate) => candidate.operationId == 'category:travel:2:upsert',
        );
        final category = await firstDatabase
            .select(firstDatabase.vocabularyCategories)
            .getSingle();
        expect(applied, isFalse);
        expect(row.state, 'inFlight');
        expect(row.acknowledgedAtUtcMs, isNull);
        expect(later.state, 'pending');
        expect(later.baseRevision, 0);
        expect(category.localRevision, 2);
        expect(category.cloudRevision, 0);
        expect(category.lastAcknowledgedAtUtcMs, isNull);
      } finally {
        await secondDatabase.close();
        await firstDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );

  test('retry wait is not claimable before its due time', () async {
    await _seedOneCategoryOperation(database);
    final claim = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-a',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final attempted = (await store.beginAttempt(
      claim: claim,
      ownerGateToken: 'test-owner-gate',
      nowUtc: nowUtc,
    ))!;
    final dueAt = nowUtc.add(const Duration(minutes: 10));
    await store.markRetry(
      operationId: attempted.mutation.operationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: 'test-owner-gate',
      nowUtc: nowUtc,
      nextAttemptAtUtc: dueAt,
      failure: const OfflineSyncFailure(),
    );

    final early = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: dueAt.subtract(const Duration(milliseconds: 1)),
    );
    final due = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      ownerGateToken: 'test-owner-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: dueAt,
    );

    expect(early, isEmpty);
    expect(due, hasLength(1));
  });

  test('owner gate loss prevents a stale retry transition', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final leased = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final attempted = (await store.beginAttempt(
      claim: leased,
      ownerGateToken: 'owner-token-a',
      nowUtc: nowUtc,
    ))!;
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    await store.markRetry(
      operationId: attempted.mutation.operationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: 'owner-token-a',
      nowUtc: lostAt,
      nextAttemptAtUtc: lostAt.add(const Duration(minutes: 1)),
      failure: const OfflineSyncFailure(),
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(row.state, 'inFlight');
    expect(row.leaseToken, 'operation-token-a');
  });

  test('owner gate loss prevents a stale terminal transition', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final leased = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final attempted = (await store.beginAttempt(
      claim: leased,
      ownerGateToken: 'owner-token-a',
      nowUtc: nowUtc,
    ))!;
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    await store.markTerminalFailure(
      operationId: attempted.mutation.operationId,
      leaseToken: attempted.leaseToken,
      ownerGateToken: 'owner-token-a',
      nowUtc: lostAt,
      failure: const PermissionDeniedSyncFailure(),
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(row.state, 'inFlight');
    expect(row.leaseToken, 'operation-token-a');
  });

  test('owner gate loss prevents a stale claim release', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final leased = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    await store.releaseClaim(
      claim: leased,
      ownerGateToken: 'owner-token-a',
      nowUtc: lostAt,
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(row.state, 'inFlight');
    expect(row.leaseToken, 'operation-token-a');
  });

  test(
    'push conflict records evidence and applies acknowledged cloud state',
    () async {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:travel',
        name: 'Local edit',
        revision: 2,
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:travel:2:upsert',
        entityId: 'category:travel',
        baseRevision: 0,
        createdAtUtcMs: 1,
      );
      final claim = (await store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-a',
        ownerGateToken: 'test-owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      )).single;
      final attempted = (await store.beginAttempt(
        claim: claim,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
      ))!;

      await store.resolvePushConflict(
        claim: attempted,
        ownerGateToken: 'test-owner-gate',
        cloudEntity: SyncEntity(
          collection: SyncCollection.categories,
          entityId: 'category:travel',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: nowUtc,
          serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
          payload: const <String, Object?>{'name': 'Cloud edit'},
        ),
        resolvedAtUtc: nowUtc.add(const Duration(seconds: 2)),
      );

      final category = await database
          .select(database.vocabularyCategories)
          .getSingle();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();
      final conflict = await database
          .select(database.syncConflicts)
          .getSingle();
      expect(category.name, 'Cloud edit');
      expect(category.localRevision, 1);
      expect(category.cloudRevision, 1);
      expect(operation.state, 'conflictResolved');
      expect(conflict.outcome, 'cloudWins');
      expect(conflict.localSnapshotJson, isNotNull);
      expect(conflict.cloudSnapshotJson, isNotNull);
    },
  );

  test('owner gate loss prevents stale conflict resolution', () async {
    await _seedOneCategoryOperation(database);
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final leased = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'operation-token-a',
      ownerGateToken: 'owner-token-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final attempted = (await store.beginAttempt(
      claim: leased,
      ownerGateToken: 'owner-token-a',
      nowUtc: nowUtc,
    ))!;
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );

    await store.resolvePushConflict(
      claim: attempted,
      ownerGateToken: 'owner-token-a',
      cloudEntity: SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'category:travel',
        revision: 2,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: lostAt,
        serverUpdatedAtUtc: lostAt,
        payload: const <String, Object?>{'name': 'Cloud Travel'},
      ),
      resolvedAtUtc: lostAt,
    );

    final operation = await database
        .select(database.outboxOperations)
        .getSingle();
    final category = await database
        .select(database.vocabularyCategories)
        .getSingle();
    expect(operation.state, 'inFlight');
    expect(category.name, 'Travel');
    expect(await database.select(database.syncConflicts).get(), isEmpty);
  });

  test('failed pull transaction does not advance its checkpoint', () async {
    final page = PullPage(
      changes: <SyncEntity>[
        SyncEntity(
          collection: SyncCollection.words,
          entityId: 'word:orphan',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: nowUtc,
          serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
          payload: const <String, Object?>{
            'categoryId': 'category:missing',
            'spelling': 'orphan',
            'meaning': 'ไม่มีหมวด',
            'partOfSpeech': 'noun',
            'source': 'manual',
          },
        ),
      ],
      nextCursor: SyncCursor(
        serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        documentId: 'word:orphan',
      ),
      hasMore: false,
    );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.words,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: page,
      ),
      throwsA(anything),
    );

    expect(await store.readCheckpoint('owner-a', SyncCollection.words), isNull);
  });

  test(
    'legacy word payload preserves null storage and exposes canonical read identity',
    () async {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:travel',
        name: 'Travel',
      );
      final changedAt = nowUtc.add(const Duration(seconds: 1));
      final cursor = SyncCursor(
        serverUpdatedAtUtc: changedAt,
        documentId: 'word:station',
      );

      await store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.words,
        ownerGateToken: 'test-owner-gate',
        nowUtc: changedAt,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.words,
              entityId: 'word:station',
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: changedAt,
              serverUpdatedAtUtc: changedAt,
              payload: <String, Object?>{
                'categoryId': 'category:travel',
                'spelling': 'station',
                'normalizedSpelling': 'station',
                'meaning': 'สถานี',
                'normalizedMeaning': 'สถานี',
                'partOfSpeech': 'noun',
                'cefrLevel': null,
                'source': 'manual',
                'isGlobal': false,
                'isDeleted': false,
                'createdAtUtcMs': 0,
                'updatedAtUtcMs': changedAt.millisecondsSinceEpoch,
              },
            ),
          ],
          nextCursor: cursor,
          hasMore: false,
        ),
      );

      final word = await database.select(database.vocabularyWords).getSingle();
      expect(word.contentRevision, 1);
      expect(word.contentChecksumSha256, isNull);
      final readableWord =
          (await DriftLearningRepository(database).listQuizWords(
            ownerId: 'owner-a',
            categoryId: 'category:travel',
            limit: 1,
          )).single;
      expect(
        readableWord.contentChecksumSha256,
        ContentQualityPolicy.vocabularyChecksumSha256(
          categoryId: 'category:travel',
          spelling: 'station',
          normalizedSpelling: 'station',
          meaning: 'สถานี',
          normalizedMeaning: 'สถานี',
          partOfSpeech: 'noun',
          cefrLevel: null,
          source: 'manual',
          isGlobal: false,
        ),
      );
    },
  );

  test(
    'stored cursor rejects a lexicographically older cursor before mutation',
    () async {
      final timestamp = nowUtc.add(const Duration(seconds: 1));
      final storedCursor = SyncCursor(
        serverUpdatedAtUtc: timestamp,
        documentId: 'b',
      );
      await database
          .into(database.syncCheckpoints)
          .insert(
            SyncCheckpointsCompanion.insert(
              id: 'owner-a:categories',
              ownerId: 'owner-a',
              collectionName: SyncCollection.categories.wireName,
              serverCursor: Value(storedCursor.toJsonString()),
            ),
          );

      await expectLater(
        store.applyPullPage(
          ownerId: 'owner-a',
          collection: SyncCollection.categories,
          ownerGateToken: 'test-owner-gate',
          nowUtc: nowUtc,
          page: PullPage(
            changes: <SyncEntity>[
              SyncEntity(
                collection: SyncCollection.categories,
                entityId: 'a',
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: timestamp,
                serverUpdatedAtUtc: timestamp,
                payload: const <String, Object?>{'name': 'Regressing'},
              ),
            ],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: timestamp,
              documentId: 'a',
            ),
            hasMore: false,
          ),
        ),
        throwsA(isA<InvalidSyncCursorFailure>()),
      );

      expect(
        await (database.select(
          database.vocabularyCategories,
        )..where((row) => row.id.equals('a'))).get(),
        isEmpty,
      );
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.categories),
        storedCursor,
      );
    },
  );

  test('equal checkpoint replay is an idempotent no-op', () async {
    final timestamp = nowUtc.add(const Duration(seconds: 1));
    final cursor = SyncCursor(serverUpdatedAtUtc: timestamp, documentId: 'b');
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            id: 'owner-a:categories',
            ownerId: 'owner-a',
            collectionName: SyncCollection.categories.wireName,
            serverCursor: Value(cursor.toJsonString()),
          ),
        );

    await store.applyPullPage(
      ownerId: 'owner-a',
      collection: SyncCollection.categories,
      ownerGateToken: 'test-owner-gate',
      nowUtc: nowUtc,
      page: PullPage(
        changes: <SyncEntity>[
          SyncEntity(
            collection: SyncCollection.categories,
            entityId: 'b',
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: timestamp,
            serverUpdatedAtUtc: timestamp,
            payload: const <String, Object?>{'name': 'Replay'},
          ),
        ],
        nextCursor: cursor,
        hasMore: false,
      ),
    );

    expect(await database.select(database.vocabularyCategories).get(), isEmpty);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      cursor,
    );
  });

  test('empty page cannot advance beyond the stored cursor', () async {
    final timestamp = nowUtc.add(const Duration(seconds: 1));
    final stored = SyncCursor(serverUpdatedAtUtc: timestamp, documentId: 'a');
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            id: 'owner-a:categories',
            ownerId: 'owner-a',
            collectionName: SyncCollection.categories.wireName,
            serverCursor: Value(stored.toJsonString()),
          ),
        );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: const <SyncEntity>[],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: timestamp,
            documentId: 'b',
          ),
          hasMore: false,
        ),
      ),
      throwsA(isA<InvalidSyncCursorFailure>()),
    );

    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      stored,
    );
  });

  test('empty page without a checkpoint accepts only a null cursor', () async {
    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: const <SyncEntity>[],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: nowUtc,
            documentId: 'category:unseen',
          ),
          hasMore: false,
        ),
      ),
      throwsA(isA<InvalidSyncCursorFailure>()),
    );

    expect(
      await store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: const <SyncEntity>[],
          nextCursor: null,
          hasMore: false,
        ),
      ),
      isTrue,
    );
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      isNull,
    );
  });

  test('empty page may preserve its exact stored cursor', () async {
    final stored = SyncCursor(
      serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
      documentId: 'category:stored',
    );
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            id: 'owner-a:categories',
            ownerId: 'owner-a',
            collectionName: SyncCollection.categories.wireName,
            serverCursor: Value(stored.toJsonString()),
          ),
        );

    expect(
      await store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: const <SyncEntity>[],
          nextCursor: stored,
          hasMore: false,
        ),
      ),
      isTrue,
    );
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      stored,
    );
  });

  test(
    'mixed collection page is rejected before applying its first row',
    () async {
      final firstTimestamp = nowUtc.add(const Duration(seconds: 1));
      final secondTimestamp = firstTimestamp.add(const Duration(seconds: 1));

      await expectLater(
        store.applyPullPage(
          ownerId: 'owner-a',
          collection: SyncCollection.words,
          ownerGateToken: 'test-owner-gate',
          nowUtc: nowUtc,
          page: PullPage(
            changes: <SyncEntity>[
              SyncEntity(
                collection: SyncCollection.words,
                entityId: 'a-word-with-missing-category',
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: firstTimestamp,
                serverUpdatedAtUtc: firstTimestamp,
                payload: const <String, Object?>{
                  'categoryId': 'category:missing',
                  'spelling': 'first',
                  'meaning': 'first',
                  'partOfSpeech': 'noun',
                  'source': 'manual',
                },
              ),
              SyncEntity(
                collection: SyncCollection.categories,
                entityId: 'z-category',
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: secondTimestamp,
                serverUpdatedAtUtc: secondTimestamp,
                payload: const <String, Object?>{'name': 'Wrong collection'},
              ),
            ],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: secondTimestamp,
              documentId: 'z-category',
            ),
            hasMore: false,
          ),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );

      expect(await database.select(database.vocabularyWords).get(), isEmpty);
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.words),
        isNull,
      );
    },
  );

  test('hasMore without a cursor is transactionally invalid', () async {
    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: const <SyncEntity>[],
          nextCursor: null,
          hasMore: true,
        ),
      ),
      throwsA(isA<InvalidSyncCursorFailure>()),
    );

    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      isNull,
    );
    expect(await database.select(database.vocabularyCategories).get(), isEmpty);
  });

  test('hasMore with an equal cursor rolls back entity mutation', () async {
    final timestamp = nowUtc.add(const Duration(seconds: 1));
    final cursor = SyncCursor(serverUpdatedAtUtc: timestamp, documentId: 'b');
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            id: 'owner-a:categories',
            ownerId: 'owner-a',
            collectionName: SyncCollection.categories.wireName,
            serverCursor: Value(cursor.toJsonString()),
          ),
        );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.categories,
              entityId: 'b',
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: timestamp,
              serverUpdatedAtUtc: timestamp,
              payload: const <String, Object?>{'name': 'No progress'},
            ),
          ],
          nextCursor: cursor,
          hasMore: true,
        ),
      ),
      throwsA(isA<InvalidSyncCursorFailure>()),
    );

    expect(await database.select(database.vocabularyCategories).get(), isEmpty);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      cursor,
    );
  });

  test('hasMore with a regressing cursor rolls back entity mutation', () async {
    final timestamp = nowUtc.add(const Duration(seconds: 1));
    final storedCursor = SyncCursor(
      serverUpdatedAtUtc: timestamp,
      documentId: 'b',
    );
    await database
        .into(database.syncCheckpoints)
        .insert(
          SyncCheckpointsCompanion.insert(
            id: 'owner-a:categories',
            ownerId: 'owner-a',
            collectionName: SyncCollection.categories.wireName,
            serverCursor: Value(storedCursor.toJsonString()),
          ),
        );

    await expectLater(
      store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.categories,
              entityId: 'a',
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: timestamp,
              serverUpdatedAtUtc: timestamp,
              payload: const <String, Object?>{'name': 'Regression'},
            ),
          ],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: timestamp,
            documentId: 'a',
          ),
          hasMore: true,
        ),
      ),
      throwsA(isA<InvalidSyncCursorFailure>()),
    );

    expect(await database.select(database.vocabularyCategories).get(), isEmpty);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      storedCursor,
    );
  });

  test('owner gate loss fences a late pull-page completion', () async {
    final gate = DriftOwnerOperationGate(database);
    await gate.release(token: 'test-owner-gate');
    expect(
      await gate.tryAcquire(
        token: 'owner-token-a',
        nowUtc: nowUtc,
        leaseDuration: const Duration(minutes: 1),
      ),
      isTrue,
    );
    final lostAt = nowUtc.add(const Duration(minutes: 1));
    expect(
      await gate.tryAcquire(
        token: 'owner-token-b',
        nowUtc: lostAt,
        leaseDuration: const Duration(minutes: 5),
      ),
      isTrue,
    );
    final cursor = SyncCursor(
      serverUpdatedAtUtc: lostAt,
      documentId: 'category:late',
    );

    await store.applyPullPage(
      ownerId: 'owner-a',
      collection: SyncCollection.categories,
      ownerGateToken: 'owner-token-a',
      nowUtc: lostAt,
      page: PullPage(
        changes: <SyncEntity>[
          SyncEntity(
            collection: SyncCollection.categories,
            entityId: 'category:late',
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: lostAt,
            serverUpdatedAtUtc: lostAt,
            payload: const <String, Object?>{'name': 'Late'},
          ),
        ],
        nextCursor: cursor,
        hasMore: false,
      ),
    );

    expect(await database.select(database.vocabularyCategories).get(), isEmpty);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      isNull,
    );
  });

  test('successful pull commits entity and checkpoint together', () async {
    final cursor = SyncCursor(
      serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
      documentId: 'category:remote',
    );
    await store.applyPullPage(
      ownerId: 'owner-a',
      collection: SyncCollection.categories,
      ownerGateToken: 'test-owner-gate',
      nowUtc: nowUtc,
      page: PullPage(
        changes: <SyncEntity>[
          SyncEntity(
            collection: SyncCollection.categories,
            entityId: 'category:remote',
            revision: 4,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: nowUtc,
            serverUpdatedAtUtc: cursor.serverUpdatedAtUtc,
            payload: const <String, Object?>{'name': 'Remote'},
          ),
        ],
        nextCursor: cursor,
        hasMore: false,
      ),
    );

    final category = await (database.select(
      database.vocabularyCategories,
    )..where((row) => row.id.equals('category:remote'))).getSingle();
    expect(category.ownerId, 'owner-a');
    expect(category.localRevision, 4);
    expect(category.cloudRevision, 4);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      cursor,
    );
  });

  test(
    'pull conflict retires losing local outbox and records snapshots',
    () async {
      await _insertCategory(
        database,
        ownerId: 'owner-a',
        id: 'category:travel',
        name: 'Local edit',
        revision: 2,
      );
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'category:travel:2:upsert',
        entityId: 'category:travel',
        baseRevision: 0,
        createdAtUtcMs: 1,
      );
      final cursor = SyncCursor(
        serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        documentId: 'category:travel',
      );

      await store.applyPullPage(
        ownerId: 'owner-a',
        collection: SyncCollection.categories,
        ownerGateToken: 'test-owner-gate',
        nowUtc: nowUtc,
        page: PullPage(
          changes: <SyncEntity>[
            SyncEntity(
              collection: SyncCollection.categories,
              entityId: 'category:travel',
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: nowUtc,
              serverUpdatedAtUtc: cursor.serverUpdatedAtUtc,
              payload: const <String, Object?>{'name': 'Cloud edit'},
            ),
          ],
          nextCursor: cursor,
          hasMore: false,
        ),
      );

      final category = await database
          .select(database.vocabularyCategories)
          .getSingle();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();
      final conflicts = await database.select(database.syncConflicts).get();
      expect(category.name, 'Cloud edit');
      expect(operation.state, 'conflictResolved');
      expect(conflicts, hasLength(1));
      expect(conflicts.single.outcome, 'cloudWins');
    },
  );
}

Future<void> _insertOwner(AppDatabase database, String ownerId) {
  return database
      .into(database.localOwners)
      .insert(LocalOwnersCompanion.insert(id: ownerId, createdAtUtcMs: 0));
}

Future<void> _insertCategory(
  AppDatabase database, {
  required String ownerId,
  required String id,
  required String name,
  int revision = 1,
}) {
  return database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: id,
          ownerId: ownerId,
          name: name,
          normalizedName: name.toLowerCase(),
          localRevision: Value(revision),
          createdAtUtcMs: 0,
          updatedAtUtcMs: 0,
        ),
      );
}

Future<void> _insertOutbox(
  AppDatabase database, {
  required String ownerId,
  required String operationId,
  required String entityId,
  required int baseRevision,
  required int createdAtUtcMs,
}) {
  return database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: operationId,
          ownerId: ownerId,
          entityType: 'category',
          entityId: entityId,
          operationKind: 'upsert',
          baseRevision: Value(baseRevision),
          createdAtUtcMs: createdAtUtcMs,
        ),
      );
}

Future<void> _seedOneCategoryOperation(AppDatabase database) async {
  await _insertCategory(
    database,
    ownerId: 'owner-a',
    id: 'category:travel',
    name: 'Travel',
  );
  await _insertOutbox(
    database,
    ownerId: 'owner-a',
    operationId: 'category:travel:1:upsert',
    entityId: 'category:travel',
    baseRevision: 0,
    createdAtUtcMs: 1,
  );
}

final class _IdempotentFakeCloud {
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
