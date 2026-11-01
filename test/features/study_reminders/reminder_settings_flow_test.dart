import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/learning_profile/domain/learning_timezone.dart';
import 'package:vocab_learning_app/features/study_reminders/application/study_reminder_runtime.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/study_reminders/presentation/study_reminder_settings_screen.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../quest/support/quest_repository_harness.dart';
import '../../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  for (final dark in [false, true]) {
    testWidgets(
      'default off and cancelled time picker preserve all facts at 320/200 ${dark ? 'dark' : 'light'}',
      (tester) async {
        final f = await _open(tester);
        Future<void>? closing;
        Future<void> close() =>
            closing ??= closeMotivationPresentation(tester, f.close);
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        try {
          final before = await motivationPresentationIo(
            tester,
            f.h.storage.snapshot,
          );
          await _mount(tester, f, dark: dark, large: true);
          expect(find.text('ค่าที่บันทึก: ปิดการเตือน'), findsOneWidget);
          await _show(tester, find.byKey(const Key('reminder-time')));
          expect(find.text('เลือกเวลา'), findsOneWidget);
          await tester.tap(find.byKey(const Key('reminder-time')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.text(
              MaterialLocalizations.of(
                tester.element(find.byType(TimePickerDialog)),
              ).cancelButtonLabel,
            ),
          );
          await tester.pumpAndSettle();
          await _show(tester, find.byKey(const Key('reminder-time')));
          expect(find.text('เลือกเวลา'), findsOneWidget);
          expect(f.platform.permissionRequests, 0);
          expect(f.platform.alarmRevision, isNull);
          expect(
            await motivationPresentationIo(tester, f.h.storage.snapshot),
            before,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await close();
        }
      },
    );
  }

  testWidgets(
    'explicit enable saves actual chosen preference and one accepted alarm',
    (tester) async {
      final f = await _open(tester);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, f.close);
      try {
        await motivationPresentationIo(
          tester,
          () => f.runtime.repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1140,
              timezoneId: 'Asia/Bangkok',
            ),
            updatedAtUtc: f.h.now,
            stillCurrent: () => true,
          ),
        );
        await _mount(tester, f);
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await _show(tester, find.byKey(const Key('reminder-save')));
        await tester.tap(find.byKey(const Key('reminder-save')));
        await _wait(tester, () => f.platform.alarmRevision == 2);
        expect(
          find.textContaining('ระบบรับคำขอเตือนรอบถัดไปแล้ว'),
          findsOneWidget,
        );
        final saved = await motivationPresentationIo(
          tester,
          () => f.runtime.repository.readForOwner(
            ownerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
        );
        expect(saved.enabled, isTrue);
        expect(saved.minuteOfDay, 1140);
        expect(saved.timezoneId, 'Asia/Bangkok');
        expect(saved.revision, 2);
        expect(f.platform.permissionRequests, 0);
        expect(tester.takeException(), isNull);
      } finally {
        await close();
      }
    },
  );

  testWidgets(
    'actual timezone popup selection keeps settings usable through explicit save',
    (tester) async {
      final f = await _open(tester);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, f.close);
      try {
        await motivationPresentationIo(
          tester,
          () => f.runtime.repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1140,
              timezoneId: 'Asia/Bangkok',
            ),
            updatedAtUtc: f.h.now,
            stillCurrent: () => true,
          ),
        );
        await _mount(tester, f);
        await _show(tester, find.byKey(const Key('reminder-zone')));
        await tester.tap(find.byKey(const Key('reminder-zone')));
        await tester.pumpAndSettle();
        final selected = learningTimezoneIds.first;
        final popup = find.byType(Scrollable).last;
        final option = find.descendant(
          of: popup,
          matching: find.text(selected),
        );
        await tester.scrollUntilVisible(
          option,
          -400,
          scrollable: popup,
          maxScrolls: 100,
        );
        await tester.tap(option);
        await tester.pumpAndSettle();
        expect(
          find.textContaining('พื้นที่ข้อมูลหรือหน้าจอเปลี่ยนแล้ว'),
          findsNothing,
        );
        await _show(
          tester,
          find.byKey(const Key('reminder-enabled')),
          delta: -300,
        );
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await _show(tester, find.byKey(const Key('reminder-save')));
        await tester.tap(find.byKey(const Key('reminder-save')));
        await _wait(tester, () => f.platform.alarmRevision == 2);
        final saved = await motivationPresentationIo(
          tester,
          () => f.runtime.repository.readForOwner(
            ownerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
        );
        expect(saved.enabled, isTrue);
        expect(saved.timezoneId, selected);
        expect(saved.revision, 2);
      } finally {
        await close();
      }
    },
  );

  testWidgets(
    'retained save while actual time picker covers settings changes no stored facts',
    (tester) async {
      final f = await _open(tester);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, f.close);
      try {
        await motivationPresentationIo(
          tester,
          () => f.runtime.repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1140,
              timezoneId: 'Asia/Bangkok',
            ),
            updatedAtUtc: f.h.now,
            stillCurrent: () => true,
          ),
        );
        await _mount(tester, f);
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await _show(tester, find.byKey(const Key('reminder-save')));
        final retained = tester
            .widget<FilledButton>(find.byKey(const Key('reminder-save')))
            .onPressed!;
        final before = await motivationPresentationIo(
          tester,
          f.h.storage.snapshot,
        );
        await _show(
          tester,
          find.byKey(const Key('reminder-time')),
          delta: -300,
        );
        await tester.tap(find.byKey(const Key('reminder-time')));
        await tester.pumpAndSettle();
        expect(find.byType(TimePickerDialog), findsOneWidget);
        retained();
        await tester.pump();
        await _wait(
          tester,
          () =>
              find.text('กำลังบันทึก…', skipOffstage: false).evaluate().isEmpty,
        );
        expect(
          await motivationPresentationIo(tester, f.h.storage.snapshot),
          before,
        );
        expect(f.platform.alarmRevision, isNull);
        expect(f.platform.permissionRequests, 0);
        await tester.tap(
          find.text(
            MaterialLocalizations.of(
              tester.element(find.byType(TimePickerDialog)),
            ).cancelButtonLabel,
          ),
        );
        await tester.pumpAndSettle();
      } finally {
        await close();
      }
    },
  );

  testWidgets(
    'actual ChooseMode reminder retains owned permission intent across inactive and resume',
    (tester) async {
      final f = await _open(tester);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, f.close);
      try {
        await motivationPresentationIo(
          tester,
          () => f.runtime.repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1140,
              timezoneId: 'Asia/Bangkok',
            ),
            updatedAtUtc: f.h.now,
            stillCurrent: () => true,
          ),
        );
        f.platform.allowed = false;
        f.platform.permissionGate = Completer<bool>();
        final before = await motivationPresentationIo(
          tester,
          f.h.storage.snapshot,
        );
        final progress = ProgressUseCases(
          owners: f.h.storage.owners,
          queries: DriftProgressQueries(f.h.database),
          nowUtc: () => f.h.now,
        );
        await motivationPresentationDeadline(
          tester,
          'reminder-entry/mount',
          () => tester.pumpWidget(
            AppDependenciesScope(
              dependencies: AppDependencies(
                runtimeStatus: const AppRuntimeStatus(
                  localData: RuntimeAvailability.ready,
                  firebase: RuntimeAvailability.unavailable,
                  supabase: RuntimeAvailability.unavailable,
                  backends: RuntimeAvailability.unavailable,
                ),
                config: null,
                guestSessionService: _NoGuest(),
                database: f.h.database,
                localOwners: f.h.storage.owners,
                progress: progress,
                studyReminders: f.runtime,
              ),
              child: MaterialApp(
                theme: M3Theme.lightTheme,
                home: const ChooseModeScreen(),
              ),
            ),
          ),
        );
        final entry = find.byKey(const ValueKey('study-reminder-entry'));
        await _show(tester, entry);
        await _wait(
          tester,
          () =>
              tester
                  .widget<ListTile>(
                    find.descendant(of: entry, matching: find.byType(ListTile)),
                  )
                  .onTap !=
              null,
        );
        await tester.tap(find.byKey(const ValueKey('study-reminder-entry')));
        await _wait(
          tester,
          () => find
              .byKey(const Key('reminder-saved-state'))
              .evaluate()
              .isNotEmpty,
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await _show(tester, find.byKey(const Key('reminder-save')));
        await tester.tap(find.byKey(const Key('reminder-save')));
        await _wait(tester, () => f.platform.requestStarted.isCompleted);
        f.runtime.setForeground(false);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.inactive,
        );
        await tester.pump();
        f.platform.permissionGate!.complete(true);
        expect(
          await motivationPresentationIo(tester, f.h.storage.snapshot),
          before,
        );
        expect(f.platform.alarmRevision, isNull);
        f.runtime.setForeground(true);
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pump();
        expect(
          find.byType(StudyReminderSettingsScreen),
          findsOneWidget,
          reason:
              'Owned notification permission must retain the mounted settings route',
        );
        await _wait(tester, () => f.platform.alarmRevision == 2);
        final saved = await motivationPresentationIo(
          tester,
          () => f.runtime.repository.readForOwner(
            ownerId: configuredOwnerId,
            stillCurrent: () => true,
          ),
        );
        expect(saved.enabled, isTrue);
        expect(saved.revision, 2);
        expect(f.platform.permissionRequests, 1);
      } finally {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await close();
      }
    },
  );

  testWidgets(
    'actual owner ABA clears the draft and retained save cannot write',
    (tester) async {
      final f = await _open(tester);
      Future<void>? closing;
      Future<void> close() =>
          closing ??= closeMotivationPresentation(tester, f.close);
      try {
        await _mount(tester, f);
        await _show(tester, find.byKey(const Key('reminder-save')));
        final stale = tester
            .widget<FilledButton>(find.byKey(const Key('reminder-save')))
            .onPressed!;
        await motivationPresentationIo(
          tester,
          () => f.switchOwner(configuredOtherOwnerId),
        );
        await motivationPresentationIo(
          tester,
          () => f.switchOwner(configuredOwnerId),
        );
        final before = await motivationPresentationIo(
          tester,
          f.h.storage.snapshot,
        );
        stale();
        await tester.pump();
        expect(
          find.textContaining('พื้นที่ข้อมูลหรือหน้าจอเปลี่ยนแล้ว'),
          findsOneWidget,
        );
        expect(
          await motivationPresentationIo(tester, f.h.storage.snapshot),
          before,
        );
        expect(f.platform.alarmRevision, isNull);
        expect(f.platform.permissionRequests, 0);
      } finally {
        await close();
      }
    },
  );
}

Future<_Fixture> _open(WidgetTester tester) async =>
    (await motivationPresentationDeadline<_Fixture?>(
      tester,
      'reminder/open',
      () => tester.runAsync(_Fixture.open),
    ))!;

Future<void> _mount(
  WidgetTester tester,
  _Fixture f, {
  bool dark = false,
  bool large = false,
}) async {
  await motivationPresentationDeadline(
    tester,
    'reminder/mount',
    () => tester.pumpWidget(
      MaterialApp(
        theme: M3Theme.lightTheme,
        darkTheme: M3Theme.darkTheme,
        themeMode: dark ? ThemeMode.dark : ThemeMode.light,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(large ? 2 : 1),
            disableAnimations: true,
          ),
          child: child!,
        ),
        home: StudyReminderSettingsScreen(
          runtime: f.runtime,
          ownerId: configuredOwnerId,
        ),
      ),
    ),
  );
  await _wait(
    tester,
    () => find.byKey(const Key('reminder-saved-state')).evaluate().isNotEmpty,
  );
}

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    await motivationPresentationDeadline(
      tester,
      'reminder-wait/io-$i',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      ),
    );
    await motivationPresentationDeadline(
      tester,
      'reminder-wait/pump-$i',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    if (ready()) return;
  }
  fail('Reminder UI did not become ready');
}

Future<void> _show(
  WidgetTester tester,
  Finder target, {
  double delta = 300,
}) async {
  await tester.scrollUntilVisible(
    target,
    delta,
    scrollable: find.byType(Scrollable).first,
    maxScrolls: 80,
  );
  await tester.ensureVisible(target);
  await tester.pumpAndSettle();
  expect(target.hitTestable(), findsOneWidget);
}

final class _Fixture {
  _Fixture(this.directory, this.h, this.platform, this.runtime);
  final Directory directory;
  final QuestHarness h;
  final _Platform platform;
  final StudyReminderRuntime runtime;
  static Future<_Fixture> open() async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-reminder-ui-',
    );
    final h = await QuestHarness.open(
      file: File('${directory.path}/synthetic.sqlite'),
    );
    final platform = _Platform();
    final progress = ProgressUseCases(
      owners: h.storage.owners,
      queries: DriftProgressQueries(h.database),
      nowUtc: () => h.now,
    );
    final runtime = StudyReminderRuntime(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
      ownerChanges: progress.watchActiveOwnerId(),
      platform: platform,
      nowUtc: () => h.now,
    );
    runtime.setForeground(true);
    await _until(() => runtime.currentOwnerId == configuredOwnerId);
    await runtime.reconcileForeground();
    return _Fixture(directory, h, platform, runtime);
  }

  Future<void> switchOwner(String owner) async {
    await (h.database.update(h.database.localOwners)
          ..where((row) => row.isActive.equals(true)))
        .write(const db.LocalOwnersCompanion(isActive: Value(false)));
    await (h.database.update(h.database.localOwners)
          ..where((row) => row.id.equals(owner)))
        .write(const db.LocalOwnersCompanion(isActive: Value(true)));
    await _until(() => runtime.currentOwnerId == owner);
  }

  Future<void> close() async {
    await runtime.dispose();
    await h.close();
    await directory.delete(recursive: true);
  }
}

final class _Platform implements StudyReminderPlatform {
  int permissionRequests = 0;
  int? alarmRevision;
  bool allowed = true;
  Completer<bool>? permissionGate;
  final requestStarted = Completer<void>();
  @override
  Future<StudyReminderPlatformStatus> inspect() async =>
      StudyReminderPlatformStatus(
        supported: true,
        notificationsAllowed: allowed,
      );
  @override
  Future<StudyReminderPlatformStatus> requestPermission() async {
    permissionRequests++;
    if (!requestStarted.isCompleted) requestStarted.complete();
    if (permissionGate != null) allowed = await permissionGate!.future;
    return inspect();
  }

  @override
  Future<String> bindScope({
    required String databasePath,
    required String ownerId,
  }) async => 'synthetic-ui-scope';
  @override
  Future<StudyReminderRequestAck> schedule({
    required String scopeToken,
    required int revision,
  }) async {
    alarmRevision = revision;
    return StudyReminderRequestAck(
      revision: revision,
      nextAtUtc: DateTime.utc(2026, 11, 2),
    );
  }

  @override
  Future<StudyReminderRequestAck> cancel({
    required String scopeToken,
    required int revision,
  }) async {
    alarmRevision = null;
    return StudyReminderRequestAck(revision: revision);
  }

  @override
  Future<void> retire({String? scopeToken}) async {
    alarmRevision = null;
  }
}

class _NoGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() =>
      throw StateError('Reminder fixture must not authenticate');
}

Future<void> _until(bool Function() ready) async {
  for (var i = 0; i < 200; i++) {
    if (ready()) return;
    await Future<void>.delayed(const Duration(milliseconds: 5));
  }
  fail('Actual reminder owner did not become ready');
}
