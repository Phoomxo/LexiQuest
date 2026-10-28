import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _SmokeAccountGateway implements AccountGateway {
  const _SmokeAccountGateway();

  @override
  AccountSession? get currentSession => null;
  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);
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
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<AccountSession?> reloadSession() => throw UnimplementedError();
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
  @override
  Future<String> verifyPasswordResetCode(String code) =>
      throw UnimplementedError();
}

final class _SmokeGuestSessionService implements GuestSessionService {
  const _SmokeGuestSessionService();

  @override
  Future<GuestSessionResult> start() => throw UnimplementedError();
}

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: LoginScreen(
          accountGateway: _SmokeAccountGateway(),
          guestSessionService: _SmokeGuestSessionService(),
        ),
      ),
    );

    expect(find.byKey(const ValueKey<String>('login-email')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('login-password')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey<String>('login-submit')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('login-guest')), findsOneWidget);
  });
}
