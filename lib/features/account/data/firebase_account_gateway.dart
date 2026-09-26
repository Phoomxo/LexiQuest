import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';

import '../domain/account_contracts.dart';

const _authActionUrl =
    'https://vocab-learning-app-219ef.firebaseapp.com/auth/action';

final class FirebaseAccountGateway
    implements AccountGateway, AccountSessionObserver {
  FirebaseAccountGateway(this.auth);

  final FirebaseAuth auth;
  bool _passwordChanging = false;

  @override
  AccountSession? get currentSession => _session(auth.currentUser);

  @override
  Stream<AccountSession?> get sessionChanges =>
      auth.authStateChanges().map(_session);

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async {
    try {
      final current = auth.currentUser;
      final credential = EmailAuthProvider.credential(
        email: email,
        password: password,
      );
      final result = current != null && current.isAnonymous
          ? await current.linkWithCredential(credential)
          : await auth.createUserWithEmailAndPassword(
              email: email,
              password: password,
            );
      final session = _session(result.user);
      if (session == null) {
        throw const AccountException(AccountFailureCode.unknown);
      }
      try {
        await result.user!.sendEmailVerification(_actionSettings());
      } on Object {
        // Account creation/linking has committed. Return that identity so the
        // application can bind it and retry delivery without creating again.
        return AccountSession(
          uid: session.uid,
          email: session.email,
          isAnonymous: session.isAnonymous,
          emailVerified: session.emailVerified,
          verificationEmailPending: true,
        );
      }
      return session;
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    } catch (_) {
      throw const AccountException(AccountFailureCode.unavailable);
    }
  }

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) async {
    try {
      final result = await auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );
      final session = _session(result.user);
      if (session == null) {
        throw const AccountException(AccountFailureCode.unknown);
      }
      return session;
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    } catch (_) {
      throw const AccountException(AccountFailureCode.unavailable);
    }
  }

  @override
  Future<AccountSession> reload() async {
    final user = auth.currentUser;
    if (user == null) {
      throw const AccountException(AccountFailureCode.invalidCredential);
    }
    try {
      await user.reload();
      final session = _session(auth.currentUser);
      if (session == null) {
        throw const AccountException(AccountFailureCode.invalidCredential);
      }
      return session;
    } on AccountException {
      rethrow;
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> sendVerification() async {
    final user = auth.currentUser;
    if (user == null || user.emailVerified) return;
    try {
      await user.sendEmailVerification(_actionSettings());
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> sendPasswordReset(String email) async {
    try {
      await auth.sendPasswordResetEmail(
        email: email,
        actionCodeSettings: _actionSettings(),
      );
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> applyEmailVerificationCode(String code) async {
    try {
      await auth.checkActionCode(code);
      await auth.applyActionCode(code);
      await auth.currentUser?.reload();
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    try {
      await auth.verifyPasswordResetCode(code);
      await auth.confirmPasswordReset(code: code, newPassword: newPassword);
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool Function()? isCurrent,
  }) async {
    if (_passwordChanging) {
      throw const AccountException(AccountFailureCode.cancelled);
    }
    final user = auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AccountException(AccountFailureCode.invalidCredential);
    }
    var retired = false;
    var firstEvent = true;
    final observed = Completer<void>();
    StreamSubscription<User?>? subscription;
    void requireCurrent() {
      if (retired ||
          auth.currentUser?.uid != user.uid ||
          (isCurrent != null && !isCurrent())) {
        throw const AccountException(AccountFailureCode.cancelled);
      }
    }

    requireCurrent();
    _passwordChanging = true;
    try {
      subscription = auth.authStateChanges().listen(
        (session) {
          // The initial snapshot is not a new sign-in. Subsequent auth-state
          // events, even for the same UID, retire this operation.
          if (!firstEvent || session?.uid != user.uid) retired = true;
          firstEvent = false;
          if (!observed.isCompleted) observed.complete();
        },
        onError: (Object _, StackTrace _) {
          retired = true;
          if (!observed.isCompleted) observed.complete();
        },
        onDone: () {
          retired = true;
          if (!observed.isCompleted) observed.complete();
        },
      );
      await observed.future;
      requireCurrent();
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      requireCurrent();
      await user.updatePassword(newPassword);
      // Once sent, a password update cannot be rolled back or read back.
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    } finally {
      await subscription?.cancel();
      _passwordChanging = false;
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await auth.signOut();
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  ActionCodeSettings _actionSettings() => ActionCodeSettings(
    url: _authActionUrl,
    handleCodeInApp: true,
    androidPackageName: 'com.lexiquest.app',
    androidInstallApp: true,
    androidMinimumVersion: '1',
  );

  AccountSession? _session(User? user) => user == null
      ? null
      : AccountSession(
          uid: user.uid,
          sessionIdentity: user.uid,
          email: user.email,
          isAnonymous: user.isAnonymous,
          emailVerified: user.emailVerified,
        );

  AccountFailureCode _map(String code) => switch (code) {
    'invalid-email' => AccountFailureCode.invalidEmail,
    'weak-password' => AccountFailureCode.weakPassword,
    'email-already-in-use' ||
    'credential-already-in-use' => AccountFailureCode.emailInUse,
    'wrong-password' ||
    'invalid-credential' ||
    'user-not-found' => AccountFailureCode.invalidCredential,
    'user-disabled' => AccountFailureCode.userDisabled,
    'too-many-requests' => AccountFailureCode.tooManyRequests,
    'requires-recent-login' => AccountFailureCode.requiresRecentLogin,
    'invalid-action-code' => AccountFailureCode.invalidActionCode,
    'expired-action-code' => AccountFailureCode.expiredActionCode,
    'network-request-failed' => AccountFailureCode.network,
    'operation-not-allowed' => AccountFailureCode.unavailable,
    _ => AccountFailureCode.unknown,
  };
}
