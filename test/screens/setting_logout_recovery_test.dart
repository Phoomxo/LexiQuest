import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drift/native.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';

void main() {
  testWidgets('BC completed failed attempt retires its old entry callback', (
    t,
  ) async {
    final f = LogoutFixture();
    f.gateway.failure = StateError('synthetic failure');
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    final old = logout(t);
    old();
    await t.pumpAndSettle();
    expect(f.gateway.calls, 1);
    old();
    await t.pumpAndSettle();
    expect(f.gateway.calls, 1);
    f.gateway.failure = null;
    logout(t)();
    await t.pumpAndSettle();
    expect(f.gateway.calls, 2);
  });
  for (final remove in [false, true]) {
    testWidgets(
      'BC inherited account replacement/removal retires logout remove=$remove',
      (t) async {
        final db = AppDatabase(NativeDatabase.memory());
        final f = LogoutFixture();
        final replacement = LogoutFixture();
        Widget app(AccountUseCases? account) => MaterialApp(
          navigatorKey: f.nav,
          routes: {'/login': (_) => const Text('login-destination')},
          home: AppDependenciesScope(
            dependencies: dependencies(db, account),
            child: const SettingScreen(),
          ),
        );
        await t.pumpWidget(app(f.account));
        await t.pumpAndSettle();
        final old = logout(t);
        await t.pumpWidget(app(remove ? null : replacement.account));
        await t.pumpAndSettle();
        old();
        await t.pumpAndSettle();
        expect(f.gateway.calls, 0);
        expect(replacement.gateway.calls, 0);
        if (!remove) {
          logout(t)();
          await t.pumpAndSettle();
          expect(replacement.gateway.calls, 1);
        }
        await t.pumpWidget(const SizedBox());
        await t.pumpAndSettle();
        await db.close();
      },
    );
  }
  for (final transition in ['tab', 'route', 'lifecycle']) {
    testWidgets(
      'BC return from $transition keeps old entry inert and current logout usable',
      (t) async {
        final f = LogoutFixture();
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        final old = logout(t);
        await retire(t, f, transition);
        if (transition == 'route') f.nav.currentState!.pop();
        if (transition == 'lifecycle') {
          t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        }
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        old();
        await t.pumpAndSettle();
        expect(f.gateway.calls, 0);
        logout(t)();
        await t.pumpAndSettle();
        expect(f.gateway.calls, 1);
        expect(find.text('login-destination'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'BC provider null event still completes explicit logout navigation',
    (t) async {
      final f = LogoutFixture();
      f.gateway.emitOnSuccess = true;
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      logout(t)();
      await t.pumpAndSettle();
      expect(find.text('login-destination'), findsOneWidget);
      expect(f.upgrades.rollbacks, 0);
      expect(t.takeException(), isNull);
    },
  );
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  for (final transition in [
    'replace',
    'remove',
    'session',
    'event',
    'tab',
    'route',
    'lifecycle',
    'dispose',
  ]) {
    testWidgets('BC retained logout is inert after $transition', (t) async {
      final f = LogoutFixture();
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      final old = logout(t);
      await retire(t, f, transition);
      old();
      await t.pumpAndSettle();
      expect(f.entry.clears, 0);
      expect(f.gateway.calls, 0);
      expect(f.replacement?.gateway.calls ?? 0, 0);
      expect(t.takeException(), isNull);
    });
    testWidgets(
      'BC late logout acknowledgement cannot navigate after $transition',
      (t) async {
        final f = LogoutFixture();
        final hold = Completer<void>();
        f.gateway.hold = hold.future;
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        logout(t)();
        await t.pump();
        expect(f.gateway.calls, 1);
        await retire(t, f, transition);
        hold.complete();
        await t.pumpAndSettle();
        expect(find.text('login-destination'), findsNothing);
        expect(f.gateway.calls, 1);
        expect(t.takeException(), isNull);
      },
    );
  }
  for (final failure in ['sync', 'async', 'recent-login']) {
    testWidgets(
      'BC $failure logout failure is contained and explicit retry works',
      (t) async {
        final f = LogoutFixture();
        f.gateway.failure = failure == 'recent-login'
            ? const AccountException(AccountFailureCode.requiresRecentLogin)
            : StateError('synthetic provider failure');
        f.gateway.synchronous = failure == 'sync';
        await t.pumpWidget(f.app());
        await t.pumpAndSettle();
        logout(t)();
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(SnackBar), findsOneWidget);
        expect(f.gateway.calls, 1);
        expect(f.owners.active.id, 'account-owner');
        expect(f.entry.mode, AppEntryMode.guest);
        f.gateway.failure = null;
        logout(t)();
        await t.pumpAndSettle();
        expect(f.gateway.calls, 2);
        expect(find.text('login-destination'), findsOneWidget);
      },
    );
  }
  testWidgets(
    'BC ordinary rebuild preserves entry and duplicate submission is single flight',
    (t) async {
      final f = LogoutFixture();
      final hold = Completer<void>();
      f.gateway.hold = hold.future;
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      final old = logout(t);
      await t.pumpWidget(f.app());
      await t.pumpAndSettle();
      old();
      old();
      await t.pump();
      hold.complete();
      await t.pumpAndSettle();
      expect(f.gateway.calls, 1);
      expect(f.upgrades.creates, 1);
      expect(find.text('login-destination'), findsOneWidget);
    },
  );
  testWidgets(
    'BC immediate pop retires retained native and semantics callbacks',
    (t) async {
      final f = LogoutFixture();
      await t.pumpWidget(
        MaterialApp(
          navigatorKey: f.nav,
          home: const Text('home'),
          routes: {'/login': (_) => const Text('login-destination')},
        ),
      );
      f.nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => SettingScreen(account: f.account),
        ),
      );
      await t.pumpAndSettle();
      final old = logout(t);
      final semantics = t
          .widget<Semantics>(
            find
                .descendant(of: binding(), matching: find.byType(Semantics))
                .first,
          )
          .properties
          .onTap!;
      f.nav.currentState!.pop();
      old();
      semantics();
      await t.pumpAndSettle();
      expect(f.gateway.calls, 0);
      expect(f.entry.clears, 0);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets('BC retired pending entry read does not clear or sign out', (
    t,
  ) async {
    final f = LogoutFixture();
    final hold = Completer<void>();
    f.entry.hold = hold.future;
    await t.pumpWidget(f.app());
    await t.pumpAndSettle();
    logout(t)();
    await t.pump();
    await retire(t, f, 'tab');
    hold.complete();
    await t.pumpAndSettle();
    expect(f.entry.clears, 0);
    expect(f.upgrades.creates, 0);
    expect(f.gateway.calls, 0);
    expect(t.takeException(), isNull);
  });
}

AppDependencies dependencies(AppDatabase db, AccountUseCases? account) {
  final research = InertResearchDependencies(db);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: NoGuest(),
    quest: testQuestUseCases(),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    account: account,
  );
}

class NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('no automatic guest action');
}

Finder binding() => find.byWidgetPredicate(
  (w) => w is MenuActionBinding && w.id == 'settings/logout',
);
VoidCallback logout(WidgetTester t) => t
    .widget<ListTile>(
      find.descendant(of: binding(), matching: find.byType(ListTile)),
    )
    .onTap!;
Future<void> retire(WidgetTester t, LogoutFixture f, String transition) async {
  switch (transition) {
    case 'replace':
      f.replacement = LogoutFixture();
      f.account = f.replacement!.account;
      await t.pumpWidget(f.app());
    case 'remove':
      f.account = null;
      await t.pumpWidget(f.app());
    case 'session':
      f.gateway.currentSession = null;
      await t.pumpWidget(f.app());
    case 'event':
      f.gateway.events.add(f.gateway.currentSession);
      await t.pump();
    case 'tab':
      await t.pumpWidget(f.app(visible: false));
    case 'route':
      f.nav.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => const Text('cover')),
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

class LogoutFixture {
  final gateway = LogoutGateway();
  final owners = LogoutOwners();
  final entry = LogoutEntry();
  late final upgrades = LogoutUpgrades(owners);
  final nav = GlobalKey<NavigatorState>();
  LogoutFixture? replacement;
  late AccountUseCases? account = AccountUseCases(
    gateway: gateway,
    owners: owners,
    upgradeGuestOwner: UpgradeGuestOwner(upgrades),
    entryState: entry,
  );
  Widget app({bool visible = true}) => MaterialApp(
    navigatorKey: nav,
    routes: {'/login': (_) => const Scaffold(body: Text('login-destination'))},
    home: TickerMode(
      enabled: visible,
      child: SettingScreen(account: account),
    ),
  );
}

class LogoutGateway implements AccountGateway, AccountSessionObserver {
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
  Future<void>? hold;
  Object? failure;
  bool synchronous = false;
  bool commitBeforeError = false;
  bool emitOnSuccess = false;
  @override
  Future<void> signOut() {
    calls++;
    if (synchronous && failure != null) throw failure!;
    return () async {
      if (hold != null) await hold;
      if (commitBeforeError) currentSession = null;
      if (failure != null) throw failure!;
      currentSession = null;
      if (emitOnSuccess) events.add(null);
    }();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

LocalOwner accountOwner() => LocalOwner(
  id: 'account-owner',
  firebaseUid: 'synthetic-user',
  createdAtUtc: DateTime.utc(2026),
);

class LogoutOwners implements LocalOwnerRepository {
  LocalOwner active = accountOwner();
  Future<void>? hold;
  Object? failure;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    if (hold != null) await hold;
    if (failure != null) throw failure!;
    return active;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class LogoutUpgrades implements OwnerUpgradeRepository {
  LogoutUpgrades(this.owners);
  final LogoutOwners owners;
  int creates = 0, rollbacks = 0;
  Future<void>? hold;
  Object? failure;
  Object? rollbackFailure;
  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() async {
    creates++;
    if (hold != null) await hold;
    if (failure != null) throw failure!;
    owners.active = LocalOwner(
      id: 'new-guest',
      createdAtUtc: DateTime.utc(2026),
    );
    return const OwnerUpgradeResult(
      targetOwnerId: 'new-guest',
      mode: OwnerUpgradeMode.localGuestCreated,
      conflictCount: 0,
    );
  }

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) async {
    rollbacks++;
    if (rollbackFailure != null) throw rollbackFailure!;
    if (owners.active.id != guestOwnerId) {
      throw StateError('new owner must remain');
    }
    owners.active = accountOwner();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class LogoutEntry implements AppEntryStateStore {
  AppEntryMode mode = AppEntryMode.guest;
  int clears = 0, restores = 0;
  Future<void>? hold;
  Object? readFailure, clearFailure;
  bool clearBeforeError = false;
  @override
  Future<AppEntryMode> read() async {
    if (hold != null) await hold;
    if (readFailure != null) throw readFailure!;
    return mode;
  }

  @override
  Future<void> clear() async {
    clears++;
    if (clearBeforeError) mode = AppEntryMode.signedOut;
    if (clearFailure != null) throw clearFailure!;
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    restores++;
    mode = AppEntryMode.guest;
  }
}
