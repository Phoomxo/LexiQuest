import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/application/sync_status.dart';
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
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      );
      final rows = await database.select(database.outboxOperations).get();

      expect(claimed, hasLength(1));
      expect(claimed.single.mutation.operationId, 'category:travel:2:upsert');
      expect(claimed.single.mutation.baseRevision, 0);
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
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      ),
      store.claimPending(
        ownerId: 'owner-a',
        firebaseUid: 'firebase-a',
        limit: 1,
        leaseToken: 'lease-b',
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

  test('only an expired lease is reclaimable', () async {
    await _seedOneCategoryOperation(database);
    await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    );

    final early = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc.add(const Duration(minutes: 4)),
    );
    final recovered = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc.add(const Duration(minutes: 5)),
    );
    final row = await database.select(database.outboxOperations).getSingle();

    expect(early, isEmpty);
    expect(recovered, hasLength(1));
    expect(recovered.single.leaseToken, 'lease-b');
    expect(row.attemptCount, 2);
  });

  test('acknowledgement is idempotent and advances cloud revision', () async {
    await _seedOneCategoryOperation(database);
    final claim = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final acknowledgement = PushAcknowledged(
      operationId: claim.mutation.operationId,
      resultingRevision: 1,
      acknowledgedAtUtc: nowUtc.add(const Duration(seconds: 1)),
    );

    await store.acknowledge(
      operationId: acknowledgement.operationId,
      leaseToken: claim.leaseToken,
      acknowledgement: acknowledgement,
    );
    await store.acknowledge(
      operationId: acknowledgement.operationId,
      leaseToken: claim.leaseToken,
      acknowledgement: acknowledgement,
    );

    final operation = await database
        .select(database.outboxOperations)
        .getSingle();
    final category = await database
        .select(database.vocabularyCategories)
        .getSingle();
    expect(operation.state, 'acknowledged');
    expect(operation.acknowledgedAtUtcMs, nowUtc.millisecondsSinceEpoch + 1000);
    expect(category.cloudRevision, 1);
  });

  test('retry wait is not claimable before its due time', () async {
    await _seedOneCategoryOperation(database);
    final claim = (await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-a',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: nowUtc,
    )).single;
    final dueAt = nowUtc.add(const Duration(minutes: 10));
    await store.markRetry(
      operationId: claim.mutation.operationId,
      leaseToken: claim.leaseToken,
      nextAttemptAtUtc: dueAt,
      failure: const OfflineSyncFailure(),
    );

    final early = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: dueAt.subtract(const Duration(milliseconds: 1)),
    );
    final due = await store.claimPending(
      ownerId: 'owner-a',
      firebaseUid: 'firebase-a',
      limit: 1,
      leaseToken: 'lease-b',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: dueAt,
    );

    expect(early, isEmpty);
    expect(due, hasLength(1));
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
        leaseDuration: const Duration(minutes: 5),
        nowUtc: nowUtc,
      )).single;

      await store.resolvePushConflict(
        claim: claim,
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
        page: page,
      ),
      throwsA(anything),
    );

    expect(await store.readCheckpoint('owner-a', SyncCollection.words), isNull);
  });

  test('successful pull commits entity and checkpoint together', () async {
    final cursor = SyncCursor(
      serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
      documentId: 'category:remote',
    );
    await store.applyPullPage(
      ownerId: 'owner-a',
      collection: SyncCollection.categories,
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

  test(
    'status counts five live states and handled history independently',
    () async {
      for (final (index, state) in <String>[
        'pending',
        'retryWaiting',
        'inFlight',
        'blockedAuth',
        'permanentFailure',
        'acknowledged',
        'superseded',
        'conflictResolved',
      ].indexed) {
        await _insertOutbox(
          database,
          ownerId: 'owner-a',
          operationId: 'operation:$state',
          entityId: 'entity:$index',
          baseRevision: 0,
          createdAtUtcMs: index,
          state: state,
        );
      }
      for (var index = 0; index < 3; index++) {
        await _insertConflict(
          database,
          ownerId: 'owner-a',
          id: 'conflict:$index',
        );
      }

      final status = await store.watchCurrentOwnerSyncStatus().firstWhere(
        (snapshot) => snapshot != null,
      );

      expect(
        status,
        const SyncStatusSnapshot(
          ownerId: 'owner-a',
          pending: 1,
          retryWaiting: 1,
          inFlight: 1,
          blockedAuth: 1,
          permanentFailure: 1,
          handledConflicts: 3,
        ),
      );
      expect(
        await database.select(database.outboxOperations).get(),
        hasLength(8),
      );
      expect(await database.select(database.syncConflicts).get(), hasLength(3));
    },
  );

  test('status distinguishes an empty owner from no active owner', () async {
    final empty = await store.watchCurrentOwnerSyncStatus().firstWhere(
      (snapshot) => snapshot != null,
    );

    expect(
      empty,
      const SyncStatusSnapshot(
        ownerId: 'owner-a',
        pending: 0,
        retryWaiting: 0,
        inFlight: 0,
        blockedAuth: 0,
        permanentFailure: 0,
        handledConflicts: 0,
      ),
    );

    await (database.update(database.localOwners)
          ..where((row) => row.id.equals('owner-a')))
        .write(const LocalOwnersCompanion(isActive: Value(false)));

    expect(await store.watchCurrentOwnerSyncStatus().first, isNull);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(await database.select(database.syncConflicts).get(), isEmpty);
  });

  test(
    'status emits no previous owner snapshot after atomic owner switch',
    () async {
      await _insertOwner(database, 'owner-b', active: false);
      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'operation:a:1',
        entityId: 'entity:a:1',
        baseRevision: 0,
        createdAtUtcMs: 1,
      );
      for (var index = 0; index < 2; index++) {
        await _insertOutbox(
          database,
          ownerId: 'owner-b',
          operationId: 'operation:b:$index',
          entityId: 'entity:b:$index',
          baseRevision: 0,
          createdAtUtcMs: index,
          state: 'retryWaiting',
        );
      }
      final events = StreamIterator<SyncStatusSnapshot?>(
        store.watchCurrentOwnerSyncStatus(),
      );
      addTearDown(events.cancel);

      expect(await events.moveNext(), isTrue);
      expect(events.current, isNull);
      expect(await events.moveNext(), isTrue);
      expect(events.current?.ownerId, 'owner-a');
      expect(events.current?.pending, 1);
      expect(events.current?.retryWaiting, 0);

      await _insertOutbox(
        database,
        ownerId: 'owner-a',
        operationId: 'operation:a:2',
        entityId: 'entity:a:2',
        baseRevision: 0,
        createdAtUtcMs: 2,
      );
      expect(await events.moveNext(), isTrue);
      expect(events.current?.ownerId, 'owner-a');
      expect(events.current?.pending, 2);

      await database.transaction(() async {
        await _insertOutbox(
          database,
          ownerId: 'owner-a',
          operationId: 'operation:a:3',
          entityId: 'entity:a:3',
          baseRevision: 0,
          createdAtUtcMs: 3,
        );
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('owner-a')))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('owner-b')))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
      });

      expect(await events.moveNext(), isTrue);
      expect(events.current, isNull);
      expect(await events.moveNext(), isTrue);
      expect(events.current?.ownerId, 'owner-b');
      expect(events.current?.pending, 0);
      expect(events.current?.retryWaiting, 2);
    },
  );
}

Future<void> _insertOwner(
  AppDatabase database,
  String ownerId, {
  bool active = true,
}) {
  return database
      .into(database.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: ownerId,
          createdAtUtcMs: 0,
          isActive: Value(active),
        ),
      );
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
  String state = 'pending',
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
          state: Value(state),
          createdAtUtcMs: createdAtUtcMs,
        ),
      );
}

Future<void> _insertConflict(
  AppDatabase database, {
  required String ownerId,
  required String id,
}) {
  return database
      .into(database.syncConflicts)
      .insert(
        SyncConflictsCompanion.insert(
          id: id,
          ownerId: ownerId,
          entityType: 'category',
          entityId: 'entity:$id',
          localRevision: 1,
          cloudRevision: 2,
          resolutionPolicy: 'cloudWins',
          outcome: 'cloudWins',
          resolvedAtUtcMs: 1,
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
