import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_cooldown.dart';
import 'package:vocab_learning_app/account/account_error_mapper.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_validation.dart';
import 'package:vocab_learning_app/screens/forgot_password_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.resetError});

  final Object? resetError;
  final List<String> resetRequests = <String>[];

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
  }) => throw UnimplementedError();
  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> requestPasswordReset(String email) async {
    resetRequests.add(email);
    final error = resetError;
    if (error != null) throw error;
  }

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

Widget _subject(_FakeAccountGateway gateway) => MaterialApp(
  home: ForgotPasswordScreen(
    accountGateway: gateway,
    cooldown: AccountCooldown(duration: Duration.zero),
  ),
);

Future<void> _submit(WidgetTester tester, String email) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('recovery-email')),
    email,
  );
  await tester.tap(find.byKey(const ValueKey<String>('recovery-submit')));
  await tester.pump();
}

void main() {
  for (final error in <Object?>[
    null,
    const AccountOperationException('user-not-found'),
    const AccountOperationException('email-not-found'),
  ]) {
    testWidgets(
      'shows neutral acknowledgement for accepted and non-existent accounts',
      (tester) async {
        final gateway = _FakeAccountGateway(resetError: error);
        await tester.pumpWidget(_subject(gateway));

        await _submit(tester, ' Student@Example.com ');

        expect(gateway.resetRequests, equals(<String>['student@example.com']));
        expect(
          find.text(AccountErrorMapper.recoveryAcceptedMessage),
          findsOneWidget,
        );
      },
    );
  }

  testWidgets('rejects an invalid local email before calling the gateway', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_subject(gateway));

    await _submit(tester, 'not-an-email');

    expect(gateway.resetRequests, isEmpty);
    expect(
      find.text(AccountValidation.emailError('not-an-email')!),
      findsOneWidget,
    );
  });

  testWidgets(
    'shows a network failure instead of an accepted acknowledgement',
    (tester) async {
      final gateway = _FakeAccountGateway(
        resetError: const AccountOperationException('network-request-failed'),
      );
      await tester.pumpWidget(_subject(gateway));

      await _submit(tester, 'student@example.com');

      expect(
        find.text(AccountErrorMapper.recoveryAcceptedMessage),
        findsNothing,
      );
      expect(
        find.text(AccountErrorMapper.messageFor('network-request-failed')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey<String>('recovery-retry')),
        findsOneWidget,
      );
    },
  );
}
