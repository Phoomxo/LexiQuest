import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/account/account_profile_provisioner.dart';
import 'package:vocab_learning_app/navigation/app_route.dart';
import 'package:vocab_learning_app/navigation/app_router.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/change_password_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _FakeAccountGateway implements AccountGateway {
  _FakeAccountGateway({this.applyVerificationError});

  final Object? applyVerificationError;
  final List<String> appliedVerificationCodes = <String>[];

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<void> applyVerificationCode(String code) async {
    appliedVerificationCodes.add(code);
    final error = applyVerificationError;
    if (error != null) throw error;
  }

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

final class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.unknown);
}

final class _FakeProfileProvisioner implements AccountProfileProvisioning {
  const _FakeProfileProvisioner();

  @override
  Future<void> ensureProfile(String uid, AccountProfile profile) =>
      throw UnimplementedError();

  @override
  Future<AccountProvisioningState> provisioningState(String uid) async =>
      AccountProvisioningState.complete;
}

AppRouter _router({
  _FakeAccountGateway? accountGateway,
  GuestUpgradeHandoff? guestUpgradeHandoff,
}) => AppRouter(
  AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      firebase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    accountGateway: accountGateway ?? _FakeAccountGateway(),
    accountProfileProvisioning: const _FakeProfileProvisioner(),
    guestSessionService: _FakeGuestSessionService(),
    guestUpgradeHandoff: guestUpgradeHandoff ?? noOpGuestUpgradeHandoff,
  ),
);

void main() {
  test('canonical account routes are unique and stable', () {
    expect(
      AppRoute.values.map((route) => route.path).toSet().length,
      AppRoute.values.length,
    );
    expect(AppRoute.login.path, '/login');
    expect(AppRoute.forgotPassword.path, '/forgot-password');
    expect(AppRoute.resetPassword.path, '/reset-password');
    expect(AppRoute.changePassword.path, '/change-password');
  });

  test('router constructs the implemented typed routes', () {
    final router = _router();

    for (final route in <AppRoute>[
      AppRoute.sessionGate,
      AppRoute.login,
      AppRoute.register,
      AppRoute.changePassword,
      AppRoute.home,
    ]) {
      expect(
        router.generateRoute(RouteSettings(name: route.path)),
        isA<Route<dynamic>>(),
      );
    }
  });

  test('change-password route rejects unexpected arguments', () {
    final router = _router();

    expect(
      router.generateRoute(const RouteSettings(name: '/change-password')),
      isA<Route<dynamic>>(),
    );
    expect(
      router.generateRoute(
        const RouteSettings(name: '/change-password', arguments: 'unexpected'),
      ),
      isNull,
    );
  });

  testWidgets('router constructs change-password with its injected gateway', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    final router = _router(accountGateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: router.generateRoute,
        initialRoute: AppRoute.changePassword.path,
      ),
    );

    expect(find.byType(ChangePasswordScreen), findsOneWidget);
  });

  testWidgets('router passes its required guest handoff to registration', (
    tester,
  ) async {
    Future<void> handoff(String previousUid, AccountSession session) async {}
    final router = _router(guestUpgradeHandoff: handoff);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: router.generateRoute,
        initialRoute: '/register',
      ),
    );

    expect(
      identical(
        tester
            .widget<RegisterScreen>(find.byType(RegisterScreen))
            .guestUpgradeHandoff,
        handoff,
      ),
      isTrue,
    );
  });

  test('router requires typed verification arguments', () {
    final router = _router();
    const args = VerifyEmailRouteArgs(email: 'student@example.com');

    final route = router.generateRoute(
      const RouteSettings(name: '/verify-email', arguments: args),
    );

    expect(route, isA<Route<dynamic>>());
    expect(route!.settings.arguments, same(args));
    expect(
      router.generateRoute(
        const RouteSettings(name: '/verify-email', arguments: 'email'),
      ),
      isNull,
    );
    expect(
      router.generateRoute(const RouteSettings(name: '/verify-email')),
      isNull,
    );
  });

  testWidgets('verification action applies its code once and routes to login', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway();
    final router = _router(accountGateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: router.generateRoute,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoute.verifyEmail.path,
              arguments: const VerifyEmailActionRouteArgs(
                code: 'verification-code',
              ),
            ),
            child: const Text('OPEN_ACTION'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN_ACTION'));
    await tester.pumpAndSettle();

    expect(
      gateway.appliedVerificationCodes,
      equals(<String>['verification-code']),
    );
    expect(find.byKey(const ValueKey<String>('login-email')), findsOneWidget);
  });

  testWidgets('verification action failure keeps the code out of the UI', (
    tester,
  ) async {
    final gateway = _FakeAccountGateway(
      applyVerificationError: const AccountOperationException(
        'invalid-action-code',
      ),
    );
    final router = _router(accountGateway: gateway);
    await tester.pumpWidget(
      MaterialApp(
        onGenerateRoute: router.generateRoute,
        home: Builder(
          builder: (context) => FilledButton(
            onPressed: () => Navigator.of(context).pushNamed(
              AppRoute.verifyEmail.path,
              arguments: const VerifyEmailActionRouteArgs(
                code: 'private-action-code',
              ),
            ),
            child: const Text('OPEN_ACTION'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('OPEN_ACTION'));
    await tester.pumpAndSettle();

    expect(
      gateway.appliedVerificationCodes,
      equals(<String>['private-action-code']),
    );
    expect(find.byKey(const ValueKey<String>('login-email')), findsNothing);
    expect(find.textContaining('private-action-code'), findsNothing);
  });
}
