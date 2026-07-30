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

  SyncEngine engine({bool cloudEnabled = true, SyncMutex? mutex}) {
    return SyncEngine(
      owners: owners,
      store: store,
      gateway: gateway,
      policyProvider: () async => CloudSyncPolicy(
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

  test('owner without Firebase UID skips without claiming work', () async {
    owners.owner = identity.LocalOwner(id: 'owner-a', createdAtUtc: nowUtc);
    await _seedCategoryOperation(database);

    final result = await engine().run();
    final operation = await database
        .select(database.outboxOperations)
        .getSingle();

    expect(result.status, SyncRunStatus.skippedUnauthenticated);
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

Future<void> _seedCategoryOperation(AppDatabase database) async {
  await database
      .into(database.vocabularyCategories)
      .insert(
        VocabularyCategoriesCompanion.insert(
          id: 'category:travel',
          ownerId: 'owner-a',
          name: 'Travel',
          normalizedName: 'travel',
          createdAtUtcMs: 0,
          updatedAtUtcMs: 0,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: 'category:travel:1:upsert',
          ownerId: 'owner-a',
          entityType: 'category',
          entityId: 'category:travel',
          operationKind: 'upsert',
          createdAtUtcMs: 0,
        ),
      );
}
