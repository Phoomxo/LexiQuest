import 'dart:async';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/account/application/account_use_cases.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/consent/application/research_consent_use_cases.dart';
import 'package:vocab_learning_app/features/consent/domain/research_consent.dart';
import 'package:vocab_learning_app/features/device_model/application/device_model_use_cases.dart';
import 'package:vocab_learning_app/features/device_model/application/model_download_manager.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_lifecycle.dart';
import 'package:vocab_learning_app/features/device_model/domain/model_manifest.dart';
import 'package:vocab_learning_app/features/identity/application/upgrade_guest_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/sync/application/sync_engine.dart';
import 'package:vocab_learning_app/features/sync/application/sync_status.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/field_feature.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/screens/device_permission_center_screen.dart';
import 'package:vocab_learning_app/screens/appearance_settings_screen.dart';
import 'package:vocab_learning_app/screens/gemini_settings_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

const _syncButtonKey = ValueKey<String>('settings-sync-now');
const _syncStatusKey = ValueKey<String>('settings-sync-status');
const _syncQueueStatusKey = ValueKey<String>('settings-sync-queue-status');
const _withdrawKey = ValueKey<String>('settings-research-withdraw');
const _modelActionKey = ValueKey<String>('settings-device-model-action');

void main() {
  testWidgets('settings exposes a plain-Thai appearance destination', (
    tester,
  ) async {
    await _pumpSettings(tester);

    expect(find.text('การแสดงผล'), findsOneWidget);
    expect(
      find.text('เลือกโหมดสว่าง มืด หรือใช้ตามการตั้งค่าของอุปกรณ์'),
      findsOneWidget,
    );
  });

  testWidgets('appearance destination opens the persisted preference screen', (
    tester,
  ) async {
    final appearance = await AppAppearanceController.load(
      _AppearancePreferences(),
    );
    addTearDown(appearance.dispose);
    await _pumpSettings(tester, appearance: appearance);

    await tester.tap(find.text('การแสดงผล'));
    await tester.pumpAndSettle();

    expect(find.byType(AppearanceSettingsScreen), findsOneWidget);
    expect(find.text('ใช้ตามอุปกรณ์'), findsOneWidget);
  });

  testWidgets('account card distinguishes local, anonymous, and email users', (
    tester,
  ) async {
    await _pumpSettings(tester);
    expect(find.text('ไม่ใช้บัญชี'), findsOneWidget);
    expect(find.textContaining('ข้อมูลการเรียนอยู่ในเครื่อง'), findsOneWidget);

    await _pumpSettings(
      tester,
      account: _account(
        const AccountSession(
          uid: 'anonymous-user',
          email: null,
          isAnonymous: true,
          emailVerified: false,
        ),
      ),
    );
    expect(find.text('ไม่ใช้บัญชี'), findsOneWidget);
    expect(find.textContaining('ไม่ต้องยืนยันอีเมล'), findsOneWidget);
    expect(find.text('รอยืนยันอีเมล'), findsNothing);
    expect(find.text('เปลี่ยนรหัสผ่าน'), findsNothing);
    expect(find.text('ออกจากระบบ'), findsNothing);

    await _pumpSettings(
      tester,
      account: _account(
        const AccountSession(
          uid: 'registered-user',
          email: 'learner@example.test',
          isAnonymous: false,
          emailVerified: false,
        ),
      ),
    );
    expect(find.text('รอยืนยันอีเมล'), findsOneWidget);

    await _pumpSettings(
      tester,
      account: _account(
        const AccountSession(
          uid: 'verified-user',
          email: 'verified@example.test',
          isAnonymous: false,
          emailVerified: true,
        ),
      ),
    );
    expect(find.text('ยืนยันอีเมลแล้ว'), findsOneWidget);
  });

  testWidgets(
    'change password validates inside the dialog before provider use',
    (tester) async {
      final gateway = _AccountGateway(
        const AccountSession(
          uid: 'verified-user',
          email: 'verified@example.test',
          isAnonymous: false,
          emailVerified: true,
        ),
      );
      final account = AccountUseCases(
        gateway: gateway,
        owners: const _Owners(),
        upgradeGuestOwner: UpgradeGuestOwner(const _Upgrades()),
      );
      await _pumpSettings(tester, account: account);
      await tester.scrollUntilVisible(
        find.text('เปลี่ยนรหัสผ่าน'),
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.tap(find.text('เปลี่ยนรหัสผ่าน'));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pump();
      final fields = find.descendant(
        of: find.byType(AlertDialog),
        matching: find.byType(TextField),
      );
      expect(
        tester.widget<TextField>(fields.first).decoration?.errorText,
        'กรอกรหัสผ่านปัจจุบัน',
      );
      expect(
        tester.widget<TextField>(fields.last).decoration?.errorText,
        'กรอกรหัสผ่านใหม่',
      );
      expect(gateway.changePasswordCalls, 0);

      await tester.enterText(fields.first, 'current123');
      await tester.enterText(fields.last, 'short');
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pump();
      expect(
        tester.widget<TextField>(fields.last).decoration?.errorText,
        'รหัสผ่านใหม่ต้องมีอย่างน้อย 8 ตัวอักษร',
      );
      expect(gateway.changePasswordCalls, 0);

      await tester.enterText(fields.last, 'newpassword123');
      await tester.tap(find.widgetWithText(FilledButton, 'บันทึก'));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
      expect(gateway.changePasswordCalls, 1);
      expect(gateway.lastCurrentPassword, 'current123');
      expect(gateway.lastNewPassword, 'newpassword123');
    },
  );

  testWidgets('nonparticipant and withdrawn research states stay read-only', (
    tester,
  ) async {
    final undecided = _ConsentRepository(
      const ResearchConsentStatus(
        ownerId: 'synthetic-owner',
        version: 1,
        accepted: false,
      ),
    );
    await _pumpSettings(tester, consent: _consent(undecided));
    expect(find.textContaining('ไม่ได้เข้าร่วม'), findsOneWidget);
    expect(find.byKey(_withdrawKey), findsNothing);
    expect(find.widgetWithText(TextButton, 'ยินยอม'), findsNothing);
    expect(undecided.decideCalls, 0);

    await _pumpSettings(tester, consent: _consent(undecided));
    expect(undecided.decideCalls, 0);

    final withdrawn = _ConsentRepository(
      ResearchConsentStatus(
        ownerId: 'synthetic-owner',
        version: 1,
        accepted: false,
        decidedAtUtc: DateTime.utc(2026, 10, 20),
        withdrawnAtUtc: DateTime.utc(2026, 10, 21),
      ),
    );
    await _pumpSettings(tester, consent: _consent(withdrawn));
    expect(find.textContaining('ไม่ได้เข้าร่วม'), findsOneWidget);
    expect(find.textContaining('ถอนความยินยอมแล้ว'), findsNothing);
    expect(find.byKey(_withdrawKey), findsNothing);
    expect(withdrawn.decideCalls, 0);
  });

  testWidgets('accepted research withdrawal requires confirmation', (
    tester,
  ) async {
    final repository = _ConsentRepository(
      ResearchConsentStatus(
        ownerId: 'synthetic-owner',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    final decision = Completer<bool>();
    repository.decision = decision;
    await _pumpSettings(tester, consent: _consent(repository));

    await tester.tap(find.byKey(_withdrawKey));
    await tester.pumpAndSettle();
    expect(find.text('ยืนยันการถอนความยินยอม'), findsOneWidget);
    await tester.tap(find.widgetWithText(TextButton, 'ยกเลิก'));
    await tester.pumpAndSettle();
    expect(repository.decideCalls, 0);

    await tester.tap(find.byKey(_withdrawKey));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'ถอนความยินยอม'));
    await tester.pump();
    await tester.fling(find.byType(ListView), const Offset(0, -4000), 10000);
    await tester.pump();

    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .semanticsLabel,
      'กำลังดำเนินการ โปรดรอสักครู่',
    );

    decision.complete(true);
    await tester.pumpAndSettle();
    await tester.fling(find.byType(ListView), const Offset(0, 4000), 10000);
    await tester.pumpAndSettle();

    expect(repository.decideCalls, 1);
    expect(repository.lastAccepted, isFalse);
    expect(find.byKey(_withdrawKey), findsNothing);
    expect(find.textContaining('ไม่ได้เข้าร่วม'), findsOneWidget);
    expect(find.textContaining('ถอนความยินยอมแล้ว'), findsNothing);
  });

  testWidgets('A confirmation cannot create consent for nonparticipant B', (
    tester,
  ) async {
    await _expectOwnerRetargetRejected(tester, bAccepted: false);
  });

  testWidgets('A confirmation cannot withdraw accepted B', (tester) async {
    await _expectOwnerRetargetRejected(tester, bAccepted: true);
  });

  testWidgets('delayed A consent load cannot render authority after B switch', (
    tester,
  ) async {
    final owners = _MutableOwners(_owner('owner-a'));
    final repository = _DelayedConsentRepository();
    final consent = ResearchConsentUseCases(
      owners: owners,
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );

    await _pumpSettings(tester, consent: consent, settle: false);
    await repository.started.future;
    owners.current = _owner('owner-b');
    repository.result.complete(
      ResearchConsentStatus(
        ownerId: 'owner-a',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(_withdrawKey), findsNothing);
    expect(find.textContaining('ตรวจสอบสถานะไม่ได้'), findsOneWidget);
  });

  testWidgets('research load failure stays unavailable and reveals no error', (
    tester,
  ) async {
    final repository = _ConsentRepository(
      const ResearchConsentStatus(
        ownerId: 'synthetic-owner',
        version: 1,
        accepted: false,
      ),
    )..loadError = StateError('private-sentinel');

    await _pumpSettings(tester, consent: _consent(repository));

    expect(find.textContaining('ตรวจสอบสถานะไม่ได้'), findsOneWidget);
    expect(
      tester
          .widgetList<Semantics>(
            find.ancestor(
              of: find.textContaining('ตรวจสอบสถานะไม่ได้'),
              matching: find.byType(Semantics),
            ),
          )
          .any((semantics) => semantics.properties.liveRegion == true),
      isTrue,
    );
    expect(find.textContaining('private-sentinel'), findsNothing);
    expect(find.byKey(_withdrawKey), findsNothing);
    expect(find.widgetWithText(TextButton, 'ยินยอม'), findsNothing);
    expect(repository.decideCalls, 0);
  });

  testWidgets('manual Cloud request is single-flight and reports run counts', (
    tester,
  ) async {
    final result = Completer<SyncRunResult>();
    var runs = 0;
    final trigger = SyncTrigger(() {
      runs++;
      return result.future;
    });
    await _pumpSettings(tester, syncTrigger: trigger);

    await tester.tap(find.byKey(_syncButtonKey));
    await tester.tap(find.byKey(_syncButtonKey));
    await tester.pump();
    expect(runs, 1);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byKey(_syncButtonKey),
              matching: find.byType(CircularProgressIndicator),
            ),
          )
          .semanticsLabel,
      'กำลังตรวจสอบการซิงก์',
    );

    result.complete(
      const SyncRunResult(
        status: SyncRunStatus.completed,
        pushed: 2,
        pulled: 3,
        conflicts: 1,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('ส่ง 2'), findsOneWidget);
    expect(find.textContaining('รับ 3'), findsOneWidget);
    expect(find.textContaining('ความขัดแย้ง 1'), findsOneWidget);
    expect(find.textContaining('ซิงก์ทั้งหมดแล้ว'), findsNothing);
    expect(find.textContaining('คิวว่าง'), findsNothing);
    expect(find.textContaining('ออนไลน์'), findsNothing);
    expect(_liveRegion(tester, _syncStatusKey), isTrue);
  });

  testWidgets('manual Cloud clears the previous result while a new run waits', (
    tester,
  ) async {
    final second = Completer<SyncRunResult>();
    var runs = 0;
    final trigger = SyncTrigger(() {
      runs++;
      if (runs == 1) {
        return Future.value(
          const SyncRunResult(status: SyncRunStatus.completed, pushed: 1),
        );
      }
      return second.future;
    });
    await _pumpSettings(tester, syncTrigger: trigger);

    await tester.tap(find.byKey(_syncButtonKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('ส่ง 1'), findsOneWidget);

    await tester.tap(find.byKey(_syncButtonKey));
    await tester.pump();
    expect(runs, 2);
    expect(find.byKey(_syncStatusKey), findsNothing);
    expect(find.textContaining('ส่ง 1'), findsNothing);

    second.complete(
      const SyncRunResult(status: SyncRunStatus.completed, pulled: 2),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('รับ 2'), findsOneWidget);
  });

  testWidgets('manual Cloud feedback is truthful for every non-success state', (
    tester,
  ) async {
    const cases = <(SyncRunResult, String)>[
      (
        SyncRunResult(
          status: SyncRunStatus.partialFailure,
          pushed: 1,
          failures: 2,
          retryRecommended: true,
        ),
        'สำเร็จบางส่วน',
      ),
      (
        SyncRunResult(status: SyncRunStatus.skippedCloudDisabled),
        'ปิดตามนโยบาย',
      ),
      (
        SyncRunResult(status: SyncRunStatus.skippedUnauthenticated),
        'ยังไม่ได้เชื่อมบัญชี',
      ),
      (SyncRunResult(status: SyncRunStatus.alreadyRunning), 'กำลังทำงานอยู่'),
    ];

    for (final (result, expected) in cases) {
      await _pumpSettings(tester, syncTrigger: SyncTrigger(() async => result));
      await tester.tap(find.byKey(_syncButtonKey));
      await tester.pumpAndSettle();
      expect(find.textContaining(expected), findsOneWidget);
      expect(find.textContaining('ซิงก์ทั้งหมดแล้ว'), findsNothing);
      expect(_statusText(tester), isNot(contains('คิวที่รอส่ง')));
      expect(_liveRegion(tester, _syncStatusKey), isTrue);
    }

    await _pumpSettings(
      tester,
      syncTrigger: SyncTrigger(() async {
        throw StateError('private-sync-sentinel');
      }),
    );
    await tester.tap(find.byKey(_syncButtonKey));
    await tester.pumpAndSettle();
    expect(find.textContaining('ไม่สำเร็จ'), findsOneWidget);
    expect(find.textContaining('ข้อมูลในเครื่องยังไม่ถูกลบ'), findsOneWidget);
    expect(find.textContaining('private-sync-sentinel'), findsNothing);
    expect(_statusText(tester), isNot(contains('คิวที่รอส่ง')));
  });

  testWidgets('local sync status shows truthful privacy-safe aggregates', (
    tester,
  ) async {
    final source = _SyncStatusSource();
    addTearDown(source.close);
    await _pumpSettings(tester, syncStatus: source, settle: false);

    expect(find.text('กำลังตรวจสอบสถานะคิวในเครื่อง…'), findsOneWidget);
    source.add(
      const SyncStatusSnapshot(
        ownerId: 'private-owner-a',
        pending: 1,
        retryWaiting: 2,
        inFlight: 3,
        blockedAuth: 4,
        permanentFailure: 5,
        handledConflicts: 6,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('รอส่ง 1'), findsOneWidget);
    expect(find.textContaining('รอลองใหม่ 2'), findsOneWidget);
    expect(find.textContaining('กำลังประมวลผลหรือรอกู้คืน 3'), findsOneWidget);
    expect(find.textContaining('รอเชื่อมบัญชี 4'), findsOneWidget);
    expect(find.textContaining('ต้องตรวจสอบ 5'), findsOneWidget);
    expect(
      find.textContaining('ประวัติความขัดแย้งที่จัดการแล้ว 6'),
      findsOneWidget,
    );
    expect(find.textContaining('private-owner-a'), findsNothing);
    expect(find.textContaining('failureCode'), findsNothing);
    expect(_semanticsLabel(tester, _syncQueueStatusKey), contains('รอส่ง 1'));
  });

  testWidgets('local sync status fails closed without revealing errors', (
    tester,
  ) async {
    final source = _SyncStatusSource();
    addTearDown(source.close);
    await _pumpSettings(tester, syncStatus: source, settle: false);

    source.addError(StateError('private-status-sentinel'));
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบสถานะคิวในเครื่องไม่ได้'), findsOneWidget);
    expect(find.textContaining('private-status-sentinel'), findsNothing);

    source.add(null);
    await tester.pumpAndSettle();
    expect(find.text('ตรวจสอบสถานะคิวในเครื่องไม่ได้'), findsOneWidget);
  });

  testWidgets('local sync status becomes unavailable when its source closes', (
    tester,
  ) async {
    final source = _SyncStatusSource();
    await _pumpSettings(tester, syncStatus: source, settle: false);
    source.add(const SyncStatusSnapshot(ownerId: 'owner-a', pending: 7));
    await tester.pumpAndSettle();
    expect(find.textContaining('รอส่ง 7'), findsOneWidget);

    await source.close();
    await tester.pumpAndSettle();

    expect(find.text('ตรวจสอบสถานะคิวในเครื่องไม่ได้'), findsOneWidget);
    expect(find.textContaining('รอส่ง 7'), findsNothing);
  });

  testWidgets('replacing status source clears A and ignores delayed A events', (
    tester,
  ) async {
    const screenKey = ValueKey<String>('stable-settings');
    final sourceA = _SyncStatusSource();
    final sourceB = _SyncStatusSource();
    addTearDown(sourceA.close);
    addTearDown(sourceB.close);
    await _pumpSettings(
      tester,
      screenKey: screenKey,
      syncStatus: sourceA,
      settle: false,
    );
    sourceA.add(const SyncStatusSnapshot(ownerId: 'owner-a', pending: 7));
    await tester.pumpAndSettle();
    expect(find.textContaining('รอส่ง 7'), findsOneWidget);

    sourceA.add(const SyncStatusSnapshot(ownerId: 'owner-a', pending: 9));
    await _pumpSettings(
      tester,
      screenKey: screenKey,
      syncStatus: sourceB,
      settle: false,
    );
    expect(find.text('กำลังตรวจสอบสถานะคิวในเครื่อง…'), findsOneWidget);
    expect(find.textContaining('รอส่ง 7'), findsNothing);
    expect(find.textContaining('รอส่ง 9'), findsNothing);

    sourceB.add(const SyncStatusSnapshot(ownerId: 'owner-b', pending: 2));
    await tester.pumpAndSettle();
    expect(find.textContaining('รอส่ง 2'), findsOneWidget);
    expect(find.textContaining('owner-b'), findsNothing);
  });

  testWidgets('settings supports 360x800 at 200 percent text', (tester) async {
    tester.view
      ..physicalSize = const Size(360, 800)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _ConsentRepository(
      ResearchConsentStatus(
        ownerId: 'synthetic-owner',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime.utc(2026, 10, 20),
      ),
    );
    await _pumpSettings(
      tester,
      textScale: 2,
      account: _account(
        const AccountSession(
          uid: 'verified-user',
          email: 'verified@example.test',
          isAnonymous: false,
          emailVerified: true,
        ),
      ),
      consent: _consent(repository),
      syncTrigger: SyncTrigger(
        () async => const SyncRunResult(status: SyncRunStatus.completed),
      ),
    );

    await tester.scrollUntilVisible(find.byKey(_withdrawKey), 200);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_withdrawKey)).height,
      greaterThanOrEqualTo(48),
    );
    await tester.scrollUntilVisible(find.byKey(_syncButtonKey), 200);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_syncButtonKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('sync status supports dark 800x360 at 200 percent text', (
    tester,
  ) async {
    tester.view
      ..physicalSize = const Size(800, 360)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final source = _SyncStatusSource();
    addTearDown(source.close);
    await _pumpSettings(
      tester,
      syncStatus: source,
      textScale: 2,
      themeMode: ThemeMode.dark,
      settle: false,
    );
    source.add(
      const SyncStatusSnapshot(
        ownerId: 'owner-a',
        pending: 999999999,
        retryWaiting: 999999999,
        inFlight: 999999999,
        blockedAuth: 999999999,
        permanentFailure: 999999999,
        handledConflicts: 999999999,
      ),
    );
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.byKey(_syncQueueStatusKey), 200);
    await tester.pump();
    expect(_semanticsLabel(tester, _syncQueueStatusKey), contains('รอส่ง'));
    await tester.scrollUntilVisible(find.byKey(_syncButtonKey), 200);
    await tester.pump();
    expect(
      tester.getSize(find.byKey(_syncButtonKey)).height,
      greaterThanOrEqualTo(48),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('settings discloses enabled, limited, and hidden features', (
    tester,
  ) async {
    const limited = BuildFieldFeatureRegistry({
      FieldFeature.export: FieldFeatureState.enabled,
      FieldFeature.aiTutor: FieldFeatureState.limited,
      FieldFeature.speechPractice: FieldFeatureState.limited,
      FieldFeature.objectScanner: FieldFeatureState.hidden,
    });
    await _pumpSettings(tester, fieldFeatures: limited);

    expect(
      find.byKey(const ValueKey('settings-feature-export')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('settings-feature-ai')), findsOneWidget);
    expect(find.textContaining('ต้องเชื่อมต่อผู้ช่วย AI'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-feature-voice')),
      200,
    );
    expect(
      find.byKey(const ValueKey('settings-feature-voice')),
      findsOneWidget,
    );
    expect(find.text('ฝึกพูดตามเสียง'), findsOneWidget);
    expect(find.textContaining('ต้องอนุญาตไมโครโฟน'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('settings-feature-scanner')),
      findsNothing,
    );
  });

  testWidgets('data and AI rows open their existing destinations', (
    tester,
  ) async {
    await _pumpSettings(
      tester,
      fieldFeatures: const BuildFieldFeatureRegistry.allEnabled(),
    );

    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-feature-export')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('settings-feature-export')));
    await tester.pumpAndSettle();
    expect(find.byType(ExportCenterScreen), findsOneWidget);

    Navigator.of(tester.element(find.byType(ExportCenterScreen))).pop();
    await tester.pumpAndSettle();
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey('settings-feature-ai')),
      250,
    );
    await tester.tap(find.byKey(const ValueKey('settings-feature-ai')));
    await tester.pumpAndSettle();
    expect(find.byType(GeminiSettingsScreen), findsOneWidget);
  });

  testWidgets('opening settings starts no model download or media screen', (
    tester,
  ) async {
    final models = _DeviceModelHarness();
    addTearDown(models.dispose);
    await _pumpSettings(tester, deviceModels: models.useCases);

    expect(models.source.openCalls, 0);
    expect(find.byType(ExportCenterScreen), findsNothing);
    expect(find.byType(GeminiSettingsScreen), findsNothing);
  });

  testWidgets('settings opens the read-only device permission center', (
    tester,
  ) async {
    await _pumpSettings(tester);
    final center = find.byKey(
      const ValueKey<String>('settings-permission-center'),
    );
    await tester.scrollUntilVisible(center, 250);
    await tester.ensureVisible(center);
    await tester.drag(find.byType(ListView), const Offset(0, -120));
    await tester.pumpAndSettle();
    await tester.tap(center);
    await tester.pumpAndSettle();

    expect(find.byType(DevicePermissionCenterScreen), findsOneWidget);
    expect(find.text('สิทธิ์กล้องและไมโครโฟน'), findsWidgets);
  });

  testWidgets('device model reports absent, downloading, active and failed', (
    tester,
  ) async {
    final models = _DeviceModelHarness();
    addTearDown(models.dispose);
    await _pumpSettings(tester, deviceModels: models.useCases);

    await tester.scrollUntilVisible(find.byKey(_modelActionKey), 250);
    expect(
      find.textContaining('เวอร์ชัน ${models.manifest.version}'),
      findsOneWidget,
    );
    expect(
      find.textContaining('${models.manifest.expectedBytes} ไบต์'),
      findsOneWidget,
    );
    expect(find.text('ยังไม่ได้ดาวน์โหลด'), findsOneWidget);

    for (final (state, expected) in <(ModelDownloadState, String)>[
      (ModelDownloadState.downloading, 'กำลังดาวน์โหลด'),
      (ModelDownloadState.active, 'พร้อมใช้งานบนอุปกรณ์นี้'),
      (ModelDownloadState.failed, 'ดาวน์โหลดไม่สำเร็จ'),
    ]) {
      models.repository.record = models.record(state);
      await _pumpSettings(tester, deviceModels: models.useCases);
      await tester.scrollUntilVisible(find.textContaining(expected), 250);
      expect(find.textContaining(expected), findsOneWidget);
    }
  });

  testWidgets('explicit model download is single-flight and refreshes status', (
    tester,
  ) async {
    final models = _DeviceModelHarness();
    final result = Completer<ModelDownloadRecord>();
    var downloads = 0;
    addTearDown(models.dispose);
    await _pumpSettings(
      tester,
      deviceModels: models.useCases,
      deviceModelDownload: () {
        downloads++;
        return result.future;
      },
    );
    await tester.scrollUntilVisible(find.byKey(_modelActionKey), 250);
    await tester.ensureVisible(find.byKey(_modelActionKey));
    await tester.pump();

    await tester.tap(find.byKey(_modelActionKey));
    await tester.pump();
    expect(
      tester.widget<FilledButton>(find.byKey(_modelActionKey)).onPressed,
      isNull,
    );
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.descendant(
              of: find.byKey(_modelActionKey),
              matching: find.byType(CircularProgressIndicator),
            ),
          )
          .semanticsLabel,
      'กำลังดาวน์โหลดเนื้อหาสำหรับสแกน',
    );
    await tester.tap(find.byKey(_modelActionKey));
    expect(downloads, 1);
    models.repository.record = models.record(ModelDownloadState.active);
    result.complete(models.repository.record!);
    await tester.pumpAndSettle();

    expect(downloads, 1);
    expect(find.text('พร้อมใช้งานบนอุปกรณ์นี้'), findsOneWidget);
    expect(find.text('ดาวน์โหลดและเปิดใช้งานแล้ว'), findsOneWidget);
  });

  testWidgets('failed model download offers an explicit retry', (tester) async {
    final models = _DeviceModelHarness();
    addTearDown(models.dispose);
    await _pumpSettings(
      tester,
      deviceModels: models.useCases,
      deviceModelDownload: () async {
        models.repository.record = models.record(ModelDownloadState.failed);
        throw const ModelLifecycleException(ModelFailureCode.network);
      },
    );
    await tester.scrollUntilVisible(find.byKey(_modelActionKey), 250);
    await tester.ensureVisible(find.byKey(_modelActionKey));
    await tester.pump();

    await tester.tap(find.byKey(_modelActionKey));
    await tester.pumpAndSettle();

    expect(find.text('เชื่อมต่อเพื่อดาวน์โหลดไม่ได้'), findsOneWidget);
    expect(
      find.widgetWithText(FilledButton, 'ลองดาวน์โหลดอีกครั้ง'),
      findsOneWidget,
    );
  });

  testWidgets('late model status cannot replace a newer injected dependency', (
    tester,
  ) async {
    final oldStatus = Completer<ModelDownloadRecord?>();
    final oldModels = _DeviceModelHarness(statusOverride: oldStatus.future);
    final newModels = _DeviceModelHarness(
      initialState: ModelDownloadState.active,
    );
    addTearDown(oldModels.dispose);
    addTearDown(newModels.dispose);
    const key = ValueKey<String>('stable-settings-model');

    await _pumpSettings(
      tester,
      screenKey: key,
      deviceModels: oldModels.useCases,
      settle: false,
    );
    await _pumpSettings(
      tester,
      screenKey: key,
      deviceModels: newModels.useCases,
    );
    oldStatus.complete(oldModels.record(ModelDownloadState.failed));
    await tester.pumpAndSettle();

    await tester.scrollUntilVisible(find.text('พร้อมใช้งานบนอุปกรณ์นี้'), 250);
    expect(find.text('พร้อมใช้งานบนอุปกรณ์นี้'), findsOneWidget);
    expect(find.textContaining('ดาวน์โหลดไม่สำเร็จ'), findsNothing);
  });

  testWidgets(
    'new settings cards remain usable at compact accessibility sizes',
    (tester) async {
      for (final (size, mode) in <(Size, ThemeMode)>[
        (const Size(360, 800), ThemeMode.light),
        (const Size(800, 360), ThemeMode.dark),
      ]) {
        tester.view
          ..physicalSize = size
          ..devicePixelRatio = 1;
        final models = _DeviceModelHarness();
        addTearDown(models.dispose);
        await _pumpSettings(
          tester,
          deviceModels: models.useCases,
          textScale: 2,
          themeMode: mode,
        );
        await tester.scrollUntilVisible(find.byKey(_modelActionKey), 250);
        await tester.ensureVisible(find.byKey(_modelActionKey));
        await tester.pump();
        expect(
          tester.getSize(find.byKey(_modelActionKey)).height,
          greaterThanOrEqualTo(48),
          reason: '$size $mode',
        );
        expect(tester.takeException(), isNull, reason: '$size $mode');
      }
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
    },
  );
}

Future<void> _pumpSettings(
  WidgetTester tester, {
  AccountUseCases? account,
  ResearchConsentUseCases? consent,
  SyncTrigger? syncTrigger,
  SyncStatusSource? syncStatus,
  DeviceModelUseCases? deviceModels,
  AppAppearanceController? appearance,
  Future<ModelDownloadRecord> Function()? deviceModelDownload,
  FieldFeatureRegistry fieldFeatures =
      const BuildFieldFeatureRegistry.fieldDefaults(),
  Key? screenKey,
  double textScale = 1,
  ThemeMode themeMode = ThemeMode.light,
  bool settle = true,
}) async {
  final dependencies = AppDependencies(
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: const _GuestSessionService(),
    syncTrigger: syncTrigger,
    syncStatus: syncStatus,
    deviceModels: deviceModels,
    fieldFeatures: fieldFeatures,
  );
  final app = AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(
      theme: M3Theme.lightTheme,
      darkTheme: M3Theme.darkTheme,
      themeMode: themeMode,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(
          context,
        ).copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: SettingScreen(
        key: screenKey ?? UniqueKey(),
        account: account,
        researchConsent: consent,
        deviceModelDownload: deviceModelDownload,
      ),
    ),
  );
  await tester.pumpWidget(
    appearance == null
        ? app
        : AppAppearanceScope(controller: appearance, child: app),
  );
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump();
  }
}

final class _AppearancePreferences implements AppAppearancePreferences {
  AppAppearanceMode mode = AppAppearanceMode.system;

  @override
  Future<AppAppearanceMode> load() async => mode;

  @override
  Future<bool> save(AppAppearanceMode mode) async {
    this.mode = mode;
    return true;
  }
}

Future<void> _expectOwnerRetargetRejected(
  WidgetTester tester, {
  required bool bAccepted,
}) async {
  final owners = _MutableOwners(_owner('owner-a'));
  final repository = _OwnerConsentRepository({
    'owner-a': ResearchConsentStatus(
      ownerId: 'owner-a',
      version: 1,
      accepted: true,
      decidedAtUtc: DateTime.utc(2026, 10, 20),
    ),
    if (bAccepted)
      'owner-b': ResearchConsentStatus(
        ownerId: 'owner-b',
        version: 1,
        accepted: true,
        decidedAtUtc: DateTime.utc(2026, 10, 20),
      ),
  });
  final consent = ResearchConsentUseCases(
    owners: owners,
    repository: repository,
    nowUtc: () => DateTime.utc(2026, 10, 21, 12),
  );
  await _pumpSettings(tester, consent: consent);
  await tester.tap(find.byKey(_withdrawKey));
  await tester.pumpAndSettle();

  owners.current = _owner('owner-b');
  await tester.tap(find.widgetWithText(FilledButton, 'ถอนความยินยอม'));
  await tester.pumpAndSettle();

  expect(repository.statuses['owner-a']!.accepted, isTrue);
  if (bAccepted) {
    expect(repository.statuses['owner-b']!.accepted, isTrue);
    expect(find.byKey(_withdrawKey), findsOneWidget);
  } else {
    expect(repository.statuses['owner-b'], isNull);
    expect(find.byKey(_withdrawKey), findsNothing);
    expect(find.textContaining('ไม่ได้เข้าร่วม'), findsOneWidget);
  }
  expect(repository.decisions, isEmpty);
  expect(find.byType(SnackBar), findsOneWidget);
  expect(find.textContaining('สถานะความยินยอมเปลี่ยน'), findsOneWidget);
}

LocalOwner _owner(String id) =>
    LocalOwner(id: id, createdAtUtc: DateTime.utc(2026, 10, 21));

bool _liveRegion(WidgetTester tester, Key statusKey) {
  final semantics = tester.widget<Semantics>(
    find
        .ancestor(of: find.byKey(statusKey), matching: find.byType(Semantics))
        .first,
  );
  return semantics.properties.liveRegion == true;
}

String _statusText(WidgetTester tester) =>
    tester.widget<Text>(find.byKey(_syncStatusKey)).data!;

String _semanticsLabel(WidgetTester tester, Key statusKey) => tester
    .widget<Semantics>(
      find
          .ancestor(of: find.byKey(statusKey), matching: find.byType(Semantics))
          .first,
    )
    .properties
    .label!;

AccountUseCases _account(AccountSession? session) => AccountUseCases(
  gateway: _AccountGateway(session),
  owners: const _Owners(),
  upgradeGuestOwner: UpgradeGuestOwner(const _Upgrades()),
);

ResearchConsentUseCases _consent(_ConsentRepository repository) =>
    ResearchConsentUseCases(
      owners: const _Owners(),
      repository: repository,
      nowUtc: () => DateTime.utc(2026, 10, 21),
    );

final class _ConsentRepository implements ResearchConsentRepository {
  _ConsentRepository(this.status);

  ResearchConsentStatus status;
  Object? loadError;
  Completer<bool>? decision;
  int decideCalls = 0;
  bool? lastAccepted;

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async {
    if (loadError case final error?) throw error;
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
    lastAccepted = accepted;
    final result = await (decision?.future ?? Future<bool>.value(true));
    if (!result) return false;
    status = ResearchConsentStatus(
      ownerId: ownerId,
      version: version,
      accepted: accepted,
      decidedAtUtc: decidedAtUtc,
      withdrawnAtUtc: accepted ? null : decidedAtUtc,
    );
    return result;
  }
}

final class _MutableOwners implements LocalOwnerRepository {
  _MutableOwners(this.current);

  LocalOwner current;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _DelayedConsentRepository implements ResearchConsentRepository {
  final started = Completer<void>();
  final result = Completer<ResearchConsentStatus>();

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) {
    started.complete();
    return result.future;
  }

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) => throw UnimplementedError();
}

final class _OwnerConsentRepository implements ResearchConsentRepository {
  _OwnerConsentRepository(this.statuses);

  final Map<String, ResearchConsentStatus> statuses;
  final List<(String, bool)> decisions = [];

  @override
  Future<ResearchConsentStatus> load({
    required String ownerId,
    required int version,
  }) async =>
      statuses[ownerId] ??
      ResearchConsentStatus(
        ownerId: ownerId,
        version: version,
        accepted: false,
      );

  @override
  Future<bool> decide({
    required String ownerId,
    required int version,
    required bool accepted,
    required DateTime decidedAtUtc,
  }) async {
    decisions.add((ownerId, accepted));
    statuses[ownerId] = ResearchConsentStatus(
      ownerId: ownerId,
      version: version,
      accepted: accepted,
      decidedAtUtc: decidedAtUtc,
      withdrawnAtUtc: accepted ? null : decidedAtUtc,
    );
    return true;
  }
}

final class _AccountGateway implements AccountGateway {
  _AccountGateway(this.currentSession);

  int changePasswordCalls = 0;
  String? lastCurrentPassword;
  String? lastNewPassword;

  @override
  AccountSession? currentSession;

  @override
  Future<void> applyEmailVerificationCode(String code) =>
      throw UnimplementedError();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    changePasswordCalls++;
    lastCurrentPassword = currentPassword;
    lastNewPassword = newPassword;
  }

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<AccountSession> reload() => throw UnimplementedError();

  @override
  Future<void> sendPasswordReset(String email) => throw UnimplementedError();

  @override
  Future<void> sendVerification() => throw UnimplementedError();

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => throw UnimplementedError();

  @override
  Future<void> signOut() => throw UnimplementedError();

  @override
  Future<AccountSession> updateDisplayName(String displayName) =>
      throw UnimplementedError();
}

final class _Owners implements LocalOwnerRepository {
  const _Owners();

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'synthetic-owner',
    firebaseUid: 'synthetic-user',
    createdAtUtc: DateTime.utc(2026, 10, 21),
  );
}

final class _Upgrades implements OwnerUpgradeRepository {
  const _Upgrades();

  @override
  Future<OwnerUpgradeResult> createLocalGuestAfterLogout() =>
      throw UnimplementedError();

  @override
  Future<void> rollbackLocalGuestLogout({
    required String previousOwnerId,
    required String guestOwnerId,
  }) => throw UnimplementedError();

  @override
  Future<OwnerUpgradeResult> upgrade({
    required String activeOwnerId,
    required String firebaseUid,
  }) => throw UnimplementedError();
}

final class _GuestSessionService implements GuestSessionService {
  const _GuestSessionService();

  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'synthetic-guest');
}

final class _SyncStatusSource implements SyncStatusSource {
  final _controller = StreamController<SyncStatusSnapshot?>.broadcast();

  void add(SyncStatusSnapshot? snapshot) => _controller.add(snapshot);

  void addError(Object error) => _controller.addError(error);

  Future<void> close() => _controller.close();

  @override
  Stream<SyncStatusSnapshot?> watchCurrentOwnerSyncStatus() =>
      _controller.stream;
}

final class _DeviceModelHarness {
  _DeviceModelHarness({
    ModelDownloadState? initialState,
    Stream<List<int>>? stream,
    Object? sourceError,
    Future<ModelDownloadRecord?>? statusOverride,
  }) : directory = Directory.systemTemp.createTempSync('settings-model-'),
       bytes = const [1, 2, 3],
       manifest = ModelManifest(
         id: 'settings-test-model',
         version: '1.2.3-test',
         minimumAppVersion: '1.0.0+1',
         sourceUri: Uri.parse('https://example.test/model.tflite'),
         license: 'Apache-2.0',
         licenseUri: Uri.parse('https://example.test/license'),
         expectedSha256: sha256.convert(const [1, 2, 3]).toString(),
         expectedBytes: 3,
         inputShape: const [1, 1, 1, 3],
         inputType: ModelTensorType.uint8,
         outputShape: const [1, 1],
         outputType: ModelTensorType.uint8,
         inputEncoding: ModelInputEncoding.rawUint8Rgb,
         labelAssetName: 'labels.txt',
         supportedDelegates: const {ModelDelegate.cpu},
       ) {
    repository = _ModelRepository(statusOverride: statusOverride);
    source = _ModelSource(
      stream: stream ?? Stream<List<int>>.value(bytes),
      error: sourceError,
    );
    manager = ModelDownloadManager(
      repository: repository,
      source: source,
      verifier: const _ModelVerifier(),
      modelDirectory: () async => directory,
      nowUtc: () => DateTime.utc(2026, 10, 23),
    );
    useCases = DeviceModelUseCases(
      manifest: manifest,
      repository: repository,
      downloadManager: manager,
      openRuntime: ({required path, required manifest, required delegate}) =>
          throw UnimplementedError(),
    );
    if (initialState case final state?) repository.record = record(state);
  }

  final Directory directory;
  final List<int> bytes;
  final ModelManifest manifest;
  late final _ModelRepository repository;
  late final _ModelSource source;
  late final ModelDownloadManager manager;
  late final DeviceModelUseCases useCases;

  ModelDownloadRecord record(ModelDownloadState state) => ModelDownloadRecord(
    id: manifest.recordId,
    modelVersion: manifest.version,
    sourceUrl: manifest.sourceUri.toString(),
    expectedChecksum: manifest.expectedSha256,
    expectedBytes: manifest.expectedBytes,
    downloadedBytes: state == ModelDownloadState.notStarted ? 0 : 1,
    retryCount: state == ModelDownloadState.failed ? 1 : 0,
    state: state,
    updatedAtUtc: DateTime.utc(2026, 10, 23),
    localPath: '${directory.path}${Platform.pathSeparator}model.tflite',
    failureCode: state == ModelDownloadState.failed
        ? ModelFailureCode.network
        : null,
  );

  Future<void> dispose() async {
    await manager.dispose();
    if (directory.existsSync()) directory.deleteSync(recursive: true);
  }
}

final class _ModelRepository implements ModelDownloadRepository {
  _ModelRepository({this.statusOverride});

  final Future<ModelDownloadRecord?>? statusOverride;
  bool _usedStatusOverride = false;
  ModelDownloadRecord? record;

  @override
  Future<void> activate(ModelDownloadRecord next) async {
    record = next.copyWith(state: ModelDownloadState.active);
  }

  @override
  Future<ModelDownloadRecord?> find(String id) {
    if (!_usedStatusOverride && statusOverride != null) {
      _usedStatusOverride = true;
      return statusOverride!;
    }
    return Future.value(record);
  }

  @override
  Future<void> save(ModelDownloadRecord next) async {
    record = next;
  }
}

final class _ModelSource implements ModelByteSource {
  _ModelSource({required this.stream, this.error});

  final Stream<List<int>> stream;
  final Object? error;
  int openCalls = 0;

  @override
  Future<ModelByteResponse> open(
    Uri uri, {
    required int start,
    ModelCancellation? cancellation,
  }) async {
    openCalls++;
    if (error case final value?) throw value;
    return ModelByteResponse(statusCode: 200, bytes: stream);
  }
}

final class _ModelVerifier implements ModelFileVerifier {
  const _ModelVerifier();

  @override
  Future<void> verify(String path, ModelManifest manifest) async {}
}
