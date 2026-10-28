import '../../identity/application/upgrade_guest_owner.dart';
import '../../identity/domain/local_owner.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../identity/domain/owner_upgrade.dart';
import '../../session/domain/app_entry_state.dart';
import '../domain/account_contracts.dart';

final class AccountUseCases {
  const AccountUseCases({
    required this.gateway,
    required this.owners,
    required this.upgradeGuestOwner,
    required this.entryState,
    this.onOwnerTransitionCommitted,
  });

  final AccountGateway gateway;
  final LocalOwnerRepository owners;
  final UpgradeGuestOwner upgradeGuestOwner;
  final AppEntryStateStore entryState;
  final Future<void> Function()? onOwnerTransitionCommitted;

  AccountSession? get currentSession => gateway.currentSession;

  Future<void> reconcileLocalOwner() async {
    final session = gateway.currentSession;
    final owner = await owners.getOrCreateActiveOwner();
    if (session != null) {
      if (owner.firebaseUid != session.uid) {
        await _bindOrSignOut(session.uid);
        await _notifyOwnerTransitionCommitted();
      }
      return;
    }
    if (owner.firebaseUid != null) {
      await upgradeGuestOwner.createLocalGuestAfterLogout(
        sourceOwnerId: owner.id,
      );
      await _notifyOwnerTransitionCommitted();
    }
  }

  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    final session = await gateway.register(
      email: _email(email),
      password: _password(password),
    );
    await _bindAndClearOrSignOut(session.uid);
    return session;
  }

  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    final session = await gateway.signIn(
      email: _email(email),
      password: _password(password),
    );
    await _bindAndClearOrSignOut(session.uid);
    return session;
  }

  Future<AccountSession> refreshVerification() => gateway.reload();

  Future<void> resendVerification() => gateway.sendVerification();

  Future<void> sendPasswordReset(String email) =>
      gateway.sendPasswordReset(_email(email));

  Future<void> applyEmailAction(EmailAction action, {String? newPassword}) {
    return switch (action.mode) {
      EmailActionMode.verifyEmail => gateway.applyEmailVerificationCode(
        action.code,
      ),
      EmailActionMode.resetPassword => gateway.confirmPasswordReset(
        code: action.code,
        newPassword: _password(newPassword ?? ''),
      ),
      EmailActionMode.unknown => throw const AccountException(
        AccountFailureCode.invalidActionCode,
      ),
    };
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => gateway.changePassword(
    currentPassword: _password(currentPassword),
    newPassword: _password(newPassword),
  );

  Future<OwnerUpgradeResult> signOutToLocalGuest() async {
    final previousEntry = await entryState.read();
    await entryState.clear();
    LocalOwner? previous;
    OwnerUpgradeResult? guest;
    try {
      previous = await owners.getOrCreateActiveOwner();
      guest = await upgradeGuestOwner.createLocalGuestAfterLogout(
        sourceOwnerId: previous.id,
      );
      await gateway.signOut();
    } catch (error, stackTrace) {
      if (previous != null && guest != null) {
        try {
          await upgradeGuestOwner.rollbackLocalGuestLogout(
            previousOwnerId: previous.id,
            guestOwnerId: guest.targetOwnerId,
          );
        } catch (_) {
          // Continue restoring entry state and preserve the original failure.
        }
      }
      try {
        await _restoreEntryState(previousEntry);
      } catch (_) {
        // Preserve the original failure after best-effort rollback.
      }
      await _notifyOwnerTransitionAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _notifyOwnerTransitionCommitted();
    return guest;
  }

  Future<void> _bindAndClearOrSignOut(String uid) async {
    AppEntryMode? previousEntry;
    try {
      previousEntry = await entryState.read();
      await _bind(uid);
      await entryState.clear();
    } catch (error, stackTrace) {
      try {
        await gateway.signOut();
      } catch (_) {
        // Preserve the binding/entry failure after best-effort provider reset.
      }
      if (previousEntry != null) {
        try {
          await _restoreEntryState(previousEntry);
        } catch (_) {
          // Preserve the original failure after best-effort entry restoration.
        }
      }
      await _notifyOwnerTransitionAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _notifyOwnerTransitionCommitted();
  }

  Future<void> _bindOrSignOut(String uid) async {
    try {
      await _bind(uid);
    } catch (_) {
      await gateway.signOut();
      await _notifyOwnerTransitionAfterFailure();
      rethrow;
    }
  }

  Future<void> _bind(String uid) async {
    final owner = await owners.getOrCreateActiveOwner();
    await upgradeGuestOwner(activeOwnerId: owner.id, firebaseUid: uid);
  }

  Future<void> _notifyOwnerTransitionCommitted() async {
    final callback = onOwnerTransitionCommitted;
    if (callback != null) await callback();
  }

  Future<void> _notifyOwnerTransitionAfterFailure() async {
    try {
      await _notifyOwnerTransitionCommitted();
    } on Object {
      // Preserve the transition's original failure after best-effort refresh.
    }
  }

  Future<void> _restoreEntryState(AppEntryMode previousEntry) {
    return previousEntry == AppEntryMode.guest
        ? entryState.markGuest()
        : entryState.clear();
  }

  String _email(String value) {
    final email = value.trim().toLowerCase();
    if (email.length > 254 ||
        !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
      throw const AccountException(AccountFailureCode.invalidEmail);
    }
    return email;
  }

  String _password(String value) {
    if (value.length < 8 || value.length > 128) {
      throw const AccountException(AccountFailureCode.weakPassword);
    }
    return value;
  }
}
