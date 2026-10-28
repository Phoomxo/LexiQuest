import 'package:firebase_auth/firebase_auth.dart';

import 'account_gateway.dart';
import 'account_models.dart';

final class FirebaseAccountGateway implements AccountGateway {
  FirebaseAccountGateway({FirebaseAuth? firebaseAuth})
    : _firebaseAuth = firebaseAuth ?? FirebaseAuth.instance;

  final FirebaseAuth _firebaseAuth;

  @override
  AccountSession? get currentSession => _toSession(_firebaseAuth.currentUser);

  @override
  Stream<AccountSession?> authStateChanges() =>
      _firebaseAuth.authStateChanges().map(_toSession);

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => _run(() async {
    final credential = await _firebaseAuth.signInWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireSession(credential.user);
  });

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) => _run(() async {
    final credential = await _firebaseAuth.createUserWithEmailAndPassword(
      email: email,
      password: password,
    );
    return _requireSession(credential.user);
  });

  @override
  Future<void> signOut() => _run(_firebaseAuth.signOut);

  @override
  Future<AccountSession?> reloadSession() => _run(() async {
    final user = _requireCurrentUser();
    await user.reload();
    return _toSession(_firebaseAuth.currentUser);
  });

  @override
  Future<void> sendVerificationEmail() =>
      _run(() => _requireCurrentUser().sendEmailVerification());

  @override
  Future<void> applyVerificationCode(String code) =>
      _run(() => _firebaseAuth.applyActionCode(code));

  @override
  Future<void> requestPasswordReset(String email) =>
      _run(() => _firebaseAuth.sendPasswordResetEmail(email: email));

  @override
  Future<String> verifyPasswordResetCode(String code) =>
      _run(() => _firebaseAuth.verifyPasswordResetCode(code));

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => _run(
    () => _firebaseAuth.confirmPasswordReset(
      code: code,
      newPassword: newPassword,
    ),
  );

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _run(() async {
    final user = _requireCurrentUser();
    final email = user.email;
    if (email == null || email.isEmpty) {
      throw const AccountOperationException('email-unavailable');
    }
    final credential = EmailAuthProvider.credential(
      email: email,
      password: currentPassword,
    );
    await user.reauthenticateWithCredential(credential);
    await user.updatePassword(newPassword);
  });

  @override
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  }) => _run(() async {
    final user = _requireCurrentUser();
    if (!user.isAnonymous) {
      throw const AccountOperationException('not-anonymous');
    }
    final previousUid = user.uid;
    final credential = EmailAuthProvider.credential(
      email: email,
      password: password,
    );
    final upgraded = await user.linkWithCredential(credential);
    return GuestUpgradeResult(
      previousUid: previousUid,
      session: _requireSession(upgraded.user),
    );
  });

  User _requireCurrentUser() {
    final user = _firebaseAuth.currentUser;
    if (user == null) {
      throw const AccountOperationException('no-current-user');
    }
    return user;
  }

  AccountSession _requireSession(User? user) {
    final session = _toSession(user);
    if (session == null) {
      throw const AccountOperationException('missing-user');
    }
    return session;
  }

  AccountSession? _toSession(User? user) {
    if (user == null) return null;
    return AccountSession(
      uid: user.uid,
      email: user.email,
      isAnonymous: user.isAnonymous,
      isEmailVerified: user.emailVerified,
    );
  }

  Future<T> _run<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on AccountOperationException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountOperationException(error.code);
    } on FirebaseException catch (error) {
      throw AccountOperationException(error.code);
    } on Object {
      throw const AccountOperationException('unknown');
    }
  }
}
