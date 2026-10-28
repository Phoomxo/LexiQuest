import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_validation.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/reset_password_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.verifyError, this.confirmError});

  final Object? verifyError;
  final Object? confirmError;
  final List<String> verifiedCodes = <String>[];
  final List<({String code, String password})> confirmedResets =
      <({String code, String password})>[];

  @override
  AccountSession? get currentSession => null;
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
  }) async {
    confirmedResets.add((code: code, password: newPassword));
    final error = confirmError;
    if (error != null) throw error;
  }

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
  Future<String> verifyPasswordResetCode(String code) async {
    verifiedCodes.add(code);
    final error = verifyError;
    if (error != null) throw error;
    return 'student@example.com';
  }
}

Widget _subject(_FakeAccountGateway gateway) => MaterialApp(
  onGenerateRoute: (settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => settings.name == AppRoute.login.path
        ? const Scaffold(body: Text('LOGIN_REACHED'))
        : ResetPasswordScreen(accountGateway: gateway, code: 'one-time-code'),
  ),
  home: ResetPasswordScreen(accountGateway: gateway, code: 'one-time-code'),
);

void main() {
  testWidgets('verifies the reset code before enabling password submission', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_subject(gateway));

    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('reset-submit')),
          )
          .onPressed,
      isNull,
    );
    await tester.pumpAndSettle();

    expect(gateway.verifiedCodes, equals(<String>['one-time-code']));
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey<String>('reset-submit')),
          )
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'enforces password policy and confirmation before confirming reset',
    (tester) async {
      final gateway = _FakeAccountGateway();
      await tester.pumpWidget(_subject(gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-password')),
        'short',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-confirmation')),
        'short',
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
      await tester.pump();
      expect(gateway.confirmedResets, isEmpty);

      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-password')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-confirmation')),
        'Different1',
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
      await tester.pump();
      expect(gateway.confirmedResets, isEmpty);
    },
  );

  testWidgets('accepts the centralized Thai password policy', (tester) async {
    final gateway = _FakeAccountGateway();
    const password = 'ภาษาไทย๑๒๓';
    expect(AccountValidation.passwordError(password), isNull);
    await tester.pumpWidget(_subject(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('reset-password')),
      password,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('reset-confirmation')),
      password,
    );
    await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
    await tester.pumpAndSettle();

    expect(gateway.confirmedResets, [
      (code: 'one-time-code', password: password),
    ]);
  });

  testWidgets('confirms exactly once and routes to login', (tester) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_subject(gateway));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey<String>('reset-password')),
      'Password1',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('reset-confirmation')),
      'Password1',
    );
    await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
    await tester.pumpAndSettle();

    expect(
      gateway.confirmedResets,
      equals(<({String code, String password})>[
        (code: 'one-time-code', password: 'Password1'),
      ]),
    );
    expect(find.text('LOGIN_REACHED'), findsOneWidget);
  });

  testWidgets(
    'offers to request a new link for expired or invalid reset codes',
    (tester) async {
      final gateway = _FakeAccountGateway(
        verifyError: const AccountOperationException('expired-action-code'),
      );
      await tester.pumpWidget(_subject(gateway));
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('reset-request-new-link')),
        findsOneWidget,
      );
    },
  );

  for (final code in <String>['expired-action-code', 'invalid-action-code']) {
    testWidgets('offers a new link when confirmation reports $code', (
      tester,
    ) async {
      final gateway = _FakeAccountGateway(
        confirmError: AccountOperationException(code),
      );
      await tester.pumpWidget(_subject(gateway));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-password')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-confirmation')),
        'Password1',
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
      await tester.pumpAndSettle();

      expect(gateway.confirmedResets, hasLength(1));
      expect(
        find.byKey(const ValueKey<String>('reset-request-new-link')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey<String>('reset-submit')), findsNothing);
    });
  }
}
