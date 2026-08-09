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
        expect(beforeReopen['checkpointCount'], 0);
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

  test(
    'anonymous bind preserves complete inventory and replays once after reopen',
    () async {
      final previousWarningSetting =
          driftRuntimeOptions.dontWarnAboutMultipleDatabases;
      driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-anonymous-bind-',
      );
      final path = '${directory.path}${Platform.pathSeparator}upgrade.sqlite';
      var nowUtc = DateTime.utc(2026, 8, 9, 11);
      var leaseSequence = 0;
      var conflictSequence = 0;
      var operationTokenSequence = 0;
      final gateway = _AnonymousBoundCloud(nowUtc);

      AppDatabase openDatabase() => AppDatabase(NativeDatabase(File(path)));
      SyncEngine buildEngine(AppDatabase database) => SyncEngine(
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'unexpected-owner',
          nowUtc: () => nowUtc,
        ),
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
        generateLeaseToken: () => 'anonymous-bind-${leaseSequence++}',
      );

      AppDatabase? database;
      try {
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        await _seedAnonymousBoundCompleteInventory(database);
        final seededInventory = await _completeInventoryIdentity(database);
        final seededCounts = await _completeInventoryCounts(database);
        final seededForeign = await _foreignOwnerSnapshot(database);

        expect(seededCounts.keys.toSet(), ownerUpgradeInventory);
        expect(seededCounts.values, everyElement(greaterThanOrEqualTo(1)));
        expect(await _tableCount(database, 'vocabulary_import_rows'), 2);
        expect(await _tableCount(database, 'quest_objective_progress'), 2);
        expect(await _projectionEventCount(database, 'guest-owner'), 2);
        expect(await _projectionEventCount(database, 'foreign-owner'), 2);

        final repository = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'bind-${conflictSequence++}',
          generateOwnerId: () => 'unexpected-guest',
          generateOwnerOperationToken: () =>
              'bind-operation-${operationTokenSequence++}',
          deleteOwnerSecrets: (_) async {
            fail('anonymous bind must not delete external owner secrets');
          },
        );
        final bound = await UpgradeGuestOwner(repository)(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        );
        final ownerAfterBind = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
        final resetOperations = await database
            .customSelect(
              'SELECT operation_id, attempt_count, state, failure_code '
              'FROM outbox_operations WHERE owner_id = ? '
              'ORDER BY operation_id',
              variables: [const Variable<String>('guest-owner')],
            )
            .get();

        expect(bound.mode, OwnerUpgradeMode.anonymousBound);
        expect(bound.targetOwnerId, 'guest-owner');
        expect(ownerAfterBind.id, 'guest-owner');
        expect(ownerAfterBind.firebaseUid, 'firebase-new');
        expect(ownerAfterBind.isActive, isTrue);
        expect(await _completeInventoryIdentity(database), seededInventory);
        expect(await _completeInventoryCounts(database), seededCounts);
        expect(await _foreignOwnerSnapshot(database), seededForeign);
        expect(
          resetOperations.map((row) => row.read<int>('attempt_count')),
          everyElement(0),
        );
        expect(
          resetOperations.map((row) => row.read<String>('state')),
          everyElement('pending'),
        );
        expect(
          resetOperations.map(
            (row) => row.readNullable<String>('failure_code'),
          ),
          everyElement(isNull),
        );
        final invariantGate = DriftOwnerOperationGate(database);
        expect(
          await invariantGate.tryAcquire(
            token: 'verify-srs-rehome',
            nowUtc: nowUtc,
            leaseDuration: const Duration(minutes: 5),
          ),
          isTrue,
        );
        final invariantStore = DriftSyncStore(database);
        final rehomedClaims = await invariantStore.claimPending(
          ownerId: 'guest-owner',
          firebaseUid: 'firebase-new',
          limit: 20,
          leaseToken: 'verify-srs-rehome-lease',
          ownerGateToken: 'verify-srs-rehome',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: nowUtc,
        );
        final rehomedSrs = rehomedClaims.singleWhere(
          (claim) => claim.mutation.collection == SyncCollection.srsStates,
        );
        expect(rehomedSrs.mutation.operationId, 'operation:srs');
        expect(
          rehomedSrs.mutation.localRevision,
          greaterThan(rehomedSrs.mutation.baseRevision),
        );
        for (final claim in rehomedClaims) {
          expect(
            await invariantStore.releaseClaim(
              claim: claim,
              ownerGateToken: 'verify-srs-rehome',
              nowUtc: nowUtc,
            ),
            isTrue,
          );
        }
        await invariantGate.release(token: 'verify-srs-rehome');

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        final firstReplay = await buildEngine(database).run();
        final afterReplay = await _completeInventorySnapshot(database);

        expect(firstReplay.status, SyncRunStatus.completed);
        expect(firstReplay.pushed, 7);
        expect(gateway.pushFirebaseUids, everyElement('firebase-new'));
        expect(gateway.namespaceApplyCounts, hasLength(7));
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(afterReplay['activeOwnerId'], 'guest-owner');
        expect(afterReplay['inventoryIdentity'], seededInventory);
        expect(afterReplay['inventoryCounts'], seededCounts);
        expect(afterReplay['operationTypes'], _sevenEntityTypes);
        expect(await _foreignOwnerSnapshot(database), seededForeign);
        expect(
          afterReplay['operationRows'],
          everyElement(contains('|acknowledged|1|')),
        );
        final pushesAfterReplay = gateway.pushFirebaseUids.length;

        await database.close();
        database = openDatabase();
        await database.customSelect('SELECT 1').getSingle();
        nowUtc = nowUtc.add(const Duration(minutes: 1));
        final replayRepository = DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => nowUtc,
          generateConflictId: () => 'replay-${conflictSequence++}',
          generateOwnerId: () => 'unexpected-replay-owner',
          generateOwnerOperationToken: () =>
              'replay-operation-${operationTokenSequence++}',
          deleteOwnerSecrets: (_) async {
            fail('already-bound replay must not delete external secrets');
          },
        );
        final replayedBinding = await UpgradeGuestOwner(replayRepository)(
          activeOwnerId: 'guest-owner',
          firebaseUid: 'firebase-new',
        );
        final secondReplay = await buildEngine(database).run();
        final stable = await _completeInventorySnapshot(database);

        expect(replayedBinding.mode, OwnerUpgradeMode.alreadyBound);
        expect(replayedBinding.targetOwnerId, 'guest-owner');
        expect(secondReplay.status, SyncRunStatus.completed);
        expect(secondReplay.pushed, 0);
        expect(gateway.pushFirebaseUids, hasLength(pushesAfterReplay));
        expect(gateway.namespaceApplyCounts.values, everyElement(1));
        expect(stable, afterReplay);
        expect(await _foreignOwnerSnapshot(database), seededForeign);
      } finally {
        await database?.close();
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
      nextCursor: after,
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

final class _AnonymousBoundCloud implements SyncGateway {
  _AnonymousBoundCloud(this.nowUtc);

  final DateTime nowUtc;
  final List<String> pushFirebaseUids = <String>[];
  final Map<String, int> namespaceApplyCounts = <String, int>{};
  final Map<String, PushAcknowledged> acknowledgements =
      <String, PushAcknowledged>{};

  @override
  Future<PushResult> push(PushMutation mutation) async {
    pushFirebaseUids.add(mutation.firebaseUid);
    final key = '${mutation.firebaseUid}:${mutation.operationId}';
    final existing = acknowledgements[key];
    if (existing != null) return existing;
    namespaceApplyCounts.update(key, (count) => count + 1, ifAbsent: () => 1);
    final acknowledgement = PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: nowUtc,
    );
    acknowledgements[key] = acknowledgement;
    return acknowledgement;
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async => PullPage(
    changes: const <SyncEntity>[],
    nextCursor: after,
    hasMore: false,
  );

  @override
  Future<CloudSyncPolicy> fetchPolicy() async => CloudSyncPolicy(
    enabled: true,
    source: CloudSyncPolicySource.remote,
    fetchedAtUtc: nowUtc,
    expiresAtUtc: nowUtc.add(const Duration(hours: 1)),
  );
}

const Map<String, String> _inventoryIdentityColumns = <String, String>{
  'research_consents': 'id',
  'vocabulary_categories': 'id',
  'vocabulary_words': 'id',
  'vocabulary_imports': 'id',
  'vocabulary_import_rows': 'id',
  'learning_sessions': 'id',
  'answer_attempts': 'id',
  'srs_states': 'id',
  'reading_progress_entries': 'id',
  'reading_events': 'id',
  'points_ledger_entries': 'id',
  'achievement_unlocks': 'id',
  'reward_transactions': 'id',
  'owned_reward_items': 'id',
  'equipped_reward_items': 'id',
  'outbox_operations': 'operation_id',
  'sync_checkpoints': 'id',
  'sync_conflicts': 'id',
  'events_v2': 'event_id',
  'quest_instances': 'instance_id',
  'quest_objective_progress': 'id',
  'streak_states': 'owner_id',
  'learning_day_log': 'id',
  'association_records': 'id',
  'associative_memory_states': 'id',
  'speech_evidence': 'id',
  'ai_usage_events': "owner_id || ':' || event_id",
};

Future<Map<String, List<String>>> _completeInventoryIdentity(
  AppDatabase database,
) async {
  final result = <String, List<String>>{};
  for (final entry in _inventoryIdentityColumns.entries) {
    final rows = await database
        .customSelect(
          'SELECT ${entry.value} AS row_identity FROM ${entry.key} '
          'ORDER BY row_identity',
        )
        .get();
    result[entry.key] = rows
        .map((row) => row.read<String>('row_identity'))
        .toList();
  }
  return result;
}

Future<Map<String, int>> _completeInventoryCounts(AppDatabase database) async {
  final result = <String, int>{};
  for (final table in ownerUpgradeInventory) {
    result[table] = await _tableCount(database, table);
  }
  return result;
}

Future<int> _tableCount(AppDatabase database, String table) => database
    .customSelect('SELECT COUNT(*) AS count FROM $table')
    .getSingle()
    .then((row) => row.read<int>('count'));

Future<int> _projectionEventCount(AppDatabase database, String ownerId) =>
    database
        .customSelect(
          'SELECT COUNT(*) AS count FROM events_v2 '
          'WHERE owner_id = ? AND event_type LIKE ?',
          variables: [
            Variable<String>(ownerId),
            const Variable<String>('LearningProjection%'),
          ],
        )
        .getSingle()
        .then((row) => row.read<int>('count'));

Future<Map<String, List<String>>> _foreignOwnerSnapshot(
  AppDatabase database,
) async {
  final result = <String, List<String>>{};
  final ownerRows = await database
      .customSelect(
        'SELECT * FROM local_owners WHERE id = ?',
        variables: [const Variable<String>('foreign-owner')],
      )
      .get();
  result['local_owners'] = ownerRows.map(_rowFingerprint).toList();
  for (final table in ownerUpgradeInventory) {
    final rows = await database
        .customSelect(
          'SELECT * FROM $table WHERE owner_id = ? ORDER BY rowid',
          variables: [const Variable<String>('foreign-owner')],
        )
        .get();
    result[table] = rows.map(_rowFingerprint).toList();
  }
  final importRows = await database
      .customSelect(
        'SELECT child.* FROM vocabulary_import_rows AS child '
        'JOIN vocabulary_imports AS parent ON parent.id = child.import_id '
        'WHERE parent.owner_id = ? ORDER BY child.rowid',
        variables: [const Variable<String>('foreign-owner')],
      )
      .get();
  result['vocabulary_import_rows'] = importRows.map(_rowFingerprint).toList();
  final objectiveRows = await database
      .customSelect(
        'SELECT child.* FROM quest_objective_progress AS child '
        'JOIN quest_instances AS parent '
        'ON parent.instance_id = child.instance_id '
        'WHERE parent.owner_id = ? ORDER BY child.rowid',
        variables: [const Variable<String>('foreign-owner')],
      )
      .get();
  result['quest_objective_progress'] = objectiveRows
      .map(_rowFingerprint)
      .toList();
  return result;
}

String _rowFingerprint(QueryRow row) {
  final entries = row.data.entries.toList()
    ..sort((left, right) => left.key.compareTo(right.key));
  return entries
      .map((entry) => '${entry.key}:${entry.value.runtimeType}:${entry.value}')
      .join('|');
}

Future<Map<String, Object>> _completeInventorySnapshot(
  AppDatabase database,
) async {
  final owner = await (database.select(
    database.localOwners,
  )..where((row) => row.isActive.equals(true))).getSingle();
  final operations = await database
      .customSelect(
        'SELECT operation_id, entity_type, entity_id, state, attempt_count, '
        'acknowledged_at_utc_ms FROM outbox_operations WHERE owner_id = ? '
        'ORDER BY operation_id',
        variables: [const Variable<String>('guest-owner')],
      )
      .get();
  final objectives = await database
      .customSelect(
        'SELECT child.id, child.instance_id, child.objective_id '
        'FROM quest_objective_progress AS child '
        'JOIN quest_instances AS parent '
        'ON parent.instance_id = child.instance_id '
        'WHERE parent.owner_id = ? ORDER BY child.id',
        variables: [const Variable<String>('guest-owner')],
      )
      .get();
  return <String, Object>{
    'activeOwnerId': owner.id,
    'firebaseUid': owner.firebaseUid ?? '',
    'inventoryIdentity': await _completeInventoryIdentity(database),
    'inventoryCounts': await _completeInventoryCounts(database),
    'operationRows': operations
        .map(
          (row) =>
              '${row.read<String>('operation_id')}|'
              '${row.read<String>('entity_type')}|'
              '${row.read<String>('entity_id')}|'
              '${row.read<String>('state')}|'
              '${row.read<int>('attempt_count')}|'
              '${row.readNullable<int>('acknowledged_at_utc_ms')}',
        )
        .toList(),
    'operationTypes': operations
        .map((row) => row.read<String>('entity_type'))
        .toSet(),
    'objectiveRows': objectives
        .map(
          (row) =>
              '${row.read<String>('id')}|'
              '${row.read<String>('instance_id')}|'
              '${row.read<String>('objective_id')}',
        )
        .toList(),
  };
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

Future<void> _seedAnonymousBoundCompleteInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('guest-owner', NULL, 'localGuest', 1, 1)",
  );
  await database.customInsert(
    "INSERT INTO research_consents VALUES "
    "('consent-1', 'guest-owner', 1, 'accepted', 10, NULL)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_categories '
    '(id, owner_id, name, normalized_name, sort_order, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('category-1', 'guest-owner', 'Travel', 'travel', 0, 1, 4, 0, 10, 10)",
  );
  await database.customInsert(
    'INSERT INTO vocabulary_words '
    '(id, owner_id, category_id, spelling, normalized_spelling, meaning, '
    'normalized_meaning, part_of_speech, source, is_global, local_revision, '
    'cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES '
    "('word-1', 'guest-owner', 'category-1', 'station', 'station', "
    "'station', 'station', 'noun', 'manual', 0, 1, 3, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_imports VALUES "
    "('import-1', 'guest-owner', 'category-1', 'csv', 'travel.csv', "
    "'hash-1', 'complete', 1, 0, 0, 10, 11)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_import_rows VALUES "
    "('import-row-1', 'import-1', 1, 'row-hash-1', 'accepted', NULL, 'word-1')",
  );
  await database.customInsert(
    "INSERT INTO learning_sessions VALUES ('session-1', 'guest-owner', "
    "'quiz', 'completed', 10, 20, 1, 0, 100, '1', '1')",
  );
  await database.customInsert(
    "INSERT INTO answer_attempts VALUES ('attempt-1', 'guest-owner', "
    "'session-1', 'word-1', 'meaning', 1, 100, 1, 15, NULL)",
  );
  await database.customInsert(
    "INSERT INTO srs_states VALUES ('srs-1', 'guest-owner', 'word-1', "
    '1, 1, 1, 1, 0, 15, 30, 1)',
  );
  await database.customInsert(
    "INSERT INTO reading_progress_entries VALUES ('reading-progress-1', "
    "'guest-owner', 'doc-1', 1, 5, 0, 20)",
  );
  await database.customInsert(
    "INSERT INTO reading_events VALUES ('reading-1', 'guest-owner', "
    "'doc-1', 1, 'position', 5, 20)",
  );
  await database.customInsert(
    "INSERT INTO points_ledger_entries VALUES ('points-1', 'guest-owner', "
    "'answer:1', 'quiz', 200, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO achievement_unlocks VALUES ('achievement-1', 'guest-owner', "
    "'first-answer', 1, 'attempt-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO reward_transactions VALUES ('reward-1', 'guest-owner', "
    "'reward-key-1', 'purchase', -80, 'theme_ocean', 1, NULL, 20)",
  );
  await database.customInsert(
    "INSERT INTO owned_reward_items VALUES ('owned-1', 'guest-owner', "
    "'theme_ocean', 1, 'reward-1', 20)",
  );
  await database.customInsert(
    "INSERT INTO equipped_reward_items VALUES ('equipped-1', 'guest-owner', "
    "'theme', 'theme_ocean', 20)",
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
  var createdAt = 20;
  for (final operation in operations) {
    if (operation.$1 == 'operation:category') {
      await database.customInsert(
        'INSERT INTO outbox_operations '
        '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
        'state, attempt_count, last_attempt_at_utc_ms, created_at_utc_ms, '
        'failure_code) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        variables: [
          Variable<String>(operation.$1),
          const Variable<String>('guest-owner'),
          Variable<String>(operation.$2),
          Variable<String>(operation.$3),
          const Variable<String>('upsert'),
          const Variable<String>('permanentFailure'),
          const Variable<int>(5),
          const Variable<int>(19),
          Variable<int>(createdAt++),
          const Variable<String>('oldNamespaceFailure'),
        ],
      );
      continue;
    }
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

  final seededCursor = SyncCursor(
    serverUpdatedAtUtc: DateTime.utc(2026, 8, 8, 8),
    documentId: 'old-namespace-word',
  );
  await database.customInsert(
    'INSERT INTO sync_checkpoints '
    '(id, owner_id, collection_name, server_cursor, last_success_at_utc_ms) '
    'VALUES (?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('guest-owner:words'),
      const Variable<String>('guest-owner'),
      const Variable<String>('words'),
      Variable<String>(seededCursor.toJsonString()),
      const Variable<int>(19),
    ],
  );
  await database.customInsert(
    'INSERT INTO sync_conflicts '
    '(id, owner_id, entity_type, entity_id, local_revision, cloud_revision, '
    'resolution_policy, outcome, resolved_at_utc_ms) VALUES '
    "('conflict-1', 'guest-owner', 'word', 'word-1', 1, 2, "
    "'cloudWins', 'cloudApplied', 20)",
  );

  const eventRows = <(String, String, String, String, String)>[
    (
      'event-source-1',
      'QuizCompleted',
      'LearningSession',
      'session-1',
      'source-event-1',
    ),
    (
      'projection-result-1',
      'LearningProjectionApplied',
      'LearningProjection',
      'event-source-1',
      'projection-result-1',
    ),
    (
      'projection-cursor-1',
      'LearningProjectionCursor',
      'LearningProjectionCursor',
      'event-source-1',
      'projection-cursor-1',
    ),
  ];
  for (final event in eventRows) {
    await database.customInsert(
      'INSERT INTO events_v2 '
      '(event_id, event_type, event_version, occurred_at_utc, recorded_at_utc, '
      'actor_identity, owner_id, aggregate_type, aggregate_id, '
      'idempotency_key, consent_context_json, app_version, build_id, '
      'privacy_classification, payload_json) VALUES '
      '(?, ?, 1, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
      variables: [
        Variable<String>(event.$1),
        Variable<String>(event.$2),
        Variable<DateTime>(DateTime.utc(2026, 8, 9, 10)),
        Variable<DateTime>(DateTime.utc(2026, 8, 9, 10, 0, 1)),
        const Variable<String>('guest-owner'),
        const Variable<String>('guest-owner'),
        Variable<String>(event.$3),
        Variable<String>(event.$4),
        Variable<String>(event.$5),
        const Variable<String>('{}'),
        const Variable<String>('1.0.0'),
        const Variable<String>('task-5-scenario'),
        const Variable<String>('anonymized'),
        const Variable<String>('{}'),
      ],
    );
  }

  await database.customInsert(
    'INSERT INTO quest_definitions '
    '(quest_id, catalog_version, title, description, type, objectives_json, '
    'reward_json) VALUES '
    "('quest-1', 1, 'Seed Quest', 'Seed', 'daily', '[]', "
    "'{\"xpAmount\":10,\"rewardItemId\":null}')",
  );
  await database.customInsert(
    'INSERT INTO quest_instances '
    '(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, '
    "state) VALUES ('quest-instance-1', 'quest-1', 'guest-owner', 1, 20, "
    "'active')",
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    "source_event_ids_json) VALUES ('objective-1', 'quest-instance-1', "
    "'answer-once', 1, 1, '[\"event-source-1\"]')",
  );
  await database.customInsert(
    'INSERT INTO streak_states '
    '(owner_id, current_streak_days, longest_streak_days, freeze_count, '
    "updated_at_utc_ms) VALUES ('guest-owner', 1, 1, 0, 20)",
  );
  await database.customInsert(
    'INSERT INTO learning_day_log '
    '(id, owner_id, learning_day, first_session_at_utc_ms) VALUES '
    "('day:guest-owner:2026-08-09', 'guest-owner', '2026-08-09', 20)",
  );
  await database.customInsert(
    'INSERT INTO association_records '
    '(id, owner_id, word_key, type, content, created_at_utc_ms) VALUES '
    "('association-1', 'guest-owner', 'station', 'keyword', 'train stop', 20)",
  );
  await database.customInsert(
    'INSERT INTO associative_memory_states '
    '(id, owner_id, word_key, stability, difficulty, cue_dependency, '
    'lapse_count, next_due_at_utc_ms, algorithm_version) VALUES '
    "('memory-1', 'guest-owner', 'station', 1.0, 5.0, 0.0, 0, 30, 'v1')",
  );
  await database.customInsert(
    'INSERT INTO speech_evidence '
    '(id, owner_id, session_id, word_id, prompt_mode, target_content, '
    'recognized_transcript, locale, stt_engine, similarity_algorithm, '
    'similarity_score, is_exact_match, recognition_confidence, sample_size, '
    'occurred_at_utc_ms, duration_ms) VALUES '
    "('speech-1', 'guest-owner', 'session-1', 'word-1', 'meaning', "
    "'station', 'station', 'en-US', 'fake-stt', 'levenshtein', 100, 1, "
    '0.95, 1, 20, 500)',
  );
  await database.customInsert(
    'INSERT INTO ai_usage_events '
    '(event_id, owner_id, occurred_at_utc_ms, provider_id, model, '
    'request_type, outcome, latency_ms) VALUES '
    "('ai-usage-1', 'guest-owner', 20, 'fake-provider', 'fake-model', "
    "'tutorReply', 'success', 10)",
  );
  await _seedForeignOwnerInventory(database);
}

Future<void> _seedForeignOwnerInventory(AppDatabase database) async {
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES '
    "('foreign-owner', 'firebase-foreign', 'firebaseBound', 2, 0)",
  );
  for (final table in ownerUpgradeInventory) {
    final schema = await database
        .customSelect('PRAGMA table_info("$table")')
        .get();
    final columns = schema.map((row) => row.read<String>('name')).toList();
    final quotedColumns = columns.map((column) => '"$column"').join(', ');
    final projections = columns
        .map((column) {
          final quoted = '"$column"';
          if (column == 'owner_id') return "'foreign-owner'";
          if (column == 'quest_id') return quoted;
          if (column == 'idempotency_key') return "'foreign:' || $quoted";
          if (column == 'id' || column.endsWith('_id')) {
            return 'CASE WHEN $quoted IS NULL THEN NULL '
                "ELSE 'foreign:' || $quoted END";
          }
          return quoted;
        })
        .join(', ');
    await database.customInsert(
      'INSERT INTO "$table" ($quotedColumns) '
      'SELECT $projections FROM "$table" WHERE owner_id = ?',
      variables: [const Variable<String>('guest-owner')],
    );
  }
  await database.customInsert(
    'INSERT INTO vocabulary_import_rows '
    '(id, import_id, row_number, payload_hash, status, failure_code, word_id) '
    "SELECT 'foreign:' || id, 'foreign:' || import_id, row_number, "
    'payload_hash, status, failure_code, '
    "CASE WHEN word_id IS NULL THEN NULL ELSE 'foreign:' || word_id END "
    'FROM vocabulary_import_rows WHERE import_id = ?',
    variables: [const Variable<String>('import-1')],
  );
  await database.customInsert(
    'INSERT INTO quest_objective_progress '
    '(id, instance_id, objective_id, current_count, target_count, '
    'source_event_ids_json) '
    "SELECT 'foreign:' || id, 'foreign:' || instance_id, objective_id, "
    'current_count, target_count, source_event_ids_json '
    'FROM quest_objective_progress WHERE instance_id = ?',
    variables: [const Variable<String>('quest-instance-1')],
  );
}
