import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/screens/session_gate_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway(this.session, {Stream<AccountSession?>? authState})
    : _authState = authState ?? Stream<AccountSession?>.value(session);

  final AccountSession? session;
  final Stream<AccountSession?> _authState;

  @override
  AccountSession? get currentSession => session;

  @override
  Stream<AccountSession?> authStateChanges() => _authState;

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

final class _FakeProfileProvisioner implements AccountProfileProvisioning {
  const _FakeProfileProvisioner(this.complete);

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

final class _SequencedProfileProvisioner implements AccountProfileProvisioning {
  _SequencedProfileProvisioner(this.results);

  final List<Object> results;
  int lookupCalls = 0;

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) =>
      throw UnimplementedError();

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async {
    final result = results[lookupCalls++];
    if (result is bool) {
      return result
          ? AccountProvisioningState.complete
          : AccountProvisioningState.incomplete;
    }
    throw result;
  }
}

final class _PendingGuestSessionService implements GuestSessionService {
  int startCalls = 0;
  final Completer<GuestSessionResult> _completion = Completer();

  @override
  Future<GuestSessionResult> start() {
    startCalls++;
    return _completion.future;
  }
}

final class _CountingNavigatorObserver extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
    super.didPush(route, previousRoute);
  }
}

Future<void> _pumpGate(
  WidgetTester tester,
  AccountSession? session, {
  GuestSessionService? guestSessionService,
  bool provisioningComplete = true,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: SessionGateScreen(
        accountGateway: _FakeAccountGateway(session),
        profileProvisioner: _FakeProfileProvisioner(provisioningComplete),
        guestSessionService:
            guestSessionService ?? _PendingGuestSessionService(),
        guestUpgradeHandoff: noOpGuestUpgradeHandoff,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('signed-out sessions open LoginScreen', (tester) async {
    await _pumpGate(tester, null);

    expect(find.byType(LoginScreen), findsOneWidget);
  });

  testWidgets('signed-out root guest entry uses the injected service', (
    tester,
  ) async {
    final guestSessionService = _PendingGuestSessionService();
    await _pumpGate(tester, null, guestSessionService: guestSessionService);

    await tester.tap(find.byKey(const ValueKey<String>('login-guest')));
    await tester.pump();

    expect(guestSessionService.startCalls, 1);
  });

  testWidgets('anonymous sessions open MainNavigationScreen', (tester) async {
    await _pumpGate(
      tester,
      const AccountSession(
        uid: 'anonymous-user',
        email: null,
        isAnonymous: true,
        isEmailVerified: false,
      ),
    );

    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });

  testWidgets('verified registered sessions open MainNavigationScreen', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      const AccountSession(
        uid: 'verified-user',
        email: 'verified@example.com',
        isAnonymous: false,
        isEmailVerified: true,
      ),
    );

    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });

  testWidgets('unverified registered sessions open OTPScreen', (tester) async {
    await _pumpGate(
      tester,
      const AccountSession(
        uid: 'unverified-user',
        email: 'unverified@example.com',
        isAnonymous: false,
        isEmailVerified: false,
      ),
    );

    expect(find.byType(OTPScreen), findsOneWidget);
  });

  testWidgets(
    'verified incomplete sessions open profile recovery instead of home',
    (tester) async {
      await _pumpGate(
        tester,
        const AccountSession(
          uid: 'incomplete-user',
          email: 'incomplete@example.com',
          isAnonymous: false,
          isEmailVerified: true,
        ),
        provisioningComplete: false,
      );

      expect(find.byType(MainNavigationScreen), findsNothing);
      expect(find.byType(RegisterScreen), findsOneWidget);
    },
  );

  testWidgets('unverified incomplete sessions also open profile recovery', (
    tester,
  ) async {
    await _pumpGate(
      tester,
      const AccountSession(
        uid: 'incomplete-user',
        email: 'incomplete@example.com',
        isAnonymous: false,
        isEmailVerified: false,
      ),
      provisioningComplete: false,
    );

    expect(find.byType(OTPScreen), findsNothing);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });

  testWidgets(
    'lookup failure with no durable completion opens neither shell nor recovery',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: SessionGateScreen(
            accountGateway: _FakeAccountGateway(
              const AccountSession(
                uid: 'unknown-user',
                email: 'unknown@example.com',
                isAnonymous: false,
                isEmailVerified: true,
              ),
            ),
            profileProvisioner: _SequencedProfileProvisioner([
              StateError('offline'),
            ]),
            guestSessionService: _PendingGuestSessionService(),
            guestUpgradeHandoff: noOpGuestUpgradeHandoff,
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(MainNavigationScreen), findsNothing);
      expect(find.byType(RegisterScreen), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('provisioning-retry')),
        findsOneWidget,
      );
    },
  );

  testWidgets('retry after restored connectivity rechecks provisioning', (
    tester,
  ) async {
    final provisioner = _SequencedProfileProvisioner([
      StateError('offline'),
      true,
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: SessionGateScreen(
          accountGateway: _FakeAccountGateway(
            const AccountSession(
              uid: 'restored-user',
              email: 'restored@example.com',
              isAnonymous: false,
              isEmailVerified: true,
            ),
          ),
          profileProvisioner: provisioner,
          guestSessionService: _PendingGuestSessionService(),
          guestUpgradeHandoff: noOpGuestUpgradeHandoff,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey<String>('provisioning-retry')));
    await tester.pumpAndSettle();

    expect(provisioner.lookupCalls, 2);
    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });

  testWidgets('live session changes replace the root child without pushing', (
    tester,
  ) async {
    final sessions = StreamController<AccountSession?>.broadcast();
    final guestSessionService = _PendingGuestSessionService();
    final observer = _CountingNavigatorObserver();
    addTearDown(sessions.close);

    await tester.pumpWidget(
      MaterialApp(
        navigatorObservers: [observer],
        home: SessionGateScreen(
          accountGateway: _FakeAccountGateway(null, authState: sessions.stream),
          guestSessionService: guestSessionService,
          profileProvisioner: const _FakeProfileProvisioner(true),
          guestUpgradeHandoff: noOpGuestUpgradeHandoff,
        ),
      ),
    );
    await tester.pump();
    sessions.add(null);
    await tester.pump();

    final navigator = tester.state<NavigatorState>(find.byType(Navigator));
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(observer.pushes, 1);

    sessions.add(
      const AccountSession(
        uid: 'anonymous-user',
        email: null,
        isAnonymous: true,
        isEmailVerified: false,
      ),
    );
    await tester.pump();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(observer.pushes, 1);

    sessions.add(
      const AccountSession(
        uid: 'unverified-user',
        email: 'unverified@example.com',
        isAnonymous: false,
        isEmailVerified: false,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(OTPScreen), findsOneWidget);
    expect(navigator.canPop(), isFalse);
    expect(observer.pushes, 1);
  });
}
