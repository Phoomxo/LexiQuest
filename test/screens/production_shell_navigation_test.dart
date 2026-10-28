import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
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

final class _FakeAccountGateway implements AccountGateway {
  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(currentSession);

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

const _drawerButtonKey = ValueKey<String>('legacy-drawer-button');

AppDependencies _dependencies({
  RuntimeAvailability firebase = RuntimeAvailability.ready,
  RuntimeAvailability backends = RuntimeAvailability.ready,
  RuntimeAvailability deviceCapabilities = RuntimeAvailability.ready,
  RuntimeAvailability onDeviceInference = RuntimeAvailability.ready,
}) {
  return AppDependencies(
    runtimeStatus: AppRuntimeStatus(
      firebase: firebase,
      backends: backends,
      deviceCapabilities: deviceCapabilities,
      onDeviceInference: onDeviceInference,
    ),
    config: null,
    accountGateway: _FakeAccountGateway(),
    guestSessionService: _FakeGuestSessionService(),
    guestUpgradeHandoff: noOpGuestUpgradeHandoff,
  );
}

Future<void> _pumpHome(
  WidgetTester tester, {
  RuntimeAvailability firebase = RuntimeAvailability.ready,
  RuntimeAvailability backends = RuntimeAvailability.ready,
  RuntimeAvailability deviceCapabilities = RuntimeAvailability.ready,
  RuntimeAvailability onDeviceInference = RuntimeAvailability.ready,
}) async {
  await tester.pumpWidget(
    MyApp(
      dependencies: _dependencies(
        firebase: firebase,
        backends: backends,
        deviceCapabilities: deviceCapabilities,
        onDeviceInference: onDeviceInference,
      ),
    ),
  );
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

  testWidgets('drawer says the full system and online services are ready', (
    tester,
  ) async {
    await _pumpHome(tester);
    await _openDrawer(tester);

    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, 'ระบบพร้อมใช้งาน รวมบริการออนไลน์');
  });

  testWidgets('drawer keeps local learning available when cloud is degraded', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.degraded,
    );
    await _openDrawer(tester);

    expect(find.text('คลังหมวดหมู่'), findsOneWidget);
    expect(find.text('ร้านค้า'), findsNothing);
    expect(find.text('ตั้งค่าเดิม'), findsOneWidget);

    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, contains('เรียนแบบออฟไลน์ได้'));
    expect(status.data, contains('การซิงค์บัญชี'));
    expect(status.data, contains('AI/เสียงออนไลน์'));
    expect(status.data, isNot(contains('Supabase')));
  });

  testWidgets(
    'drawer distinguishes capability readiness from unavailable inference',
    (tester) async {
      await _pumpHome(
        tester,
        deviceCapabilities: RuntimeAvailability.ready,
        onDeviceInference: RuntimeAvailability.unavailable,
      );
      await _openDrawer(tester);

      final status = tester.widget<Text>(
        find.byKey(const ValueKey<String>('runtime-status-summary')),
      );
      expect(status.data, contains('On-device inference'));
      expect(status.data, isNot(contains('Device capabilities')));
      expect(status.data, isNot(contains('ระบบพร้อมใช้งาน')));
      expect(status.data, contains('เรียนแบบออฟไลน์ได้'));
    },
  );

  testWidgets('drawer names a degraded device capability profile', (
    tester,
  ) async {
    await _pumpHome(
      tester,
      deviceCapabilities: RuntimeAvailability.degraded,
      onDeviceInference: RuntimeAvailability.unavailable,
    );
    await _openDrawer(tester);

    final status = tester.widget<Text>(
      find.byKey(const ValueKey<String>('runtime-status-summary')),
    );
    expect(status.data, contains('Device capabilities (degraded)'));
    expect(status.data, contains('On-device inference'));
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
