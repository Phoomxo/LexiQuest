import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/sync/application/sync_backoff.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_mutex.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  test(
    'complete guest inventory upgrades in order and replays stably after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-guest-upgrade-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      final nowUtc = DateTime.utc(2026, 8, 9, 10);
      final gateway = _UpgradeCloud(nowUtc);
      var leaseSequence = 0;

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      late AppDatabase syncDatabase;
      late AppDatabase upgradeDatabase;
      var syncDatabaseOpen = false;
      var upgradeDatabaseOpen = false;
      try {
        syncDatabase = openDatabase();
        syncDatabaseOpen = true;
        upgradeDatabase = openDatabase();
        upgradeDatabaseOpen = true;
        await syncDatabase.customSelect('SELECT 1').getSingle();
        await _seedCompleteSyncInventory(syncDatabase);
        await upgradeDatabase.customSelect('SELECT 1').getSingle();

        final owners = DriftLocalOwnerRepository(
          syncDatabase,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        );
        final syncEngine = SyncEngine(
          owners: owners,
          store: DriftSyncStore(syncDatabase),
          gateway: gateway,
          policyProvider: () async => CloudSyncPolicy(
            enabled: true,
            source: CloudSyncPolicySource.cache,
            fetchedAtUtc: nowUtc,
            expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
          ),
          ownerGate: DriftOwnerOperationGate(syncDatabase),
          mutex: SyncMutex(),
          backoff: const SyncBackoff(jitterFraction: 0),
          nowUtc: () => nowUtc,
          generateLeaseToken: () => 'upgrade-sync-${leaseSequence++}',
        );

        final upgradeWaitEntered = Completer<void>();
        final releaseUpgradeWait = Completer<void>();
        final secretDeletionEntered = Completer<void>();
        final releaseSecretDeletion = Completer<void>();
        final neverHeartbeat = Completer<void>();
        var ownerOperationSequence = 0;
        final ownerUpgrades = DriftOwnerUpgradeRepository(
          upgradeDatabase,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'upgrade-conflict',
          generateOwnerId: () => 'unexpected-guest',
          generateOwnerOperationToken: () =>
              'upgrade-owner-operation-${ownerOperationSequence++}',
          deleteOwnerSecrets: (_) async {
            secretDeletionEntered.complete();
            await releaseSecretDeletion.future;
          },
          ownerGateDelay: (delay) {
            if (delay == const Duration(milliseconds: 50)) {
              if (!upgradeWaitEntered.isCompleted) {
                upgradeWaitEntered.complete();
              }
              return releaseUpgradeWait.future;
            }
            return neverHeartbeat.future;
          },
        );
        final upgradeGuestOwner = UpgradeGuestOwner(ownerUpgrades);

        final oldSync = syncEngine.run();
        await gateway.firstPushEntered.future;
        var upgradeCompleted = false;
        final upgrading = upgradeGuestOwner(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        ).whenComplete(() => upgradeCompleted = true);
        await upgradeWaitEntered.future;
        expect(upgradeCompleted, isFalse);
        expect(gateway.pushFirebaseUids, ['anonymous-old']);

        gateway.releaseFirstPush.complete();
        final oldResult = await oldSync;
        expect(oldResult.status, SyncRunStatus.completed);
        expect(gateway.pushFirebaseUids, everyElement('anonymous-old'));
        releaseUpgradeWait.complete();
        await secretDeletionEntered.future;

        final callsWhileUpgradeHeld = gateway.totalProviderCalls;
        final triggerWaitEntered = Completer<void>();
        final releaseTriggerWait = Completer<void>();
        final trigger = SyncTrigger(
          syncEngine.run,
          retryDelay: (_) {
            if (!triggerWaitEntered.isCompleted) {
              triggerWaitEntered.complete();
            }
            return releaseTriggerWait.future;
          },
        );
        final requestedDuringUpgrade = trigger.request(
          SyncTriggerReason.accountBinding,
        );
        await triggerWaitEntered.future;
        expect(gateway.totalProviderCalls, callsWhileUpgradeHeld);

        releaseSecretDeletion.complete();
        final upgradeResult = await upgrading;
        expect(upgradeResult.targetOwnerId, 'account-owner');
        expect(upgradeResult.mode, OwnerUpgradeMode.mergedExisting);
        releaseTriggerWait.complete();
        final newResult = await requestedDuringUpgrade;
        expect(newResult.status, SyncRunStatus.completed);

        final oldNamespaceCalls = gateway.pushFirebaseUids
            .where((uid) => uid == 'anonymous-old')
            .length;
        expect(oldNamespaceCalls, 7);
        expect(gateway.pushFirebaseUids.skip(oldNamespaceCalls), isNotEmpty);
        expect(
          gateway.pushFirebaseUids.skip(oldNamespaceCalls),
          everyElement('firebase-new'),
        );
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(gateway.namespaceApplyCounts, hasLength(14));

        final beforeReopen = await _inventorySnapshot(syncDatabase);
        expect(beforeReopen['activeOwnerId'], 'account-owner');
        expect(beforeReopen['operationTypes'], _sevenEntityTypes);
        expect(beforeReopen['checkpointCount'], 7);
        expect(beforeReopen['guestInventoryCount'], 0);

        await upgradeDatabase.close();
        upgradeDatabaseOpen = false;
        await syncDatabase.close();
        syncDatabaseOpen = false;

        syncDatabase = openDatabase();
        syncDatabaseOpen = true;
        await syncDatabase.customSelect('SELECT 1').getSingle();
        final replayRepository = DriftOwnerUpgradeRepository(
          syncDatabase,
          nowUtc: () => nowUtc.add(const Duration(minutes: 1)),
          generateConflictId: () => 'replay-conflict',
          generateOwnerId: () => 'replay-owner',
          generateOwnerOperationToken: () => 'replay-owner-operation',
          deleteOwnerSecrets: (_) async {
            fail('already-bound replay must not delete secrets');
          },
        );
        final replayed = await UpgradeGuestOwner(replayRepository)(
          activeOwnerId: 'account-owner',
          firebaseUid: 'firebase-new',
        );
        final afterReopen = await _inventorySnapshot(syncDatabase);

        expect(replayed.mode, OwnerUpgradeMode.alreadyBound);
        expect(replayed.targetOwnerId, 'account-owner');
        expect(afterReopen, beforeReopen);
        await syncDatabase.close();
        syncDatabaseOpen = false;
      } finally {
        if (upgradeDatabaseOpen) await upgradeDatabase.close();
        if (syncDatabaseOpen) await syncDatabase.close();
        await directory.delete(recursive: true);
        driftRuntimeOptions.dontWarnAboutMultipleDatabases =
            previousWarningSetting;
      }
    },
  );
}

const Set<String> _sevenEntityTypes = <String>{
  'category',
  'word',
  'attempt',
  'readingEvent',
  'rewardTransaction',
  'srsState',
  'achievementUnlock',
};

final class _UpgradeCloud implements SyncGateway {
  _UpgradeCloud(this.nowUtc);

  final DateTime nowUtc;
  final Completer<void> firstPushEntered = Completer<void>();
  final Completer<void> releaseFirstPush = Completer<void>();
  final List<String> pushFirebaseUids = <String>[];
  final List<String> pullFirebaseUids = <String>[];
  final Map<String, int> namespaceApplyCounts = <String, int>{};

  int get totalProviderCalls =>
      pushFirebaseUids.length + pullFirebaseUids.length;

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushFirebaseUids.add(mutation.firebaseUid);
    if (!firstPushEntered.isCompleted) {
      firstPushEntered.complete();
      await releaseFirstPush.future;
    }
    final namespaceKey = '${mutation.firebaseUid}:${mutation.operationId}';
    namespaceApplyCounts.update(
      namespaceKey,
      (count) => count + 1,
      ifAbsent: () => 1,
    );
    return PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: nowUtc,
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async {
    pullFirebaseUids.add(firebaseUid);
    return PullPage(
      changes: const <SyncEntity>[],
      nextCursor: SyncCursor(
        serverUpdatedAtUtc: nowUtc.add(const Duration(seconds: 1)),
        documentId: 'z:${collection.wireName}',
      ),
      hasMore: false,
    );
  }

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );
}

Future<Map<String, Object>> _inventorySnapshot(AppDatabase database) async {
  const inventoryTables = <String>[
    'vocabulary_categories',
    'vocabulary_words',
    'answer_attempts',
    'reading_events',
    'reward_transactions',
    'srs_states',
    'achievement_unlocks',
  ];
  final rowIds = <String>[];
  var guestInventoryCount = 0;
  for (final table in inventoryTables) {
    final rows = await database
        .customSelect('SELECT id, owner_id FROM $table ORDER BY id')
        .get();
    rowIds.addAll(rows.map((row) => '$table:${row.read<String>('id')}'));
    guestInventoryCount += rows
        .where((row) => row.read<String>('owner_id') == 'guest-owner')
        .length;
  }
  final operations = await database
      .customSelect(
        'SELECT operation_id, entity_type, entity_id, attempt_count, state '
        'FROM outbox_operations ORDER BY operation_id',
      )
      .get();
  final checkpoints = await database
      .customSelect(
        'SELECT id, server_cursor FROM sync_checkpoints ORDER BY id',
      )
      .get();
  final activeOwner = await database
      .customSelect('SELECT id FROM local_owners WHERE is_active = 1')
      .getSingle();

  return <String, Object>{
    'activeOwnerId': activeOwner.read<String>('id'),
    'rowIds': rowIds,
    'operationRows': operations
        .map(
          (row) =>
              '${row.read<String>('operation_id')}|'
              '${row.read<String>('entity_type')}|'
              '${row.read<String>('entity_id')}|'
              '${row.read<int>('attempt_count')}|'
              '${row.read<String>('state')}',
        )
        .toList(),
    'operationTypes': operations
        .map((row) => row.read<String>('entity_type'))
        .toSet(),
    'checkpointRows': checkpoints
        .map(
          (row) =>
              '${row.read<String>('id')}|${row.readNullable<String>('server_cursor')}',
        )
        .toList(),
    'checkpointCount': checkpoints.length,
    'guestInventoryCount': guestInventoryCount,
  };
}

Future<void> _seedCompleteSyncInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('guest-owner', 'anonymous-old', 'firebaseBound', 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('account-owner', 'firebase-new', 'firebaseBound', 2, 0)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, is_global, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'station', 'station', 'noun', 'manual', 0, 1, 0, 0, 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES ('session-1', 'guest-owner', "
    "'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    "INSERT INTO answer_attempts VALUES ('attempt-1', 'guest-owner', "
    "'session-1', 'word-1', 'meaning', 1, 100, 1, 2, NULL)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES ('srs-1', 'guest-owner', 'word-1', "
    '1, 1, 1, 1, 0, 2, 3, 1)',
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES ('reading-1', 'guest-owner', "
    "'doc-1', 1, 'position', 5, 2)",
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES ('reading-progress-1', "
    "'guest-owner', 'doc-1', 1, 5, 0, 2)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES ('points-1', 'guest-owner', "
    "'seed-points', 'learning', 200, NULL, 2)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES ('reward-1', 'guest-owner', "
    "'reward-key-1', 'purchase', -80, 'theme_ocean', 1, NULL, 2)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES ('achievement-1', 'guest-owner', "
    "'first-answer', 1, 'attempt-1', 2)",
  );

  const operations = <(String, String, String)>[
    ('operation:category', 'category', 'category-1'),
    ('operation:word', 'word', 'word-1'),
    ('operation:attempt', 'attempt', 'attempt-1'),
    ('operation:reading', 'readingEvent', 'reading-1'),
    ('operation:reward', 'rewardTransaction', 'reward-1'),
    ('operation:srs', 'srsState', 'word-1'),
    ('operation:achievement', 'achievementUnlock', 'achievement-1'),
  ];
  var createdAt = 1;
  for (final operation in operations) {
    await database.customInsert(
      'INSERT INTO outbox_operations '
      '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
      'created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(operation.$1),
        const Variable<String>('guest-owner'),
        Variable<String>(operation.$2),
        Variable<String>(operation.$3),
        const Variable<String>('upsert'),
        Variable<int>(createdAt++),
      ],
    );
  }
}
