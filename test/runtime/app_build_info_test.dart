import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'app-build-info-test');
}

AppDependencies _dependencies(
  AppBuildInfo buildInfo, {
  Future<void> Function()? disposeResources,
  SyncTrigger? syncTrigger,
  DisplayPreferencesController? displayPreferences,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _FakeGuestSessionService(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    buildInfo: buildInfo,
    syncTrigger: syncTrigger,
    displayPreferences: displayPreferences,
    disposeResources: disposeResources,
  );
}

Future<void> _pumpHome(WidgetTester tester, AppBuildInfo buildInfo) async {
  await tester.pumpWidget(MyApp(dependencies: _dependencies(buildInfo)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey<String>('legacy-drawer-button')));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(Drawer), findsOneWidget);
}

void main() {
  group('AppBuildInfo', () {
    test('stores the provided version and build id', () {
      const info = AppBuildInfo(version: '9.9.9+9', buildId: 'feedface');
      expect(info.version, '9.9.9+9');
      expect(info.buildId, 'feedface');
    });

    test(
      'fromEnvironment defaults to pubspec version and a development id',
      () {
        const info = AppBuildInfo.fromEnvironment();
        expect(info.version, '1.0.0+1');
        expect(info.buildId, 'development');
      },
    );
  });

  group('MainNavigationScreen build identity', () {
    setUp(() {});

    testWidgets('drawer renders version and buildId under build-identity', (
      tester,
    ) async {
      const buildInfo = AppBuildInfo(version: '9.9.9+9', buildId: 'feedface');
      await _pumpHome(tester, buildInfo);
      await _openDrawer(tester);
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey<String>('build-identity')),
        300,
        scrollable: find.byType(Scrollable).last,
      );

      final identity = tester.widget<Text>(
        find.byKey(const ValueKey<String>('build-identity')),
      );
      expect(identity.data, contains('9.9.9+9'));
      expect(identity.data, contains('feedface'));
    });
  });

  testWidgets('MyApp disposes runtime resources exactly once', (tester) async {
    var disposeCalls = 0;
    final dependencies = _dependencies(
      const AppBuildInfo.fromEnvironment(),
      disposeResources: () async {
        disposeCalls++;
      },
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.runAsync(() => Future<void>.delayed(Duration.zero));
    await dependencies.dispose();

    expect(disposeCalls, 1);
  });

  testWidgets(
    'MyApp consumes bounded cleanup failures on replace and unmount',
    (tester) async {
      var firstDisposeCalls = 0;
      var secondDisposeCalls = 0;
      Future<void> failCleanup(void Function() count) async {
        count();
        await Future<void>.value();
        throw StateError('bounded cleanup failed');
      }

      final first = _dependencies(
        const AppBuildInfo.fromEnvironment(),
        disposeResources: () => failCleanup(() => firstDisposeCalls += 1),
      );
      final second = _dependencies(
        const AppBuildInfo.fromEnvironment(),
        disposeResources: () => failCleanup(() => secondDisposeCalls += 1),
      );

      await tester.pumpWidget(MyApp(dependencies: first));
      await tester.pumpWidget(MyApp(dependencies: second));
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(tester.takeException(), isNull);
      expect(firstDisposeCalls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      expect(tester.takeException(), isNull);
      expect(secondDisposeCalls, 1);
    },
  );

  testWidgets('MyApp requests shared sync after initial startup', (
    tester,
  ) async {
    var runs = 0;
    final trigger = SyncTrigger(() async {
      runs += 1;
      return const SyncRunResult(status: SyncRunStatus.completed);
    });
    final dependencies = _dependencies(
      const AppBuildInfo.fromEnvironment(),
      syncTrigger: trigger,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();

    expect(runs, 1);
  });

  testWidgets('MyApp requests shared sync when returning to foreground', (
    tester,
  ) async {
    var runs = 0;
    final trigger = SyncTrigger(() async {
      runs += 1;
      return const SyncRunResult(status: SyncRunStatus.completed);
    });
    final dependencies = _dependencies(
      const AppBuildInfo.fromEnvironment(),
      syncTrigger: trigger,
    );
    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();
    runs = 0;

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pump();

    expect(runs, 1);
  });

  testWidgets('MyApp is driven by the durable display preference controller', (
    tester,
  ) async {
    final repository = _DisplayRepository();
    final controller = DisplayPreferencesController(
      LearnerPreferencesUseCases(
        repository: repository,
        owners: _DisplayOwner(),
        nowUtc: () => DateTime.utc(2026, 8, 30, 12),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    await controller.selectThemeMode(ThemeMode.dark);
    await controller.setReducedMotion(true);
    final dependencies = _dependencies(
      const AppBuildInfo.fromEnvironment(),
      displayPreferences: controller,
    );

    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();

    expect(
      tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode,
      ThemeMode.dark,
    );
    final descendant = find.descendant(
      of: find.byType(MaterialApp),
      matching: find.byType(Navigator),
    );
    expect(descendant, findsOneWidget);
    expect(MediaQuery.of(tester.element(descendant)).disableAnimations, isTrue);
  });

  testWidgets('MyApp system theme follows platform brightness changes', (
    tester,
  ) async {
    final controller = DisplayPreferencesController(
      LearnerPreferencesUseCases(
        repository: _DisplayRepository(),
        owners: _DisplayOwner(),
        nowUtc: () => DateTime.utc(2026, 8, 30, 12),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();
    final dispatcher = tester.binding.platformDispatcher;
    addTearDown(dispatcher.clearPlatformBrightnessTestValue);
    dispatcher.platformBrightnessTestValue = Brightness.light;
    final dependencies = _dependencies(
      const AppBuildInfo.fromEnvironment(),
      displayPreferences: controller,
    );
    await tester.pumpWidget(MyApp(dependencies: dependencies));
    await tester.pump();
    final navigator = find.descendant(
      of: find.byType(MaterialApp),
      matching: find.byType(Navigator),
    );
    expect(Theme.of(tester.element(navigator)).brightness, Brightness.light);

    dispatcher.platformBrightnessTestValue = Brightness.dark;
    dispatcher.onPlatformBrightnessChanged?.call();
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.system);
    expect(Theme.of(tester.element(navigator)).brightness, Brightness.dark);
  });
}

final class _DisplayOwner implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'owner:display-main',
    createdAtUtc: DateTime.utc(2026, 8, 30),
  );

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      getOrCreateActiveOwner();
}

final class _DisplayRepository implements LearnerPreferencesRepository {
  LearnerPreferences current = LearnerPreferences.defaults(
    ownerId: 'owner:display-main',
    updatedAtUtc: DateTime.utc(2026, 8, 30),
  );

  @override
  Future<LearnerPreferences> read(String ownerId) async => current;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    current = preferences;
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    current = LearnerPreferences(
      ownerId: current.ownerId,
      preferenceVersion: current.preferenceVersion,
      goal: current.goal,
      availableMinutesPerDay: current.availableMinutesPerDay,
      activityPreference: current.activityPreference,
      updatedAtUtc: current.updatedAtUtc,
      display: display,
    );
  }
}
