import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _FakeGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'app-build-info-test');
}

final class _FakeAccountGateway implements AccountGateway {
  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

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

AppDependencies _dependencies(AppBuildInfo buildInfo) {
  return AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      firebase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    accountGateway: _FakeAccountGateway(),
    guestSessionService: _FakeGuestSessionService(),
    guestUpgradeHandoff: noOpGuestUpgradeHandoff,
    buildInfo: buildInfo,
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
        expect(info.version, '0.1.0+1');
        expect(info.buildId, 'development');
      },
    );
  });

  group('MainNavigationScreen build identity', () {
    setUp(() {
      GoogleFonts.config.allowRuntimeFetching = false;
    });

    testWidgets('drawer renders version and buildId under build-identity', (
      tester,
    ) async {
      const buildInfo = AppBuildInfo(version: '9.9.9+9', buildId: 'feedface');
      await _pumpHome(tester, buildInfo);
      await _openDrawer(tester);

      final identity = tester.widget<Text>(
        find.byKey(const ValueKey<String>('build-identity')),
      );
      expect(identity.data, contains('9.9.9+9'));
      expect(identity.data, contains('feedface'));
    });
  });
}
