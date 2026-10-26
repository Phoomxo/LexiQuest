import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/navigation/app_route_factory.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/email_action_screen.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _code = 'synthetic-reset-code';
const _password = 'synthetic-password';
const _reset = EmailAction(mode: EmailActionMode.resetPassword, code: _code);
const _verify = EmailAction(
  mode: EmailActionMode.verifyEmail,
  code: 'synthetic-verification-code',
);
const _success = 'เปลี่ยนรหัสผ่านสำเร็จ';
const _uncertain = 'ยังยืนยันผลไม่ได้ กรุณาลองเข้าสู่ระบบหรือขอลิงก์ใหม่';
Finder get _submit => find.widgetWithText(FilledButton, 'เปลี่ยนรหัสผ่าน');

void main() {
  late _Fixture fixture;
  setUp(() => fixture = _Fixture());

  for (final invalid in ['short', 'x' * 129]) {
    testWidgets(
      'invalid length ${invalid.length} stays editable before provider',
      (tester) async {
        await tester.pumpWidget(_app(account: fixture.account));
        await _send(tester, invalid);
        expect(fixture.gateway.resets, isEmpty);
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text('รหัสผ่านต้องมี 8–128 ตัวอักษร'), findsOneWidget);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          invalid,
        );
        await _send(tester, _password);
        expect(find.text(_success), findsOneWidget);
        expect(find.byType(TextField), findsNothing);
        expect(fixture.gateway.resets, [(_code, _password)]);
      },
    );
  }

  for (final unexpected in [false, true]) {
    testWidgets(
      '${unexpected ? 'unexpected' : 'network'} failure allows explicit retry only',
      (tester) async {
        fixture.gateway.reset = () async => throw unexpected
            ? StateError('synthetic raw $_code $_password')
            : const AccountException(AccountFailureCode.network);
        await tester.pumpWidget(_app(account: fixture.account));
        await _send(tester, _password);
        expect(tester.takeException(), isNull);
        expect(
          find.text(unexpected ? _uncertain : 'เชื่อมต่อไม่ได้ กรุณาลองใหม่'),
          findsOneWidget,
        );
        expect(
          tester
              .widgetList<Semantics>(
                find.ancestor(
                  of: find.text(
                    unexpected ? _uncertain : 'เชื่อมต่อไม่ได้ กรุณาลองใหม่',
                  ),
                  matching: find.byType(Semantics),
                ),
              )
              .any((widget) => widget.properties.liveRegion == true),
          isTrue,
        );
        expect(find.byType(TextField), findsOneWidget);
        expect(find.text(_success), findsNothing);
        final visibleText = tester
            .widgetList<Text>(find.byType(Text))
            .map((text) => text.data ?? '')
            .join(' ');
        expect(visibleText, isNot(contains(_password)));
        expect(visibleText, isNot(contains(_code)));
        expect(visibleText, isNot(contains('synthetic raw')));
        await tester.pumpWidget(_app(account: fixture.account));
        await tester.pumpAndSettle();
        expect(fixture.gateway.resets, hasLength(1));
        fixture.gateway.reset = () async {};
        await _send(tester, _password);
        expect(fixture.gateway.resets, hasLength(2));
        expect(find.text(_success), findsOneWidget);
      },
    );
  }

  testWidgets('pending and stale submit callbacks cannot duplicate success', (
    tester,
  ) async {
    final pending = Completer<void>();
    fixture.gateway.reset = () => pending.future;
    await tester.pumpWidget(_app(account: fixture.account));
    await tester.enterText(find.byType(TextField), _password);
    final controller = tester
        .widget<TextField>(find.byType(TextField))
        .controller!;
    final submit = tester.widget<FilledButton>(_submit).onPressed!;
    submit();
    submit();
    await tester.pump();
    expect(fixture.gateway.resets, hasLength(1));
    expect(tester.widget<TextField>(find.byType(TextField)).enabled, isFalse);
    expect(find.text('กำลังเปลี่ยนรหัสผ่าน…'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังเปลี่ยนรหัสผ่าน',
    );
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
    pending.complete();
    await tester.pumpAndSettle();
    expect(find.text(_success), findsOneWidget);
    expect(controller.text, isEmpty);
    submit();
    await tester.pumpAndSettle();
    expect(fixture.gateway.resets, hasLength(1));
  });

  for (final expired in [false, true]) {
    testWidgets(
      '${expired ? 'expired' : 'invalid'} code after uncertain write stays honest',
      (tester) async {
        fixture.gateway.reset = () async =>
            throw const AccountException(AccountFailureCode.network);
        await tester.pumpWidget(_app(account: fixture.account));
        await _send(tester, _password);
        fixture.gateway.reset = () async => throw AccountException(
          expired
              ? AccountFailureCode.expiredActionCode
              : AccountFailureCode.invalidActionCode,
        );
        await _send(tester, _password);
        expect(
          find.text(
            expired
                ? 'ลิงก์นี้หมดอายุแล้ว กรุณาขอลิงก์ใหม่จากหน้าเข้าสู่ระบบ'
                : 'ลิงก์นี้ไม่ถูกต้องหรือถูกใช้แล้ว',
          ),
          findsOneWidget,
        );
        expect(find.text(_uncertain), findsOneWidget);
        expect(find.text(_success), findsNothing);
        expect(tester.widget<FilledButton>(_submit).onPressed, isNull);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
      },
    );
  }

  testWidgets('unknown action fails closed without dispatch', (tester) async {
    await tester.pumpWidget(
      _app(
        account: fixture.account,
        action: const EmailAction(mode: EmailActionMode.unknown, code: _code),
      ),
    );
    expect(find.text('ลิงก์นี้ไม่ถูกต้องหรือถูกใช้แล้ว'), findsOneWidget);
    expect(find.byType(TextField), findsNothing);
    expect(fixture.gateway.resets, isEmpty);
    expect(fixture.gateway.verifications, isEmpty);
    await _returnToLogin(tester);
  });

  for (final action in [_reset, _verify]) {
    testWidgets(
      '${action.mode.name} unavailable has guidance and login navigation',
      (tester) async {
        await tester.pumpWidget(_app(action: action));
        expect(
          find.text(
            'ระบบบัญชีออนไลน์ไม่พร้อม กรุณาลองภายหลังหรือกลับหน้าเข้าสู่ระบบ',
          ),
          findsOneWidget,
        );
        expect(find.text(_success), findsNothing);
        await _returnToLogin(tester);
      },
    );
  }

  for (final fails in [false, true]) {
    testWidgets(
      'disposed pending reset ${fails ? 'failure' : 'success'} has no stale UI',
      (tester) async {
        final pending = Completer<void>();
        fixture.gateway.reset = () => pending.future;
        await tester.pumpWidget(_app(account: fixture.account));
        await _send(tester, _password, settle: false);
        await tester.pumpWidget(const MaterialApp(home: Text('left-action')));
        if (fails) {
          pending.completeError(StateError('synthetic uncertain write'));
        } else {
          pending.complete();
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(find.text('left-action'), findsOneWidget);
        expect(fixture.gateway.resets, hasLength(1));
      },
    );
  }

  testWidgets(
    'changed action ignores old acknowledgement without ending new pending work',
    (tester) async {
      final oldPending = Completer<void>();
      final newPending = Completer<void>();
      fixture.gateway.reset = () => oldPending.future;
      await tester.pumpWidget(_app(account: fixture.account));
      final obsoleteSubmit = tester.widget<FilledButton>(_submit).onPressed!;
      await _send(tester, _password, settle: false);
      const nextAction = EmailAction(
        mode: EmailActionMode.resetPassword,
        code: 'synthetic-next-code',
      );
      await tester.pumpWidget(
        _app(account: fixture.account, action: nextAction),
      );
      obsoleteSubmit();
      await tester.pump();
      expect(fixture.gateway.resets, hasLength(1));
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        isEmpty,
      );
      fixture.gateway.reset = () => newPending.future;
      await _send(tester, 'synthetic-next-password', settle: false);
      oldPending.complete();
      await tester.pump();
      expect(find.text(_success), findsNothing);
      expect(find.text('กำลังเปลี่ยนรหัสผ่าน…'), findsOneWidget);
      newPending.complete();
      await tester.pumpAndSettle();
      expect(find.text(_success), findsOneWidget);
      expect(fixture.gateway.resets, [
        (_code, _password),
        ('synthetic-next-code', 'synthetic-next-password'),
      ]);
    },
  );

  for (final inherited in [false, true]) {
    testWidgets(
      '${inherited ? 'inherited' : 'injected'} account replacement fences old completion',
      (tester) async {
        final replacement = _Fixture();
        final pending = Completer<void>();
        fixture.gateway.reset = () => pending.future;
        Widget host(AccountUseCases account) => inherited
            ? AppDependenciesScope(
                dependencies: _dependencies(account),
                child: _app(),
              )
            : _app(account: account);
        await tester.pumpWidget(host(fixture.account));
        await _send(tester, _password, settle: false);
        await tester.pumpWidget(host(replacement.account));
        pending.complete();
        await tester.pumpAndSettle();
        expect(find.text(_success), findsNothing);
        expect(
          tester.widget<TextField>(find.byType(TextField)).controller!.text,
          isEmpty,
        );
        expect(replacement.gateway.resets, isEmpty);
        await _send(tester, _password);
        expect(find.text(_success), findsOneWidget);
        expect(replacement.gateway.resets, [(_code, _password)]);
      },
    );
  }

  for (final failure in [false, true]) {
    testWidgets(
      'verification ${failure ? 'error' : 'success'} is applied once',
      (tester) async {
        if (failure) {
          fixture.gateway.verify = () async => throw const AccountException(
            AccountFailureCode.expiredActionCode,
          );
        }
        await tester.pumpWidget(
          _app(account: fixture.account, action: _verify),
        );
        await tester.pumpAndSettle();
        expect(
          find.text(
            failure
                ? 'ลิงก์นี้หมดอายุแล้ว กรุณาขอลิงก์ใหม่จากหน้าเข้าสู่ระบบ'
                : 'ยืนยันอีเมลสำเร็จ',
          ),
          findsOneWidget,
        );
        await tester.pumpWidget(
          _app(account: fixture.account, action: _verify),
        );
        await tester.pumpAndSettle();
        expect(fixture.gateway.verifications, [_verify.code]);
        expect(fixture.gateway.resets, isEmpty);
        await _returnToLogin(tester);
      },
    );
  }

  testWidgets(
    'verification dependency change never silently repeats an attempt',
    (tester) async {
      final replacement = _Fixture();
      final pending = Completer<void>();
      fixture.gateway.verify = () => pending.future;
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(fixture.account),
          child: _app(action: _verify),
        ),
      );
      await tester.pump();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(replacement.account),
          child: _app(action: _verify),
        ),
      );
      pending.complete();
      await tester.pumpAndSettle();
      expect(find.text('ยืนยันอีเมลสำเร็จ'), findsNothing);
      expect(fixture.gateway.verifications, [_verify.code]);
      expect(replacement.gateway.verifications, isEmpty);
      expect(find.text('กลับหน้าเข้าสู่ระบบ'), findsOneWidget);
    },
  );

  testWidgets(
    'real deep-link route dispatches the original action code only on submit',
    (tester) async {
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(fixture.account),
          child: MaterialApp(
            initialRoute: '/auth/action?mode=resetPassword&oobCode=$_code',
            onGenerateRoute: AppRouteFactory.onGenerateRoute,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(fixture.gateway.resets, isEmpty);
      await _send(tester, _password);
      expect(fixture.gateway.resets, [(_code, _password)]);
      await _returnToLogin(tester);
    },
  );

  for (final size in [const Size(360, 800), const Size(800, 360)]) {
    for (final dark in [false, true]) {
      testWidgets(
        '${size.width}x${size.height} 200% IME ${dark ? 'dark' : 'light'} remains reachable',
        (tester) async {
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = size;
          final keyboardHeight = size.height > size.width ? 300.0 : 120.0;
          tester.view.viewInsets = FakeViewPadding(bottom: keyboardHeight);
          addTearDown(() {
            tester.view.resetViewInsets();
            tester.view.resetPhysicalSize();
            tester.view.resetDevicePixelRatio();
          });
          await tester.pumpWidget(
            _app(
              account: fixture.account,
              dark: dark,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(2),
                  disableAnimations: true,
                  padding: const EdgeInsets.only(bottom: 24),
                ),
                child: child!,
              ),
            ),
          );
          await tester.pumpAndSettle();
          final media = MediaQuery.of(
            tester.element(find.byType(EmailActionScreen)),
          );
          expect(media.size, size);
          expect(media.viewInsets.bottom, keyboardHeight);
          expect(media.textScaler.scale(16), 32);
          await tester.enterText(find.byType(TextField), 'short');
          await tester.ensureVisible(_submit);
          await tester.tap(_submit);
          await tester.pumpAndSettle();
          final error = find.text('รหัสผ่านต้องมี 8–128 ตัวอักษร');
          await tester.ensureVisible(error);
          expect(error.hitTestable(), findsOneWidget);
          expect(tester.takeException(), isNull);
          await tester.ensureVisible(_submit);
          final buttonSize = tester.getSize(_submit);
          expect(buttonSize.height, greaterThanOrEqualTo(48));
          expect(_submit.hitTestable(), findsOneWidget);
          await tester.enterText(find.byType(TextField), _password);
          await tester.ensureVisible(_submit);
          await tester.tap(_submit);
          await tester.pumpAndSettle();
          expect(find.text(_success), findsOneWidget);
          expect(tester.takeException(), isNull);
          await _returnToLogin(tester);
        },
      );
    }
  }
}

Widget _app({
  AccountUseCases? account,
  EmailAction action = _reset,
  bool dark = false,
  TransitionBuilder? builder,
}) => MaterialApp(
  theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
  builder: builder,
  home: EmailActionScreen(action: action, account: account),
  onGenerateRoute: AppRouteFactory.onGenerateRoute,
);

Future<void> _send(
  WidgetTester tester,
  String password, {
  bool settle = true,
}) async {
  await tester.enterText(find.byType(TextField), password);
  await tester.ensureVisible(_submit);
  await tester.tap(_submit);
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _returnToLogin(WidgetTester tester) async {
  final back = find.text('กลับหน้าเข้าสู่ระบบ');
  await tester.ensureVisible(back);
  await tester.tap(back);
  await tester.pumpAndSettle();
  expect(find.byType(LoginScreen), findsOneWidget);
  expect(find.byType(EmailActionScreen, skipOffstage: false), findsNothing);
}

final class _Fixture {
  _Fixture() {
    account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(upgrades),
    );
    addTearDown(() {
      expect(gateway.forbidden, 0);
      expect(owners.calls, 0);
      expect(upgrades.calls, 0);
    });
  }
  final gateway = _Gateway();
  final owners = _Owners();
  final upgrades = _Upgrades();
  late final AccountUseCases account;
}

final class _Gateway implements AccountGateway {
  final resets = <(String, String)>[];
  final verifications = <String>[];
  Future<void> Function() reset = () async {};
  Future<void> Function() verify = () async {};
  int forbidden = 0;
  @override
  AccountSession? get currentSession => const AccountSession(
    uid: 'other-open-account',
    email: 'other@example.test',
    isAnonymous: false,
    emailVerified: true,
  );
  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) {
    resets.add((code, newPassword));
    return reset();
  }

  @override
  Future<void> applyEmailVerificationCode(String code) {
    verifications.add(code);
    return verify();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    forbidden++;
    throw StateError('unexpected identity mutation');
  }
}

final class _Owners implements LocalOwnerRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('email action must not access local owners');
  }
}

final class _Upgrades implements OwnerUpgradeRepository {
  int calls = 0;
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('email action must not bind or delete owners');
  }
}

AppDependencies _dependencies(AccountUseCases account) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.ready,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _UnusedGuest(),
  account: account,
);

final class _UnusedGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() => throw StateError('no guest transition');
}
