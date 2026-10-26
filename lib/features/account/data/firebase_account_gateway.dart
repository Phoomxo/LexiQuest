import 'package:firebase_auth/firebase_auth.dart';

import '../domain/account_contracts.dart';
import 'google_sign_in_credential_source.dart';

const _authActionUrl =
    'https://vocab-learning-app-219ef.firebaseapp.com/auth/action';

final class FirebaseAccountGateway
    implements AccountGateway, GoogleAccountGateway {
  FirebaseAccountGateway(FirebaseAuth auth, {GoogleCredentialSource? google})
    : this._(auth, google);

  FirebaseAccountGateway._(this.auth, this._google);

  final FirebaseAuth auth;
  final GoogleCredentialSource? _google;

  @override
  bool get googleSignInAvailable => _google != null;

  @override
  AccountSession? get currentSession => _session(auth.currentUser);

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
      } catch (_) {
        // Account creation/linking is already committed. The verification
        // screen exposes an explicit resend instead of misreporting failure.
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
  Future<AccountSession> signInWithGoogle() async {
    final google = _google;
    if (google == null) {
      throw const AccountException(AccountFailureCode.unavailable);
    }
    try {
      final credential = await google.credential();
      final current = auth.currentUser;
      UserCredential result;
      if (current != null && current.isAnonymous) {
        try {
          result = await current.linkWithCredential(credential);
        } on FirebaseAuthException catch (error) {
          if (error.code != 'credential-already-in-use' &&
              error.code != 'account-exists-with-different-credential') {
            rethrow;
          }
          result = await auth.signInWithCredential(credential);
        }
      } else {
        result = await auth.signInWithCredential(credential);
      }
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
  Future<AccountSession> updateDisplayName(String displayName) async {
    final user = auth.currentUser;
    if (user == null || user.isAnonymous) {
      throw const AccountException(AccountFailureCode.invalidCredential);
    }
    try {
      await user.updateDisplayName(displayName);
      return _session(user)!;
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    } catch (_) {
      throw const AccountException(AccountFailureCode.unavailable);
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
  }) async {
    final user = auth.currentUser;
    final email = user?.email;
    if (user == null || email == null) {
      throw const AccountException(AccountFailureCode.invalidCredential);
    }
    try {
      await user.reauthenticateWithCredential(
        EmailAuthProvider.credential(email: email, password: currentPassword),
      );
      await user.updatePassword(newPassword);
    } on FirebaseAuthException catch (error) {
      throw AccountException(_map(error.code));
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await auth.signOut();
      await _google?.signOut();
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
          email: user.email,
          displayName: user.displayName,
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
