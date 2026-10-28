import 'dart:async';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore store;
  late _OwnerRepository owners;
  late _FakeGateway gateway;
  late DateTime nowUtc;
  late int leaseCounter;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    nowUtc = DateTime.utc(2026, 7, 30, 9);
    leaseCounter = 0;
    owners = _OwnerRepository(
      identity.LocalOwner(
        id: 'owner-a',
        firebaseUid: 'firebase-a',
        createdAtUtc: nowUtc,
      ),
    );
    gateway = _FakeGateway(nowUtc);
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-a',
            firebaseUid: const Value('firebase-a'),
            accountState: const Value('firebaseBound'),
            createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
          ),
        );
  });

  tearDown(() async {
    await database.close();
  });

  SyncEngine engine({
    bool cloudEnabled = true,
    SyncMutex? mutex,
    SyncPolicyProvider? policyProvider,
  }) {
    return SyncEngine(
      owners: owners,
      store: store,
      gateway: gateway,
      policyProvider:
          policyProvider ??
          () async => CloudSyncPolicy(
            enabled: cloudEnabled,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: nowUtc,
            expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
          ),
      mutex: mutex ?? SyncMutex(),
      backoff: const SyncBackoff(jitterFraction: 0),
      nowUtc: () => nowUtc,
      generateLeaseToken: () => 'lease-${++leaseCounter}',
    );
  }

  test('cloud kill switch leaves pending local work untouched', () async {
    await _seedCategoryOperation(database);

    final result = await engine(cloudEnabled: false).run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.skippedCloudDisabled);
    expect(gateway.pushCalls, 0);
    expect(operation.state, 'pending');
  });

  test(
    'one run drains a vocabulary backlog larger than one push batch',
    () async {
      for (var index = 0; index < 51; index++) {
        final id = 'category:$index';
        await database
            .into(database.vocabularyCategories)
            .insert(
              VocabularyCategoriesCompanion.insert(
                id: id,
                ownerId: 'owner-a',
                name: 'Category $index',
                normalizedName: 'category $index',
                createdAtUtcMs: 0,
                updatedAtUtcMs: 0,
              ),
            );
        await database
            .into(database.outboxOperations)
            .insert(
              OutboxOperationsCompanion.insert(
                operationId: '$id:1:upsert',
                ownerId: 'owner-a',
                entityType: 'category',
                entityId: id,
                operationKind: 'upsert',
                createdAtUtcMs: 0,
              ),
            );
      }
      final result = await engine().run();
      expect(result.pushed, 51);
      expect(gateway.appliedOperationIds, hasLength(51));
    },
  );

  test(
    'one run follows advancing pull cursors until hasMore is false',
    () async {
      var categoryPages = 0;
      gateway.onPull = (collection, after, limit) async {
        if (collection != SyncCollection.categories) {
          return PullPage(changes: const [], nextCursor: after, hasMore: false);
        }
        categoryPages++;
        final id = 'pulled:$categoryPages';
        final timestamp = nowUtc.add(Duration(seconds: categoryPages));
        return PullPage(
          changes: [
            SyncEntity(
              collection: collection,
              entityId: id,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: timestamp,
              serverUpdatedAtUtc: timestamp,
              payload: {'name': id, 'normalizedName': id},
            ),
          ],
          nextCursor: SyncCursor(serverUpdatedAtUtc: timestamp, documentId: id),
          hasMore: categoryPages < 2,
        );
      };
      final result = await engine().run();
      expect(categoryPages, 2);
      expect(result.pulled, 2);
      expect(
        await database.select(database.vocabularyCategories).get(),
        hasLength(2),
      );
    },
  );

  test('hasMore with a stationary cursor fails instead of spinning', () async {
    gateway.onPull = (collection, after, limit) async => PullPage(
      changes: const [],
      nextCursor: after,
      hasMore: collection == SyncCollection.categories,
    );
    final result = await engine().run();
    expect(result.status, SyncRunStatus.partialFailure);
    expect(result.failures, 1);
  });

  test('pull budget retains a checkpoint and requests continuation', () async {
    var pages = 0;
    gateway.onPull = (collection, after, limit) async {
      if (collection != SyncCollection.categories) {
        return PullPage(changes: const [], nextCursor: after, hasMore: false);
      }
      pages++;
      final id = 'budget:$pages';
      final timestamp = nowUtc.add(Duration(seconds: pages));
      return PullPage(
        changes: [
          SyncEntity(
            collection: collection,
            entityId: id,
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: timestamp,
            serverUpdatedAtUtc: timestamp,
            payload: {'name': id, 'normalizedName': id},
          ),
        ],
        nextCursor: SyncCursor(serverUpdatedAtUtc: timestamp, documentId: id),
        hasMore: true,
      );
    };
    final result = await engine().run();
    expect(pages, SyncEngine.maxBatchesPerRun);
    expect(result.hasMoreWork, isTrue);
    expect(result.retryRecommended, isTrue);
    expect(
      (await store.readCheckpoint(
        'owner-a',
        SyncCollection.categories,
      ))!.documentId,
      'budget:$pages',
    );
  });

  test('pull cannot replace a checkpoint with an older cursor', () async {
    final checkpoint = SyncCursor(
      serverUpdatedAtUtc: nowUtc,
      documentId: 'z-last',
    );
    await store.applyPullPage(
      ownerId: 'owner-a',
      collection: SyncCollection.categories,
      page: PullPage(changes: const [], nextCursor: checkpoint, hasMore: false),
    );
    gateway.onPull = (collection, after, limit) async => PullPage(
      changes: const [],
      nextCursor: collection == SyncCollection.categories
          ? SyncCursor(serverUpdatedAtUtc: nowUtc, documentId: 'a-old')
          : after,
      hasMore: false,
    );
    final result = await engine().run();
    expect(result.status, SyncRunStatus.partialFailure);
    expect(result.failures, 1);
    expect(
      await store.readCheckpoint('owner-a', SyncCollection.categories),
      checkpoint,
    );
  });

  test('owner without Firebase UID skips without claiming work', () async {
    owners.owner = identity.LocalOwner(id: 'owner-a', createdAtUtc: nowUtc);
    await _seedCategoryOperation(database);
    var policyCalls = 0;

    final result = await engine(
      policyProvider: () async {
        policyCalls++;
        return CloudSyncPolicy(
          enabled: true,
          source: CloudSyncPolicySource.remote,
          fetchedAtUtc: nowUtc,
          expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
        );
      },
    ).run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.skippedUnauthenticated);
    expect(policyCalls, 0);
    expect(operation.state, 'pending');
  });

  test(
    'offline work retries then applies exactly once after reconnect',
    () async {
      await _seedCategoryOperation(database);
      gateway.pushFailure = const OfflineSyncFailure();
      final syncEngine = engine();

      final offlineResult = await syncEngine.run();
      var operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(offlineResult.status, SyncRunStatus.partialFailure);
      expect(operation.state, 'retryWaiting');
      expect(operation.nextAttemptAtUtcMs, isNotNull);

      nowUtc = DateTime.fromMillisecondsSinceEpoch(
        operation.nextAttemptAtUtcMs!,
        isUtc: true,
      );
      gateway.pushFailure = null;
      final onlineResult = await syncEngine.run();
      operation = await database.select(database.outboxOperations).getSingle();
      final replayResult = await syncEngine.run();

      expect(onlineResult.status, SyncRunStatus.completed);
      expect(operation.state, 'acknowledged');
      expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
      expect(replayResult.pushed, 0);
      expect(gateway.appliedOperationIds, hasLength(1));
    },
  );

  test(
    'unsupported legacy outbox is quarantined while valid work syncs once',
    () async {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'owner-b',
              firebaseUid: const Value('firebase-b'),
              accountState: const Value('firebaseBound'),
              createdAtUtcMs: nowUtc.millisecondsSinceEpoch,
              isActive: const Value(false),
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'legacy:time-segment:1:upsert',
              ownerId: 'owner-a',
              entityType: 'learningTimeSegment',
              entityId: 'legacy:time-segment:1',
              operationKind: 'upsert',
              createdAtUtcMs: 0,
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'legacy:other-owner:1:upsert',
              ownerId: 'owner-b',
              entityType: 'learningTimeSegment',
              entityId: 'legacy:other-owner:1',
              operationKind: 'upsert',
              createdAtUtcMs: 0,
            ),
          );
      await _seedCategoryOperation(database);

      final firstResult = await engine().run();
      final legacyAfterFirstRun =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('legacy:time-segment:1:upsert'),
              ))
              .getSingle();
      final validAfterFirstRun =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('category:travel:1:upsert'),
              ))
              .getSingle();
      final status = await store.watchCurrentOwnerSyncStatus().firstWhere(
        (snapshot) => snapshot != null,
      );

      final secondResult = await engine().run();
      final legacyAfterSecondRun =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('legacy:time-segment:1:upsert'),
              ))
              .getSingle();
      final otherOwnerOperation =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals('legacy:other-owner:1:upsert'),
              ))
              .getSingle();

      expect(firstResult.status, SyncRunStatus.completed);
      expect(firstResult.pushed, 1);
      expect(validAfterFirstRun.state, 'acknowledged');
      expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
      expect(legacyAfterFirstRun.state, 'permanentFailure');
      expect(legacyAfterFirstRun.failureCode, 'invalidPayload');
      expect(legacyAfterFirstRun.leaseToken, isNull);
      expect(legacyAfterFirstRun.leaseExpiresAtUtcMs, isNull);
      expect(legacyAfterFirstRun.acknowledgedAtUtcMs, isNull);
      expect(legacyAfterFirstRun.entityType, 'learningTimeSegment');
      expect(status!.permanentFailure, 1);
      expect(status.ownerId, 'owner-a');
      expect(otherOwnerOperation.state, 'pending');
      expect(otherOwnerOperation.attemptCount, 0);
      expect(secondResult.status, SyncRunStatus.completed);
      expect(secondResult.pushed, 0);
      expect(legacyAfterSecondRun.attemptCount, 1);
      expect(gateway.pushCalls, 1);
    },
  );

  test('invalid first batch does not hide later valid pending work', () async {
    for (var index = 0; index < SyncEngine.pushLimit; index++) {
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: '000-legacy:$index:1:upsert',
              ownerId: 'owner-a',
              entityType: 'learningTimeSegment',
              entityId: 'legacy:$index',
              operationKind: 'upsert',
              createdAtUtcMs: 0,
            ),
          );
    }
    await _seedCategoryOperation(database);

    final result = await engine().run();
    final valid =
        await (database.select(database.outboxOperations)..where(
              (row) => row.operationId.equals('category:travel:1:upsert'),
            ))
            .getSingle();
    final invalid = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('learningTimeSegment'))).get();

    expect(result.pushed, 1);
    expect(result.status, SyncRunStatus.completed);
    expect(result.hasMoreWork, isFalse);
    expect(valid.state, 'acknowledged');
    expect(invalid, hasLength(SyncEngine.pushLimit));
    expect(invalid.every((row) => row.state == 'permanentFailure'), isTrue);
    expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
  });

  test('invalid backlog respects budget and continues the next run', () async {
    final invalidCount = SyncEngine.pushLimit * SyncEngine.maxBatchesPerRun;
    for (var index = 0; index < invalidCount; index++) {
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: '000-legacy:$index:1:upsert',
              ownerId: 'owner-a',
              entityType: 'learningTimeSegment',
              entityId: 'legacy:$index',
              operationKind: 'upsert',
              createdAtUtcMs: 0,
            ),
          );
    }
    await _seedCategoryOperation(database);

    final first = await engine().run();
    final invalid = await (database.select(
      database.outboxOperations,
    )..where((row) => row.entityType.equals('learningTimeSegment'))).get();
    expect(first.pushed, 0);
    expect(first.hasMoreWork, isTrue);
    expect(first.retryRecommended, isTrue);
    expect(invalid.every((row) => row.state == 'permanentFailure'), isTrue);

    final second = await engine().run();
    expect(second.pushed, 1);
    expect(second.hasMoreWork, isFalse);
    expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
  });

  test('missing backing row still fails without quarantining work', () async {
    await database
        .into(database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: 'category:missing:1:upsert',
            ownerId: 'owner-a',
            entityType: 'category',
            entityId: 'category:missing',
            operationKind: 'upsert',
            createdAtUtcMs: 0,
          ),
        );

    await expectLater(engine().run(), throwsA(isA<StateError>()));
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(operation.state, 'pending');
    expect(operation.attemptCount, 0);
    expect(operation.failureCode, isNull);
    expect(operation.leaseToken, isNull);
    expect(operation.leaseExpiresAtUtcMs, isNull);
  });

  test(
    'a new process retries permission failures once after cloud recovery',
    () async {
      await _seedCategoryOperation(database);
      gateway.pushFailure = const PermissionDeniedSyncFailure();

      final deniedResult = await engine().run();
      var operation = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(deniedResult.status, SyncRunStatus.partialFailure);
      expect(operation.state, 'permanentFailure');
      expect(operation.failureCode, SyncFailureCode.permissionDenied.name);

      gateway.pushFailure = null;
      final recoveredResult = await engine().run();
      operation = await database.select(database.outboxOperations).getSingle();
      final replayResult = await engine().run();

      expect(recoveredResult.status, SyncRunStatus.completed);
      expect(operation.state, 'acknowledged');
      expect(gateway.appliedOperationIds, {'category:travel:1:upsert'});
      expect(replayResult.pushed, 0);
      expect(gateway.appliedOperationIds, hasLength(1));
    },
  );

  test('push conflict records evidence and selects cloud state', () async {
    await _seedCategoryOperation(database);
    gateway.pushResult = PushConflict(
      SyncEntity(
        collection: SyncCollection.categories,
        entityId: 'category:travel',
        revision: 2,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: nowUtc,
        serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        payload: const <String, Object?>{'name': 'Cloud Travel'},
      ),
    );

    final result = await engine().run();
    final category = await database
        .select(database.vocabularyCategories)
        .getSingle();
    final conflicts = await database.select(database.syncConflicts).get();

    expect(result.conflicts, 1);
    expect(category.name, 'Cloud Travel');
    expect(conflicts, hasLength(1));
  });

  test('separate foreground and background isolates cannot overlap', () async {
    await _seedCategoryOperation(database);
    final pushEntered = Completer<void>();
    final releasePush = Completer<void>();
    gateway.onPush = (mutation) async {
      pushEntered.complete();
      await releasePush.future;
      return PushAcknowledged(
        operationId: mutation.operationId,
        resultingRevision: mutation.localRevision,
        acknowledgedAtUtc: nowUtc,
      );
    };
    final foregroundEngine = engine(mutex: SyncMutex());
    final backgroundEngine = engine(mutex: SyncMutex());

    final firstRun = foregroundEngine.run();
    await pushEntered.future;
    final secondResult = await backgroundEngine.run();
    releasePush.complete();
    final firstResult = await firstRun;

    expect(secondResult.status, SyncRunStatus.alreadyRunning);
    expect(firstResult.status, SyncRunStatus.completed);
    expect(gateway.appliedOperationIds, hasLength(1));
  });

  test(
    'slow backlog retains the run lease across more than 300 pushes',
    () async {
      for (var index = 0; index < 351; index++) {
        await _seedCategoryOperation(
          database,
          id: 'category:$index',
          name: 'Category $index',
        );
      }
      final backgroundEngine = engine(mutex: SyncMutex());
      SyncRunResult? backgroundResult;
      gateway.onPush = (mutation) async {
        nowUtc = nowUtc.add(const Duration(seconds: 2));
        if (gateway.pushCalls == 301) {
          backgroundResult = await backgroundEngine.run();
        }
        return PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
      };

      final result = await engine(mutex: SyncMutex()).run();

      expect(backgroundResult?.status, SyncRunStatus.alreadyRunning);
      expect(result.status, SyncRunStatus.completed);
      expect(result.pushed, 351);
      expect(gateway.pushCalls, 351);
      expect(gateway.appliedOperationIds, hasLength(351));
    },
  );

  for (final successorAcquires in [false, true]) {
    test('push outliving its run lease leaves the claim for retry '
        'with successor=$successorAcquires', () async {
      await _seedCategoryOperation(database);
      gateway.onPush = (mutation) async {
        nowUtc = nowUtc.add(
          SyncEngine.runLeaseDuration + const Duration(seconds: 1),
        );
        if (successorAcquires) {
          expect(
            await store.tryAcquireRunLease(
              ownerId: 'owner-a',
              leaseToken: 'successor',
              nowUtc: nowUtc,
              leaseDuration: SyncEngine.runLeaseDuration,
            ),
            isTrue,
          );
        }
        return PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
      };

      final result = await engine().run();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();
      final lease =
          await (database.select(database.runtimeFlags)
                ..where((row) => row.key.equals('syncRunLease:owner-a')))
              .getSingleOrNull();

      expect(result.status, SyncRunStatus.partialFailure);
      expect(result.retryRecommended, isTrue);
      expect(result.hasMoreWork, isTrue);
      expect(result.pushed, 0);
      expect(operation.state, 'inFlight');
      expect(operation.acknowledgedAtUtcMs, isNull);
      expect(lease?.source, successorAcquires ? 'successor' : null);
    });
  }

  test(
    'pull outliving its run lease does not apply the page or cursor',
    () async {
      var pullCalls = 0;
      gateway.onPull = (collection, after, limit) async {
        pullCalls++;
        if (collection != SyncCollection.categories) {
          return PullPage(changes: const [], nextCursor: after, hasMore: false);
        }
        nowUtc = nowUtc.add(
          SyncEngine.runLeaseDuration + const Duration(seconds: 1),
        );
        final id = 'expired-pull:${collection.wireName}';
        return PullPage(
          changes: [
            SyncEntity(
              collection: collection,
              entityId: id,
              revision: 1,
              isDeleted: false,
              payloadVersion: 1,
              clientUpdatedAtUtc: nowUtc,
              serverUpdatedAtUtc: nowUtc,
              payload: {'name': id, 'normalizedName': id},
            ),
          ],
          nextCursor: SyncCursor(serverUpdatedAtUtc: nowUtc, documentId: id),
          hasMore: false,
        );
      };

      final result = await engine().run();

      expect(result.status, SyncRunStatus.partialFailure);
      expect(result.retryRecommended, isTrue);
      expect(result.hasMoreWork, isTrue);
      expect(result.pulled, 0);
      expect(pullCalls, 1);
      expect(
        await database.select(database.vocabularyCategories).get(),
        isEmpty,
      );
      expect(
        await store.readCheckpoint('owner-a', SyncCollection.categories),
        isNull,
      );
    },
  );

  test(
    'network failure after lease loss cannot change a successor claim',
    () async {
      await _seedCategoryOperation(database);
      gateway.onPush = (mutation) async {
        nowUtc = nowUtc.add(
          SyncEngine.runLeaseDuration + const Duration(seconds: 1),
        );
        expect(
          await store.tryAcquireRunLease(
            ownerId: 'owner-a',
            leaseToken: 'successor',
            nowUtc: nowUtc,
            leaseDuration: SyncEngine.runLeaseDuration,
          ),
          isTrue,
        );
        final claimed = await store.claimPending(
          ownerId: 'owner-a',
          firebaseUid: 'firebase-a',
          limit: 1,
          leaseToken: 'successor-operation',
          leaseDuration: SyncEngine.leaseDuration,
          nowUtc: nowUtc,
        );
        expect(claimed, hasLength(1));
        throw const OfflineSyncFailure();
      };

      final result = await engine().run();
      final operation = await database
          .select(database.outboxOperations)
          .getSingle();

      expect(result.status, SyncRunStatus.partialFailure);
      expect(result.retryRecommended, isTrue);
      expect(result.hasMoreWork, isTrue);
      expect(operation.state, 'inFlight');
      expect(operation.leaseToken, 'successor-operation');
      expect(operation.failureCode, isNull);
    },
  );
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

final class _FakeGateway implements SyncGateway {
  _FakeGateway(this.nowUtc);

  DateTime nowUtc;
  int pushCalls = 0;
  SyncFailure? pushFailure;
  PushResult? pushResult;
  Future<PushResult> Function(PushMutation mutation)? onPush;
  Future<PullPage> Function(
    SyncCollection collection,
    SyncCursor? after,
    int limit,
  )?
  onPull;
  final Set<String> appliedOperationIds = <String>{};

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    if (onPull case final handler?) return handler(collection, after, limit);
    return PullPage(changes: const [], nextCursor: after, hasMore: false);
  }

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushCalls++;
    final handler = onPush;
    if (handler != null) {
      final result = await handler(mutation);
      appliedOperationIds.add(mutation.operationId);
      return result;
    }
    final failure = pushFailure;
    if (failure != null) throw failure;
    final result =
        pushResult ??
        PushAcknowledged(
          operationId: mutation.operationId,
          resultingRevision: mutation.localRevision,
          acknowledgedAtUtc: nowUtc,
        );
    if (result is PushAcknowledged) {
      appliedOperationIds.add(mutation.operationId);
    }
    return result;
  }
}

Future<void> _seedCategoryOperation(
  AppDatabase database, {
  String id = 'category:travel',
  String name = 'Travel',
}) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: id,
          ownerId: 'owner-a',
          name: name,
          normalizedName: name.toLowerCase(),
          createdAtUtcMs: 0,
          updatedAtUtcMs: 0,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: '$id:1:upsert',
          ownerId: 'owner-a',
          entityType: 'category',
          entityId: id,
          operationKind: 'upsert',
          createdAtUtcMs: 0,
        ),
      );
}
