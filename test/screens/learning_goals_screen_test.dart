import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/reminders/application/study_reminder_use_cases.dart';
import 'package:vocab_learning_app/features/reminders/domain/reminder_scheduler.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder_repository.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';

void main() {
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
    expect(find.textContaining('days'), findsOneWidget);
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
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/deadline')),
      '2026-09-01T05:00:00Z',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/timezone')),
      'Asia/Bangkok',
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
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/deadline')),
      '2026-09-01T05:00:00Z',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/timezone')),
      'Asia/Bangkok',
    );
    final create = find.byKey(const ValueKey('learning-goals/create'));
    await tester.tap(create);
    await tester.tap(create);

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
  }) async {
    saveCalls += 1;
    await release.future;
    goals
      ..removeWhere((candidate) => candidate.id == goal.id)
      ..add(goal);
  }
}

final class _ReminderRepository implements StudyReminderRepository {
  final List<StudyReminder> reminders = [];

  @override
  Future<String> activeOwnerId() async => 'owner-a';

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
