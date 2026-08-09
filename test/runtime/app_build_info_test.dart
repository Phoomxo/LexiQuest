import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'app-build-info-test');
}

AppDependencies _dependencies(
  AppBuildInfo buildInfo, {
  Future<void> Function()? disposeResources,
  SyncTrigger? syncTrigger,
}) {
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
    buildInfo: buildInfo,
    syncTrigger: syncTrigger,
    disposeResources: disposeResources,
  );
}

Future<void> _pumpHome(WidgetTester tester, AppBuildInfo buildInfo) async {
  await tester.pumpWidget(MyApp(dependencies: _dependencies(buildInfo)));
  await tester.pump();
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pushReplacementNamed('/home');
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
}
