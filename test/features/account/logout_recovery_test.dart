import 'dart:async';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import '../../screens/setting_logout_recovery_test.dart' as fixtures;

void main() {
  test(
    'BC observation setup error releases admission for a separate explicit attempt',
    () async {
      final f = fixtures.LogoutFixture();
      final gateway = FailingObservationGateway();
      final account = AccountUseCases(
        gateway: gateway,
        owners: f.owners,
        upgradeGuestOwner: UpgradeGuestOwner(f.upgrades),
        entryState: f.entry,
      );
      await expectLater(account.signOutToLocalGuest(), throwsStateError);
      expect(f.entry.clears, 0);
      gateway.fail = false;
      await account.signOutToLocalGuest();
      expect(gateway.calls, 1);
    },
  );
  test(
    'BC newer owner survives successful late provider acknowledgement',
    () async {
      final f = fixtures.LogoutFixture();
      final hold = Completer<void>();
      f.gateway.hold = hold.future;
      final result = expectLater(
        f.account!.signOutToLocalGuest(),
        throwsA(isA<AccountException>()),
      );
      await Future<void>.delayed(Duration.zero);
      f.owners.active = LocalOwner(
        id: 'newer-owner',
        createdAtUtc: DateTime.utc(2026),
      );
      hold.complete();
      await result;
      expect(f.owners.active.id, 'newer-owner');
      expect(f.upgrades.rollbacks, 0);
      expect(f.gateway.calls, 1);
    },
  );
  test(
    'BC partial entry clear failure restores previous local entry',
    () async {
      final f = fixtures.LogoutFixture();
      f.entry.clearBeforeError = true;
      f.entry.clearFailure = StateError('synthetic clear acknowledgement');
      await expectLater(f.account!.signOutToLocalGuest(), throwsStateError);
      expect(f.entry.mode, AppEntryMode.guest);
      expect(f.gateway.calls, 0);
    },
  );
  test(
    'BC rollback failure still restores local entry when guest remains active',
    () async {
      final f = fixtures.LogoutFixture();
      f.gateway.failure = StateError('synthetic provider failure');
      f.upgrades.rollbackFailure = StateError('synthetic rollback failure');
      await expectLater(f.account!.signOutToLocalGuest(), throwsStateError);
      expect(f.owners.active.id, 'new-guest');
      expect(f.entry.mode, AppEntryMode.guest);
    },
  );
  test('BC duplicate use case call cannot create two guests', () async {
    final f = fixtures.LogoutFixture();
    final hold = Completer<void>();
    f.entry.hold = hold.future;
    final first = f.account!.signOutToLocalGuest();
    final second = expectLater(
      f.account!.signOutToLocalGuest(),
      throwsA(isA<AccountException>()),
    );
    hold.complete();
    await first;
    await second;
    expect(f.upgrades.creates, 1);
    expect(f.gateway.calls, 1);
  });
  test(
    'BC same UID event during owner read retires provider admission',
    () async {
      final f = fixtures.LogoutFixture();
      final hold = Completer<void>();
      f.owners.hold = hold.future;
      final result = expectLater(
        f.account!.signOutToLocalGuest(),
        throwsA(isA<AccountException>()),
      );
      await Future<void>.delayed(Duration.zero);
      f.gateway.events.add(f.gateway.currentSession);
      hold.complete();
      await result;
      expect(f.gateway.calls, 0);
      expect(f.upgrades.creates, 0);
    },
  );
  test(
    'BC queued owner coordination cannot create guest after retirement',
    () async {
      final f = fixtures.LogoutFixture();
      final hold = Completer<void>();
      var current = true;
      final account = AccountUseCases(
        gateway: f.gateway,
        owners: f.owners,
        entryState: f.entry,
        upgradeGuestOwner: UpgradeGuestOwner(
          f.upgrades,
          coordinate: (_, operation) async {
            await hold.future;
            return operation();
          },
        ),
      );
      final result = expectLater(
        account.signOutToLocalGuest(isCurrent: () => current),
        throwsA(isA<AccountException>()),
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      hold.complete();
      await result;
      expect(f.upgrades.creates, 0);
      expect(f.gateway.calls, 0);
      expect(f.entry.mode, AppEntryMode.guest);
    },
  );
  test(
    'BC owner replacement during coordination cannot be signed out',
    () async {
      final f = fixtures.LogoutFixture();
      final hold = Completer<void>();
      final account = AccountUseCases(
        gateway: f.gateway,
        owners: f.owners,
        entryState: f.entry,
        upgradeGuestOwner: UpgradeGuestOwner(
          f.upgrades,
          coordinate: (_, operation) async {
            await hold.future;
            return operation();
          },
        ),
      );
      final result = expectLater(
        account.signOutToLocalGuest(),
        throwsA(isA<AccountException>()),
      );
      await Future<void>.delayed(Duration.zero);
      f.owners.active = LocalOwner(
        id: 'newer-owner',
        createdAtUtc: DateTime.utc(2026),
      );
      hold.complete();
      await result;
      expect(f.owners.active.id, 'newer-owner');
      expect(f.entry.restores, 0);
      expect(f.gateway.calls, 0);
    },
  );
  test(
    'BC retired guest completion finishes canonical rollback without provider',
    () async {
      final f = fixtures.LogoutFixture();
      final hold = Completer<void>();
      f.upgrades.hold = hold.future;
      var current = true;
      final result = expectLater(
        f.account!.signOutToLocalGuest(isCurrent: () => current),
        throwsA(isA<AccountException>()),
      );
      await Future<void>.delayed(Duration.zero);
      current = false;
      hold.complete();
      await result;
      expect(f.upgrades.rollbacks, 1);
      expect(f.owners.active.id, 'account-owner');
      expect(f.entry.mode, AppEntryMode.guest);
      expect(f.gateway.calls, 0);
    },
  );
  test(
    'BC provider committed before error must not restore account owner or entry',
    () async {
      final f = fixtures.LogoutFixture();
      f.gateway.commitBeforeError = true;
      f.gateway.failure = StateError('synthetic acknowledgement lost');
      await expectLater(f.account!.signOutToLocalGuest(), throwsStateError);
      expect(f.owners.active.id, 'new-guest');
      expect(f.upgrades.rollbacks, 0);
      expect(f.entry.mode, AppEntryMode.signedOut);
    },
  );
  test('BC newer session and owner survive delayed provider failure', () async {
    final f = fixtures.LogoutFixture();
    final hold = Completer<void>();
    f.gateway.hold = hold.future;
    f.gateway.failure = StateError('synthetic late failure');
    final result = expectLater(
      f.account!.signOutToLocalGuest(),
      throwsStateError,
    );
    await Future<void>.delayed(Duration.zero);
    f.gateway.currentSession = const AccountSession(
      uid: 'new-account',
      email: 'new@example.test',
      isAnonymous: false,
      emailVerified: true,
    );
    f.owners.active = LocalOwner(
      id: 'new-owner',
      firebaseUid: 'new-account',
      createdAtUtc: DateTime.utc(2026),
    );
    hold.complete();
    await result;
    expect(f.owners.active.id, 'new-owner');
    expect(f.upgrades.rollbacks, 0);
    expect(f.entry.restores, 0);
  });
  for (final failure in ['read', 'clear', 'owner', 'guest']) {
    test('BC $failure failure leaves provider untouched', () async {
      final f = fixtures.LogoutFixture();
      final error = StateError('synthetic $failure failure');
      switch (failure) {
        case 'read':
          f.entry.readFailure = error;
        case 'clear':
          f.entry.clearFailure = error;
        case 'owner':
          f.owners.failure = error;
        case 'guest':
          f.upgrades.failure = error;
      }
      await expectLater(f.account!.signOutToLocalGuest(), throwsA(same(error)));
      expect(f.gateway.calls, 0);
      expect(f.owners.active.id, 'account-owner');
      expect(f.entry.mode, AppEntryMode.guest);
    });
  }
}

class FailingObservationGateway extends fixtures.LogoutGateway {
  bool fail = true;
  @override
  Stream<AccountSession?> get sessionChanges {
    if (fail) throw StateError('synthetic observation setup');
    return super.sessionChanges;
  }
}
