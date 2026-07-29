import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'guest-shell-test');
  }
}

const _drawerButtonKey = ValueKey<String>('legacy-drawer-button');

AppDependencies _dependencies({bool ready = true}) {
  final availability = ready
      ? RuntimeAvailability.ready
      : RuntimeAvailability.unavailable;
  return AppDependencies(
    runtimeStatus: AppRuntimeStatus(
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
  final navigator = tester.state<NavigatorState>(find.byType(Navigator).first);
  navigator.pushReplacementNamed('/home');
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
  setUp(() {
    GoogleFonts.config.allowRuntimeFetching = false;
  });

  testWidgets('/home resolves to the canonical learning shell', (tester) async {
    await _pumpHome(tester);

    expect(find.byType(MainNavigationScreen), findsOneWidget);
    expect(find.byKey(_drawerButtonKey), findsOneWidget);
  });

  testWidgets('shell has exactly five ordered destinations', (tester) async {
    await _pumpHome(tester);

    final destinations = tester
        .widgetList<NavigationDestination>(
          find.descendant(
            of: find.byType(MainNavigationScreen),
            matching: find.byType(NavigationDestination),
          ),
        )
        .toList();

    expect(destinations, hasLength(5));
    expect(destinations.map((destination) => destination.label), <String>[
      'เรียนรู้',
      'สถิติ',
      'จุดอ่อน',
      'รางวัล',
      'โปรไฟล์',
    ]);
  });

  testWidgets('all destinations switch the persistent IndexedStack', (
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

    for (var index = 0; index < 5; index++) {
      await tester.tap(destinations.at(index));
      await tester.pump(const Duration(milliseconds: 50));
      expect(tester.widget<IndexedStack>(stackFinder).index, index);
    }
  });

  testWidgets('drawer lists legacy destinations and safe runtime status', (
    tester,
  ) async {
    await _pumpHome(tester, ready: false);
    await _openDrawer(tester);

    expect(find.text('คลังหมวดหมู่'), findsOneWidget);
    expect(find.text('ร้านค้า'), findsNothing);
    expect(find.text('ตั้งค่าเดิม'), findsOneWidget);

    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, contains('ไม่พร้อม'));
  });

  testWidgets('drawer category item reaches CategoriesPage', (tester) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.tap(find.text('คลังหมวดหมู่'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(CategoriesPage), findsOneWidget);
  });

  testWidgets('drawer settings item reaches SettingScreen', (tester) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    await tester.tap(find.text('ตั้งค่าเดิม'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(SettingScreen), findsOneWidget);
  });
}
