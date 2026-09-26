import 'dart:async';
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
  static final _logoutPending = Expando<bool>();

  AccountSession? get currentSession => gateway.currentSession;
  Stream<AccountSession?> get sessionChanges {
    final source = gateway;
    return source is AccountSessionObserver
        ? (source as AccountSessionObserver).sessionChanges
        : const Stream<AccountSession?>.empty();
  }

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
    bool Function()? isCurrent,
  }) {
    if (isCurrent != null && !isCurrent()) {
      throw const AccountException(AccountFailureCode.cancelled);
    }
    return gateway.changePassword(
      currentPassword: _password(currentPassword),
      newPassword: _password(newPassword),
      isCurrent: isCurrent,
    );
  }

  Future<OwnerUpgradeResult> signOutToLocalGuest({
    bool Function()? isCurrent,
  }) async {
    if (_logoutPending[gateway] == true) {
      throw const AccountException(AccountFailureCode.cancelled);
    }
    _logoutPending[gateway] = true;
    StreamSubscription<AccountSession?>? subscription;
    try {
      var sessionChanged = false;
      var initial = true;
      final startingUid = gateway.currentSession?.uid;
      subscription = sessionChanges.listen(
        (session) {
          if (!initial || session?.uid != startingUid) sessionChanged = true;
          initial = false;
        },
        onError: (Object _, StackTrace _) {
          sessionChanged = true;
        },
      );
      return await _signOutToLocalGuest(
        isCurrent: isCurrent,
        sessionUnchanged: () => !sessionChanged,
      );
    } finally {
      _logoutPending[gateway] = false;
      // Cancellation stops delivery immediately. Provider stream cleanup must
      // not hold an already committed account transition open.
      if (subscription != null) {
        unawaited(
          Future<void>.sync(subscription.cancel).catchError((Object _) {}),
        );
      }
    }
  }

  Future<OwnerUpgradeResult> _signOutToLocalGuest({
    bool Function()? isCurrent,
    required bool Function() sessionUnchanged,
  }) async {
    final session = gateway.currentSession;
    final identity = session?.sessionIdentity ?? session;
    bool sameSession() {
      final current = gateway.currentSession;
      return sessionUnchanged() &&
          current?.uid == session?.uid &&
          (current?.sessionIdentity ?? current) == identity;
    }

    void admit() {
      if (!(isCurrent?.call() ?? true) || !sameSession()) {
        throw const AccountException(AccountFailureCode.cancelled);
      }
    }

    admit();
    final previousEntry = await entryState.read();
    admit();
    LocalOwner? previous;
    OwnerUpgradeResult? guest;
    try {
      await entryState.clear();
      admit();
      previous = await owners.getOrCreateActiveOwner();
      admit();
      guest = await upgradeGuestOwner.createLocalGuestAfterLogout(
        sourceOwnerId: previous.id,
        isCurrent: () {
          admit();
          return true;
        },
        beforeCreate: () async {
          admit();
          final active = await owners.getOrCreateActiveOwner();
          admit();
          if (active.id != previous!.id) {
            throw const AccountException(AccountFailureCode.cancelled);
          }
        },
      );
      admit();
      await gateway.signOut();
    } catch (error, stackTrace) {
      // Preserve canonical rollback only while the original provider session
      // still owns this attempt. A committed sign-out or newer session is not
      // reversible, even if the provider returned an error.
      final canRestore = sameSession();
      var restoreEntry = canRestore;
      if (canRestore && previous != null && guest == null) {
        try {
          restoreEntry =
              (await owners.getOrCreateActiveOwner()).id == previous.id;
        } on Object {
          restoreEntry = false;
        }
      }
      if (canRestore && previous != null && guest != null) {
        try {
          await upgradeGuestOwner.rollbackLocalGuestLogout(
            previousOwnerId: previous.id,
            guestOwnerId: guest.targetOwnerId,
          );
        } catch (_) {
          try {
            restoreEntry =
                (await owners.getOrCreateActiveOwner()).id ==
                guest.targetOwnerId;
          } on Object {
            restoreEntry = false;
          }
          // Continue restoring entry state and preserve the original failure.
        }
      }
      try {
        if (restoreEntry && sameSession()) {
          await _restoreEntryState(previousEntry);
        }
      } catch (_) {
        // Preserve the original failure after best-effort rollback.
      }
      await _notifyOwnerTransitionAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    }
    await _notifyOwnerTransitionCommitted();
    if (session != null) {
      final active = await owners.getOrCreateActiveOwner();
      if (active.id != guest.targetOwnerId ||
          (gateway.currentSession != null && !sameSession())) {
        // Provider success is retained. A newer owner/session must not be
        // represented as this attempt's guest or navigated away from.
        throw const AccountException(AccountFailureCode.cancelled);
      }
    }
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
