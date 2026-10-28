import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_error_mapper.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

final class _SignOutGateway implements AccountGateway {
  _SignOutGateway({this.signOutError, this.pendingSignOut});

  final Object? signOutError;
  final Future<void>? pendingSignOut;
  int signOutCalls = 0;

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<void> signOut() async {
    signOutCalls++;
    await pendingSignOut;
    final error = signOutError;
    if (error != null) throw error;
  }

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
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<String> verifyPasswordResetCode(String code) =>
      throw UnimplementedError();
}

void main() {
  testWidgets(
    'settings hides wallpaper selection while remote economy is disabled',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            accountGateway: _SignOutGateway(),
            profileData: const {'first_name': 'Phet'},
          ),
        ),
      );

      expect(find.byIcon(Icons.wallpaper), findsNothing);
    },
  );

  testWidgets('sign-out clears navigation back to the session gate', (
    tester,
  ) async {
    final gateway = _SignOutGateway();
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/settings',
        routes: {
          '/settings': (_) => SettingScreen(
            accountGateway: gateway,
            profileData: const {'first_name': 'Phet'},
          ),
          AppRoute.sessionGate.path: (_) =>
              const Scaffold(body: Center(child: Text('SESSION_GATE_REACHED'))),
        },
      ),
    );

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pumpAndSettle();

    expect(gateway.signOutCalls, 1);
    expect(find.text('SESSION_GATE_REACHED'), findsOneWidget);
    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(navigator.canPop(), isFalse);
  });

  for (final failure in <Object>[
    const AccountOperationException('network-request-failed'),
    StateError('unexpected'),
  ]) {
    testWidgets('sign-out failure stays on settings with a safe message', (
      tester,
    ) async {
      final gateway = _SignOutGateway(signOutError: failure);
      await tester.pumpWidget(
        MaterialApp(
          home: SettingScreen(
            accountGateway: gateway,
            profileData: const {'first_name': 'Phet'},
          ),
        ),
      );

      await tester.tap(find.byIcon(Icons.logout));
      await tester.pumpAndSettle();

      final expectedCode = failure is AccountOperationException
          ? failure.code
          : 'unknown';
      expect(gateway.signOutCalls, 1);
      expect(find.byType(SettingScreen), findsOneWidget);
      expect(
        find.text(AccountErrorMapper.messageFor(expectedCode)),
        findsOneWidget,
      );
    });
  }

  testWidgets('sign-out ignores repeated submission while pending', (
    tester,
  ) async {
    final completion = Completer<void>();
    final gateway = _SignOutGateway(pendingSignOut: completion.future);
    await tester.pumpWidget(
      MaterialApp(
        home: SettingScreen(
          accountGateway: gateway,
          profileData: const {'first_name': 'Phet'},
        ),
      ),
    );

    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();
    await tester.tap(find.byIcon(Icons.logout));
    await tester.pump();

    expect(gateway.signOutCalls, 1);
    completion.complete();
    await tester.pumpAndSettle();
  });
}
