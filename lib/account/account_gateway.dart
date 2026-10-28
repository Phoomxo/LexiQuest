import 'account_models.dart';

final class AccountOperationException implements Exception {
  const AccountOperationException(this.code);

  final String code;

  @override
  String toString() => 'AccountOperationException($code)';
}

abstract interface class AccountGateway {
  AccountSession? get currentSession;
  Stream<AccountSession?> authStateChanges();
  Future<AccountSession> signIn({
    required String email,
    required String password,
  });
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  });
  Future<void> signOut();
  Future<AccountSession?> reloadSession();
  Future<void> sendVerificationEmail();
  Future<void> applyVerificationCode(String code);
  Future<void> requestPasswordReset(String email);
  Future<String> verifyPasswordResetCode(String code);
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  });
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  });
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  });
}
