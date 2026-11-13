import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_sign_in/google_sign_in.dart';

import '../domain/account_contracts.dart';

abstract interface class GoogleCredentialSource {
  Future<AuthCredential> credential();

  Future<void> signOut();
}

typedef GoogleSignInInitialize = Future<void> Function();
typedef GoogleSignInIdToken = Future<String?> Function();
typedef GoogleProviderSignOut = Future<void> Function();

final class GoogleSignInCredentialSource implements GoogleCredentialSource {
  GoogleSignInCredentialSource({
    required GoogleSignInInitialize initialize,
    required GoogleSignInIdToken authenticateIdToken,
    required GoogleProviderSignOut signOut,
  }) : this._(initialize, authenticateIdToken, signOut);

  GoogleSignInCredentialSource._(
    this._initialize,
    this._authenticateIdToken,
    this._signOut,
  );

  factory GoogleSignInCredentialSource.production() {
    final google = GoogleSignIn.instance;
    return GoogleSignInCredentialSource(
      initialize: google.initialize,
      authenticateIdToken: () async {
        final account = await google.authenticate();
        return account.authentication.idToken;
      },
      signOut: google.signOut,
    );
  }

  final GoogleSignInInitialize _initialize;
  final GoogleSignInIdToken _authenticateIdToken;
  final GoogleProviderSignOut _signOut;
  Future<void>? _initialization;

  @override
  Future<AuthCredential> credential() async {
    try {
      await (_initialization ??= _initialize());
      final idToken = await _authenticateIdToken();
      if (idToken == null || idToken.trim().isEmpty) {
        throw const AccountException(AccountFailureCode.unavailable);
      }
      return GoogleAuthProvider.credential(idToken: idToken);
    } on AccountException {
      rethrow;
    } on GoogleSignInException catch (error) {
      throw AccountException(
        error.code == GoogleSignInExceptionCode.canceled
            ? AccountFailureCode.cancelled
            : AccountFailureCode.unavailable,
      );
    } catch (_) {
      throw const AccountException(AccountFailureCode.unavailable);
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _signOut();
    } catch (_) {
      // Firebase sign-out remains authoritative. Provider cleanup is best effort.
    }
  }
}
