import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_validation.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _emailKey = ValueKey<String>('login-email');
const _passwordKey = ValueKey<String>('login-password');
const _submitKey = ValueKey<String>('login-submit');
const _forgotPasswordKey = ValueKey<String>('login-forgot-password');

final class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'guest-test');
}

final class _CompleterGuestSessionService implements GuestSessionService {
  final Completer<GuestSessionResult> _completer = Completer();
  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() {
    startCalls++;
    return _completer.future;
  }

  void complete(GuestSessionResult result) => _completer.complete(result);
}

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({
    Future<AccountSession> Function(String email, String password)? signIn,
  }) : _signIn = signIn ?? _verifiedSignIn;

  final Future<AccountSession> Function(String email, String password) _signIn;
  final List<(String email, String password)> signInRequests = [];

  static Future<AccountSession> _verifiedSignIn(
    String email,
    String password,
  ) async => AccountSession(
    uid: 'student-1',
    email: email,
    isAnonymous: false,
    isEmailVerified: true,
  );

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) {
    signInRequests.add((email, password));
    return _signIn(email, password);
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

Widget _loginHarness(
  _FakeAccountGateway gateway, {
  GuestSessionService? guestSessionService,
}) {
  return MaterialApp(
    onGenerateRoute: (settings) => MaterialPageRoute<void>(
      settings: settings,
      builder: (_) {
        if (settings.name == AppRoute.home.path) {
          return const Scaffold(body: Center(child: Text('HOME_REACHED')));
        }
        if (settings.name == AppRoute.verifyEmail.path) {
          return Scaffold(
            body: Center(
              child: Text(
                'VERIFY:${(settings.arguments! as VerifyEmailRouteArgs).email}',
              ),
            ),
          );
        }
        if (settings.name == AppRoute.forgotPassword.path) {
          return const Scaffold(body: Center(child: Text('FORGOT_REACHED')));
        }
        return LoginScreen(
          accountGateway: gateway,
          guestSessionService:
              guestSessionService ?? _FakeGuestSessionService(),
        );
      },
    ),
  );
}

Future<void> _enterCredentials(
  WidgetTester tester, {
  String email = ' Student@Example.COM ',
  String password = ' pass word ',
}) async {
  await tester.enterText(find.byKey(_emailKey), email);
  await tester.enterText(find.byKey(_passwordKey), password);
}

void main() {
  testWidgets('submits a normalized email without trimming the password', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_loginHarness(gateway));

    await _enterCredentials(tester);
    await tester.tap(find.byKey(_submitKey));
    await tester.pumpAndSettle();

    expect(gateway.signInRequests, [('student@example.com', ' pass word ')]);
  });

  testWidgets('invalid email and empty password do not call the gateway', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_loginHarness(gateway));

    await _enterCredentials(tester, email: 'not-an-email');
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();
    await _enterCredentials(tester, email: 'student@example.com', password: '');
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();

    expect(gateway.signInRequests, isEmpty);
  });

  testWidgets('uses the centralized email validation contract', (tester) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_loginHarness(gateway));

    await _enterCredentials(tester, email: 'not-an-email');
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();

    expect(
      find.text(AccountValidation.emailError('not-an-email')!),
      findsOneWidget,
    );
  });

  testWidgets(
    'unverified sessions navigate with typed verification arguments',
    (tester) async {
      final gateway = _FakeAccountGateway(
        signIn: (email, password) async => AccountSession(
          uid: 'student-1',
          email: email,
          isAnonymous: false,
          isEmailVerified: false,
        ),
      );
      await tester.pumpWidget(_loginHarness(gateway));

      await _enterCredentials(tester);
      await tester.tap(find.byKey(_submitKey));
      await tester.pumpAndSettle();

      expect(find.text('VERIFY:student@example.com'), findsOneWidget);
    },
  );

  testWidgets('verified sessions navigate home', (tester) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_loginHarness(gateway));

    await _enterCredentials(tester);
    await tester.tap(find.byKey(_submitKey));
    await tester.pumpAndSettle();

    expect(find.text('HOME_REACHED'), findsOneWidget);
  });

  for (final code in <String>[
    'invalid-credential',
    'user-not-found',
    'wrong-password',
  ]) {
    testWidgets('$code shows the generic invalid credentials Thai message', (
      tester,
    ) async {
      final gateway = _FakeAccountGateway(
        signIn: (email, password) =>
            Future<AccountSession>.error(AccountOperationException(code)),
      );
      await tester.pumpWidget(_loginHarness(gateway));

      await _enterCredentials(tester);
      await tester.tap(find.byKey(_submitKey));
      await tester.pump();

      expect(find.text('อีเมลหรือรหัสผ่านไม่ถูกต้อง'), findsOneWidget);
    });
  }

  testWidgets('a pending login ignores repeated submit taps', (tester) async {
    final completer = Completer<AccountSession>();
    final gateway = _FakeAccountGateway(
      signIn: (email, password) => completer.future,
    );
    await tester.pumpWidget(_loginHarness(gateway));

    await _enterCredentials(tester);
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();
    await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
    await tester.pump();

    expect(gateway.signInRequests, hasLength(1));
    completer.complete(
      await _FakeAccountGateway._verifiedSignIn(
        'student@example.com',
        ' pass word ',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a pending email sign-in blocks guest authentication', (
    tester,
  ) async {
    final signIn = Completer<AccountSession>();
    final gateway = _FakeAccountGateway(
      signIn: (email, password) => signIn.future,
    );
    final guestSession = _CompleterGuestSessionService();
    await tester.pumpWidget(
      _loginHarness(gateway, guestSessionService: guestSession),
    );

    await _enterCredentials(tester);
    await tester.tap(find.byKey(_submitKey));
    await tester.pump();
    await tester.tap(
      find.byKey(const ValueKey<String>('login-guest')),
      warnIfMissed: false,
    );
    await tester.pump();

    expect(gateway.signInRequests, hasLength(1));
    expect(guestSession.startCalls, 0);
    signIn.complete(
      await _FakeAccountGateway._verifiedSignIn(
        'student@example.com',
        ' pass word ',
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('a pending guest session blocks email sign-in', (tester) async {
    final gateway = _FakeAccountGateway();
    final guestSession = _CompleterGuestSessionService();
    await tester.pumpWidget(
      _loginHarness(gateway, guestSessionService: guestSession),
    );

    await _enterCredentials(tester);
    await tester.tap(find.byKey(const ValueKey<String>('login-guest')));
    await tester.pump();
    await tester.tap(find.byKey(_submitKey), warnIfMissed: false);
    await tester.pump();

    expect(guestSession.startCalls, 1);
    expect(gateway.signInRequests, isEmpty);
    guestSession.complete(const GuestSessionStarted(uid: 'guest-test'));
    await tester.pumpAndSettle();
  });

  testWidgets('forgot-password control uses the typed route path', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    await tester.pumpWidget(_loginHarness(gateway));

    await tester.tap(find.byKey(_forgotPasswordKey));
    await tester.pumpAndSettle();

    expect(find.text('FORGOT_REACHED'), findsOneWidget);
  });
}
