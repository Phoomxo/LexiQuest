import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.upgradeError});

  final Object? upgradeError;
  int createCalls = 0;
  int upgradeCalls = 0;
  int signOutCalls = 0;

  @override
  AccountSession? get currentSession => const AccountSession(
    uid: 'guest-1',
    email: null,
    isAnonymous: true,
    isEmailVerified: false,
  );

  @override
  Stream<AccountSession?> authStateChanges() => const Stream.empty();

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) async {
    createCalls++;
    throw StateError('Guests must not create a separate account.');
  }

  @override
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  }) async {
    upgradeCalls++;
    final error = upgradeError;
    if (error != null) throw error;
    return const GuestUpgradeResult(
      previousUid: 'guest-1',
      session: AccountSession(
        uid: 'guest-1',
        email: 'student@example.com',
        isAnonymous: false,
        isEmailVerified: false,
      ),
    );
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
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<AccountSession?> reloadSession() => throw UnimplementedError();
  @override
  Future<void> sendVerificationEmail() async {}
  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> signOut() async {
    signOutCalls++;
  }

  @override
  Future<String> verifyPasswordResetCode(String code) =>
      throw UnimplementedError();
}

final class _FakeProvisioner implements AccountProfileProvisioning {
  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) async {}

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async =>
      AccountProvisioningState.complete;
}

Widget _subject(
  _FakeAccountGateway gateway, {
  required GuestUpgradeHandoff handoff,
}) => MaterialApp(
  onGenerateRoute: (settings) => MaterialPageRoute<void>(
    settings: settings,
    builder: (_) => settings.name == AppRoute.verifyEmail.path
        ? const Scaffold(body: Text('VERIFY_REACHED'))
        : RegisterScreen(
            accountGateway: gateway,
            profileProvisioner: _FakeProvisioner(),
            guestUpgradeHandoff: handoff,
          ),
  ),
);

Future<void> _enterValidRegistration(WidgetTester tester) async {
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-email')),
    'student@example.com',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-password')),
    'Password1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-confirmation')),
    'Password1',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-first-name')),
    'Ada',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-last-name')),
    'Lovelace',
  );
  await tester.enterText(
    find.byKey(const ValueKey<String>('register-age')),
    '20',
  );
}

void main() {
  testWidgets('upgrades the anonymous session and hands off both UIDs', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    final handoffs = <({String previousUid, String uid})>[];
    await tester.pumpWidget(
      _subject(
        gateway,
        handoff: (previousUid, session) async {
          handoffs.add((previousUid: previousUid, uid: session.uid));
        },
      ),
    );
    await _enterValidRegistration(tester);

    await tester.tap(find.byKey(const ValueKey<String>('register-submit')));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 0);
    expect(gateway.upgradeCalls, 1);
    expect(handoffs, equals([(previousUid: 'guest-1', uid: 'guest-1')]));
    expect(find.text('VERIFY_REACHED'), findsOneWidget);
  });

  testWidgets('keeps the guest session when the email is already in use', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway(
      upgradeError: const AccountOperationException('email-already-in-use'),
    );
    await tester.pumpWidget(_subject(gateway, handoff: (_, _) async {}));
    await _enterValidRegistration(tester);

    await tester.tap(find.byKey(const ValueKey<String>('register-submit')));
    await tester.pumpAndSettle();

    expect(gateway.upgradeCalls, 1);
    expect(gateway.createCalls, 0);
    expect(gateway.signOutCalls, 0);
    expect(find.textContaining('ใช้งานกับบัญชีอื่น'), findsOneWidget);
  });

  testWidgets('delivers a post-link handoff at most once across retry', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    final deliveries = <({String previousUid, String uid})>[];
    var firstAttempt = true;
    await tester.pumpWidget(
      _subject(
        gateway,
        handoff: (previousUid, session) async {
          deliveries.add((previousUid: previousUid, uid: session.uid));
          if (firstAttempt) {
            firstAttempt = false;
            throw StateError('handoff-recorded-then-failed');
          }
        },
      ),
    );
    await _enterValidRegistration(tester);
    await tester.tap(find.byKey(const ValueKey<String>('register-submit')));
    await tester.pumpAndSettle();

    expect(gateway.upgradeCalls, 1);
    expect(deliveries, equals([(previousUid: 'guest-1', uid: 'guest-1')]));
    expect(
      tester
          .widget<TextField>(
            find.descendant(
              of: find.byKey(const ValueKey<String>('register-email')),
              matching: find.byType(TextField),
            ),
          )
          .readOnly,
      isTrue,
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('register-email')),
      'other@example.com',
    );
    expect(
      tester
          .widget<TextFormField>(
            find.byKey(const ValueKey<String>('register-email')),
          )
          .controller!
          .text,
      'student@example.com',
    );

    await tester.tap(find.byKey(const ValueKey<String>('register-submit')));
    await tester.pumpAndSettle();

    expect(gateway.upgradeCalls, 1);
    expect(gateway.createCalls, 0);
    expect(deliveries, equals([(previousUid: 'guest-1', uid: 'guest-1')]));
    expect(find.text('VERIFY_REACHED'), findsOneWidget);
  });
}
