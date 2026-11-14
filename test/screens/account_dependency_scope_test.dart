import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/account_deletion_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _syncKey = ValueKey<String>('settings-sync-now');
const _deleteKey = ValueKey<String>('settings-delete-account');
const _withdrawKey = ValueKey<String>('settings-research-withdraw');

void main() {
  testWidgets(
    'settings replaces account and deletion dependencies without replacing State',
    (tester) async {
      final a = _AccountFixture('A');
      final b = _AccountFixture('B');
      await _pump(
        tester,
        _dependencies(account: a.account, deletion: _deletion(a)),
      );
      final state = tester.state(find.byType(SettingScreen));
      await _reveal(tester, find.byKey(_deleteKey));
      final oldDelete = tester.widget<ListTile>(find.byKey(_deleteKey)).onTap!;
      await _pump(tester, _dependencies(account: b.account));
      tester
          .state<ScrollableState>(find.byType(Scrollable).first)
          .position
          .jumpTo(0);
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(SettingScreen)), same(state));
      expect(find.textContaining('A@example.test'), findsNothing);
      expect(find.textContaining('B@example.test'), findsOneWidget);
      expect(find.byKey(_deleteKey), findsNothing);
      oldDelete();
      await tester.pumpAndSettle();
      expect(find.byType(AccountDeletionScreen), findsNothing);
    },
  );

  testWidgets(
    'missing settings account and sync cannot keep A actions enabled',
    (tester) async {
      final a = _AccountFixture('A');
      var syncCalls = 0;
      await _pump(
        tester,
        _dependencies(
          account: a.account,
          deletion: _deletion(a),
          sync: SyncTrigger(() async {
            syncCalls++;
            return const SyncRunResult(status: SyncRunStatus.completed);
          }),
        ),
      );
      await _pump(tester, _dependencies());
      expect(find.textContaining('A@example.test'), findsNothing);
      expect(find.text('เปลี่ยนรหัสผ่าน'), findsNothing);
      expect(find.text('ออกจากระบบ'), findsNothing);
      expect(find.byKey(_deleteKey), findsNothing);
      await _reveal(tester, find.byKey(_syncKey));
      expect(
        tester.widget<FilledButton>(find.byKey(_syncKey)).onPressed,
        isNull,
      );
      expect(syncCalls, 0);
    },
  );

  testWidgets(
    'password draft opened in A cannot write or retarget after replacement',
    (tester) async {
      final a = _AccountFixture('A');
      final b = _AccountFixture('B');
      await _pump(tester, _dependencies(account: a.account));
      await _reveal(tester, find.text('เปลี่ยนรหัสผ่าน'));
      await tester.tap(find.text('เปลี่ยนรหัสผ่าน'));
      await tester.pumpAndSettle();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      await tester.enterText(fields.first, 'current123');
      await tester.enterText(fields.last, 'newpassword123');
      await _pump(tester, _dependencies(account: b.account));
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();
      expect(a.gateway.passwordCalls, 0);
      expect(b.gateway.passwordCalls, 0);
    },
  );

  testWidgets('logout after scope replacement targets only current B', (
    tester,
  ) async {
    final a = _AccountFixture('A');
    final b = _AccountFixture('B');
    await _pump(tester, _dependencies(account: a.account));
    await _pump(tester, _dependencies(account: b.account));
    await _reveal(tester, find.text('ออกจากระบบ'));
    await tester.tap(find.text('ออกจากระบบ'));
    await tester.pumpAndSettle();
    expect(a.gateway.logoutCalls, 0);
    expect(b.gateway.logoutCalls, 1);
  });

  testWidgets(
    'manual sync after replacement invokes B and ignores stale A completion',
    (tester) async {
      final pending = Completer<SyncRunResult>();
      var callsA = 0;
      var callsB = 0;
      final a = SyncTrigger(() {
        callsA++;
        return pending.future;
      });
      final b = SyncTrigger(() async {
        callsB++;
        return const SyncRunResult(
          status: SyncRunStatus.completed,
          pushed: 222,
        );
      });
      try {
        await _pump(tester, _dependencies(sync: a));
        await _reveal(tester, find.byKey(_syncKey));
        await tester.tap(find.byKey(_syncKey));
        await tester.pump();
        await _pump(tester, _dependencies(sync: b), settle: false);
        expect(
          tester.widget<FilledButton>(find.byKey(_syncKey)).onPressed,
          isNotNull,
        );
        pending.complete(
          const SyncRunResult(status: SyncRunStatus.completed, pushed: 111),
        );
        await tester.pumpAndSettle();
        expect(find.textContaining('ส่ง 111'), findsNothing);
        await tester.tap(find.byKey(_syncKey));
        await tester.pumpAndSettle();
        expect(callsA, 1);
        expect(callsB, 1);
        expect(find.textContaining('ส่ง 222'), findsOneWidget);
      } finally {
        if (!pending.isCompleted) {
          pending.complete(
            const SyncRunResult(status: SyncRunStatus.completed),
          );
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
      }
    },
  );

  testWidgets(
    'profile account follows B and then missing dependency with State retained',
    (tester) async {
      final a = _AccountFixture('A');
      final b = _AccountFixture('B');
      await _pump(tester, _dependencies(account: a.account), profile: true);
      final state = tester.state(find.byType(ProfileSettingsScreen));
      expect(find.text('ผู้เรียน A'), findsOneWidget);
      await _pump(tester, _dependencies(account: b.account), profile: true);
      expect(tester.state(find.byType(ProfileSettingsScreen)), same(state));
      expect(find.text('ผู้เรียน A'), findsNothing);
      expect(find.text('ผู้เรียน B'), findsOneWidget);
      await _pump(tester, _dependencies(), profile: true);
      expect(find.text('ผู้เรียน B'), findsNothing);
      expect(find.text('ผู้เรียนในเครื่อง'), findsOneWidget);
      expect(find.text('แก้ไขชื่อที่แสดง'), findsNothing);
    },
  );

  testWidgets('name dialog opened in A rejects replacement before Save', (
    tester,
  ) async {
    final a = _AccountFixture('A');
    final b = _AccountFixture('B');
    await _pump(tester, _dependencies(account: a.account), profile: true);
    await tester.tap(find.text('แก้ไขชื่อที่แสดง'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'draft must stay local');
    await _pump(tester, _dependencies(account: b.account), profile: true);
    await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
    await tester.pumpAndSettle();
    expect(a.gateway.nameCalls, 0);
    expect(b.gateway.nameCalls, 0);
  });

  for (final confirm in [false, true]) {
    for (final reuseConsent in [false, true]) {
      testWidgets(
        'consent dialog ${confirm ? 'Confirm' : 'Cancel'} rejects replacement '
        '${reuseConsent ? 'scope with the same service' : 'authority A with B'}',
        (tester) async {
          final a = _ConsentFixture('A', accepted: true);
          final b = _ConsentFixture('B', accepted: false);
          try {
            await _pump(
              tester,
              _dependencies(consent: a.consent),
              settle: false,
            );
            await _waitForConsent(tester, accepted: true);
            final state = tester.state(find.byType(SettingScreen));
            await _reveal(tester, find.byKey(_withdrawKey));
            await tester.tap(find.byKey(_withdrawKey));
            await tester.pumpAndSettle();
            expect(find.text('ยืนยันการถอนความยินยอม'), findsOneWidget);

            await _pump(
              tester,
              _dependencies(consent: reuseConsent ? a.consent : b.consent),
              settle: false,
            );
            await _waitForConsent(tester, accepted: reuseConsent);
            expect(tester.state(find.byType(SettingScreen)), same(state));
            final readsA = a.repository.loadCalls;
            final readsB = b.repository.loadCalls;
            final beforeA = a.repository.status;
            final beforeB = b.repository.status;

            await tester.tap(
              confirm
                  ? find.widgetWithText(FilledButton, 'ถอนความยินยอม')
                  : find.widgetWithText(TextButton, 'ยกเลิก'),
            );
            await tester.pumpAndSettle();
            expect(a.repository.decideCalls, 0);
            expect(b.repository.decideCalls, 0);
            expect(a.repository.loadCalls, readsA);
            expect(b.repository.loadCalls, readsB);
            expect(a.repository.status, same(beforeA));
            expect(b.repository.status, same(beforeB));
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              find.textContaining('ไม่ได้เข้าร่วม'),
              reuseConsent ? findsNothing : findsOneWidget,
            );
            expect(
              find.byKey(_withdrawKey),
              reuseConsent ? findsOneWidget : findsNothing,
            );
          } finally {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          }
        },
      );
    }
  }
}

Future<void> _waitForConsent(
  WidgetTester tester, {
  required bool accepted,
}) async {
  await tester.pumpAndSettle();
  expect(
    accepted ? find.byKey(_withdrawKey) : find.textContaining('ไม่ได้เข้าร่วม'),
    findsOneWidget,
  );
}

Future<void> _pump(
  WidgetTester tester,
  AppDependencies dependencies, {
  bool profile = false,
  bool settle = true,
}) async {
  await tester.pumpWidget(
    AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        routes: {
          '/login': (_) => const Scaffold(body: Text('synthetic login')),
        },
        home: profile
            ? const ProfileSettingsScreen(loader: _loadProgress)
            : const SettingScreen(),
      ),
    ),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.scrollUntilVisible(
    finder,
    250,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.pumpAndSettle();
}

AppDependencies _dependencies({
  AccountUseCases? account,
  AccountDeletionUseCases? deletion,
  SyncTrigger? sync,
  ResearchConsentUseCases? consent,
}) => AppDependencies(
  runtimeStatus: const AppRuntimeStatus(
    localData: RuntimeAvailability.ready,
    firebase: RuntimeAvailability.unavailable,
    supabase: RuntimeAvailability.unavailable,
    backends: RuntimeAvailability.unavailable,
  ),
  config: null,
  guestSessionService: _UnusedGuest(),
  account: account,
  accountDeletion: deletion,
  syncTrigger: sync,
  researchConsent: consent,
);

final class _AccountFixture {
  _AccountFixture(String id) {
    gateway = _Gateway(id);
    owners = _Owners(id);
    account = AccountUseCases(
      gateway: gateway,
      owners: owners,
      upgradeGuestOwner: UpgradeGuestOwner(_Upgrades()),
    );
  }
  late final _Gateway gateway;
  late final _Owners owners;
  late final AccountUseCases account;
}

final class _Gateway extends Fake implements AccountGateway {
  _Gateway(String id)
    : currentSession = AccountSession(
        uid: 'uid-$id',
        email: '$id@example.test',
        displayName: 'ผู้เรียน $id',
        isAnonymous: false,
        emailVerified: true,
      );
  @override
  AccountSession? currentSession;
  var passwordCalls = 0;
  var nameCalls = 0;
  var logoutCalls = 0;
  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    passwordCalls++;
  }

  @override
  Future<AccountSession> updateDisplayName(String displayName) async {
    nameCalls++;
    return currentSession = AccountSession(
      uid: currentSession!.uid,
      email: currentSession!.email,
      displayName: displayName,
      isAnonymous: false,
      emailVerified: true,
    );
  }

  @override
  Future<void> signOut() async {
    logoutCalls++;
    currentSession = null;
  }
}

final class _Owners extends Fake implements LocalOwnerRepository {
  _Owners(this.id);
  final String id;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'owner-$id',
    firebaseUid: 'uid-$id',
    createdAtUtc: DateTime.utc(2026, 11, 14),
  );
}

final class _Upgrades extends Fake implements OwnerUpgradeRepository {
  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() async =>
      const OwnerUpgradeResult(
        targetOwnerId: 'synthetic-new-guest',
        mode: OwnerUpgradeMode.localGuestCreated,
        conflictCount: 0,
      );
}

AccountDeletionUseCases _deletion(_AccountFixture account) {
  final ports = _UnusedDeletionPorts();
  return AccountDeletionUseCases(
    owners: account.owners,
    currentSession: () => account.gateway.currentSession,
    exporter: ports,
    reauthenticator: ports,
    cloud: ports,
    local: ports,
    journal: ports,
    nowUtc: () => DateTime.utc(2026, 11, 14),
  );
}

final class _UnusedDeletionPorts extends Fake
    implements
        FullAccountExporter,
        AccountDeletionReauthenticator,
        PrivilegedAccountDeletionGateway,
        LocalAccountDeletionGateway,
        AccountDeletionJournal {}

final class _UnusedGuest extends Fake implements GuestSessionService {}

final class _ConsentFixture {
  _ConsentFixture(String id, {required bool accepted}) {
    repository = _CountingConsentRepository(
      ResearchConsentStatus(
        ownerId: 'owner-$id',
        version: ResearchConsentUseCases.currentVersion,
        accepted: accepted,
      ),
    );
    consent = ResearchConsentUseCases(
      owners: _Owners(id),
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 11, 14),
    );
  }

  late final _CountingConsentRepository repository;
  late final ResearchConsentUseCases consent;
}

final class _CountingConsentRepository implements ResearchConsentRepository {
  _CountingConsentRepository(this.status);

  ResearchConsentStatus status;
  var loadCalls = 0;
  var decideCalls = 0;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    loadCalls++;
    expect(ownerId, status.ownerId);
    return status;
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    decideCalls++;
    status = ResearchConsentStatus(
      ownerId: ownerId,
      version: version,
      accepted: accepted,
      decidedAtUtc: decidedAtUtc,
      withdrawnAtUtc: accepted ? null : decidedAtUtc,
    );
    return true;
  }
}

Future<ProgressSnapshot> _loadProgress() async => const ProgressSnapshot(
  sampleSize: 0,
  correctCount: 0,
  wrongCount: 0,
  accuracy: null,
  totalXp: 0,
  completedSessions: 0,
  streakDays: 0,
  dueReviewCount: 0,
  masteredWordCount: 0,
  achievementCount: 0,
  gameLevel: 1,
  skills: [],
  weaknesses: [],
  recommendations: [],
);
