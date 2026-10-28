import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

const _emailKey = ValueKey<String>('register-email');
const _passwordKey = ValueKey<String>('register-password');
const _confirmationKey = ValueKey<String>('register-confirmation');
const _firstNameKey = ValueKey<String>('register-first-name');
const _lastNameKey = ValueKey<String>('register-last-name');
const _ageKey = ValueKey<String>('register-age');
const _submitKey = ValueKey<String>('register-submit');

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.sendFailures = 0});

  final events = <String>[];
  int sendFailures;
  int createCalls = 0;

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) async {
    createCalls++;
    events.add('createAccount:$email:$password');
    return AccountSession(
      uid: 'student-1',
      email: email,
      isAnonymous: false,
      isEmailVerified: false,
    );
  }

  @override
  Future<void> sendVerificationEmail() async {
    events.add('sendVerificationEmail');
    if (sendFailures > 0) {
      sendFailures--;
      throw const AccountOperationException('network-request-failed');
    }
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
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<void> requestPasswordReset(String email) => throw UnimplementedError();
  @override
  Future<AccountSession?> reloadSession() => throw UnimplementedError();
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
  _FakeProfileProvisioner(this.events, {this.failures = 0});

  final List<String> events;
  int failures;
  final ensuredUids = <String>[];
  bool categoriesComplete = false;

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) async {
    ensuredUids.add(uid);
    events.add(
      'ensureProfile:$uid:${profile.normalizedEmail}:${profile.firstName}:${profile.lastName}:${profile.age}',
    );
    if (failures > 0) {
      failures--;
      throw StateError('profile-write-failed');
    }
    categoriesComplete = true;
  }

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async =>
      failures == 0
      ? AccountProvisioningState.complete
      : AccountProvisioningState.incomplete;
}

Widget _harness(
  _FakeAccountGateway gateway, {
  _FakeProfileProvisioner? profileProvisioner,
}) {
  final events = gateway.events;
  return MaterialApp(
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) {
        if (settings.name == AppRoute.verifyEmail.path) {
          final args = settings.arguments! as VerifyEmailRouteArgs;
          return Scaffold(body: Text('VERIFY:${args.email}'));
        }
        return RegisterScreen(
          accountGateway: gateway,
          profileProvisioner:
              profileProvisioner ?? _FakeProfileProvisioner(events),
          guestUpgradeHandoff: noOpGuestUpgradeHandoff,
        );
      },
    ),
  );
}

Future<void> _enterValidRegistration(WidgetTester tester) async {
  await tester.enterText(find.byKey(_emailKey), ' Student@Example.COM ');
  await tester.enterText(find.byKey(_passwordKey), 'password123');
  await tester.enterText(find.byKey(_confirmationKey), 'password123');
  await tester.enterText(find.byKey(_firstNameKey), 'Ada');
  await tester.enterText(find.byKey(_lastNameKey), 'Lovelace');
  await tester.enterText(find.byKey(_ageKey), '20');
}

void main() {
  testWidgets(
    'creates, provisions, sends verification, then uses typed verification navigation',
    (tester) async {
      final gateway = _FakeAccountGateway();
      await tester.pumpWidget(_harness(gateway));

      await _enterValidRegistration(tester);
      await tester.tap(find.byKey(_submitKey));
      await tester.pumpAndSettle();

      expect(gateway.events, [
        'createAccount:student@example.com:password123',
        'ensureProfile:student-1:student@example.com:Ada:Lovelace:20',
        'sendVerificationEmail',
      ]);
      expect(find.text('VERIFY:student@example.com'), findsOneWidget);
    },
  );

  testWidgets('invalid profile fields do not create an account', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_harness(gateway));

    await tester.enterText(find.byKey(_emailKey), 'student@example.com');
    await tester.enterText(find.byKey(_passwordKey), 'password123');
    await tester.enterText(find.byKey(_confirmationKey), 'different');
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();

    expect(gateway.events, isEmpty);
  });

  testWidgets('retries a failed profile provision with the created uid', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    final profile = _FakeProfileProvisioner(gateway.events, failures: 1);
    await tester.pumpWidget(_harness(gateway, profileProvisioner: profile));
    await _enterValidRegistration(tester);

    await tester.tap(find.byKey(_submitKey));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(_submitKey));
    await tester.pumpAndSettle();

    expect(gateway.createCalls, 1);
    expect(profile.ensuredUids, ['student-1', 'student-1']);
    expect(
      gateway.events.where((event) => event == 'sendVerificationEmail'),
      hasLength(1),
    );
    expect(find.text('VERIFY:student@example.com'), findsOneWidget);
  });

  testWidgets(
    'retries verification delivery after completed category provisioning',
    (tester) async {
      final gateway = _FakeAccountGateway(sendFailures: 1);
      final profile = _FakeProfileProvisioner(gateway.events);
      await tester.pumpWidget(_harness(gateway, profileProvisioner: profile));
      await _enterValidRegistration(tester);

      await tester.tap(find.byKey(_submitKey));
      await tester.pumpAndSettle();
      expect(profile.categoriesComplete, isTrue);
      await tester.tap(find.byKey(_submitKey));
      await tester.pumpAndSettle();

      expect(gateway.createCalls, 1);
      expect(profile.ensuredUids, ['student-1', 'student-1']);
      expect(
        gateway.events.where((event) => event == 'sendVerificationEmail'),
        hasLength(2),
      );
      expect(find.text('VERIFY:student@example.com'), findsOneWidget);
    },
  );
}
