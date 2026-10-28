import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/data/local/shared_preferences_account_deletion_journal.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';

import '../../support/experiment_assignment_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

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
      final retained = <String, List<Map<String, Object?>>>{};
      for (final table in [
        'motivation_measurement_runs',
        'motivation_responses',
      ]) {
        retained[table] =
            (await database
                    .customSelect(
                      'SELECT * FROM $table WHERE owner_id = ? ORDER BY id',
                      variables: const [Variable<String>('owner-b')],
                    )
                    .get())
                .map((row) => row.data)
                .toList();
      }
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
      for (final table in const [
        'research_consents',
        'experiment_assignments',
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'events_v2',
        'outbox_operations',
      ]) {
        expect(
          await _count(database, table, 'owner_id = ?', ['owner-b']),
          1,
          reason: '$table keeps owner B research evidence',
        );
      }
      for (final entry in retained.entries) {
        final after = await database
            .customSelect(
              'SELECT * FROM ${entry.key} WHERE owner_id = ? ORDER BY id',
              variables: const [Variable<String>('owner-b')],
            )
            .get();
        expect(after.map((row) => row.data).toList(), entry.value);
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
      nowUtc: () => now,
      recoveryRetention: const Duration(days: 7),
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
      ownerWrites: DriftOwnerWriteCoordinator(database, nowUtc: () => now),
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
  @override
  Future<FullAccountExportReceipt> export({required String ownerId}) =>
      throw UnimplementedError();

  @override
  Future<RecentAuthenticationReceipt> reauthenticate({
    required String firebaseUid,
  }) => throw UnimplementedError();

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) => throw UnimplementedError();
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
  await database.customStatement(
    "INSERT INTO research_consents "
    "(id, owner_id, consent_version, consent_state, decided_at_utc_ms) "
    "VALUES ('consent-research-a', 'owner-a', 1, 'accepted', $now), "
    "('consent-research-b', 'owner-b', 1, 'accepted', $now)",
  );
  final assignmentA = await seedOwnerAssignment(database, 'owner-a');
  final assignmentB = await seedOwnerAssignment(database, 'owner-b');
  final permitA = await insertOwnerParticipation(
    database,
    'owner-a',
    assignmentId: assignmentA,
  );
  final permitB = await insertOwnerParticipation(
    database,
    'owner-b',
    assignmentId: assignmentB,
  );
  await insertOwnerMotivationMeasurement(database, permitA);
  await insertOwnerMotivationMeasurement(database, permitB);
  await database.customStatement('''
    INSERT INTO events_v2 (
      event_id, event_type, event_version, occurred_at_utc, recorded_at_utc,
      actor_identity, owner_id, aggregate_type, aggregate_id,
      idempotency_key, consent_context_json, app_version, build_id,
      privacy_classification, payload_json
    ) VALUES
      ('event-research-a', 'research.synthetic', 1, 1792833600000,
       1792833600000, 'owner-a', 'owner-a', 'research', 'study-a',
       'research-key-a', '{"consentVersion":1}', '1', 'build', 'ownerOnly',
       '{"marker":"research-a"}'),
      ('event-research-b', 'research.synthetic', 1, 1792833600000,
       1792833600000, 'owner-b', 'owner-b', 'research', 'study-b',
       'research-key-b', '{"consentVersion":1}', '1', 'build', 'ownerOnly',
       '{"marker":"research-b"}')
    ''');
  await database.customStatement(
    "INSERT INTO outbox_operations "
    "(operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) "
    "VALUES ('outbox-research-a', 'owner-a', 'event_v2', "
    "'event-research-a', 'upsert', $now), "
    "('outbox-research-b', 'owner-b', 'event_v2', "
    "'event-research-b', 'upsert', $now)",
  );
}
