import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/study_reminders/application/study_reminder_runtime.dart';
import 'package:vocab_learning_app/features/study_reminders/data/method_channel_study_reminder_platform.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/study_reminders/presentation/study_reminder_settings_screen.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'first native permission grant saves and schedules without retry',
    (tester) async {
      expect(
        tester.view.physicalSize.width / tester.view.devicePixelRatio,
        greaterThanOrEqualTo(320),
        reason: 'The synthetic Android display must provide at least 320dp.',
      );
      MethodChannelStudyReminderPlatform? platform;
      const owner = 'synthetic-permission-owner';
      final owners = StreamController<String?>.broadcast(sync: true);
      Directory? directory;
      AppDatabase? database;
      StudyReminderRuntime? runtime;
      _ReminderLifecycle? lifecycle;
      try {
        await tester.runAsync(() async {
          final root = await getApplicationSupportDirectory();
          final temporary = await root.createTemp(
            'synthetic-reminder-permission-',
          );
          directory = temporary;
          final db = AppDatabase(
            NativeDatabase(
              File('${temporary.path}/authority.sqlite'),
              setup: (db) {
                db.execute('PRAGMA journal_mode=WAL');
                db.execute('PRAGMA busy_timeout=5000');
                db.execute('PRAGMA foreign_keys=ON');
              },
            ),
          );
          database = db;
          await db.customStatement(
            "INSERT INTO local_owners (id, created_at_utc_ms, is_active) "
            "VALUES ('$owner', 1, 1)",
          );
          final ownerWrites = DriftOwnerWriteCoordinator(
            db,
            nowUtc: () => DateTime.now().toUtc(),
          );
          final nativePlatform = MethodChannelStudyReminderPlatform(
            ownerWrites: ownerWrites,
            isAndroid: true,
          );
          platform = nativePlatform;
          final activeRuntime = StudyReminderRuntime(
            database: db,
            ownerWrites: ownerWrites,
            ownerChanges: owners.stream,
            platform: nativePlatform,
            nowUtc: () => DateTime.now().toUtc(),
          );
          runtime = activeRuntime;
          owners.add(owner);
          activeRuntime.setForeground(true);
          await activeRuntime.reconcileForeground();
          await activeRuntime.repository.writeForOwner(
            ownerId: owner,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1430,
              timezoneId: 'UTC',
            ),
            updatedAtUtc: DateTime.now().toUtc(),
            stillCurrent: () => true,
          );
          final status = await nativePlatform.inspect();
          expect(status.supported, isTrue);
          expect(
            status.notificationsAllowed,
            isFalse,
            reason:
                'Revoke POST_NOTIFICATIONS on the synthetic AVD before running',
          );
        });
        final activeRuntime = runtime!;
        final db = database!;
        final observer = _ReminderLifecycle(activeRuntime);
        lifecycle = observer;
        WidgetsBinding.instance.addObserver(observer);
        await tester.pumpWidget(
          MaterialApp(
            home: StudyReminderSettingsScreen(
              runtime: activeRuntime,
              ownerId: owner,
            ),
          ),
        );
        await _until(
          tester,
          () => find.text('ค่าที่บันทึก: ปิดการเตือน').evaluate().isNotEmpty,
        );
        await tester.tap(find.byKey(const Key('reminder-enabled')));
        await tester.pump();
        final save = find.byKey(const Key('reminder-save'));
        await tester.scrollUntilVisible(save, 200);
        await tester.pumpAndSettle();
        await tester.tap(save);
        await _until(
          tester,
          () =>
              find
                  .textContaining('ระบบรับคำขอเตือนรอบถัดไปแล้ว')
                  .evaluate()
                  .isNotEmpty ||
              find
                  .textContaining('ยังยืนยันคำขอของระบบไม่ได้')
                  .evaluate()
                  .isNotEmpty,
        );
        expect(
          find.textContaining('ระบบรับคำขอเตือนรอบถัดไปแล้ว'),
          findsOneWidget,
          reason:
              'The first permission grant must finish without a second Save',
        );
        expect(find.textContaining('ยังยืนยันคำขอของระบบไม่ได้'), findsNothing);
        await tester.runAsync(() async {
          final view = await activeRuntime.load(
            expectedOwnerId: owner,
            stillCurrent: () => true,
          );
          expect(view.setting.enabled, isTrue);
          expect(view.setting.revision, 2);
          expect(view.requestAck?.revision, 2);
          expect(view.requestAck?.nextAtUtc, isNotNull);
          final off = await activeRuntime.prepareChange(
            expectedOwnerId: owner,
            choice: const StudyReminderChoice(
              enabled: false,
              minuteOfDay: 1430,
              timezoneId: 'UTC',
            ),
            stillCurrent: () => true,
          );
          final disabled = await activeRuntime.apply(off);
          expect(disabled.setting.enabled, isFalse);
          expect(disabled.requestAck?.revision, 3);
          expect(
            (await db.customSelect('PRAGMA quick_check').getSingle())
                .data
                .values
                .single,
            'ok',
          );
        });
        expect(tester.takeException(), isNull);
      } finally {
        if (lifecycle != null) {
          WidgetsBinding.instance.removeObserver(lifecycle);
        }
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.runAsync(() async {
          try {
            await runtime?.dispose();
            await owners.close();
            if (database != null) {
              await database!.customStatement(
                'UPDATE study_reminder_preferences SET enabled=0',
              );
              await platform?.retire();
            }
          } finally {
            try {
              await database?.close();
            } finally {
              await directory?.delete(recursive: true);
            }
          }
        });
      }
    },
  );
}

final class _ReminderLifecycle extends WidgetsBindingObserver {
  _ReminderLifecycle(this.runtime);
  final StudyReminderRuntime runtime;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    runtime.setForeground(state == AppLifecycleState.resumed);
  }
}

Future<void> _until(WidgetTester tester, bool Function() ready) async {
  final deadline = DateTime.now().add(const Duration(seconds: 90));
  while (!ready() && DateTime.now().isBefore(deadline)) {
    await tester.pump(const Duration(milliseconds: 100));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
  }
  expect(
    ready(),
    isTrue,
    reason: 'Native permission workflow did not finish in 90 seconds',
  );
}
