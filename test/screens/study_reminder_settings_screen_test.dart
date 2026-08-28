import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/screens/study_reminder_settings_screen.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  testWidgets(
    'opt-in is an explicit calm action and persists the goal source',
    (tester) async {
      final fixture = await _Fixture.create(ReminderPermissionState.unknown);
      addTearDown(fixture.dispose);
      await _insertGoal(
        fixture.database,
        await fixture.repository.activeOwnerId(),
      );
      await tester.pumpWidget(
        MaterialApp(
          home: StudyReminderSettingsScreen(
            useCases: fixture.useCases,
            source: StudyReminderSource.goalDeadline('goal:ielts'),
            sourceLabel: 'IELTS practice target',
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('whenever'), findsWidgets);
      expect(find.textContaining('missed', findRichText: true), findsNothing);
      expect(find.textContaining('failed', findRichText: true), findsNothing);
      expect(find.textContaining('overdue', findRichText: true), findsNothing);
      expect(fixture.scheduler.requestCalls, 0);

      await tester.enterText(
        find.byKey(const ValueKey('study-reminder/scheduled-at')),
        '2026-08-29T02:00:00Z',
      );
      await tester.enterText(
        find.byKey(const ValueKey('study-reminder/timezone')),
        'Asia/Bangkok',
      );
      await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
      await tester.pumpAndSettle();

      final reminder = (await fixture.repository.list()).single;
      expect(fixture.scheduler.requestCalls, 1);
      expect(reminder.source.stableIdentity, 'goal:goal:ielts');
      expect(reminder.isEnabled, isTrue);
      expect(find.text('Reminder on'), findsOneWidget);
    },
  );

  testWidgets('permission denial stays non-punitive and does not retry', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.denied);
    fixture.scheduler.requestResult = ReminderPermissionState.denied;
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Reviews ready',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('study-reminder/scheduled-at')),
      '2026-08-29T02:00:00Z',
    );
    await tester.enterText(
      find.byKey(const ValueKey('study-reminder/timezone')),
      'Asia/Bangkok',
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();

    expect(fixture.scheduler.requestCalls, 1);
    expect(await fixture.repository.list(), isEmpty);
    expect(
      find.text(
        'Notifications are off. You can keep studying without reminders.',
      ),
      findsOneWidget,
    );
  });

  testWidgets('past time stays off without permission or durable writes', (
    tester,
  ) async {
    final fixture = await _Fixture.create(ReminderPermissionState.unknown);
    addTearDown(fixture.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: StudyReminderSettingsScreen(
          useCases: fixture.useCases,
          source: const StudyReminderSource.dueReview(),
          sourceLabel: 'Reviews ready',
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('study-reminder/scheduled-at')),
      '2026-08-28T00:00:00Z',
    );
    await tester.tap(find.byKey(const ValueKey('study-reminder/opt-in')));
    await tester.pumpAndSettle();

    expect(fixture.scheduler.requestCalls, 0);
    expect(await fixture.repository.list(includeDeleted: true), isEmpty);
    expect(await fixture.repository.pendingPlatformIntents(), isEmpty);
    expect(find.text('Reminder on'), findsNothing);
    expect(
      find.text('Choose a future time and a valid learning timezone.'),
      findsOneWidget,
    );
  });
}

Future<void> _insertGoal(AppDatabase database, String ownerId) => database
    .into(database.learningGoals)
    .insert(
      LearningGoalsCompanion.insert(
        id: 'goal:ielts',
        ownerId: ownerId,
        kind: 'exam',
        title: 'IELTS practice target',
        deadlineAtUtcMs: DateTime.utc(2026, 9, 30).millisecondsSinceEpoch,
        timezoneId: 'Asia/Bangkok',
        timezoneOffsetMinutes: 420,
        status: 'active',
        createdAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
        updatedAtUtcMs: DateTime.utc(2026, 8, 28).millisecondsSinceEpoch,
      ),
    );

final class _Fixture {
  _Fixture(this.database, this.repository, this.scheduler, this.useCases);

  static Future<_Fixture> create(ReminderPermissionState permission) async {
    final database = AppDatabase(NativeDatabase.memory());
    final repository = DriftStudyReminderRepository(
      database,
      owners: DriftLocalOwnerRepository(
        database,
        generateId: () => 'owner-a',
        nowUtc: () => DateTime.utc(2026, 8, 28),
      ),
    );
    final scheduler = _ScreenScheduler()..permission = permission;
    return _Fixture(
      database,
      repository,
      scheduler,
      StudyReminderUseCases(
        repository: repository,
        scheduler: scheduler,
        nowUtc: () => DateTime.utc(2026, 8, 28),
        generateId: () => 'reminder:screen',
      ),
    );
  }

  final AppDatabase database;
  final DriftStudyReminderRepository repository;
  final _ScreenScheduler scheduler;
  final StudyReminderUseCases useCases;

  Future<void> dispose() => database.close();
}

final class _ScreenScheduler implements ReminderScheduler {
  ReminderPermissionState permission = ReminderPermissionState.unknown;
  ReminderPermissionState requestResult = ReminderPermissionState.granted;
  int requestCalls = 0;
  final Map<int, ReminderPlatformEntry> pending = {};

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermission() async {
    requestCalls += 1;
    permission = requestResult;
    return requestResult;
  }

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async =>
      pending.values.toList(growable: false);

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {
    pending[request.platformId] = ReminderPlatformEntry(
      platformId: request.platformId,
      ownerId: request.ownerId,
      reminderId: request.reminderId,
    );
  }

  @override
  Future<void> cancel(int platformId) async {
    pending.remove(platformId);
  }
}
