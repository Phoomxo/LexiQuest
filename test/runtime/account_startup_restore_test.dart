import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/email_action_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  for (final anonymous in [false, true]) {
    testWidgets(
      '${anonymous ? 'anonymous' : 'verified'} restored session opens Home once',
      (tester) async {
        final gateway = _Gateway(_session(anonymous: anonymous));
        await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
        await tester.pumpAndSettle();

        expect(find.byType(MainNavigationScreen), findsOneWidget);
        expect(find.byType(LoginScreen, skipOffstage: false), findsNothing);
        expect(
          tester.state<NavigatorState>(find.byType(Navigator).first).canPop(),
          isFalse,
        );
        expect(gateway.mutations, 0);
      },
    );
  }

  testWidgets(
    'unverified restore uses typed verification arguments and Back reaches Login',
    (tester) async {
      final gateway = _Gateway(_session(verified: false));
      await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
      await tester.pumpAndSettle();

      final verification = find.byType(OTPScreen);
      expect(verification, findsOneWidget);
      expect(
        tester.widget<OTPScreen>(verification).email,
        'learner@example.test',
      );
      final args = ModalRoute.of(
        tester.element(verification),
      )!.settings.arguments;
      expect(args, isA<EmailVerificationArgs>());
      expect(find.byType(MainNavigationScreen), findsNothing);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(gateway.mutations, 0);
    },
  );

  for (final unavailable in [false, true]) {
    testWidgets(
      '${unavailable ? 'unavailable Firebase' : 'absent session'} retains local Guest entry',
      (tester) async {
        final gateway = _Gateway(unavailable ? _session() : null);
        final guest = _Guest();
        await tester.pumpWidget(
          MyApp(
            dependencies: _dependencies(
              gateway,
              unavailable: unavailable,
              guest: guest,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byType(LoginScreen), findsOneWidget);
        expect(guest.starts, 0);
        if (unavailable) expect(gateway.reads, 0);
        final entry = find.byKey(const ValueKey<String>('guest-mode-button'));
        await tester.ensureVisible(entry);
        await tester.tap(entry);
        await tester.pumpAndSettle();
        expect(find.byType(MainNavigationScreen), findsOneWidget);
        expect(guest.starts, 1);
        expect(gateway.mutations, 0);
      },
    );
  }

  testWidgets('failed session read leaves Login usable', (tester) async {
    final gateway = _Gateway(null)
      ..readFailure = StateError('synthetic session read failure');
    await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
    await tester.pumpAndSettle();
    expect(find.byType(LoginScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  for (final route in [
    '/login',
    '/register',
    '/home',
    '/email-verification',
    '/unknown',
  ]) {
    testWidgets(
      'explicit initial $route preserves the existing route factory',
      (tester) async {
        tester.binding.platformDispatcher.defaultRouteNameTestValue = route;
        addTearDown(
          tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
        );
        final gateway = _Gateway(_session());
        await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
        await tester.pumpAndSettle();

        if (route == '/home') {
          expect(find.byType(MainNavigationScreen), findsOneWidget);
        } else if (route == '/register') {
          expect(find.byType(RegisterScreen), findsOneWidget);
        } else {
          expect(find.byType(LoginScreen), findsOneWidget);
        }
        if (route != '/home') expect(gateway.reads, 0);
        expect(gateway.mutations, 0);
      },
    );
  }

  testWidgets('password-reset deep link is not replaced by restored Home', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/auth/action?mode=resetPassword&oobCode=synthetic-reset';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );
    final gateway = _Gateway(_session());
    await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
    await tester.pumpAndSettle();

    final action = tester.widget<EmailActionScreen>(
      find.byType(EmailActionScreen),
    );
    expect(action.action.mode, EmailActionMode.resetPassword);
    expect(action.action.code, 'synthetic-reset');
    expect(find.byType(MainNavigationScreen), findsNothing);
    expect(gateway.mutations, 0);
  });

  testWidgets('warm Android app link keeps its trusted authority', (
    tester,
  ) async {
    final gateway = _Gateway(null);
    await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
    await tester.pumpAndSettle();

    const location =
        'https://vocab-learning-app-219ef.firebaseapp.com/__/auth/links?'
        'link=https%3A%2F%2Fvocab-learning-app-219ef.firebaseapp.com%2F__%2Fauth%2Faction%3Fmode%3DresetPassword%26oobCode%3Dwarm-reset';
    final message = const JSONMethodCodec().encodeMethodCall(
      const MethodCall('pushRouteInformation', {
        'location': location,
        'state': null,
      }),
    );
    await tester.binding.defaultBinaryMessenger.handlePlatformMessage(
      'flutter/navigation',
      message,
      (_) {},
    );
    await tester.pumpAndSettle();

    final action = tester.widget<EmailActionScreen>(
      find.byType(EmailActionScreen),
    );
    expect(action.action.mode, EmailActionMode.resetPassword);
    expect(action.action.code, 'warm-reset');
    expect(gateway.mutations, 0);
  });

  testWidgets(
    'root rebuild does not replace navigation or reread startup session',
    (tester) async {
      final gateway = _Gateway(_session());
      final dependencies = _dependencies(gateway);
      await tester.pumpWidget(MyApp(dependencies: dependencies));
      await tester.pumpAndSettle();
      final navigator = tester.state<NavigatorState>(
        find.byType(Navigator).first,
      );
      navigator.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('navigation-marker')),
        ),
      );
      await tester.pumpAndSettle();
      final reads = gateway.reads;
      gateway.session = null;

      await tester.pumpWidget(MyApp(dependencies: dependencies));
      await tester.pumpAndSettle();

      expect(find.text('navigation-marker'), findsOneWidget);
      expect(gateway.reads, reads);
      expect(gateway.mutations, 0);
    },
  );
}

AccountSession _session({bool anonymous = false, bool verified = true}) =>
    AccountSession(
      uid: 'synthetic-restored-user',
      email: anonymous ? null : 'learner@example.test',
      isAnonymous: anonymous,
      emailVerified: !anonymous && verified,
    );

AppDependencies _dependencies(
  _Gateway gateway, {
  bool unavailable = false,
  _Guest? guest,
}) => AppDependencies(
  runtimeStatus: AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: unavailable
        ? RuntimeAvailability.unavailable
        : RuntimeAvailability.ready,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: guest ?? _Guest(),
  account: AccountUseCases(
    gateway: gateway,
    owners: _UnusedOwners(),
    upgradeGuestOwner: UpgradeGuestOwner(_UnusedUpgrades()),
  ),
);

final class _Gateway implements AccountGateway {
  _Gateway(this.session);
  AccountSession? session;
  Object? readFailure;
  int reads = 0;
  int mutations = 0;
  @override
  AccountSession? get currentSession {
    reads++;
    if (readFailure case final error?) throw error;
    return session;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    mutations++;
    throw StateError('startup must not invoke account mutations');
  }
}

final class _Guest implements GuestSessionService {
  int starts = 0;
  @override
  Future<GuestSessionResult> start() async {
    starts++;
    return const GuestSessionStarted(uid: 'synthetic-local-guest');
  }
}

final class _UnusedOwners implements LocalOwnerRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('routing must not rebind an owner');
}

final class _UnusedUpgrades implements OwnerUpgradeRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw StateError('routing must not upgrade an owner');
}
