import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  test(
    'offline open replays once after reopen and stays idempotent after a second reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-file-backed-sync-',
      );
      final path = '${directory.path}${Platform.pathSeparator}sync.sqlite';
      final gateway = _RestartCloud();
      var nowUtc = DateTime.utc(2026, 8, 9, 9);
      var leaseSequence = 0;

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      SyncEngine buildEngine(AppDatabase database) {
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        );
        return SyncEngine(
          owners: owners,
          store: DriftSyncStore(database),
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: nowUtc,
            expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(database),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => nowUtc,
          generateLeaseToken: () => 'restart-lease-${leaseSequence++}',
        );
      }

      try {
        var database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        await _seedRestartInventory(database);
        gateway.offline = true;

        final offline = await buildEngine(database).run();
        final offlineOperation = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(offline.status, SyncRunStatus.partialFailure);
        expect(offlineOperation.operationId, 'category:local:stable-operation');
        expect(offlineOperation.state, 'retryWaiting');
        expect(offlineOperation.attemptCount, 1);
        expect(gateway.applyCounts, isEmpty);
        nowUtc = DateTime.fromMillisecondsSinceEpoch(
          offlineOperation.nextAttemptAtUtcMs!,
          isUtc: true,
        );
        await database.close();

        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        gateway.offline = false;
        final replayed = await buildEngine(database).run();
        final acknowledged = await database
            .select(database.outboxOperations)
            .getSingle();
        final checkpoint = await DriftSyncStore(
          database,
        ).readCheckpoint('owner-a', SyncCollection.categories);
        final categoryIds =
            (await database.select(database.vocabularyCategories).get())
                .map((row) => row.id)
                .toSet();
        final acknowledgedAt = acknowledged.acknowledgedAtUtcMs;
        final successfulPushCalls = gateway.pushCalls;

        expect(replayed.status, SyncRunStatus.completed);
        expect(acknowledged.operationId, offlineOperation.operationId);
        expect(acknowledged.state, 'acknowledged');
        expect(acknowledgedAt, isNotNull);
        expect(categoryIds, {'category:local', 'category:remote'});
        expect(checkpoint, gateway.categoryCursor);
        expect(gateway.applyCounts, {'category:local:stable-operation': 1});
        await database.close();

        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        final secondReplay = await buildEngine(database).run();
        final stableOperation = await database
            .select(database.outboxOperations)
            .getSingle();
        final stableCheckpoint = await DriftSyncStore(
          database,
        ).readCheckpoint('owner-a', SyncCollection.categories);
        final stableCategoryIds =
            (await database.select(database.vocabularyCategories).get())
                .map((row) => row.id)
                .toSet();

        expect(secondReplay.status, SyncRunStatus.completed);
        expect(secondReplay.pushed, 0);
        expect(gateway.pushCalls, successfulPushCalls);
        expect(gateway.applyCounts, {'category:local:stable-operation': 1});
        expect(stableOperation.operationId, offlineOperation.operationId);
        expect(stableOperation.state, 'acknowledged');
        expect(stableOperation.acknowledgedAtUtcMs, acknowledgedAt);
        expect(stableCheckpoint, checkpoint);
        expect(stableCategoryIds, categoryIds);
        await database.close();
      } finally {
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );
}

final class _RestartCloud implements SyncGateway {
  bool offline = false;
  int pushCalls = 0;
  final Map<String, int> applyCounts = <String, int>{};
  final SyncCursor categoryCursor = SyncCursor(
    serverUpdatedAtUtc: DateTime.utc(2026, 8, 9, 9, 1),
    documentId: 'category:remote',
  );

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushCalls += 1;
    if (offline) throw const OfflineSyncFailure();
    applyCounts.update(
      mutation.operationId,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: categoryCursor.serverUpdatedAtUtc,
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    if (offline) throw const OfflineSyncFailure();
    if (collection != SyncCollection.categories) {
      return PullPage(
        changes: const <SyncEntity>[],
        nextCursor: after,
        hasMore: false,
      );
    }
    return PullPage(
      changes: <SyncEntity>[
        SyncEntity(
          collection: SyncCollection.categories,
          entityId: 'category:remote',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: categoryCursor.serverUpdatedAtUtc,
          serverUpdatedAtUtc: categoryCursor.serverUpdatedAtUtc,
          payload: const <String, Object?>{'name': 'Remote'},
        ),
      ],
      nextCursor: categoryCursor,
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: categoryCursor.serverUpdatedAtUtc,
    expiresAtUtc: categoryCursor.serverUpdatedAtUtc.add(
      const Duration(hours: 1),
    ),
  );
}

Future<void> _seedRestartInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
    "VALUES ('owner-a', 'firebase-a', 'firebaseBound', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) '
    "VALUES ('category:local', 'owner-a', 'Local', 'local', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO outbox_operations '
    '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
    'created_at_utc_ms) VALUES '
    "('category:local:stable-operation', 'owner-a', 'category', "
    "'category:local', 'upsert', 1)",
  );
}
