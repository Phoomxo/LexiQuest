import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_study_preferences_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/study_preferences.dart';

void main() {
  final now = DateTime.utc(2026, 11, 14, 12);
  late AppDatabase db;
  late DriftStudyPreferencesRepository repository;
  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    repository = DriftStudyPreferencesRepository(db, nowUtc: () => now);
    await db.customStatement(
      "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1),('owner-b','localGuest',1,0)",
    );
  });
  tearDown(() => db.close());

  test('empty read is noncreating and skipping remains distinct', () async {
    final initial = await repository.load(ownerId: 'owner-a');
    expect(initial.onboardingState, OnboardingState.unset);
    expect(initial.goalState, GoalState.unset);
    expect(await db.select(db.learningPreferences).get(), isEmpty);
    final skipped = await repository.saveLearning(
      expectedOwnerId: 'owner-a',
      expected: initial,
      onboardingState: OnboardingState.skipped,
    );
    expect(skipped.onboardingState, OnboardingState.skipped);
    expect(skipped.purpose, isNull);
    expect(
      (await repository.load(ownerId: 'owner-a')).onboardingState,
      OnboardingState.skipped,
    );
    expect(await db.select(db.outboxOperations).get(), isEmpty);
    expect(await db.select(db.eventsV2).get(), isEmpty);
  });

  test('separate goal and learning changes reject stale snapshots', () async {
    final initial = await repository.load(ownerId: 'owner-a');
    final configured = await repository.saveLearning(
      expectedOwnerId: 'owner-a',
      expected: initial,
      onboardingState: OnboardingState.completed,
      purpose: StudyPurpose.travel,
      plannedMinutes: 5,
      method: StudyMethod.reading,
    );
    final retry = await repository.saveLearning(
      expectedOwnerId: 'owner-a',
      expected: initial,
      onboardingState: OnboardingState.completed,
      purpose: StudyPurpose.travel,
      plannedMinutes: 5,
      method: StudyMethod.reading,
    );
    expect(retry.updatedAtUtcMs, configured.updatedAtUtcMs);
    final raw = await db.select(db.learningPreferences).getSingle();
    expect((raw.purpose, raw.learningMethod), ('travel', 'read'));
    final goal = await repository.setGoal(
      expectedOwnerId: 'owner-a',
      expected: configured,
      civilDate: DateTime.utc(2026, 11, 20),
    );
    final goalRetry = await repository.setGoal(
      expectedOwnerId: 'owner-a',
      expected: configured,
      civilDate: DateTime.utc(2026, 11, 20),
    );
    expect(goalRetry.updatedAtUtcMs, goal.updatedAtUtcMs);
    expect(
      (
        goal.purpose,
        goal.plannedMinutes,
        goal.method,
        goal.goalState,
        goal.goalCivilDate,
      ),
      (
        StudyPurpose.travel,
        5,
        StudyMethod.reading,
        GoalState.active,
        DateTime.utc(2026, 11, 20),
      ),
    );
    await expectLater(
      repository.saveLearning(
        expectedOwnerId: 'owner-a',
        expected: configured,
        onboardingState: OnboardingState.completed,
        purpose: StudyPurpose.travel,
        plannedMinutes: 5,
        method: StudyMethod.speaking,
      ),
      throwsStateError,
    );
    final moved = await repository.setGoal(
      expectedOwnerId: 'owner-a',
      expected: goal,
      civilDate: DateTime.utc(2026, 11, 27),
    );
    final closed = await repository.closeGoal(
      expectedOwnerId: 'owner-a',
      expected: moved,
    );
    final closeRetry = await repository.closeGoal(
      expectedOwnerId: 'owner-a',
      expected: moved,
    );
    expect(closeRetry.updatedAtUtcMs, closed.updatedAtUtcMs);
    expect(closed.goalState, GoalState.closed);
    expect(closed.goalCivilDate, DateTime.utc(2026, 11, 27));
    final edited = await repository.saveLearning(
      expectedOwnerId: 'owner-a',
      expected: closed,
      onboardingState: OnboardingState.completed,
      purpose: StudyPurpose.travel,
      plannedMinutes: 5,
      method: StudyMethod.speaking,
    );
    expect(
      (edited.method, edited.goalState, edited.goalCivilDate),
      (StudyMethod.speaking, GoalState.closed, DateTime.utc(2026, 11, 27)),
    );
    expect(await db.select(db.outboxOperations).get(), isEmpty);
    expect(await db.select(db.answerAttempts).get(), isEmpty);
    expect(await db.select(db.pointsLedgerEntries).get(), isEmpty);
  });

  test('inactive owner and malformed choices fail without writing', () async {
    final initial = await repository.load(ownerId: 'owner-a');
    await expectLater(
      repository.saveLearning(
        expectedOwnerId: 'owner-b',
        expected: initial,
        onboardingState: OnboardingState.skipped,
      ),
      throwsStateError,
    );
    await expectLater(
      repository.saveLearning(
        expectedOwnerId: 'owner-a',
        expected: initial,
        onboardingState: OnboardingState.completed,
        plannedMinutes: 0,
      ),
      throwsArgumentError,
    );
    await expectLater(
      repository.setGoal(
        expectedOwnerId: 'owner-a',
        expected: initial,
        civilDate: DateTime.utc(2026, 11, 20, 1),
      ),
      throwsArgumentError,
    );
    expect(await db.select(db.learningPreferences).get(), isEmpty);
  });

  test('unknown stored purpose is unavailable and retained unchanged', () async {
    await db.customStatement(
      "INSERT INTO learning_preferences (owner_id,onboarding_state,purpose,goal_state,updated_at_utc_ms) VALUES ('owner-a','completed','work','unset',5)",
    );
    final before = await db.select(db.learningPreferences).getSingle();
    await expectLater(repository.load(ownerId: 'owner-a'), throwsStateError);
    expect(await db.select(db.learningPreferences).getSingle(), before);
    expect(await db.select(db.outboxOperations).get(), isEmpty);
  });

  test('closed goal and learning choice survive file reopen', () async {
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-study-preferences-',
    );
    final file = File(
      '${directory.path}${Platform.pathSeparator}synthetic.sqlite',
    );
    var local = AppDatabase(NativeDatabase(file));
    try {
      await local.customStatement(
        "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-a','localGuest',1,1)",
      );
      var repo = DriftStudyPreferencesRepository(local, nowUtc: () => now);
      final initial = await repo.load(ownerId: 'owner-a');
      final configured = await repo.saveLearning(
        expectedOwnerId: 'owner-a',
        expected: initial,
        onboardingState: OnboardingState.completed,
        purpose: StudyPurpose.travel,
        plannedMinutes: 5,
        method: StudyMethod.speaking,
      );
      final goal = await repo.setGoal(
        expectedOwnerId: 'owner-a',
        expected: configured,
        civilDate: DateTime.utc(2026, 11, 27),
      );
      await repo.closeGoal(expectedOwnerId: 'owner-a', expected: goal);
      await local.close();
      local = AppDatabase(NativeDatabase(file));
      repo = DriftStudyPreferencesRepository(local, nowUtc: () => now);
      final reopened = await repo.load(ownerId: 'owner-a');
      expect(
        (
          reopened.purpose,
          reopened.plannedMinutes,
          reopened.method,
          reopened.goalState,
          reopened.goalCivilDate,
        ),
        (
          StudyPurpose.travel,
          5,
          StudyMethod.speaking,
          GoalState.closed,
          DateTime.utc(2026, 11, 27),
        ),
      );
    } finally {
      await local.close();
      final temp = await Directory.systemTemp.resolveSymbolicLinks();
      final actual = await directory.resolveSymbolicLinks();
      expect(
        actual.startsWith(
          '$temp${Platform.pathSeparator}lexiquest-study-preferences-',
        ),
        isTrue,
      );
      await directory.delete(recursive: true);
    }
  });
}
