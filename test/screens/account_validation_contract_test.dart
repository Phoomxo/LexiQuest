import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_validation.dart';
import 'package:vocab_learning_app/screens/change_password_screen.dart';
import 'package:vocab_learning_app/screens/forgot_password_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/screens/reset_password_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _ContractGateway implements AccountGateway {
  const _ContractGateway();

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() => const Stream.empty();

  @override
  Future<String> verifyPasswordResetCode(String code) async =>
      'student@example.com';

  @override
  Future<void> applyVerificationCode(String code) => throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession?> reloadSession() => throw UnimplementedError();

  @override
  Future<void> requestPasswordReset(String email) =>
      throw UnimplementedError();

  @override
  Future<void> sendVerificationEmail() => throw UnimplementedError();

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  }) => throw UnimplementedError();
}

final class _ContractGuestSessionService implements GuestSessionService {
  const _ContractGuestSessionService();

  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

String? _validate(WidgetTester tester, String key, String value) {
  final field = tester.widget<TextFormField>(
    find.byKey(ValueKey<String>(key)),
  );
  return field.validator!(value);
}

void main() {
  const gateway = _ContractGateway();

  testWidgets(
    'register reset and change share the centralized password policy',
    (tester) async {
      const password = 'ภาษาไทย๑๒๓';
      expect(AccountValidation.passwordError(password), isNull);

      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(
            guestUpgradeHandoff: noOpGuestUpgradeHandoff,
          ),
        ),
      );
      expect(_validate(tester, 'register-password', password), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: ResetPasswordScreen(
            accountGateway: gateway,
            code: 'one-time-code',
          ),
        ),
      );
      await tester.pump();
      expect(_validate(tester, 'reset-password', password), isNull);

      await tester.pumpWidget(
        const MaterialApp(
          home: ChangePasswordScreen(accountGateway: gateway),
        ),
      );
      expect(_validate(tester, 'change-password-new', password), isNull);
    },
  );

  testWidgets(
    'register login and recovery share the centralized email policy',
    (tester) async {
      const invalidEmail = 'not-an-email';
      final expected = AccountValidation.emailError(invalidEmail);

      await tester.pumpWidget(
        MaterialApp(
          home: RegisterScreen(
            guestUpgradeHandoff: noOpGuestUpgradeHandoff,
          ),
        ),
      );
      expect(_validate(tester, 'register-email', invalidEmail), expected);

      await tester.pumpWidget(
        const MaterialApp(
          home: LoginScreen(
            accountGateway: gateway,
            guestSessionService: _ContractGuestSessionService(),
          ),
        ),
      );
      expect(_validate(tester, 'login-email', invalidEmail), expected);

      await tester.pumpWidget(
        const MaterialApp(
          home: ForgotPasswordScreen(accountGateway: gateway),
        ),
      );
      expect(_validate(tester, 'recovery-email', invalidEmail), expected);
    },
  );
}
