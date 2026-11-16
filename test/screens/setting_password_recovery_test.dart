import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';

void main() {
  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed);
  });
  for (final transition in ['tab', 'route', 'lifecycle']) {
    testWidgets(
      'BB return from $transition keeps retired entry inert and current entry usable',
      (t) async {
        final f = Fixture();
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        final old = entry(t);
        await retire(t, f, transition);
        if (transition == 'route') f.nav.currentState!.pop();
        if (transition == 'lifecycle')
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        old();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        entry(t)();
        await t.pumpAndSettle();
        expect(find.byType(AlertDialog), findsOneWidget);
        await fill(t);
        await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
        await t.pumpAndSettle();
        expect(f.gateway.calls, 1);
        expect(find.text('เปลี่ยนรหัสผ่านแล้ว'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  testWidgets('BB same UID auth event retires dialog without screen rebuild', (
    t,
  ) async {
    final f = Fixture();
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    entry(t)();
    await t.pumpAndSettle();
    await fill(t);
    final save = t
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
        .onPressed!;
    f.gateway.events.add(f.gateway.currentSession);
    await t.pumpAndSettle();
    save();
    await t.pumpAndSettle();
    expect(f.gateway.calls, 0);
    expect(find.byType(AlertDialog), findsNothing);
    expect(t.takeException(), isNull);
  });
  testWidgets('BB route pop immediately retires retained entry', (t) async {
    final f = Fixture();
    await t.pumpWidget(
      MaterialApp(
        navigatorKey: f.nav,
        home: const Scaffold(body: Text('home')),
      ),
    );
    f.nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingScreen(account: f.account),
      ),
    );
    await t.pumpAndSettle();
    final old = entry(t);
    f.nav.currentState!.pop();
    old();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(f.gateway.calls, 0);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'BB replacement account is displayed before fresh password entry',
    (t) async {
      final f = Fixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      final replacement = Fixture();
      replacement.gateway.currentSession = const AccountSession(
        uid: 'replacement-user',
        email: 'replacement@example.test',
        isAnonymous: false,
        emailVerified: true,
      );
      f.account = replacement.account;
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      expect(find.text('replacement@example.test'), findsOneWidget);
      entry(t)();
      await t.pumpAndSettle();
      await fill(t);
      await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await t.pumpAndSettle();
      expect(f.gateway.calls, 0);
      expect(replacement.gateway.calls, 1);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('BB duplicate entry opens only one dialog', (t) async {
    final f = Fixture();
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    final open = entry(t);
    open();
    open();
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(f.gateway.calls, 0);
    await t.pumpWidget(const SizedBox());
    await t.pumpAndSettle();
  });
  for (final transition in [
    'replace',
    'remove',
    'session',
    'same-uid',
    'tab',
    'route',
    'lifecycle',
    'dispose',
  ]) {
    testWidgets('BB retained entry retires after $transition', (t) async {
      final f = Fixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      final old = entry(t);
      await retire(t, f, transition);
      old();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsNothing);
      expect(f.gateway.calls, 0);
      expect(t.takeException(), isNull);
    });
    testWidgets('BB dialog cannot submit after $transition', (t) async {
      final f = Fixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      entry(t)();
      await t.pumpAndSettle();
      await fill(t);
      final save = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
          .onPressed!;
      await retire(t, f, transition);
      save();
      await t.pumpAndSettle();
      expect(f.gateway.calls, 0);
      expect(t.takeException(), isNull);
    });
  }
  testWidgets(
    'BB current controls work after ordinary rebuild and duplicate save is inert',
    (t) async {
      final f = Fixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      final open = entry(t);
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      open();
      await t.pumpAndSettle();
      await fill(t);
      final save = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
          .onPressed!;
      save();
      save();
      await t.pumpAndSettle();
      expect(f.gateway.calls, 1);
      expect(find.text('เปลี่ยนรหัสผ่านแล้ว'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('BB weak input retains editable dialog without submitting', (
    t,
  ) async {
    final f = Fixture();
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    entry(t)();
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).first, 'x');
    await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await t.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(f.gateway.calls, 0);
    await fill(t);
    await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await t.pumpAndSettle();
    expect(f.gateway.calls, 1);
    expect(t.takeException(), isNull);
  });
  testWidgets(
    'BB cancelled dialog callbacks cannot pop or submit a later dialog',
    (t) async {
      final f = Fixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      entry(t)();
      await t.pumpAndSettle();
      await fill(t);
      final save = t
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'บันทึก'))
          .onPressed!;
      final cancel = t
          .widget<TextButton>(find.widgetWithText(TextButton, 'ยกเลิก'))
          .onPressed!;
      cancel();
      await t.pumpAndSettle();
      entry(t)();
      await t.pumpAndSettle();
      cancel();
      save();
      await t.pumpAndSettle();
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(f.gateway.calls, 0);
      expect(t.takeException(), isNull);
    },
  );
  for (final code in [
    AccountFailureCode.invalidCredential,
    AccountFailureCode.requiresRecentLogin,
  ]) {
    testWidgets(
      'BB known rejection is explicit and retains editable fields $code',
      (t) async {
        final f = Fixture()..gateway.failure = AccountException(code);
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        entry(t)();
        await t.pumpAndSettle();
        await fill(t);
        await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
        await t.pumpAndSettle();
        expect(find.byType(TextField), findsNWidgets(2));
        expect(f.gateway.calls, 1);
        expect(
          find.textContaining(
            code == AccountFailureCode.requiresRecentLogin
                ? 'กรุณาเข้าสู่ระบบใหม่'
                : 'ตรวจรหัสผ่าน',
          ),
          findsOneWidget,
        );
        f.gateway.failure = null;
        await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
        await t.pumpAndSettle();
        expect(f.gateway.calls, 2);
        expect(find.text('เปลี่ยนรหัสผ่านแล้ว'), findsOneWidget);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final failure in [
    const AccountException(AccountFailureCode.network),
    StateError('synthetic failure'),
  ]) {
    testWidgets(
      'BB uncertain acknowledgement requires separate explicit recovery ${failure.runtimeType}',
      (t) async {
        final f = Fixture()..gateway.failure = failure;
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        entry(t)();
        await t.pumpAndSettle();
        await fill(t);
        await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
        await t.pumpAndSettle();
        expect(
          find.textContaining('ยังยืนยันผลการเปลี่ยนรหัสผ่านไม่ได้'),
          findsOneWidget,
        );
        expect(f.gateway.calls, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final transition in [
    'replace',
    'session',
    'same-uid',
    'tab',
    'route',
    'lifecycle',
    'dispose',
  ]) {
    testWidgets('BB late completion cannot notify after $transition', (
      t,
    ) async {
      final f = Fixture();
      final hold = Completer<void>();
      f.gateway.pending = hold.future;
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      entry(t)();
      await t.pumpAndSettle();
      await fill(t);
      await t.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
      await retire(t, f, transition);
      hold.complete();
      await t.pumpAndSettle();
      expect(f.gateway.calls, 1);
      expect(find.text('เปลี่ยนรหัสผ่านแล้ว'), findsNothing);
      expect(t.takeException(), isNull);
    });
  }
}

Future<void> fill(WidgetTester t) async {
  await t.enterText(find.byType(TextField).first, 'synthetic-old-123');
  await t.enterText(find.byType(TextField).last, 'synthetic-new-456');
}

VoidCallback entry(WidgetTester t) => t
    .widget<MenuActionBinding>(
      find.byWidgetPredicate(
        (w) => w is MenuActionBinding && w.id == 'settings/change-password',
      ),
    )
    .onInvoke!;
Future<void> retire(WidgetTester t, Fixture f, String transition) async {
  switch (transition) {
    case 'replace':
      f.account = Fixture().account;
      await t.pumpWidget(f.app());
    case 'remove':
      f.account = null;
      await t.pumpWidget(f.app());
    case 'same-uid':
      f.gateway.currentSession = const AccountSession(
        uid: 'synthetic-user',
        email: 'new-session@example.test',
        isAnonymous: false,
        emailVerified: true,
      );
      await t.pumpWidget(f.app());
    case 'session':
      f.gateway.currentSession = null;
      await t.pumpWidget(f.app());
    case 'tab':
      await t.pumpWidget(f.app(visible: false));
    case 'route':
      f.nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await t.pump();
    case 'lifecycle':
      t.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await t.pump();
    case 'dispose':
      await t.pumpWidget(const SizedBox());
  }
  await t.pump(const Duration(milliseconds: 400));
}

class Fixture {
  final gateway = Gateway();
  final nav = GlobalKey<NavigatorState>();
  late AccountUseCases? account = AccountUseCases(
    gateway: gateway,
    owners: Owners(),
    upgradeGuestOwner: UpgradeGuestOwner(Upgrades()),
    entryState: Entry(),
  );
  Widget app({bool visible = true}) => MaterialApp(
    navigatorKey: nav,
    home: TickerMode(
      enabled: visible,
      child: SettingScreen(account: account),
    ),
  );
}

class Gateway implements AccountGateway, AccountSessionObserver {
  final events = StreamController<AccountSession?>.broadcast(sync: true);
  @override
  Stream<AccountSession?> get sessionChanges => Stream<AccountSession?>.multi((
    sink,
  ) {
    sink.addSync(currentSession);
    final sub = events.stream.listen(sink.addSync, onError: sink.addErrorSync);
    sink.onCancel = sub.cancel;
  });
  @override
  AccountSession? currentSession = const AccountSession(
    uid: 'synthetic-user',
    email: 'synthetic@example.test',
    isAnonymous: false,
    emailVerified: true,
  );
  int calls = 0;
  Object? failure;
  Future<void>? pending;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
    bool Function()? isCurrent,
  }) async {
    calls++;
    if (pending != null) await pending;
    if (failure != null) throw failure!;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Owners implements LocalOwnerRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Upgrades implements OwnerUpgradeRepository {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class Entry implements AppEntryStateStore {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}
