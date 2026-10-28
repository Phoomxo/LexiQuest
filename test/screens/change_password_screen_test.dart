import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_validation.dart';
import 'package:vocab_learning_app/screens/change_password_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.changeError, this.pendingChange});

  final Object? changeError;
  final Future<void>? pendingChange;
  final List<({String currentPassword, String newPassword})> changes = [];

  @override
  AccountSession? get currentSession => const AccountSession(
    uid: 'student-1',
    email: 'student@example.com',
    isAnonymous: false,
    isEmailVerified: true,
  );

  @override
  Stream<AccountSession?> authStateChanges() => const Stream.empty();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changes.add((currentPassword: currentPassword, newPassword: newPassword));
    await pendingChange;
    final error = changeError;
    if (error != null) throw error;
  }

  @override
  Future<void> applyVerificationCode(String code) => throw UnimplementedError();
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

Widget _subject(_FakeAccountGateway gateway) =>
    MaterialApp(home: ChangePasswordScreen(accountGateway: gateway));

Widget _pushHarness(_FakeAccountGateway gateway) => MaterialApp(
  home: Builder(
    builder: (context) => FilledButton(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => ChangePasswordScreen(accountGateway: gateway),
        ),
      ),
      child: const Text('OPEN_CHANGE'),
    ),
  ),
);

Future<void> _enterValidPasswords(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('change-password-current')),
    ' current Password1 ',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('change-password-new')),
    'NewPassword1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('change-password-confirmation')),
    'NewPassword1',
  );
}

void main() {
  testWidgets('requires current password, new password, and confirmation', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_subject(gateway));

    await tester.tap(
      find.byKey(const ValueKey<String>('change-password-submit')),
    );
    await tester.pump();

    expect(gateway.changes, isEmpty);
    expect(find.text('กรุณากรอกรหัสผ่านปัจจุบัน'), findsOneWidget);
    expect(find.text(AccountValidation.passwordError('')!), findsOneWidget);
    expect(
      find.text(AccountValidation.confirmationError('', '')!),
      findsOneWidget,
    );
  });

  testWidgets(
    'submits the untrimmed current password and validated new password once',
    (tester) async {
      final gateway = _FakeAccountGateway();
      await tester.pumpWidget(_subject(gateway));
      await _enterValidPasswords(tester);

      await tester.tap(
        find.byKey(const ValueKey<String>('change-password-submit')),
      );
      await tester.pumpAndSettle();

      expect(
        gateway.changes,
        equals(<({String currentPassword, String newPassword})>[
          (currentPassword: ' current Password1 ', newPassword: 'NewPassword1'),
        ]),
      );
      for (final key in <ValueKey<String>>[
        const ValueKey<String>('change-password-current'),
        const ValueKey<String>('change-password-new'),
        const ValueKey<String>('change-password-confirmation'),
      ]) {
        expect(
          tester.widget<TextFormField>(find.byKey(key)).controller!.text,
          '',
        );
      }
      expect(find.textContaining(' current Password1 '), findsNothing);
    },
  );

  testWidgets('prompts for reauthentication when authentication is stale', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway(
      changeError: const AccountOperationException('requires-recent-login'),
    );
    await tester.pumpWidget(_subject(gateway));
    await _enterValidPasswords(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('change-password-submit')),
    );
    await tester.pumpAndSettle();

    expect(gateway.changes, hasLength(1));
    expect(find.textContaining('เข้าสู่ระบบใหม่'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('change-password-current')),
          )
          .controller!
          .text,
      isEmpty,
    );
    expect(find.textContaining(' current Password1 '), findsNothing);
  });

  testWidgets('returns to the pushed route after a successful change', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_pushHarness(gateway));
    await tester.tap(find.text('OPEN_CHANGE'));
    await tester.pumpAndSettle();
    await _enterValidPasswords(tester);

    await tester.tap(
      find.byKey(const ValueKey<String>('change-password-submit')),
    );
    await tester.pumpAndSettle();

    expect(find.text('OPEN_CHANGE'), findsOneWidget);
  });

  testWidgets('does not touch disposed password controllers after completion', (
    tester,
  ) async {
    final completion = Completer<void>();
    final gateway = _FakeAccountGateway(pendingChange: completion.future);
    await tester.pumpWidget(_pushHarness(gateway));
    await tester.tap(find.text('OPEN_CHANGE'));
    await tester.pumpAndSettle();
    await _enterValidPasswords(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('change-password-submit')),
    );
    await tester.pump();

    Navigator.of(tester.element(find.byType(ChangePasswordScreen))).pop();
    await tester.pumpAndSettle();
    completion.complete();
    await tester.pumpAndSettle();

    expect(find.text('OPEN_CHANGE'), findsOneWidget);
  });
}
