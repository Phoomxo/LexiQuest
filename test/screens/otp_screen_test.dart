import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_cooldown.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway(this._reloadResult);

  AccountSession? _reloadResult;
  int resendCalls = 0;

  @override
  AccountSession? get currentSession => _reloadResult;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(_reloadResult);

  @override
  Future<AccountSession?> reloadSession() async => _reloadResult;

  @override
  Future<void> sendVerificationEmail() async => resendCalls++;

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

final class _FakeProfileProvisioner implements AccountProfileProvisioning {
  _FakeProfileProvisioner(this.complete);

  final bool complete;

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) =>
      throw UnimplementedError();

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async =>
      complete
      ? AccountProvisioningState.complete
      : AccountProvisioningState.incomplete;
}

Widget _harness(
  _FakeAccountGateway gateway,
  AccountCooldown cooldown, {
  bool provisioningComplete = true,
}) => MaterialApp(
  onGenerateRoute: (settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) {
      if (settings.name == AppRoute.home.path) {
        return const Scaffold(body: Text('HOME_REACHED'));
      }
      if (settings.name == AppRoute.register.path) {
        final args = settings.arguments! as RegisterRouteArgs;
        return Scaffold(body: Text('RECOVER:${args.uid}:${args.email}'));
      }
      return OTPScreen(
        email: 'student@example.com',
        accountGateway: gateway,
        profileProvisioner: _FakeProfileProvisioner(provisioningComplete),
        resendCooldown: cooldown,
      );
    },
  ),
);

void main() {
  testWidgets('refresh enters home only after a verified reload', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway(
      const AccountSession(
        uid: 'student-1',
        email: 'student@example.com',
        isAnonymous: false,
        isEmailVerified: false,
      ),
    );
    await tester.pumpWidget(_harness(gateway, AccountCooldown()));

    await tester.tap(find.byKey(const ValueKey<String>('verify-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('HOME_REACHED'), findsNothing);

    gateway._reloadResult = const AccountSession(
      uid: 'student-1',
      email: 'student@example.com',
      isAnonymous: false,
      isEmailVerified: true,
    );
    await tester.tap(find.byKey(const ValueKey<String>('verify-refresh')));
    await tester.pumpAndSettle();
    expect(find.text('HOME_REACHED'), findsOneWidget);
  });

  testWidgets('resend uses a sixty-second cooldown', (tester) async {
    var now = DateTime(2026, 7, 30, 12);
    final gateway = _FakeAccountGateway(null);
    final cooldown = AccountCooldown(now: () => now);
    await tester.pumpWidget(_harness(gateway, cooldown));

    await tester.tap(find.byKey(const ValueKey<String>('verify-resend')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('verify-resend')));
    await tester.pump();
    expect(gateway.resendCalls, 1);

    now = now.add(const Duration(seconds: 60));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('verify-resend')));
    await tester.pump();
    expect(gateway.resendCalls, 2);
  });

  testWidgets(
    'verified reload recovers provisioning instead of entering home',
    (tester) async {
      final gateway = _FakeAccountGateway(
        const AccountSession(
          uid: 'student-1',
          email: 'student@example.com',
          isAnonymous: false,
          isEmailVerified: true,
        ),
      );
      await tester.pumpWidget(
        _harness(gateway, AccountCooldown(), provisioningComplete: false),
      );

      await tester.tap(find.byKey(const ValueKey<String>('verify-refresh')));
      await tester.pumpAndSettle();

      expect(find.text('HOME_REACHED'), findsNothing);
      expect(
        find.text('RECOVER:student-1:student@example.com'),
        findsOneWidget,
      );
    },
  );
}
