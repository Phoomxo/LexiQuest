import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/email_action_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'guest-shell-test');
  }
}

const _drawerButtonKey = ValueKey<String>('legacy-drawer-button');

AppDependencies _dependencies({
  bool ready = true,
  AppRoute initialRoute = AppRoute.home,
}) {
  final availability = ready
      ? RuntimeAvailability.ready
      : RuntimeAvailability.unavailable;
  return AppDependencies(
    initialRoute: initialRoute,
    runtimeStatus: AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: availability,
      supabase: availability,
      backends: availability,
    ),
    config: null,
    guestSessionService: _FakeGuestSessionService(),
  );
}

Future<void> _pumpHome(WidgetTester tester, {bool ready = true}) async {
  await tester.pumpWidget(MyApp(dependencies: _dependencies(ready: ready)));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(_drawerButtonKey));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  expect(find.byType(Drawer), findsOneWidget);
}

void main() {
  testWidgets('supported cold-start email action overrides bootstrap route', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        'https://vocab-learning-app-219ef.firebaseapp.com/auth/action'
        '?mode=resetPassword&oobCode=abc123';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(EmailActionScreen), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });

  testWidgets('unsupported cold-start route uses bootstrap fallback', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/unsupported';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
  });

  testWidgets('signed-out bootstrap rejects cold-start /home', (tester) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue = '/home';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(
      MyApp(dependencies: _dependencies(initialRoute: AppRoute.login)),
    );
    await tester.pump();

    expect(find.byType(LoginScreen), findsOneWidget);
    expect(find.byType(MainNavigationScreen), findsNothing);
  });

  testWidgets('cold-start email verification without args uses bootstrap', (
    tester,
  ) async {
    tester.binding.platformDispatcher.defaultRouteNameTestValue =
        '/email-verification';
    addTearDown(
      tester.binding.platformDispatcher.clearDefaultRouteNameTestValue,
    );

    await tester.pumpWidget(MyApp(dependencies: _dependencies()));
    await tester.pump();

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byType(OTPScreen), findsNothing);
  });

  testWidgets('/home resolves to the field-safe shell', (tester) async {
    await _pumpHome(tester);

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byKey(_drawerButtonKey), findsOneWidget);
  });

  testWidgets('field shell exposes all completed primary workspaces', (
    tester,
  ) async {
    await _pumpHome(tester);

    final destinations = tester
        .widgetList<NavigationDestination>(
          find.descendant(
            of: find.byType(MainNavigationScreen),
            matching: find.byType(NavigationDestination),
          ),
        )
        .toList();

    expect(destinations.map((destination) => destination.label), <String>[
      'คลังคำศัพท์',
      'เรียนรู้',
      'สถิติ',
      'จุดอ่อน',
      'รางวัล',
      'โปรไฟล์',
    ]);
  });

  testWidgets('field destinations switch the persistent IndexedStack', (
    tester,
  ) async {
    await _pumpHome(tester);

    final stackFinder = find.descendant(
      of: find.byType(MainNavigationScreen),
      matching: find.byType(IndexedStack),
    );
    final destinations = find.descendant(
      of: find.byType(MainNavigationScreen),
      matching: find.byType(NavigationDestination),
    );

    for (var index = 0; index < 6; index++) {
      await tester.tap(destinations.at(index));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<IndexedStack>(stackFinder).index, index);
    }
  });

  testWidgets('drawer keeps completed local features during cloud outage', (
    tester,
  ) async {
    await _pumpHome(tester, ready: false);
    await _openDrawer(tester);

    expect(find.text('คลังคำศัพท์'), findsWidgets);
    expect(find.text('ร้านค้า'), findsOneWidget);

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, contains('การเรียนในเครื่องยังใช้ได้'));
  });

  testWidgets('drawer vocabulary item keeps the category workspace selected', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.tap(find.text('คลังคำศัพท์').last);
    await tester.pumpAndSettle();

    expect(find.byType(CategoriesPage), findsOneWidget);
  });

  testWidgets('drawer settings item reaches SettingScreen', (tester) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.scrollUntilVisible(
      find.text('ตั้งค่า'),
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(find.text('ตั้งค่า'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SettingScreen), findsOneWidget);
  });
}
