import 'package:vocab_learning_app/screens/study_reminder_settings_screen.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder_repository.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);
  for (final editing in [false, true]) {
    for (final scenario in ['double tap', 'lookup failure', 'owner change']) {
      testWidgets(
        'F03 goal opening $editing $scenario is fenced and retryable',
        (tester) async {
          final goal = LearningGoal(
            id: 'goal:opening',
            kind: LearningGoalKind.personal,
            title: 'Opening target',
            deadlineAtUtc: DateTime.utc(2026, 9, 25),
            timezone: const LearningGoalTimezoneContext(
              timezoneId: 'Asia/Bangkok',
              utcOffsetMinutes: 420,
            ),
            status: LearningGoalStatus.active,
            createdAtUtc: DateTime.utc(2026, 9, 19),
            updatedAtUtc: DateTime.utc(2026, 9, 19),
          );
          final gate = Completer<String>();
          var calls = 0;
          var opening = false;
          var currentOwner = 'owner-a';
          final cases = LearningGoalUseCases(
            repository: _Goals(editing ? [goal] : []),
            activeOwnerId: () {
              if (!opening) return Future.value(currentOwner);
              calls++;
              return calls == 1 ? gate.future : Future.value(currentOwner);
            },
            nowUtc: () => DateTime.utc(2026, 9, 19),
            generateId: () => 'goal:new',
          );
          await tester.pumpWidget(
            MaterialApp(home: LearningGoalsScreen(useCases: cases)),
          );
          await tester.pumpAndSettle();
          final button = find.byKey(
            ValueKey(
              editing
                  ? 'learning-goal/goal:opening/edit'
                  : 'learning-goals/add',
            ),
          );
          opening = true;
          await tester.tap(button);
          if (scenario == 'double tap') await tester.tap(button);
          await tester.pump();
          if (scenario == 'double tap') expect(calls, 1);
          if (scenario == 'lookup failure') {
            gate.completeError(StateError('owner unavailable'));
          } else {
            if (scenario == 'owner change') currentOwner = 'owner-b';
            gate.complete('owner-a');
          }
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
          if (scenario == 'double tap') {
            expect(find.byType(AlertDialog), findsOneWidget);
            Navigator.of(tester.element(find.byType(AlertDialog))).pop();
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsNothing);
          } else {
            expect(find.byType(AlertDialog), findsNothing);
            expect(
              find.text('ยังเปิดเป้าหมายไม่ได้ กรุณาลองอีกครั้ง'),
              findsOneWidget,
            );
            await tester.tap(button);
            await tester.pumpAndSettle();
            expect(find.byType(AlertDialog), findsOneWidget);
          }
        },
      );
    }
  }
  testWidgets(
    'G4.2 edits and deletes a personal goal through durable actions',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final now = DateTime.utc(2026, 9, 13, 16, 59);
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'goal-editor',
        nowUtc: () => now,
      );
      await owners.getOrCreateActiveOwner();
      final cases = LearningGoalUseCases(
        repository: DriftLearningGoalRepository(database, owners: owners),
        activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
        nowUtc: () => now,
        generateId: () => 'goal:editable',
      );
      await cases.create(
        kind: LearningGoalKind.personal,
        title: 'Original target',
        deadlineAtUtc: DateTime.utc(2026, 9, 14, 3),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );
      await tester.pumpWidget(
        MaterialApp(home: LearningGoalsScreen(useCases: cases)),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey('learning-goal/goal:editable/edit')),
      );
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('learning-goals/title')),
        'Revised personal target',
      );
      await tester.tap(find.byKey(const ValueKey('learning-goals/save')));
      await tester.pumpAndSettle();
      expect(find.text('Revised personal target'), findsOneWidget);
      expect(
        (await cases.list()).single.deadlineAtUtc,
        DateTime.utc(2026, 9, 14, 3),
      );
      await tester.tap(
        find.byKey(const ValueKey('learning-goal/goal:editable/delete')),
      );
      await tester.pumpAndSettle();
      expect(await cases.list(), isEmpty);
      final row = (await database.select(database.learningGoals).get()).single;
      expect(row.isDeleted, isTrue);
      expect(row.title, 'Revised personal target');
      expect(row.localRevision, 3);
    },
  );

  testWidgets('R15.5 goals reload when owner dependencies are replaced', (
    tester,
  ) async {
    LearningGoalUseCases cases(String owner) => LearningGoalUseCases(
      activeOwnerId: () async => owner,
      repository: _Goals([
        LearningGoal(
          id: 'goal:$owner',
          kind: LearningGoalKind.personal,
          title: 'Goal $owner',
          deadlineAtUtc: DateTime.utc(2026, 9, 1),
          timezone: const LearningGoalTimezoneContext(
            timezoneId: 'UTC',
            utcOffsetMinutes: 0,
          ),
          status: LearningGoalStatus.active,
          createdAtUtc: DateTime.utc(2026, 8, 25),
          updatedAtUtc: DateTime.utc(2026, 8, 25),
        ),
      ]),
      nowUtc: () => DateTime.utc(2026, 8, 25),
      generateId: () => 'new:$owner',
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningGoalsScreen(useCases: cases('A'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Goal A'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: LearningGoalsScreen(useCases: cases('B'))),
    );
    await tester.pumpAndSettle();
    expect(find.text('Goal A'), findsNothing);
    expect(find.text('Goal B'), findsOneWidget);
  });
  for (final changeOwner in [false, true]) {
    testWidgets(
      changeOwner
          ? 'owner change before first submit rejects the open A draft'
          : 'unchanged owner first submit persists the valid form',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owners = DriftLocalOwnerRepository(
          database,
          generateId: () => 'synthetic-owner-a',
          nowUtc: () => DateTime.utc(2026, 8, 25),
        );
        await owners.getOrCreateActiveOwner();
        await tester.pumpWidget(
          MaterialApp(
            home: LearningGoalsScreen(
              useCases: LearningGoalUseCases(
                activeOwnerId: () async =>
                    (await owners.getOrCreateActiveOwner()).id,
                repository: DriftLearningGoalRepository(
                  database,
                  owners: owners,
                ),
                nowUtc: () => DateTime.utc(2026, 8, 25),
                generateId: () => 'goal:synthetic-stale-form',
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(const ValueKey('learning-goals/add')));
        await tester.pumpAndSettle();
        await tester.enterText(
          find.byKey(const ValueKey('learning-goals/title')),
          'Synthetic owner A draft',
        );
        await _selectLocalDateTime(
          tester,
          'learning-goals/deadline',
          '09/01/2026',
          '12',
          '00',
        );

        expect(
          tester
              .widget<FilledButton>(
                find.byKey(const ValueKey('learning-goals/create')),
              )
              .onPressed,
          isNotNull,
        );
        if (changeOwner) {
          await tester.runAsync(() async {
            await database.transaction(() async {
              await database.customUpdate(
                'UPDATE local_owners SET is_active = 0',
              );
              await database
                  .into(database.localOwners)
                  .insert(
                    LocalOwnersCompanion.insert(
                      id: 'synthetic-owner-b',
                      createdAtUtcMs: DateTime.utc(
                        2026,
                        8,
                        25,
                      ).millisecondsSinceEpoch,
                    ),
                  );
            });
          });
        }
        await tester.runAsync(() async {
          await tester.tap(find.byKey(const ValueKey('learning-goals/create')));
          for (var attempt = 0; attempt < 100; attempt++) {
            await Future<void>.delayed(const Duration(milliseconds: 10));
            await tester.pump();
            if (find.byType(AlertDialog).evaluate().isEmpty) break;
          }
        });
        await tester.pumpAndSettle();
        expect(
          find.byType(AlertDialog),
          findsNothing,
          reason:
              'Observe completed submission, never mistake validation for isolation.',
        );
        final goals = await tester.runAsync(
          () => database.select(database.learningGoals).get(),
        );
        final outbox = await tester.runAsync(
          () => database.select(database.outboxOperations).get(),
        );
        expect(
          goals,
          changeOwner ? isEmpty : hasLength(1),
          reason: 'First submit must retain the form owner.',
        );
        expect(outbox, changeOwner ? isEmpty : hasLength(1));
      },
    );
  }

  testWidgets('renders typed language goals without admission-score UI', (
    tester,
  ) async {
    final repository = _Goals([
      LearningGoal(
        id: 'goal:1',
        kind: LearningGoalKind.languageTest,
        title: 'IELTS practice target',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        status: LearningGoalStatus.active,
        createdAtUtc: DateTime.utc(2026, 8, 25),
        updatedAtUtc: DateTime.utc(2026, 8, 25),
      ),
    ]);
    await tester.pumpWidget(
      MaterialApp(
        home: LearningGoalsScreen(
          useCases: LearningGoalUseCases(
            activeOwnerId: () async => 'synthetic-owner-a',
            repository: repository,
            nowUtc: () => DateTime.utc(2026, 8, 25),
            generateId: () => 'goal:new',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(AppBar, 'เป้าหมายการเรียน'), findsOneWidget);
    expect(find.text('IELTS practice target'), findsOneWidget);
    expect(find.textContaining('วัน'), findsOneWidget);
    expect(find.textContaining('admission', findRichText: true), findsNothing);
    expect(find.textContaining('TCAS', findRichText: true), findsNothing);
    expect(
      find.textContaining('university score', findRichText: true),
      findsNothing,
    );
  });

  testWidgets('creates a typed goal through the production screen action', (
    tester,
  ) async {
    final repository = _Goals([]);
    await tester.pumpWidget(
      MaterialApp(
        home: LearningGoalsScreen(
          useCases: LearningGoalUseCases(
            activeOwnerId: () async => 'synthetic-owner-a',
            repository: repository,
            nowUtc: () => DateTime.utc(2026, 8, 25),
            generateId: () => 'goal:new',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('learning-goals/add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/title')),
      'TOEFL practice target',
    );
    await _selectLocalDateTime(
      tester,
      'learning-goals/deadline',
      '09/01/2026',
      '12',
      '00',
    );

    await tester.tap(find.byKey(const ValueKey('learning-goals/create')));
    await tester.pumpAndSettle();

    expect(repository.goals, hasLength(1));
    expect(repository.goals.single.id, 'goal:new');
    expect(repository.goals.single.kind, LearningGoalKind.languageTest);
    expect(repository.goals.single.title, 'TOEFL practice target');
    expect(repository.goals.single.deadlineAtUtc, DateTime.utc(2026, 9, 1, 5));
    expect(repository.goals.single.timezone.timezoneId, 'Asia/Bangkok');
    expect(repository.goals.single.timezone.utcOffsetMinutes, 420);
    expect(find.text('TOEFL practice target'), findsOneWidget);
  });

  testWidgets('serializes duplicate create taps around one stable command', (
    tester,
  ) async {
    final repository = _BlockingGoals();
    var generatedIds = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: LearningGoalsScreen(
          useCases: LearningGoalUseCases(
            activeOwnerId: () async => 'synthetic-owner-a',
            repository: repository,
            nowUtc: () => DateTime.utc(2026, 8, 25),
            generateId: () => 'goal:${++generatedIds}',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('learning-goals/add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/title')),
      'TOEFL practice target',
    );
    await _selectLocalDateTime(
      tester,
      'learning-goals/deadline',
      '09/01/2026',
      '12',
      '00',
    );

    final create = find.byKey(const ValueKey('learning-goals/create'));
    await tester.tap(create);
    await tester.tap(create);

    await tester.pump();
    expect(repository.saveCalls, 1);
    expect(generatedIds, 1);
    repository.release.complete();
    await tester.pumpAndSettle();

    expect(repository.goals, hasLength(1));
    expect(repository.goals.single.id, 'goal:1');
  });

  testWidgets('reminder child entry is runtime and permission gated', (
    tester,
  ) async {
    final goals = _Goals([
      LearningGoal(
        id: 'goal:ielts',
        kind: LearningGoalKind.languageTest,
        title: 'IELTS practice target',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
        status: LearningGoalStatus.active,
        createdAtUtc: DateTime.utc(2026, 8, 25),
        updatedAtUtc: DateTime.utc(2026, 8, 25),
      ),
    ]);
    final scheduler = _ReminderScheduler();
    final reminderUseCases = StudyReminderUseCases(
      repository: _ReminderRepository(),
      scheduler: scheduler,
      nowUtc: () => DateTime.utc(2026, 8, 25),
      generateId: () => 'reminder:goal:ielts',
    );

    Future<void> pump({required bool enabled}) async {
      await tester.pumpWidget(
        MaterialApp(
          home: LearningGoalsScreen(
            useCases: LearningGoalUseCases(
              activeOwnerId: () async => 'synthetic-owner-a',
              repository: goals,
              nowUtc: () => DateTime.utc(2026, 8, 25),
              generateId: () => 'goal:new',
            ),
            reminderUseCases: reminderUseCases,
            reminderRuntimeEnabled: enabled,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    scheduler.permission = ReminderPermissionState.unknown;
    await pump(enabled: true);
    expect(
      find.byKey(const ValueKey('learning-goal/goal:ielts/reminder')),
      findsOneWidget,
    );

    final open = tester
        .widget<IconButton>(
          find.byKey(const ValueKey('learning-goal/goal:ielts/reminder')),
        )
        .onPressed!;
    open();
    open();
    await tester.pumpAndSettle();
    expect(find.byType(StudyReminderSettingsScreen), findsOneWidget);
    final childGuard = tester
        .widget<StudyReminderSettingsScreen>(
          find.byType(StudyReminderSettingsScreen),
        )
        .mutationAllowed;
    expect(
      childGuard(),
      isTrue,
      reason: 'Owned reminder entry must retain explicit manual authority.',
    );
    Navigator.of(
      tester.element(find.byType(StudyReminderSettingsScreen)),
    ).pop();
    expect(
      childGuard(),
      isFalse,
      reason:
          'A popped reminder must immediately retire its captured authority.',
    );
    await tester.pumpAndSettle();

    await pump(enabled: false);
    expect(
      find.byKey(const ValueKey('learning-goal/goal:ielts/reminder')),
      findsNothing,
    );

    scheduler.permission = ReminderPermissionState.denied;
    await pump(enabled: true);
    expect(
      find.byKey(const ValueKey('learning-goal/goal:ielts/reminder')),
      findsNothing,
    );
  });
}

final class _Goals implements LearningGoalRepository {
  _Goals(this.goals);

  final List<LearningGoal> goals;

  @override
  Future<List<LearningGoal>> list() async => List.of(goals);

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
  }) async {
    goals.removeWhere((candidate) => candidate.id == goal.id);
    goals.add(goal);
  }
}

final class _BlockingGoals implements LearningGoalRepository {
  final List<LearningGoal> goals = [];
  final Completer<void> release = Completer<void>();
  int saveCalls = 0;

  @override
  Future<List<LearningGoal>> list() async => List.of(goals);

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
  }) async {
    saveCalls += 1;
    await release.future;
    goals
      ..removeWhere((candidate) => candidate.id == goal.id)
      ..add(goal);
  }
}

final class _ReminderRepository implements StudyReminderRepository {
  @override
  Future<bool> platformIdentityConflicts(
    String ownerId,
    String reminderId,
  ) async => false;

  final List<StudyReminder> reminders = [];

  @override
  Future<String> activeOwnerId() async => 'owner-a';

  @override
  Future<bool> isOwnerOperationTokenOwned({
    required String operationToken,
    required DateTime nowUtc,
  }) async => false;

  @override
  Future<void> beginOwnerOperationFence({
    required String ownerId,
    required String operationToken,
    required DateTime nowUtc,
  }) async {}

  @override
  Future<bool> isOwnerOperationFenced({
    required String ownerId,
    required DateTime nowUtc,
  }) async => false;

  @override
  Future<void> endOwnerOperationFence({
    required String ownerId,
    required String operationToken,
  }) async {}

  @override
  Future<void> save(
    StudyReminder reminder, {
    StudyReminderMutationGuard? mutationAllowed,
  }) async {
    reminders
      ..removeWhere((candidate) => candidate.id == reminder.id)
      ..add(reminder);
  }

  @override
  Future<List<StudyReminder>> list({bool includeDeleted = false}) async =>
      reminders
          .where((reminder) => includeDeleted || !reminder.isDeleted)
          .toList(growable: false);

  @override
  Future<List<StudyReminderDesiredState>> listForOwner(
    String ownerId, {
    bool includeDeleted = false,
  }) async => reminders
      .where(
        (reminder) =>
            reminder.ownerId == ownerId &&
            (includeDeleted || !reminder.isDeleted),
      )
      .map(
        (reminder) =>
            StudyReminderDesiredState(reminder: reminder, localRevision: 1),
      )
      .toList(growable: false);

  @override
  Future<StudyReminderDesiredState?> desiredState(
    String ownerId,
    String reminderId,
  ) async => reminders
      .where(
        (reminder) => reminder.ownerId == ownerId && reminder.id == reminderId,
      )
      .map(
        (reminder) =>
            StudyReminderDesiredState(reminder: reminder, localRevision: 1),
      )
      .firstOrNull;

  @override
  Future<List<String>> reminderIdsForOwner(String ownerId) async => reminders
      .where((reminder) => reminder.ownerId == ownerId)
      .map((reminder) => reminder.id)
      .toList(growable: false);

  @override
  Future<void> cancel(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  }) async {}

  @override
  Future<void> delete(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  }) async {}

  @override
  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntents() async =>
      const [];

  @override
  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntentsForOwner(
    String ownerId,
  ) async => const [];

  @override
  Future<StudyReminderDesiredState?> resolvePlatformIntent(
    StudyReminderPlatformIntent intent,
  ) async => null;

  @override
  Future<bool> acknowledgePlatformIntent(
    StudyReminderPlatformIntent intent, {
    required DateTime acknowledgedAtUtc,
  }) async => false;

  @override
  Future<void> recordPlatformFailure(
    StudyReminderPlatformIntent intent, {
    required DateTime attemptedAtUtc,
    required String failureCode,
  }) async {}
}

final class _ReminderScheduler implements ReminderScheduler {
  ReminderPermissionState permission = ReminderPermissionState.unknown;

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => true;

  @override
  Future<ReminderPermissionState> permissionState() async => permission;

  @override
  Future<ReminderPermissionState> requestPermission() async => permission;

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async => const [];

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {}

  @override
  Future<void> cancel(int platformId) async {}
}

Future<void> _selectLocalDateTime(
  WidgetTester tester,
  String prefix,
  String date,
  String hour,
  String minute,
) async {
  final dateButton = find.byKey(ValueKey('$prefix/date'));
  await tester.ensureVisible(dateButton);
  await tester.tap(dateButton);
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        )
        .first,
    date,
  );
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey('$prefix/time')));
  await tester.pumpAndSettle();
  final inputs = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(inputs.at(0), hour);
  await tester.enterText(inputs.at(1), minute);
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
}
