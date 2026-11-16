import '../../identity/application/upgrade_guest_owner.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../identity/domain/owner_upgrade.dart';
import '../domain/account_contracts.dart';

final class AccountUseCases {
  const AccountUseCases({
    required this.gateway,
    required this.owners,
    required this.upgradeGuestOwner,
  });

  final AccountGateway gateway;
  final LocalOwnerRepository owners;
  final UpgradeGuestOwner upgradeGuestOwner;

  AccountSession? get currentSession => gateway.currentSession;

  bool get googleSignInAvailable =>
      gateway is GoogleAccountGateway &&
      (gateway as GoogleAccountGateway).googleSignInAvailable;

  Future<void> reconcileLocalOwner() async {
    final session = gateway.currentSession;
    final owner = await owners.getOrCreateActiveOwner();
    if (session != null) {
      if (owner.firebaseUid != session.uid) {
        await _bindOrSignOut(session.uid);
      }
      return;
    }
    if (owner.firebaseUid != null) {
      await upgradeGuestOwner.createLocalGuestAfterLogout();
    }
  }

  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    final previousSession = currentSession;
    final session = await gateway.register(
      email: _email(email),
      password: _password(password),
    );
    await _bindOrSignOut(session.uid, previousSession: previousSession);
    return session;
  }

  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    final previousSession = currentSession;
    final session = await gateway.signIn(
      email: _email(email),
      password: _password(password),
    );
    await _bindOrSignOut(session.uid, previousSession: previousSession);
    return session;
  }

  Future<AccountSession> signInWithGoogle() async {
    final google = gateway is GoogleAccountGateway
        ? gateway as GoogleAccountGateway
        : null;
    if (google == null || !google.googleSignInAvailable) {
      throw const AccountException(AccountFailureCode.unavailable);
    }
    final previousSession = currentSession;
    final session = await google.signInWithGoogle();
    await _bindOrSignOut(session.uid, previousSession: previousSession);
    return session;
  }

  Future<AccountSession> refreshVerification() => gateway.reload();

  Future<AccountSession> updateDisplayName(String value) async {
    final name = value.trim();
    if (name.isEmpty ||
        name.runes.length > 50 ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(name)) {
      throw const AccountException(AccountFailureCode.invalidDisplayName);
    }
    final session = currentSession;
    if (session == null ||
        session.isAnonymous ||
        (await owners.getOrCreateActiveOwner()).firebaseUid != session.uid) {
      throw const AccountException(AccountFailureCode.invalidCredential);
    }
    return gateway.updateDisplayName(name);
  }

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
    final previous = await owners.getOrCreateActiveOwner();
    final guest = await upgradeGuestOwner.createLocalGuestAfterLogout();
    try {
      await gateway.signOut();
      return guest;
    } catch (_) {
      await upgradeGuestOwner.rollbackLocalGuestLogout(
        previousOwnerId: previous.id,
        guestOwnerId: guest.targetOwnerId,
      );
      rethrow;
    }
  }

  Future<void> _bindOrSignOut(
    String uid, {
    AccountSession? previousSession,
  }) async {
    try {
      await _bind(uid, previousSession: previousSession);
    } catch (_) {
      await gateway.signOut();
      rethrow;
    }
  }

  Future<void> _bind(String uid, {AccountSession? previousSession}) async {
    final owner = await owners.getOrCreateActiveOwner();
    var ownerId = owner.id;
    if (owner.firebaseUid != null &&
        owner.firebaseUid != uid &&
        !(previousSession?.isAnonymous == true &&
            previousSession?.uid == owner.firebaseUid)) {
      ownerId =
          (await upgradeGuestOwner.createLocalGuestAfterLogout()).targetOwnerId;
    }
    await upgradeGuestOwner(activeOwnerId: ownerId, firebaseUid: uid);
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
