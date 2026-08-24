import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
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
