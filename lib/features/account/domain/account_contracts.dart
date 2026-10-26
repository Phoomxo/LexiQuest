enum AccountFailureCode {
  invalidEmail,
  invalidDisplayName,
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
    this.displayName,
  });

  final String uid;
  final String? email;
  final String? displayName;
  final bool isAnonymous;
  final bool emailVerified;
}

enum EmailActionMode { verifyEmail, resetPassword, unknown }

final class EmailAction {
  const EmailAction({required this.mode, required this.code});

  static const _hostingHost = 'vocab-learning-app-219ef.firebaseapp.com';

  final EmailActionMode mode;
  final String code;

  static EmailAction? parse(Uri uri) {
    final Uri actionUri;
    if (_isInternalAction(uri)) {
      actionUri = uri;
    } else if (_isTrustedHttps(uri, '/__/auth/links')) {
      final wrappedLinks = uri.queryParametersAll['link'];
      if (wrappedLinks == null) {
        actionUri = uri;
      } else {
        if (wrappedLinks.length != 1 ||
            uri.queryParametersAll.containsKey('mode') ||
            uri.queryParametersAll.containsKey('oobCode') ||
            uri.queryParametersAll.containsKey('continueUrl')) {
          return null;
        }
        final wrapped = Uri.tryParse(wrappedLinks.single);
        if (wrapped == null || !_isTrustedHttps(wrapped, '/__/auth/action')) {
          return null;
        }
        actionUri = wrapped;
      }
    } else {
      return null;
    }

    if (!_hasSafeContinueUrl(actionUri)) return null;
    final code = _singleQueryValue(actionUri, 'oobCode')?.trim();
    if (code == null || code.isEmpty) return null;
    final modes = actionUri.queryParametersAll['mode'];
    if (modes != null && modes.length != 1) return null;
    final mode = switch (modes?.single) {
      'verifyEmail' => EmailActionMode.verifyEmail,
      'resetPassword' => EmailActionMode.resetPassword,
      _ => EmailActionMode.unknown,
    };
    return EmailAction(mode: mode, code: code);
  }

  static bool _isInternalAction(Uri uri) =>
      !uri.hasScheme &&
      !uri.hasAuthority &&
      uri.path == '/auth/action' &&
      uri.fragment.isEmpty;

  static bool _isTrustedHttps(Uri uri, String path) =>
      uri.scheme == 'https' &&
      uri.host == _hostingHost &&
      uri.userInfo.isEmpty &&
      (!uri.hasPort || uri.port == 443) &&
      uri.path == path &&
      uri.fragment.isEmpty;

  static bool _hasSafeContinueUrl(Uri uri) {
    final values = uri.queryParametersAll['continueUrl'];
    if (values == null) return true;
    if (values.length != 1) return false;
    final continueUri = Uri.tryParse(values.single);
    return continueUri != null &&
        _isTrustedHttps(continueUri, '/auth/action') &&
        continueUri.query.isEmpty;
  }

  static String? _singleQueryValue(Uri uri, String name) {
    final values = uri.queryParametersAll[name];
    return values != null && values.length == 1 ? values.single : null;
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

  Future<AccountSession> updateDisplayName(String displayName);

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
  });

  Future<void> signOut();
}

abstract interface class GoogleAccountGateway {
  bool get googleSignInAvailable;

  Future<AccountSession> signInWithGoogle();
}
