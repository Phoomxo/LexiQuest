enum AccountFailureCode {
  invalidEmail,
  weakPassword,
  emailInUse,
  invalidCredential,
  userDisabled,
  tooManyRequests,
  requiresRecentLogin,
  invalidActionCode,
  expiredActionCode,
  network,
  unavailable,
  cancelled,
  unknown,
}

final class AccountException implements Exception {
  const AccountException(this.code);

  final AccountFailureCode code;
}

final class AccountSession {
  const AccountSession({
    required this.uid,
    required this.email,
    required this.isAnonymous,
    required this.emailVerified,
    this.verificationEmailPending = false,
    this.sessionIdentity,
  });

  /// In-memory provider session identity; never serialized or a credential.
  final Object? sessionIdentity;
  final String uid;
  final String? email;
  final bool isAnonymous;
  final bool emailVerified;

  /// Registration committed, but sending verification must be retried.
  /// This does not imply verified email or undo the created account.
  final bool verificationEmailPending;
}

enum EmailActionMode { verifyEmail, resetPassword, unknown }

final class EmailAction {
  const EmailAction({required this.mode, required this.code});

  final EmailActionMode mode;
  final String code;

  static EmailAction? parse(Uri uri) {
    final code = uri.queryParameters['oobCode']?.trim();
    if (code == null || code.isEmpty) return null;
    final mode = switch (uri.queryParameters['mode']) {
      'verifyEmail' => EmailActionMode.verifyEmail,
      'resetPassword' => EmailActionMode.resetPassword,
      _ => EmailActionMode.unknown,
    };
    return EmailAction(mode: mode, code: code);
  }
}

abstract interface class AccountGateway {
  AccountSession? get currentSession;

  Future<AccountSession> register({
    required String email,
    required String password,
  });

  Future<AccountSession> signIn({
    required String email,
    required String password,
  });

  Future<AccountSession> reload();

  Future<void> sendVerification();

  Future<void> sendPasswordReset(String email);

  Future<void> applyEmailVerificationCode(String code);

  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  });

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool Function()? isCurrent,
  });

  Future<void> signOut();
}

/// Optional provider observation; events retire in-memory password controls.
abstract interface class AccountSessionObserver {
  Stream<AccountSession?> get sessionChanges;
}
