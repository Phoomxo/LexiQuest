import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/data/local/shared_preferences_account_deletion_journal.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

void main() {
  late AppDatabase database;
  final now = DateTime.utc(2026, 10, 24, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    await database.customStatement('PRAGMA foreign_keys = ON');
    await _seed(database);
  });

  tearDown(() => database.close());

  test(
    'deletes only the cloud-confirmed owner and creates a local guest',
    () async {
      await _seedS6LifecycleRows(database);
      final beforeB = await _lifecycleRows(database, 'owner-b');
      final focusForeignKeys = await database
          .customSelect('PRAGMA foreign_key_list(focus_sessions)')
          .get();
      expect(
        focusForeignKeys.any(
          (row) =>
              row.data['table'] == 'owner_calendar_epochs' &&
              row.data['from'] == 'start_rule_id',
        ),
        isTrue,
      );
      expect(
        await _count(
          database,
          'focus_sessions',
          'owner_id = ? AND start_rule_id = ?',
          ['owner-a', 'rule-a'],
        ),
        1,
      );
      final purgedScopes = <(String, String)>[];
      final gateway = DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          purgedScopes.add((ownerId, firebaseUid));
        },
      );

      final receipt = await gateway.deleteAfterCloud(
        ownerId: 'owner-a',
        cloudReceipt: _cloudReceipt(now),
      );

      expect(receipt.deletedOwnerId, 'owner-a');
      expect(receipt.newGuestOwnerId, startsWith('local:deleted:'));
      expect(receipt.completedAtUtc, now);
      expect(purgedScopes, [('owner-a', 'firebase-user')]);
      expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 0);
      expect(
        await _count(database, 'local_owners', 'id = ? AND is_active = 1', [
          receipt.newGuestOwnerId,
        ]),
        1,
      );
      expect(await _count(database, 'local_owners', 'id = ?', ['owner-b']), 1);
      for (final table in ownerUpgradeInventory) {
        expect(
          await _count(database, table, 'owner_id = ?', ['owner-a']),
          0,
          reason: table,
        );
      }
      expect(await _count(database, 'vocabulary_import_rows', '1 = 1', []), 0);
      expect(
        await _count(database, 'quest_objective_progress', '1 = 1', []),
        0,
      );
      expect(await _count(database, 'quest_definitions', '1 = 1', []), 1);
      expect(
        await _count(database, 'vocabulary_categories', 'owner_id = ?', [
          'owner-b',
        ]),
        1,
      );
      for (final table in _s6OwnerTables) {
        expect(await _count(database, table, 'owner_id = ?', ['owner-a']), 0);
        expect(await _count(database, table, 'owner_id = ?', ['owner-b']), 1);
      }
      expect(await _lifecycleRows(database, 'owner-b'), beforeB);
      expect(
        await _count(database, 'quest_definition_revisions', '1 = 1', []),
        2,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  for (final version in [10, 11]) {
    test(
      'v12 client rejects a v$version export receipt before reauth or deletion',
      () async {
        SharedPreferences.setMockInitialValues({});
        final fixture =
            jsonDecode(
                  File(
                    'test/fixtures/account_deletion_export_scopes.json',
                  ).readAsStringSync(),
                )
                as Map<String, dynamic>;
        final dependencies = _UnusedAccountDeletionDependencies(
          exportReceipt: FullAccountExportReceipt(
            ownerId: 'owner-a',
            artifactId: 'synthetic-historical-v$version.json',
            artifactSha256: 'a' * 64,
            bytesWritten: 100,
            schemaVersion: version,
            coveredScopes: (fixture['exportV$version'] as List)
                .cast<String>()
                .toSet(),
            completedAtUtc: now,
          ),
        );
        final before = await _lifecycleRows(database, 'owner-a');
        var purged = false;
        final useCases = AccountDeletionUseCases(
          enabled: true,
          owners: _BoundOwners(now),
          currentSession: () => const AccountSession(
            uid: 'firebase-user',
            email: 'synthetic@example.test',
            isAnonymous: false,
            emailVerified: true,
          ),
          exporter: dependencies,
          reauthenticator: dependencies,
          cloud: dependencies,
          local: DriftLocalAccountDeletionGateway(
            database,
            nowUtc: () => now,
            purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
              purged = true;
            },
          ),
          journal: SharedPreferencesAccountDeletionJournal(
            await SharedPreferences.getInstance(),
          ),
          nowUtc: () => now,
        );
        await expectLater(
          useCases.deleteAccount(
            idempotencyKey: _cloudReceipt(now).idempotencyKey,
          ),
          throwsA(
            isA<AccountDeletionException>().having(
              (error) => error.code,
              'code',
              AccountDeletionFailureCode.fullExportRequired,
            ),
          ),
        );
        expect(dependencies.calls, ['export']);
        expect(purged, isFalse);
        expect(await _lifecycleRows(database, 'owner-a'), before);
      },
    );
  }

  test(
    'file reopen resumes secret purge after deleting all v12 owner rows',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        's6-owner-deletion-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      var persisted = AppDatabase(NativeDatabase(file));
      try {
        await persisted.customStatement('PRAGMA foreign_keys = ON');
        await _seed(persisted);
        await _seedS6LifecycleRows(persisted);
        expect(
          (await persisted.customSelect('PRAGMA user_version').getSingle())
              .data,
          {'user_version': 12},
        );
        final beforeB = await _lifecycleRows(persisted, 'owner-b');
        final cloudReceipt = _cloudReceipt(now);
        var purgeCalls = 0;
        Future<void> purge({
          required String ownerId,
          required String firebaseUid,
        }) async {
          expect((ownerId, firebaseUid), ('owner-a', 'firebase-user'));
          purgeCalls++;
          if (purgeCalls == 1) {
            throw StateError('synthetic secure storage failure');
          }
        }

        await expectLater(
          DriftLocalAccountDeletionGateway(
            persisted,
            nowUtc: () => now,
            purgeOwnerSecret: purge,
          ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: cloudReceipt),
          throwsA(
            isA<AccountDeletionException>().having(
              (error) => error.code,
              'code',
              AccountDeletionFailureCode.localDeleteFailed,
            ),
          ),
        );
        expect(
          purgeCalls,
          1,
          reason: 'owner purge committed before secret failure',
        );
        expect(
          await _count(persisted, 'local_owners', 'id = ?', ['owner-a']),
          0,
        );
        for (final table in _s6OwnerTables) {
          expect(
            await _count(persisted, table, 'owner_id = ?', ['owner-a']),
            0,
          );
        }
        await persisted.close();
        persisted = AppDatabase(NativeDatabase(file));
        await persisted.customStatement('PRAGMA foreign_keys = ON');
        final receipt = await DriftLocalAccountDeletionGateway(
          persisted,
          nowUtc: () => now.add(const Duration(hours: 1)),
          purgeOwnerSecret: purge,
        ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: cloudReceipt);
        expect(receipt.completedAtUtc, now);
        expect(receipt.newGuestOwnerId, _replacementGuestOwnerId(cloudReceipt));
        expect(purgeCalls, 2);
        expect(
          await _count(persisted, 'local_owners', 'id = ?', [
            receipt.newGuestOwnerId,
          ]),
          1,
        );
        expect(await _lifecycleRows(persisted, 'owner-b'), beforeB);
        expect(
          await persisted.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await persisted.close();
        final tempRoot = Directory.systemTemp.absolute.path;
        expect(
          directory.absolute.path.startsWith(
            '$tempRoot${Platform.pathSeparator}',
          ),
          isTrue,
        );
        await directory.delete(recursive: true);
      }
    },
  );

  test('rejects mismatched cloud receipt before any local write', () async {
    final gateway = DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now,
      purgeOwnerSecret: _noOpPurge,
    );

    await expectLater(
      gateway.deleteAfterCloud(
        ownerId: 'owner-a',
        cloudReceipt: CloudDeletionReceipt(
          receiptId: 'cloud-receipt-1',
          ownerId: 'owner-b',
          firebaseUid: 'firebase-user',
          idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
          completedAtUtc: now,
        ),
      ),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.invalidCloudReceipt,
        ),
      ),
    );

    expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 1);
    expect(
      await _count(database, 'vocabulary_categories', 'owner_id = ?', [
        'owner-a',
      ]),
      1,
    );
  });

  test('ack-loss retry after reopen returns the exact local receipt', () async {
    final cloudReceipt = _cloudReceipt(now);
    var purgeCount = 0;
    final first = await DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now,
      purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
        purgeCount += 1;
      },
    ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: cloudReceipt);

    final retried = await DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now.add(const Duration(hours: 1)),
      purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
        purgeCount += 1;
      },
    ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: cloudReceipt);

    expect(retried.deletedOwnerId, first.deletedOwnerId);
    expect(retried.newGuestOwnerId, first.newGuestOwnerId);
    expect(retried.completedAtUtc, first.completedAtUtc);
    expect(
      await _count(database, 'local_owners', 'id = ?', [first.newGuestOwnerId]),
      1,
    );
    expect(purgeCount, 2);
  });

  test('resumes secret purge after the database commit', () async {
    final cloudReceipt = _cloudReceipt(now);
    var attempts = 0;
    Future<void> purge({
      required String ownerId,
      required String firebaseUid,
    }) async {
      attempts += 1;
      expect(ownerId, 'owner-a');
      expect(firebaseUid, 'firebase-user');
      if (attempts == 1) throw StateError('synthetic secure storage failure');
    }

    final firstGateway = DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now,
      purgeOwnerSecret: purge,
    );
    await expectLater(
      firstGateway.deleteAfterCloud(
        ownerId: 'owner-a',
        cloudReceipt: cloudReceipt,
      ),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.localDeleteFailed,
        ),
      ),
    );
    expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 0);

    final receipt = await DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now.add(const Duration(hours: 1)),
      purgeOwnerSecret: purge,
    ).deleteAfterCloud(ownerId: 'owner-a', cloudReceipt: cloudReceipt);

    expect(receipt.deletedOwnerId, 'owner-a');
    expect(receipt.completedAtUtc, now);
    expect(attempts, 2);
  });

  test(
    'rejects a deterministic guest collision without deleting owner data',
    () async {
      final cloudReceipt = _cloudReceipt(now);
      final collisionId = _replacementGuestOwnerId(cloudReceipt);
      await database.customStatement(
        'INSERT INTO local_owners '
        '(id, firebase_uid, account_state, created_at_utc_ms, is_active) '
        "VALUES (?, 'collision-user', 'firebaseBound', 1792833600000, 0)",
        [collisionId],
      );
      final gateway = DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => now,
        purgeOwnerSecret: _noOpPurge,
      );

      await expectLater(
        gateway.deleteAfterCloud(
          ownerId: 'owner-a',
          cloudReceipt: cloudReceipt,
        ),
        throwsA(
          isA<AccountDeletionException>().having(
            (error) => error.code,
            'code',
            AccountDeletionFailureCode.localDeleteFailed,
          ),
        ),
      );

      expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 1);
      expect(
        await _count(database, 'vocabulary_categories', 'owner_id = ?', [
          'owner-a',
        ]),
        1,
      );
    },
  );

  test('fails closed when more than one local owner is active', () async {
    await database.customStatement(
      "UPDATE local_owners SET is_active = 1 WHERE id = 'owner-b'",
    );
    final gateway = DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now,
      purgeOwnerSecret: _noOpPurge,
    );

    await expectLater(
      gateway.deleteAfterCloud(
        ownerId: 'owner-a',
        cloudReceipt: _cloudReceipt(now),
      ),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.ownerChanged,
        ),
      ),
    );

    expect(
      await _count(database, 'local_owners', 'is_active = 1', const []),
      2,
    );
    expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 1);
    expect(await _count(database, 'local_owners', 'id = ?', ['owner-b']), 1);
    expect(
      await _count(database, 'vocabulary_categories', 'owner_id = ?', [
        'owner-a',
      ]),
      1,
    );
    expect(
      await _count(database, 'vocabulary_categories', 'owner_id = ?', [
        'owner-b',
      ]),
      1,
    );
  });

  test('use case resumes secure purge after the database commit', () async {
    SharedPreferences.setMockInitialValues({});
    final journal = SharedPreferencesAccountDeletionJournal(
      await SharedPreferences.getInstance(),
    );
    final cloudReceipt = _cloudReceipt(now);
    await journal.saveCloudReceipt(cloudReceipt);
    var attempts = 0;
    final local = DriftLocalAccountDeletionGateway(
      database,
      nowUtc: () => now,
      purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
        attempts += 1;
        if (attempts == 1) throw StateError('synthetic purge failure');
      },
    );
    final unused = _UnusedAccountDeletionDependencies();
    final useCases = AccountDeletionUseCases(
      enabled: true,
      owners: _UnusedOwners(),
      currentSession: () => null,
      exporter: unused,
      reauthenticator: unused,
      cloud: unused,
      local: local,
      journal: journal,
      nowUtc: () => now,
    );

    await expectLater(
      useCases.resumeLocalDeletion(cloudReceipt),
      throwsA(
        isA<AccountDeletionException>().having(
          (error) => error.code,
          'code',
          AccountDeletionFailureCode.localDeleteFailed,
        ),
      ),
    );
    expect(await _count(database, 'local_owners', 'id = ?', ['owner-a']), 0);

    final receipt = await useCases.resumeLocalDeletion(cloudReceipt);

    expect(receipt.deletedOwnerId, 'owner-a');
    expect(attempts, 2);
    expect(await journal.load(), null);
  });

  for (final pending in [false, true]) {
    final method = pending ? 'resumePendingDeletion' : 'resumeLocalDeletion';
    test(
      '$method clears completed journal after failed removal without repeating deletion',
      () async {
        await _seedS6LifecycleRows(database);
        final beforeB = await _lifecycleRows(database, 'owner-b');
        final preferences = _FailFirstJournalRemovePreferences();
        final journal = SharedPreferencesAccountDeletionJournal(preferences);
        final cloudReceipt = _cloudReceipt(now);
        await journal.saveCloudReceipt(cloudReceipt);
        var purges = 0;
        final local = DriftLocalAccountDeletionGateway(
          database,
          nowUtc: () => now,
          purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
            expect((ownerId, firebaseUid), ('owner-a', 'firebase-user'));
            purges++;
          },
        );
        final unused = _UnusedAccountDeletionDependencies();
        AccountDeletionUseCases open(AccountDeletionJournal currentJournal) =>
            AccountDeletionUseCases(
              enabled: true,
              owners: _UnusedOwners(),
              currentSession: () => null,
              exporter: unused,
              reauthenticator: unused,
              cloud: unused,
              local: local,
              journal: currentJournal,
              nowUtc: () => now,
            );
        Future<LocalDeletionReceipt?> resume(
          AccountDeletionUseCases useCases,
        ) => pending
            ? useCases.resumePendingDeletion()
            : useCases.resumeLocalDeletion(cloudReceipt);

        await expectLater(
          resume(open(journal)),
          throwsA(
            isA<AccountDeletionException>().having(
              (error) => error.code,
              'code',
              AccountDeletionFailureCode.localDeleteFailed,
            ),
          ),
        );
        final completed = (await journal.load())!.localReceipt!;
        expect(preferences.removeCalls, 1);
        expect(
          preferences.getString(
            SharedPreferencesAccountDeletionJournal.storageKey,
          ),
          isNotNull,
        );
        expect(purges, 1);
        expect(
          await _count(database, 'local_owners', 'id = ?', ['owner-a']),
          0,
        );
        final afterA = await _lifecycleRows(database, 'owner-a');
        final guest = await _lifecycleRows(database, completed.newGuestOwnerId);
        final reopened = SharedPreferencesAccountDeletionJournal(preferences);

        final receipt = (await resume(open(reopened)))!;

        expect(receipt.deletedOwnerId, completed.deletedOwnerId);
        expect(receipt.newGuestOwnerId, completed.newGuestOwnerId);
        expect(receipt.completedAtUtc, completed.completedAtUtc);
        expect(await reopened.load(), isNull);
        expect(
          preferences.getString(
            SharedPreferencesAccountDeletionJournal.storageKey,
          ),
          isNull,
        );
        expect(preferences.removeCalls, 2);
        expect(unused.calls, isEmpty);
        expect(purges, 1);
        expect(await _lifecycleRows(database, 'owner-a'), afterA);
        expect(await _lifecycleRows(database, 'owner-b'), beforeB);
        expect(
          await _lifecycleRows(database, completed.newGuestOwnerId),
          guest,
        );
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      },
    );
  }
}

final class _FailFirstJournalRemovePreferences implements SharedPreferences {
  final _values = <String, String>{};
  int removeCalls = 0;

  @override
  String? getString(String key) => _values[key];

  @override
  Future<bool> setString(String key, String value) async {
    _values[key] = value;
    return true;
  }

  @override
  Future<bool> remove(String key) async {
    removeCalls++;
    if (removeCalls == 1) return false;
    _values.remove(key);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _noOpPurge({
  required String ownerId,
  required String firebaseUid,
}) async {}

final class _UnusedOwners implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() =>
      throw StateError('owner lookup must not run while resuming a journal');

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

final class _UnusedAccountDeletionDependencies
    implements
        FullAccountExporter,
        AccountDeletionReauthenticator,
        PrivilegedAccountDeletionGateway {
  _UnusedAccountDeletionDependencies({this.exportReceipt});
  final FullAccountExportReceipt? exportReceipt;
  final List<String> calls = [];

  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) async {
    calls.add('export');
    if (exportReceipt case final receipt?) return receipt;
    throw UnimplementedError();
  }

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) async {
    calls.add('reauth');
    throw UnimplementedError();
  }

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    calls.add('cloud');
    throw UnimplementedError();
  }
}

final class _BoundOwners implements LocalOwnerRepository {
  _BoundOwners(this.now);
  final DateTime now;
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner-a',
        firebaseUid: 'firebase-user',
        createdAtUtc: now,
      );
  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => throw UnimplementedError();
}

String _replacementGuestOwnerId(CloudDeletionReceipt receipt) {
  final operation = jsonEncode([
    receipt.ownerId,
    receipt.firebaseUid,
    receipt.idempotencyKey,
    receipt.receiptId,
  ]);
  return 'local:deleted:${sha256.convert(utf8.encode(operation))}';
}

CloudDeletionReceipt _cloudReceipt(DateTime now) => CloudDeletionReceipt(
  receiptId: 'cloud-receipt-1',
  ownerId: 'owner-a',
  firebaseUid: 'firebase-user',
  idempotencyKey: 'delete:00000000-0000-4000-8000-000000000001',
  completedAtUtc: now,
);

Future<int> _count(
  AppDatabase database,
  String table,
  String where,
  List<String> values,
) async {
  final row = await database
      .customSelect(
        'SELECT COUNT(*) AS value FROM $table WHERE $where',
        variables: [for (final value in values) Variable<String>(value)],
      )
      .getSingle();
  return row.read<int>('value');
}

const _s6OwnerTables = {
  'owner_calendar_epochs',
  'quest_claim_receipts',
  'streak_baselines',
  'streak_token_adjustments',
  'local_content_reports',
  'focus_sessions',
  'learning_preferences',
};

Future<Map<String, Object?>> _lifecycleRows(
  AppDatabase database,
  String owner,
) async {
  final fixture =
      jsonDecode(
            File(
              'test/fixtures/account_deletion_export_scopes.json',
            ).readAsStringSync(),
          )
          as Map<String, dynamic>;
  final data = <String, Object?>{};
  for (final scope in (fixture['exportV12'] as List).cast<String>()) {
    final (sql, variables) = switch (scope) {
      'quest_definitions' || 'quest_definition_revisions' => (
        'SELECT * FROM $scope ORDER BY rowid',
        <Variable<Object>>[],
      ),
      'local_owners' => (
        'SELECT * FROM local_owners WHERE id = ? ORDER BY rowid',
        [Variable<String>(owner)],
      ),
      'vocabulary_import_rows' => (
        'SELECT r.* FROM vocabulary_import_rows r JOIN vocabulary_imports i '
            'ON i.id = r.import_id WHERE i.owner_id = ? ORDER BY r.rowid',
        [Variable<String>(owner)],
      ),
      'quest_objective_progress' => (
        'SELECT p.* FROM quest_objective_progress p JOIN quest_instances i '
            'ON i.instance_id = p.instance_id WHERE i.owner_id = ? ORDER BY p.rowid',
        [Variable<String>(owner)],
      ),
      _ => (
        'SELECT * FROM $scope WHERE owner_id = ? ORDER BY rowid',
        [Variable<String>(owner)],
      ),
    };
    data[scope] = (await database.customSelect(sql, variables: variables).get())
        .map((row) => row.data)
        .toList();
  }
  return data;
}

Future<void> _seedS6LifecycleRows(AppDatabase database) async {
  const at = 1792833600000;
  for (final (suffix, version) in [('a', 2), ('b', 3)]) {
    final body = '{"synthetic":true,"publicTitle":"$suffix","xpAmount":50}';
    final digest = sha256.convert(utf8.encode(body)).toString();
    await database.customStatement(
      'INSERT INTO owner_calendar_epochs '
      '(rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected) '
      'VALUES (?,?,?,?,?,?,1)',
      [
        'rule-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        at * 1000,
        'UTC',
        'synthetic-tzdb',
      ],
    );
    await database.customStatement(
      'INSERT INTO local_content_reports (id,owner_id,source_kind,source_id,source_revision,spelling,meaning,sentence,reason,created_at_utc_ms) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'report-$suffix',
        'owner-$suffix',
        'word',
        'synthetic-$suffix',
        1,
        'station',
        'สถานี',
        null,
        'synthetic-reason',
        at,
      ],
    );
    await database.customStatement(
      'INSERT INTO focus_sessions (id,owner_id,origin_owner_id,target_ms,started_at_utc_ms,start_rule_id,start_civil_week,state,spans_json,ended_at_utc_ms) VALUES (?,?,?,?,?,?,?,?,?,?)',
      [
        'focus-$suffix',
        'owner-$suffix',
        'owner-$suffix',
        300000,
        at,
        'rule-$suffix',
        '2026-10-19',
        'completed',
        '{"version":1,"spans":[]}',
        at + 1000,
      ],
    );
    await database.customStatement(
      'INSERT INTO learning_preferences (owner_id,onboarding_state,purpose,planned_minutes,learning_method,goal_state,updated_at_utc_ms) VALUES (?,?,?,?,?,?,?)',
      [
        'owner-$suffix',
        'completed',
        'synthetic-purpose',
        5,
        'reading',
        'closed',
        at,
      ],
    );
    await database.customStatement(
      'INSERT INTO quest_definition_revisions '
      '(quest_id,catalog_version,definition_digest,canonical_definition) VALUES (?,?,?,?)',
      ['quest-a', version, digest, body],
    );
    // Synthetic persistence evidence only; no real claim command is invoked.
    await database.customStatement(
      'INSERT INTO quest_instances '
      '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
      'origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,'
      'definition_digest,record_kind) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
      [
        'pinned-instance-$suffix',
        'quest-a',
        'owner-$suffix',
        version,
        at,
        'completed',
        'synthetic-origin-$suffix',
        'synthetic-period-$suffix',
        'rule-$suffix',
        '2026-10-24',
        '[[${at * 1000},${(at + 86400000) * 1000}]]',
        digest,
        'canonical',
      ],
    );
    await database.customStatement(
      'INSERT INTO quest_claim_receipts '
      '(id,owner_id,origin_owner_id,instance_id,issued_at_utc_ms,completed_at_utc_ms,xp_amount,evidence_json) '
      'VALUES (?,?,?,?,?,?,?,?)',
      [
        'receipt-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        'pinned-instance-$suffix',
        at + 1,
        at,
        50,
        '{"synthetic":true,"attemptIds":["synthetic-$suffix"]}',
      ],
    );
    await database.customStatement(
      'INSERT INTO streak_baselines '
      '(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,'
      'freeze_count,last_learned_at_utc_ms,updated_at_utc_ms,controls_continuity) '
      'VALUES (?,?,?,?,?,?,?,?,1)',
      ['synthetic-origin-$suffix', 'owner-$suffix', at, 3, 7, 2, null, at],
    );
    await database.customStatement(
      'INSERT INTO streak_token_adjustments '
      '(id,owner_id,origin_owner_id,command_id,occurred_at_utc_ms,kind,delta,protected_day) '
      "VALUES (?,?,?,?,?,'autoProtect',-1,'2026-10-23')",
      [
        'adjustment-$suffix',
        'owner-$suffix',
        'synthetic-origin-$suffix',
        'synthetic-command-$suffix',
        at,
      ],
    );
  }
  final canonical =
      (await database
              .customSelect(
                "SELECT * FROM quest_instances WHERE instance_id = 'pinned-instance-a'",
              )
              .getSingle())
          .data;
  await database.customStatement(
    'INSERT INTO quest_instances '
    '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
    'origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,'
    'definition_digest,canonical_instance_id,record_kind) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)',
    [
      'alias-instance-a',
      canonical['quest_id'],
      'owner-a',
      canonical['catalog_version'],
      at,
      'completed',
      canonical['origin_owner_id'],
      canonical['period_key'],
      canonical['calendar_rule_id'],
      canonical['civil_label'],
      canonical['segments_json'],
      canonical['definition_digest'],
      'pinned-instance-a',
      'alias',
    ],
  );
}

Future<void> _seed(AppDatabase database) async {
  const now = 1792833600000;
  await database.customStatement(
    "INSERT INTO local_owners "
    "(id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES "
    "('owner-a', 'firebase-user', 'firebaseBound', $now, 1), "
    "('owner-b', 'other-user', 'firebaseBound', $now, 0)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES "
    "('category-a', 'owner-a', 'A', 'a', $now, $now), "
    "('category-b', 'owner-b', 'B', 'b', $now, $now)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('word-a', 'owner-a', 'category-a', 'hello', 'hello', 'สวัสดี', "
    "'สวัสดี', 'noun', $now, $now)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_imports "
    "(id, owner_id, category_id, source_type, source_name, source_hash, status, created_at_utc_ms) "
    "VALUES ('import-a', 'owner-a', 'category-a', 'csv', 'test', 'hash', 'complete', $now)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_import_rows "
    "(id, import_id, row_number, payload_hash, status) "
    "VALUES ('row-a', 'import-a', 1, 'hash', 'accepted')",
  );
  await database.customStatement(
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) "
    "VALUES ('session-a', 'owner-a', 'quiz', 'complete', $now, '1', '1')",
  );
  await database.customStatement(
    "INSERT INTO answer_attempts "
    "(id, owner_id, session_id, word_id, prompt_mode, is_correct, attempt_number, occurred_at_utc_ms) "
    "VALUES ('attempt-a', 'owner-a', 'session-a', 'word-a', 'meaning', 1, 1, $now)",
  );
  await database.customStatement(
    "INSERT INTO reward_transactions "
    "(id, owner_id, idempotency_key, transaction_type, amount, catalog_version, occurred_at_utc_ms) "
    "VALUES ('reward-a', 'owner-a', 'reward-key', 'earn', 5, 1, $now)",
  );
  await database.customStatement(
    "INSERT INTO owned_reward_items "
    "(id, owner_id, item_id, catalog_version, acquired_by_transaction_id, acquired_at_utc_ms) "
    "VALUES ('owned-a', 'owner-a', 'theme-a', 1, 'reward-a', $now)",
  );
  await database.customStatement(
    "INSERT INTO quest_definitions "
    "(quest_id, catalog_version, title, description, type, objectives_json, reward_json) "
    "VALUES ('quest-a', 1, 'Quest', 'Description', 'daily', '[]', '{}')",
  );
  await database.customStatement(
    "INSERT INTO quest_instances "
    "(instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms, state) "
    "VALUES ('instance-a', 'quest-a', 'owner-a', 1, $now, 'active')",
  );
  await database.customStatement(
    "INSERT INTO quest_objective_progress "
    "(id, instance_id, objective_id, target_count) "
    "VALUES ('objective-a', 'instance-a', 'objective-1', 1)",
  );
}
