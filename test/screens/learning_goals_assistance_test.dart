import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';

void main() {
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'goals attach late, hide across owners and refresh after manual disconnected delete',
    (tester) async {
      String? aiOwner;
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      final repo = _Goals()..items.add(_goal());
      await tester.pumpWidget(_view(repo, _Owners(), registry));
      await tester.pumpAndSettle();
      expect(find.text('Practice English'), findsOneWidget);
      expect(registry.snapshot()['context'], isEmpty);
      aiOwner = 'local:goals';
      registry.invalidateSession(preserveContext: true);
      expect(_summary(registry)['count'], 1);
      final item = _values(registry).singleWhere((v) => v['title'] != null);
      expect(item['title'], 'Practice English');
      expect(item['status'], 'active');
      expect(item['deadlineState'], 'future');
      expect(item['days'], 2);
      expect(registry.snapshot()['actions'], isEmpty);
      await tester.tap(
        find.byKey(const ValueKey('learning-goal/goal:test/edit')),
      );
      await tester.pumpAndSettle();
      expect(
        registry.snapshot()['context'],
        isEmpty,
        reason: 'Underlying list is not current while editing dialog is open',
      );
      await tester.tap(find.text('ยกเลิก'));
      await tester.pumpAndSettle();
      expect(_summary(registry)['count'], 1);
      expect(repo.saves, 0);
      aiOwner = 'local:other';
      expect(registry.snapshot()['context'], isEmpty);
      aiOwner = null;
      registry.invalidateSession(preserveContext: true);
      await tester.tap(
        find.byKey(const ValueKey('learning-goal/goal:test/delete')),
      );
      await tester.pumpAndSettle();
      expect(repo.saves, 1);
      expect(find.text('ยังไม่ได้กำหนดเป้าหมายการเรียน'), findsOneWidget);
      aiOwner = 'local:goals';
      registry.invalidateSession(preserveContext: true);
      expect(_summary(registry)['count'], 0);
      expect(_values(registry).any((v) => v['title'] != null), isFalse);
    },
  );
  testWidgets('late previous source cannot rebind replacement owner context', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'local:other');
    final old = _Goals()..pending = Completer<List<LearningGoal>>();
    await tester.pumpWidget(_view(old, _Owners(), registry));
    await tester.pump();
    await tester.pumpWidget(
      _view(_Goals(), _Owners()..id = 'local:other', registry),
    );
    await tester.pumpAndSettle();
    expect(_summary(registry)['count'], 0);
    old.pending!.complete([_goal()]);
    await tester.pumpAndSettle();
    expect(_summary(registry)['count'], 0);
    expect(_values(registry).any((v) => v['title'] != null), isFalse);
    expect(tester.takeException(), isNull);
  });
  testWidgets('pending and failed goals never expose stale personal entries', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'local:goals');
    final repo = _Goals()..pending = Completer<List<LearningGoal>>();
    await tester.pumpWidget(_view(repo, _Owners(), registry));
    await tester.pump();
    expect(_summary(registry)['status'], 'loading');
    repo.pending!.completeError(StateError('private read failure'));
    await tester.pumpAndSettle();
    expect(_summary(registry)['status'], 'unavailable');
    expect(
      registry.snapshot().toString(),
      isNot(contains('private read failure')),
    );
  });
  testWidgets(
    'owner change during read hides personal context while baseline still renders',
    (tester) async {
      final registry = MenuActionRegistry(currentOwner: () => 'local:other');
      final owners = _Owners();
      final repo = _Goals()..pending = Completer<List<LearningGoal>>();
      await tester.pumpWidget(_view(repo, owners, registry));
      await tester.pump();
      owners.id = 'local:other';
      repo.pending!.complete([_goal()]);
      await tester.pumpAndSettle();
      expect(find.text('Practice English'), findsOneWidget);
      expect(registry.snapshot()['context'], isEmpty);
    },
  );
  testWidgets('optional identity failure does not block manual goals', (
    tester,
  ) async {
    final registry = MenuActionRegistry(currentOwner: () => 'local:goals');
    final repo = _Goals()..items.add(_goal());
    await tester.pumpWidget(_view(repo, _Owners()..fail = true, registry));
    await tester.pumpAndSettle();
    expect(find.text('Practice English'), findsOneWidget);
    expect(registry.snapshot()['context'], isEmpty);
    await tester.tap(
      find.byKey(const ValueKey('learning-goal/goal:test/delete')),
    );
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
  });
}

Widget _view(_Goals repo, _Owners owners, MenuActionRegistry registry) =>
    MenuActionScope(
      registry: registry,
      child: MaterialApp(
        home: LearningGoalsScreen(
          ownerIdentities: owners,
          useCases: LearningGoalUseCases(
            repository: repo,
            nowUtc: () => DateTime.utc(2026, 9, 23),
            generateId: () => 'new',
            activeOwnerId: () async => 'local:goals',
          ),
        ),
      ),
    );
List<Map<String, dynamic>> _values(MenuActionRegistry registry) => [
  for (final v in registry.snapshot()['context'] as List)
    jsonDecode(v['value'] as String) as Map<String, dynamic>,
];
Map<String, dynamic> _summary(MenuActionRegistry r) =>
    _values(r).singleWhere((v) => v['screen'] == 'learning-goals');
LearningGoal _goal() => LearningGoal(
  id: 'goal:test',
  kind: LearningGoalKind.personal,
  title: 'Practice English',
  deadlineAtUtc: DateTime.utc(2026, 9, 25),
  timezone: const LearningGoalTimezoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  status: LearningGoalStatus.active,
  createdAtUtc: DateTime.utc(2026, 9, 23),
  updatedAtUtc: DateTime.utc(2026, 9, 23),
);

class _Owners implements ReviewOwnerIdentityReader {
  String id = 'local:goals';
  bool fail = false;
  @override
  Future<String> requireSingleActiveOwnerId() async {
    if (fail) throw StateError('private owner detail');
    return id;
  }
}

class _Goals implements LearningGoalRepository {
  final items = <LearningGoal>[];
  int saves = 0;
  Completer<List<LearningGoal>>? pending;
  @override
  Future<List<LearningGoal>> list() async =>
      pending == null ? List.of(items) : pending!.future;
  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
  }) async {
    if (mutationAllowed?.call() == false) {
      throw const LearningGoalMutationUnavailable();
    }
    items.removeWhere((v) => v.id == goal.id);
    if (!goal.isDeleted) items.add(goal);
    saves++;
  }
}
