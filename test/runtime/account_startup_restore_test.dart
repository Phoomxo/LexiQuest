import 'dart:async';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
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
  testWidgets(
    'replacing a scope waits for an already-started SQLite settlement',
    (tester) async {
      final now = DateTime.utc(2026, 8, 4);
      final barrier = _DuringStreakRead();
      final calls = <String>[];
      var oldDisposals = 0;
      var newDisposals = 0;
      Future<AppDependencies> scope(String id, {bool delayed = false}) async {
        final executor = delayed
            ? NativeDatabase.memory().interceptWith(barrier)
            : NativeDatabase.memory();
        final database = AppDatabase(executor);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => id,
          nowUtc: () => now,
        );
        final owner = await owners.getOrCreateActiveOwner();
        await database.customStatement(
          'INSERT INTO streak_baselines(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,freeze_count,updated_at_utc_ms,controls_continuity) VALUES (?,?,1,0,0,2,1,1)',
          [owner.id, owner.id],
        );
        return AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _Guest(),
          database: database,
          localOwners: owners,
          streak: StreakUseCases(
            owners: owners,
            repository: DriftStreakRepository(database),
            nowUtc: () => now,
            onSettled: () => calls.add(id),
          ),
          disposeResources: () async {
            if (delayed) {
              oldDisposals++;
            } else {
              newDisposals++;
            }
            await database.close();
          },
        );
      }

      final old = (await tester.runAsync(() => scope('old-a', delayed: true)))!;
      final next = (await tester.runAsync(() => scope('new-b')))!;
      barrier.armed = true;
      try {
        await tester.pumpWidget(MyApp(dependencies: old));
        for (var i = 0; i < 200 && !barrier.entered.isCompleted; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        expect(
          barrier.entered.isCompleted,
          isTrue,
          reason: 'the old SQLite settlement must reach the read barrier',
        );
        await tester.pumpWidget(MyApp(dependencies: next));
        expect(
          oldDisposals,
          0,
          reason: 'the active transaction still owns the old database',
        );
        barrier.release.complete();
        for (
          var i = 0;
          i < 100 && (oldDisposals == 0 || !calls.contains('new-b'));
          i++
        ) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(oldDisposals, 1);
        expect(calls.where((id) => id == 'new-b'), hasLength(1));
        final newState = (await tester.runAsync(
          () => next.database!.select(next.database!.streakStates).getSingle(),
        ))!;
        final newOwner = (await tester.runAsync(
          next.localOwners!.getOrCreateActiveOwner,
        ))!;
        expect((newState.ownerId, newState.freezeCount), (newOwner.id, 2));
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
      } finally {
        if (!barrier.release.isCompleted) barrier.release.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        for (
          var i = 0;
          i < 100 &&
              barrier.entered.isCompleted &&
              !calls.contains('old-a') &&
              oldDisposals == 0;
          i++
        ) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        final oldClosed = old.dispose();
        final nextClosed = next.dispose();
        for (var i = 0; i < 100; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          if (oldDisposals == 1 && newDisposals == 1) break;
        }
        await tester.runAsync(() async {
          await oldClosed.timeout(const Duration(seconds: 5));
          await nextClosed.timeout(const Duration(seconds: 5));
        });
      }
    },
  );

  testWidgets(
    'startup, resume and replacement recover the active streak once each',
    (tester) async {
      final now = DateTime.utc(2026, 8, 4);
      final calls = <String>[];
      final closed = <String>{};
      Future<AppDependencies> scope(String id) async {
        final database = AppDatabase(NativeDatabase.memory());
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => id,
          nowUtc: () => now,
        );
        final owner = await owners.getOrCreateActiveOwner();
        await database.customStatement(
          'INSERT INTO streak_baselines(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,freeze_count,updated_at_utc_ms,controls_continuity) VALUES (?,?,1,0,0,2,1,1)',
          [owner.id, owner.id],
        );
        return AppDependencies(
          runtimeStatus: const AppRuntimeStatus(
            localData: RuntimeAvailability.ready,
            firebase: RuntimeAvailability.unavailable,
            supabase: RuntimeAvailability.unavailable,
            backends: RuntimeAvailability.unavailable,
          ),
          config: null,
          guestSessionService: _Guest(),
          database: database,
          localOwners: owners,
          streak: StreakUseCases(
            owners: owners,
            repository: DriftStreakRepository(database),
            nowUtc: () => now,
            onSettled: () => calls.add(id),
          ),
          disposeResources: () async {
            await database.close();
            closed.add(id);
          },
        );
      }

      Future<void> finish(List<String> expected) async {
        for (var i = 0; i < 40 && calls.length < expected.length; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
          await tester.pump();
        }
        expect(calls, expected);
      }

      final first = (await tester.runAsync(() => scope('active-a')))!;
      final second = (await tester.runAsync(() => scope('active-b')))!;
      try {
        await tester.pumpWidget(MyApp(dependencies: first));
        await finish(['active-a']);
        expect(
          (await tester.runAsync(
            () => first.database!
                .select(first.database!.streakStates)
                .getSingle(),
          ))!.freezeCount,
          2,
        );
        for (final state in [
          AppLifecycleState.inactive,
          AppLifecycleState.hidden,
          AppLifecycleState.paused,
          AppLifecycleState.hidden,
          AppLifecycleState.inactive,
          AppLifecycleState.resumed,
        ]) {
          tester.binding.handleAppLifecycleStateChanged(state);
        }
        await finish(['active-a', 'active-a']);
        await tester.pumpWidget(MyApp(dependencies: first));
        await tester.pumpWidget(MyApp(dependencies: second));
        await finish(['active-a', 'active-a', 'active-b']);
        expect(
          (await tester.runAsync(
            () => second.database!
                .select(second.database!.streakStates)
                .getSingle(),
          ))!.ownerId,
          (await tester.runAsync(
            second.localOwners!.getOrCreateActiveOwner,
          ))!.id,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        final firstClosed = first.dispose();
        final secondClosed = second.dispose();
        for (var i = 0; i < 100 && closed.length < 2; i++) {
          await tester.pump();
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 5)),
          );
        }
        await tester.runAsync(() async {
          await firstClosed.timeout(const Duration(seconds: 5));
          await secondClosed.timeout(const Duration(seconds: 5));
        });
      }
    },
  );
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

final class _DuringStreakRead extends QueryInterceptor {
  bool armed = false;
  final entered = Completer<void>();
  final release = Completer<void>();

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (armed &&
        !entered.isCompleted &&
        statement.toLowerCase().contains('answer_attempts')) {
      entered.complete();
      await release.future;
    }
    return rows;
  }
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
