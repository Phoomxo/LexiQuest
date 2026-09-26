import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import '../../screens/setting_logout_recovery_test.dart' as fixtures;

void main() {
  test('BC queued logout cannot replace a newer canonical guest', () async {
    final db = AppDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final realOwners = DriftLocalOwnerRepository(
      db,
      generateId: () => 'account',
      nowUtc: () => DateTime.utc(2026),
    );
    final original = await realOwners.getOrCreateActiveOwner();
    await realOwners.bindFirebaseUid(original.id, 'synthetic-user');
    final lifecycle = HeldLifecycle();
    var id = 0;
    final repository = DriftOwnerUpgradeRepository(
      db,
      nowUtc: () => DateTime.utc(2026),
      generateOwnerId: () => 'guest-${id++}',
      generateConflictId: () => 'conflict',
      generateOwnerOperationToken: () => 'token-${id++}',
      deleteOwnerSecrets: (_) async {},
      transitionLifecycle: lifecycle,
    );
    final first = repository.createLocalGuestAfterLogout();
    await lifecycle.entered.future;
    final owners = ObservedOwners(realOwners);
    final gateway = fixtures.LogoutGateway();
    final account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(repository),
      entryState: fixtures.LogoutEntry(),
    );
    final second = expectLater(
      account.signOutToLocalGuest(),
      throwsA(anything),
    );
    await owners.beforeCreate.future;
    await Future<void>.delayed(Duration.zero);
    lifecycle.release.complete();
    final committed = await first;
    await second;
    expect(
      (await realOwners.getOrCreateActiveOwner()).id,
      committed.targetOwnerId,
    );
    expect(gateway.calls, 0);
    expect(await db.select(db.localOwners).get(), hasLength(2));
  });
  test(
    'BC retirement inside canonical transition rolls back guest transaction',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'account',
        nowUtc: () => DateTime.utc(2026),
      );
      final original = await owners.getOrCreateActiveOwner();
      await owners.bindFirebaseUid(original.id, 'synthetic-user');
      var current = true;
      var token = 0;
      final repository = DriftOwnerUpgradeRepository(
        db,
        nowUtc: () => DateTime.utc(2026),
        generateOwnerId: () => 'guest',
        generateConflictId: () => 'conflict',
        generateOwnerOperationToken: () => 'logout-${token++}',
        deleteOwnerSecrets: (_) async {},
        transitionLifecycle: RetireLifecycle(() => current = false),
      );
      final gateway = fixtures.LogoutGateway();
      final account = AccountUseCases(
        gateway: gateway,
        owners: owners,
        upgradeGuestOwner: UpgradeGuestOwner(repository),
        entryState: fixtures.LogoutEntry(),
      );
      await expectLater(
        account.signOutToLocalGuest(isCurrent: () => current),
        throwsA(anything),
      );
      expect((await owners.getOrCreateActiveOwner()).id, original.id);
      expect(
        await (db.select(
          db.localOwners,
        )..where((r) => r.id.equals('local:guest'))).get(),
        isEmpty,
      );
      expect(
        await (db.select(
          db.eventsV2,
        )..where((r) => r.ownerId.equals('local:guest'))).get(),
        isEmpty,
      );
      expect(gateway.calls, 0);
    },
  );
}

class HeldLifecycle implements OwnerTransitionLifecycle {
  final entered = Completer<void>(), release = Completer<void>();
  @override
  Future<T> run<T>({
    required String sourceOwnerId,
    required String operationToken,
    required Future<T> Function() operation,
    required String Function(T) targetOwnerId,
  }) async {
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return operation();
  }
}

class ObservedOwners implements LocalOwnerRepository {
  ObservedOwners(this.inner);
  final LocalOwnerRepository inner;
  final beforeCreate = Completer<void>();
  int reads = 0;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    final result = await inner.getOrCreateActiveOwner();
    if (++reads == 2) beforeCreate.complete();
    return result;
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) =>
      inner.bindFirebaseUid(ownerId, uid);
}

class RetireLifecycle implements OwnerTransitionLifecycle {
  RetireLifecycle(this.retire);
  final void Function() retire;
  @override
  Future<T> run<T>({
    required String sourceOwnerId,
    required String operationToken,
    required Future<T> Function() operation,
    required String Function(T) targetOwnerId,
  }) async {
    retire();
    return operation();
  }
}
