import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late AccountUseCases account;
  late _Gateway gateway;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner-${sequence++}',
      nowUtc: () => DateTime.utc(2026, 10, 20),
    );
    gateway = _Gateway();
    account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(
        DriftOwnerUpgradeRepository(
          database,
          nowUtc: () => DateTime.utc(2026, 10, 20),
          generateConflictId: () => 'conflict-${sequence++}',
          generateOwnerId: () => 'guest-${sequence++}',
        ),
      ),
    );
    await _seedA(database);
  });

  tearDown(() => database.close());

  for (final existingB in [false, true]) {
    for (final entry in ['restore', 'signIn', 'register', 'google']) {
      test(
        '$entry isolates registered A from ${existingB ? 'existing' : 'new'} B',
        () async {
          if (existingB) await _seedB(database);
          final before = await _snapshotA(database);
          gateway.currentSession = _session(
            entry == 'restore' ? 'uid-b' : 'uid-a',
          );

          await _enter(account, entry);

          expect(await _snapshotA(database), before);
          final active = await owners.getOrCreateActiveOwner();
          expect(active.firebaseUid, 'uid-b');
          expect(active.id, isNot('owner-a'));
          if (existingB) expect(active.id, 'owner-b');
          final exported = await DriftExportReader(database).load(
            ownerId: active.id,
            vocabulary: true,
            attempts: true,
            reading: true,
          );
          expect(exported.recordCount, 0);
        },
      );
    }

    test(
      'anonymous upgrade preserves evidence and requeues once (${existingB ? 'existing' : 'new'} B)',
      () async {
        if (existingB) await _seedB(database);
        gateway.currentSession = _session('uid-a', anonymous: true);

        await account.signIn(email: 'b@example.test', password: 'synthetic123');
        await account.reconcileLocalOwner();

        final active = await owners.getOrCreateActiveOwner();
        expect(active.firebaseUid, 'uid-b');
        final word = await database
            .select(database.vocabularyWords)
            .getSingle();
        final attempt = await database
            .select(database.answerAttempts)
            .getSingle();
        expect(word.ownerId, active.id);
        expect(attempt.ownerId, active.id);
        expect(word.cloudRevision, 0);
        final pending =
            await (database.select(database.outboxOperations)..where(
                  (row) =>
                      row.ownerId.equals(active.id) &
                      row.state.equals('pending'),
                ))
                .get();
        expect(pending.where((row) => row.entityType == 'word'), hasLength(1));
        expect(
          pending.where((row) => row.entityType == 'attempt'),
          hasLength(1),
        );
      },
    );

    test(
      'binding failure preserves A and signs out (${existingB ? 'existing' : 'new'} B)',
      () async {
        if (existingB) await _seedB(database);
        final before = await _snapshotA(database);
        gateway.currentSession = _session('uid-b');
        await database.customStatement('''
        CREATE TRIGGER fail_binding BEFORE UPDATE ON local_owners
        WHEN NEW.firebase_uid = 'uid-b' AND NEW.is_active = 1
        BEGIN SELECT RAISE(ABORT, 'synthetic binding failure'); END
      ''');

        await expectLater(
          account.reconcileLocalOwner(),
          throwsA(isA<Exception>()),
        );

        expect(await _snapshotA(database), before);
        expect(gateway.signOutCalls, 1);
        expect(gateway.currentSession, isNull);
        await account.reconcileLocalOwner();
        expect((await owners.getOrCreateActiveOwner()).firebaseUid, isNull);
      },
    );
  }

  test(
    'restoring the same uid changes no owner data or local owners',
    () async {
      gateway.currentSession = _session('uid-a');
      final before = await _snapshotA(database);

      await account.reconcileLocalOwner();

      expect(await _snapshotA(database), before);
      expect(await database.select(database.localOwners).get(), hasLength(1));
      expect(gateway.signOutCalls, 0);
    },
  );
}

Future<void> _enter(AccountUseCases account, String entry) async {
  switch (entry) {
    case 'restore':
      await account.reconcileLocalOwner();
    case 'signIn':
      await account.signIn(email: 'b@example.test', password: 'synthetic123');
    case 'register':
      await account.register(email: 'b@example.test', password: 'synthetic123');
    case 'google':
      await account.signInWithGoogle();
  }
}

Future<Map<String, Object?>> _snapshotA(AppDatabase database) async {
  final snapshot = <String, Object?>{};
  for (final table in [
    'vocabulary_categories',
    'vocabulary_words',
    'learning_sessions',
    'answer_attempts',
    'outbox_operations',
    'sync_checkpoints',
  ]) {
    snapshot[table] =
        (await database
                .customSelect(
                  'SELECT * FROM $table WHERE owner_id = ?',
                  variables: const [Variable<String>('owner-a')],
                )
                .get())
            .map((row) => row.data)
            .toList();
  }
  final owner = await (database.select(
    database.localOwners,
  )..where((row) => row.id.equals('owner-a'))).getSingle();
  snapshot['binding'] = owner.firebaseUid;
  snapshot['accountState'] = owner.accountState;
  return snapshot;
}

Future<void> _seedA(AppDatabase database) async {
  await database.customStatement(
    "INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES ('owner-a', 'uid-a', 'firebaseBound', 1, 1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, sort_order, local_revision, cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) VALUES ('category-a', 'owner-a', 'Travel', 'travel', 0, 1, 4, 0, 1, 1)",
  );
  await database.customStatement(
    "INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, source, is_global, local_revision, cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms, last_acknowledged_at_utc_ms, server_updated_at_utc_ms) VALUES ('word-a', 'owner-a', 'category-a', 'station', 'station', 'สถานี', 'สถานี', 'noun', 'manual', 0, 1, 4, 0, 1, 1, 40, 40)",
  );
  await database.customStatement(
    "INSERT INTO learning_sessions VALUES ('session-a', 'owner-a', 'quiz', 'completed', 1, 2, 1, 0, 100, '1', '1')",
  );
  await database.customStatement(
    "INSERT INTO answer_attempts VALUES ('attempt-a', 'owner-a', 'session-a', 'word-a', 'meaning', 1, 10, 1, 2, NULL)",
  );
  await database.customStatement(
    "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, state, base_revision, created_at_utc_ms, acknowledged_at_utc_ms) VALUES ('word-a:1', 'owner-a', 'word', 'word-a', 'upsert', 'acknowledged', 3, 1, 40)",
  );
  await database.customStatement(
    "INSERT INTO sync_checkpoints VALUES ('checkpoint-a', 'owner-a', 'words', 'cursor-a', 40)",
  );
}

Future<void> _seedB(AppDatabase database) => database.customStatement(
  "INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES ('owner-b', 'uid-b', 'firebaseBound', 2, 0)",
);

AccountSession _session(String uid, {bool anonymous = false}) => AccountSession(
  uid: uid,
  email: anonymous ? null : '$uid@example.test',
  isAnonymous: anonymous,
  emailVerified: !anonymous,
);

final class _Gateway implements AccountGateway, GoogleAccountGateway {
  @override
  AccountSession? currentSession;
  int signOutCalls = 0;

  @override
  bool get googleSignInAvailable => true;

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async => currentSession = _session('uid-b');

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => signIn(email: email, password: password);

  @override
  Future<AccountSession> signInWithGoogle() async =>
      currentSession = _session('uid-b');

  @override
  Future<void> signOut() async {
    signOutCalls++;
    currentSession = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}
