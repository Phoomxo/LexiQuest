import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';

import '../../support/populated_owner_migration_fixture.dart';

const _source = 'synthetic-time-source';
const _target = 'synthetic-time-target';
const _third = 'synthetic-time-third';
const _targetUid = 'synthetic-time-target-uid';
const _sourceUid = 'synthetic-time-source-uid';
final _now = DateTime.utc(2026, 10, 31, 12);

void main() {
  for (final targetEnabled in <bool?>[null, false, true]) {
    test('merge preserves exact target choice $targetEnabled and removes source choice', () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await f.preference(_source, enabled: true, revision: 5, updatedAt: 50);
      if (targetEnabled != null) {
        await f.preference(_target, enabled: targetEnabled, revision: 9, updatedAt: 90);
      }
      final targetBefore = await f.preferenceRows(_target);
      expect((await f.merge()).mode, OwnerUpgradeMode.mergedExisting);
      expect(await f.preferenceRows(_source), isEmpty);
      expect(await f.preferenceRows(_target), targetBefore);
      expect(await f.rows('outbox_operations'), isEmpty);
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _target,
          firebaseUid: _targetUid,
        )).mode,
        OwnerUpgradeMode.alreadyBound,
      );
      expect(await f.preferenceRows(_target), targetBefore);
      await f.expectForeignKeys();
    });
  }

  test('disabled source cannot replace an enabled target preference', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: false, revision: 7, updatedAt: 70);
    await f.preference(_target, enabled: true, revision: 11, updatedAt: 110);
    final targetBefore = await f.preferenceRows(_target);
    await f.merge();
    expect(await f.preferenceRows(_source), isEmpty);
    expect(await f.preferenceRows(_target), targetBefore);
  });

  test('same-owner anonymous bind and already-bound replay retain choice and facts', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: true, revision: 7, updatedAt: 70);
    await f.time(_source, 'same-owner', linked: false);
    final before = await f.timeRows(_source);
    const uid = 'synthetic-time-new-uid';
    expect(
      (await f.repository.upgrade(activeOwnerId: _source, firebaseUid: uid)).mode,
      OwnerUpgradeMode.anonymousBound,
    );
    expect(await f.timeRows(_source), before);
    expect(
      (await f.repository.upgrade(activeOwnerId: _source, firebaseUid: uid)).mode,
      OwnerUpgradeMode.alreadyBound,
    );
    expect(await f.timeRows(_source), before);
    expect(await f.rows('outbox_operations'), isEmpty);
  });

  test('merge changes only scope ownership and keeps immutable linked and unlinked facts', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.time(_source, 'source-linked', linked: true);
    await f.time(_source, 'source-early-reading', linked: false);
    await f.time(_target, 'target-reading', linked: false);
    await f.time(_third, 'third-reading', linked: false);
    final scopesBefore = await f.rows('learning_time_scopes');
    final segmentsBefore = await f.rows('learning_time_segments');
    final sessionsBefore = await f.rows('learning_sessions');
    await f.merge();
    expect(
      await f.rows('learning_time_scopes'),
      [
        for (final row in scopesBefore)
          if (row['owner_id'] == _source)
            {...row, 'owner_id': _target}
          else
            row,
      ],
    );
    expect(await f.rows('learning_time_segments'), segmentsBefore);
    expect(
      await f.rows('learning_sessions'),
      [
        for (final row in sessionsBefore)
          if (row['owner_id'] == _source)
            {...row, 'owner_id': _target}
          else
            row,
      ],
    );
    expect((await f.timeRows(_source)).values, everyElement(isEmpty));
    expect(await f.rows('outbox_operations'), isEmpty);
    await f.expectForeignKeys();
  });

  test('scope move failure rolls back deleted preference and every other owner row', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: true, revision: 3, updatedAt: 30);
    await f.preference(_target, enabled: false, revision: 8, updatedAt: 80);
    await f.time(_source, 'rollback-linked', linked: true);
    final before = await ownerMigrationRows(f.db);
    await f.db.customStatement(
      "CREATE TEMP TRIGGER reject_synthetic_time_rehome "
      "BEFORE UPDATE OF owner_id ON learning_time_scopes "
      "WHEN OLD.owner_id = '$_source' "
      "BEGIN SELECT RAISE(ABORT, 'synthetic-time-rehome-failure'); END",
    );
    await expectLater(f.merge(), throwsA(isA<Object>()));
    expect(await ownerMigrationRows(f.db), before);
    await f.expectForeignKeys();
  });

  test('full snapshot includes disabled-owner history and joins segments through scopes', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: false, revision: 4, updatedAt: 40);
    await f.time(_source, 'snapshot-linked', linked: true);
    await f.time(_source, 'snapshot-reading', linked: false);
    await f.preference(_target, enabled: true, revision: 9, updatedAt: 90);
    await f.time(_target, 'private-target', linked: false);
    await f.time(_third, 'private-third', linked: false);
    final expected = await f.timeRows(_source);
    final before = await ownerMigrationRows(f.db);
    final snapshot = await DriftAccountSnapshotBuilder(
      f.db,
      nowUtc: () => _now,
    ).build(ownerId: _source);
    expect(snapshot.coveredScopes, requiredFullAccountExportScopes);
    expect(snapshot.coveredScopes, containsAll([
      'learning_time_preferences',
      'learning_time_scopes',
      'learning_time_segments',
    ]));
    final document = jsonDecode(utf8.decode(snapshot.bytes)) as Map<String, dynamic>;
    final data = document['data'] as Map<String, dynamic>;
    for (final table in expected.entries) {
      expect(data[table.key], table.value, reason: table.key);
    }
    expect(data['learning_time_segments'], hasLength(4));
    final text = utf8.decode(snapshot.bytes);
    expect(text, isNot(contains('private-target')));
    expect(text, isNot(contains('private-third')));
    expect(await ownerMigrationRows(f.db), before);
    final columns = await f.db.customSelect('PRAGMA table_info(learning_time_segments)').get();
    expect(columns.map((row) => row.read<String>('name')), isNot(contains('owner_id')));
    expect(ownerUpgradeInventory, containsAll([
      'learning_time_preferences',
      'learning_time_scopes',
    ]));
    expect(ownerUpgradeInventory, isNot(contains('learning_time_segments')));
  });

  test('cloud-confirmed purge removes linked and unlinked time and preserves every other owner', () async {
    final f = await _Fixture.open(sourceBound: true);
    addTearDown(f.close);
    await f.preference(_source, enabled: true, revision: 4, updatedAt: 40);
    await f.time(_source, 'purge-linked', linked: true);
    await f.time(_source, 'purge-reading', linked: false);
    await f.preference(_target, enabled: false, revision: 9, updatedAt: 90);
    await f.time(_target, 'retained-target', linked: true);
    await f.time(_third, 'retained-third', linked: false);
    final targetBefore = await f.timeRows(_target);
    final thirdBefore = await f.timeRows(_third);
    final secretPurges = <(String, String)>[];
    final gateway = DriftLocalAccountDeletionGateway(
      f.db,
      nowUtc: () => _now,
      purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
        secretPurges.add((ownerId, firebaseUid));
      },
    );
    final cloud = CloudDeletionReceipt(
      receiptId: 'synthetic-time-cloud-receipt',
      ownerId: _source,
      firebaseUid: _sourceUid,
      idempotencyKey: 'synthetic-time-delete',
      completedAtUtc: _now,
    );
    final result = await gateway.deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
    expect(result.deletedOwnerId, _source);
    expect(secretPurges, [(_source, _sourceUid)]);
    expect((await f.timeRows(_source)).values, everyElement(isEmpty));
    expect(await f.timeRows(_target), targetBefore);
    expect(await f.timeRows(_third), thirdBefore);
    final childRows = await f.rows('learning_time_segments');
    expect(childRows, hasLength(4));
    expect(
      (await f.db.customSelect(
        'SELECT * FROM local_owners WHERE id = ?',
        variables: const [drift.Variable<String>(_source)],
      ).get()),
      isEmpty,
    );
    final replay = await gateway.deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
    expect(replay.newGuestOwnerId, result.newGuestOwnerId);
    expect(await f.timeRows(_target), targetBefore);
    expect(await f.timeRows(_third), thirdBefore);
    await f.expectForeignKeys();
  });

  test('deleting an actual linked session cascades its scope only', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: true, revision: 2, updatedAt: 20);
    await f.time(_source, 'deleted-session', linked: true);
    await f.time(_source, 'unlinked-reading', linked: false);
    await f.time(_target, 'other-owner', linked: false);
    final targetBefore = await f.timeRows(_target);
    final preferenceBefore = await f.preferenceRows(_source);
    await f.db.customStatement(
      'DELETE FROM learning_sessions WHERE id = ?',
      ['synthetic-time-session-deleted-session'],
    );
    final remaining = await f.timeRows(_source);
    expect(remaining['learning_time_scopes']!.single['id'], 'time-scope:unlinked-reading');
    expect(remaining['learning_time_segments'], hasLength(2));
    expect(remaining['learning_time_segments']!.every(
      (row) => row['scope_id'] == 'time-scope:unlinked-reading',
    ), isTrue);
    expect(await f.preferenceRows(_source), preferenceBefore);
    expect(await f.timeRows(_target), targetBefore);
    await f.expectForeignKeys();
  });

  for (final guestState in ['preference', 'unlinked-scope']) {
    test('logout rollback cannot discard guest time $guestState', () async {
      final f = await _Fixture.open(sourceBound: true);
      addTearDown(f.close);
      final guest = await f.repository.createLocalGuestAfterLogout();
      if (guestState == 'preference') {
        await f.preference(guest.targetOwnerId, enabled: true, revision: 1, updatedAt: 10);
      } else {
        await f.time(guest.targetOwnerId, 'logout-retained-reading', linked: false);
      }
      final before = await ownerMigrationRows(f.db);
      await expectLater(
        f.repository.rollbackLocalGuestLogout(
          previousOwnerId: _source,
          guestOwnerId: guest.targetOwnerId,
        ),
        throwsA(isA<Object>()),
      );
      expect(await ownerMigrationRows(f.db), before);
      await f.expectForeignKeys();
    });
  }

  test('local time history has no sync collection, operation or claimed mutation after rehome', () async {
    final f = await _Fixture.open();
    addTearDown(f.close);
    await f.preference(_source, enabled: true, revision: 5, updatedAt: 50);
    await f.time(_source, 'sync-excluded', linked: true);
    await f.time(_source, 'sync-early-reading', linked: false);
    final oldSegments = await f.rows('learning_time_segments');
    await f.merge();
    expect(await f.rows('learning_time_segments'), oldSegments);
    expect(await f.rows('outbox_operations'), isEmpty);
    expect(
      SyncCollection.values.map((value) => value.wireName),
      isNot(anyElement(startsWith('learning_time'))),
    );
    expect(
      await DriftSyncStore(f.db).claimPending(
        ownerId: _target,
        firebaseUid: _targetUid,
        limit: 10,
        leaseToken: 'synthetic-time-sync-lease',
        leaseDuration: const Duration(minutes: 1),
        nowUtc: _now,
      ),
      isEmpty,
    );
    expect(await f.rows('outbox_operations'), isEmpty);
    expect(await f.rows('learning_time_segments'), oldSegments);
    await f.expectForeignKeys();
  });
}

final class _Fixture {
  _Fixture(this.db)
      : repository = DriftOwnerUpgradeRepository(
          db,
          nowUtc: () => _now,
          generateConflictId: () => 'synthetic-time-unexpected-conflict',
          generateOwnerId: () => 'synthetic-time-new-guest',
        );

  final AppDatabase db;
  final DriftOwnerUpgradeRepository repository;

  static Future<_Fixture> open({bool sourceBound = false}) async {
    final database = AppDatabase(NativeDatabase.memory());
    try {
      await database.customStatement('PRAGMA foreign_keys = ON');
      await insertOwnerMigrationRow(database, 'local_owners', {
        'id': _source,
        'firebase_uid': sourceBound ? _sourceUid : null,
        'account_state': sourceBound ? 'firebaseBound' : 'localGuest',
        'created_at_utc_ms': 1,
        'is_active': 1,
      });
      for (final row in [
        (_target, _targetUid),
        (_third, 'synthetic-time-third-uid'),
      ]) {
        await insertOwnerMigrationRow(database, 'local_owners', {
          'id': row.$1,
          'firebase_uid': row.$2,
          'account_state': 'firebaseBound',
          'created_at_utc_ms': 2,
          'is_active': 0,
        });
      }
      return _Fixture(database);
    } catch (_) {
      await database.close();
      rethrow;
    }
  }

  Future<void> close() => db.close();

  Future<OwnerUpgradeResult> merge() =>
      repository.upgrade(activeOwnerId: _source, firebaseUid: _targetUid);

  Future<void> preference(
    String ownerId, {
    required bool enabled,
    required int revision,
    required int updatedAt,
  }) => insertOwnerMigrationRow(db, 'learning_time_preferences', {
    'owner_id': ownerId,
    'enabled': enabled ? 1 : 0,
    'revision': revision,
    'updated_at_utc_ms': updatedAt,
  });

  Future<List<Map<String, Object?>>> preferenceRows(String owner) =>
      _query('SELECT * FROM learning_time_preferences WHERE owner_id = ? ORDER BY rowid', owner);

  Future<void> time(String owner, String fixtureId, {required bool linked}) async {
    final sessionId = 'synthetic-time-session-$fixtureId';
    if (linked) {
      await insertOwnerMigrationRow(db, 'learning_sessions', {
        'id': sessionId,
        'owner_id': owner,
        'activity_type': 'quiz',
        'state': 'completed',
        'started_at_utc_ms': 1000,
        'ended_at_utc_ms': 4500,
        'app_version': 'synthetic-lifecycle',
        'build_id': 'storage-only',
      });
    }
    final scopeId = 'time-scope:$fixtureId';
    await insertOwnerMigrationRow(db, 'learning_time_scopes', {
      'id': scopeId,
      'owner_id': owner,
      'source_kind': linked ? 'configuredQuiz' : 'reading',
      'source_binding_json': jsonEncode({
        'schemaVersion': 1,
        'syntheticStorageFixture': fixtureId,
        'historicalContentPin': 'synthetic-time-content-v1',
      }),
      'created_at_utc_ms': 1000,
      'linked_session_id': linked ? sessionId : null,
      'session_link_binding_json': linked
          ? jsonEncode({'schemaVersion': 1, 'syntheticSessionId': sessionId})
          : null,
    });
    for (var ordinal = 0; ordinal < 2; ordinal++) {
      await insertOwnerMigrationRow(db, 'learning_time_segments', {
        'id': 'time-segment:$fixtureId-$ordinal',
        'scope_id': scopeId,
        'ordinal': ordinal,
        'eligibility_context_json': jsonEncode({
          'schemaVersion': 1,
          'syntheticStorageFixture': fixtureId,
          'ordinal': ordinal,
        }),
        'started_at_utc_ms': ordinal == 0 ? 1000 : 2500,
        'ended_at_utc_ms': ordinal == 0 ? 2500 : 4500,
        'active_duration_us': ordinal == 0 ? 1500000 : 2000000,
        'capture_policy_revision': 'confirmed-interaction-v1',
      });
    }
  }

  Future<List<Map<String, Object?>>> rows(String table) async => [
    for (final row in await db.customSelect('SELECT * FROM "$table" ORDER BY rowid').get())
      Map<String, Object?>.from(row.data),
  ];

  Future<List<Map<String, Object?>>> _query(String sql, String owner) async => [
    for (final row in await db.customSelect(
      sql,
      variables: [drift.Variable<String>(owner)],
    ).get())
      Map<String, Object?>.from(row.data),
  ];

  Future<Map<String, List<Map<String, Object?>>>> timeRows(String owner) async => {
    'learning_time_preferences': await preferenceRows(owner),
    'learning_time_scopes': await _query(
      'SELECT * FROM learning_time_scopes WHERE owner_id = ? ORDER BY rowid',
      owner,
    ),
    'learning_time_segments': await _query(
      'SELECT g.* FROM learning_time_segments g '
      'INNER JOIN learning_time_scopes s ON s.id = g.scope_id '
      'WHERE s.owner_id = ? ORDER BY g.scope_id, g.ordinal, g.id',
      owner,
    ),
  };

  Future<void> expectForeignKeys() async {
    expect(
      (await db.customSelect('PRAGMA foreign_keys').getSingle()).read<int>('foreign_keys'),
      1,
    );
    expect(await db.customSelect('PRAGMA foreign_key_check').get(), isEmpty);
  }
}
