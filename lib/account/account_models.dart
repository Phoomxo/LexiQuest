enum AccountActionMode { resetPassword, verifyEmail }

final class AccountActionLink {
  const AccountActionLink({required this.mode, required this.code});

  static const host = 'vocab-learning-app-219ef.web.app';
  static const path = '/auth/action';

  final AccountActionMode mode;
  final String code;

  static AccountActionLink? tryParse(Uri uri) {
    if (uri.scheme != 'https' ||
        uri.host != host ||
        uri.path != path ||
        uri.userInfo.isNotEmpty ||
        uri.hasFragment) {
      return null;
    }
    final code = uri.queryParameters['oobCode']?.trim() ?? '';
    final rawMode = uri.queryParameters['mode'];
    if (code.isEmpty) return null;
    final mode = switch (rawMode) {
      'resetPassword' => AccountActionMode.resetPassword,
      'verifyEmail' => AccountActionMode.verifyEmail,
      _ => null,
    };
    return mode == null ? null : AccountActionLink(mode: mode, code: code);
  }

  @override
  bool operator ==(Object other) =>
      other is AccountActionLink && other.mode == mode && other.code == code;

  @override
  int get hashCode => Object.hash(mode, code);
}

final class AccountSession {
  const AccountSession({
    required this.uid,
    required this.email,
    required this.isAnonymous,
    required this.isEmailVerified,
  });

  final String uid;
  final String? email;
  final bool isAnonymous;
  final bool isEmailVerified;
}

final class GuestUpgradeResult {
  const GuestUpgradeResult({required this.previousUid, required this.session});

  final String previousUid;
  final AccountSession session;
}

/// Receives a successfully linked guest identity at most once per upgrade.
///
/// A caller must make any durable migration idempotent: if this callback throws
/// after committing work, registration will not automatically deliver the same
/// old/new identity pair again. Plan 2 injects [noOpGuestUpgradeHandoff]; Plan
/// 3 replaces it with durable ownership migration and recovery.
typedef GuestUpgradeHandoff =
    Future<void> Function(String previousUid, AccountSession session);

Future<void> noOpGuestUpgradeHandoff(
  String previousUid,
  AccountSession session,
) async {}
