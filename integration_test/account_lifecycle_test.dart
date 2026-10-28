import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/account/account_gateway.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/account_link_coordinator.dart';
import 'package:vocab_learning_app/navigation/app_router.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

final class _RecoveryAccountGateway implements AccountGateway {
  final resetRequests = <String>[];
  final verifiedCodes = <String>[];
  final confirmedResets = <({String code, String password})>[];
  final resetCompletion = Completer<void>();

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<void> requestPasswordReset(String email) async {
    resetRequests.add(email);
  }

  @override
  Future<String> verifyPasswordResetCode(String code) async {
    verifiedCodes.add(code);
    return 'student@example.com';
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {
    confirmedResets.add((code: code, password: newPassword));
    await resetCompletion.future;
  }

  @override
  Future<void> applyVerificationCode(String code) => throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) => throw UnimplementedError();

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
}

final class _UnavailableGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.providerDisabled);
}

AppDependencies _dependencies(_RecoveryAccountGateway gateway) =>
    AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        firebase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      accountGateway: gateway,
      guestSessionService: _UnavailableGuestSessionService(),
      guestUpgradeHandoff: noOpGuestUpgradeHandoff,
    );

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'completes the local account recovery UI lifecycle through typed routing',
    (tester) async {
      final gateway = _RecoveryAccountGateway();
      final coordinator = AccountLinkCoordinator.forTesting(
        initialLink: Future<Uri?>.value(
          Uri.parse(
            'https://vocab-learning-app-219ef.web.app/auth/action'
            '?mode=resetPassword&oobCode=local-reset-code',
          ),
        ),
        uriLinks: const Stream<Uri>.empty(),
        navigate: (route, arguments) {
          AppRouter.navigatorKey.currentState?.pushNamed(
            route.path,
            arguments: arguments,
          );
        },
      );
      addTearDown(coordinator.dispose);

      await tester.pumpWidget(MyApp(dependencies: _dependencies(gateway)));
      await tester.pumpAndSettle();

      await tester.tap(
        find.byKey(const ValueKey<String>('login-forgot-password')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('recovery-email')),
        ' Student@Example.com ',
      );
      await tester.tap(find.byKey(const ValueKey<String>('recovery-submit')));
      await tester.pumpAndSettle();
      expect(gateway.resetRequests, <String>['student@example.com']);

      await coordinator.start();
      await tester.pumpAndSettle();
      expect(gateway.verifiedCodes, <String>['local-reset-code']);
      expect(
        tester
            .widget<FilledButton>(
              find.byKey(const ValueKey<String>('reset-submit')),
            )
            .onPressed,
        isNotNull,
      );

      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-password')),
        'Password1',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('reset-confirmation')),
        'Password1',
      );
      await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey<String>('reset-submit')));
      await tester.pump();
      expect(gateway.confirmedResets, <({String code, String password})>[
        (code: 'local-reset-code', password: 'Password1'),
      ]);

      gateway.resetCompletion.complete();
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('login-email')), findsOneWidget);
    },
  );
}
