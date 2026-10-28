import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.session});

  final AccountSession? session;

  @override
  AccountSession? get currentSession =>
      session ??
      const AccountSession(
        uid: 'student-1',
        email: 'student@example.com',
        isAnonymous: false,
        isEmailVerified: true,
      );

  @override
  Stream<AccountSession?> authStateChanges() => const Stream.empty();
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

void main() {
  testWidgets('ProfileSettingsScreen displays user rank and accent settings', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProfileSettingsScreen(
          userName: 'คุณเพชร (Khun Phet)',
          totalXp: 2000,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('คุณเพชร (Khun Phet)'), findsOneWidget);
    expect(find.text('ยศ: Gold (ทอง)'), findsOneWidget);
    expect(find.text('⚙️ ตั้งค่าเสียง AI OmniVoice'), findsOneWidget);
  });

  testWidgets('shows the signed-in account actions', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ProfileSettingsScreen(accountGateway: _FakeAccountGateway()),
      ),
    );

    expect(find.text('เปลี่ยนรหัสผ่าน'), findsOneWidget);
    expect(find.text('ออกจากระบบ'), findsOneWidget);
  });

  testWidgets('anonymous account action navigates to registration', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway(
      session: const AccountSession(
        uid: 'guest-1',
        email: null,
        isAnonymous: true,
        isEmailVerified: false,
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: (settings) => MaterialPageRoute<void>(
          settings: settings,
          builder: (_) => settings.name == '/register'
              ? const Scaffold(body: Text('REGISTER_REACHED'))
              : ProfileSettingsScreen(accountGateway: gateway),
        ),
      ),
    );

    await tester.tap(find.text('สร้างบัญชีเพื่อสำรองข้อมูล'));
    await tester.pumpAndSettle();

    expect(find.text('REGISTER_REACHED'), findsOneWidget);
  });
}
