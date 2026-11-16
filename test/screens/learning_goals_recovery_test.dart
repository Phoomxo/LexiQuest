import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';

final now = DateTime.utc(2026, 9, 24);
LearningGoal goal() => LearningGoal(
  id: 'goal:recovery',
  kind: LearningGoalKind.personal,
  title: 'Private A goal',
  deadlineAtUtc: DateTime.utc(2026, 10, 1),
  timezone: const LearningGoalTimezoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  status: LearningGoalStatus.active,
  createdAtUtc: now,
  updatedAtUtc: now,
);
LearningGoalUseCases cases(_Goals repo, {Future<String> Function()? owner}) =>
    LearningGoalUseCases(
      repository: repo,
      activeOwnerId: owner ?? () async => 'owner-a',
      nowUtc: () => now,
      generateId: () => 'goal:new',
    );
Widget view(
  LearningGoalUseCases useCases, {
  bool active = true,
  GlobalKey<NavigatorState>? navigator,
}) => MaterialApp(
  navigatorKey: navigator,
  navigatorObservers: [appRouteObserver],
  home: TickerMode(
    enabled: active,
    child: LearningGoalsScreen(useCases: useCases),
  ),
);
Finder key(String value) => find.byKey(ValueKey(value));

void main() {
  additionalTests();
  setUpAll(tz.initializeTimeZones);
  testWidgets(
    'AK immediate and repeated read failures have bounded read-only retry',
    (tester) async {
      final repo = _Goals()
        ..read = () => Future.error(StateError('private read failure'));
      await tester.pumpWidget(view(cases(repo)));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      final retry = key('learning-goals/retry');
      expect(retry, findsOneWidget);
      await tester.tap(retry);
      await tester.pumpAndSettle();
      expect(repo.reads, 2);
      expect(tester.takeException(), isNull);
      final gate = Completer<List<LearningGoal>>();
      repo.read = () => gate.future;
      final callback = tester.widget<FilledButton>(retry).onPressed!;
      callback();
      callback();
      await tester.pump();
      expect(repo.reads, 3);
      gate.complete([goal()]);
      await tester.pumpAndSettle();
      expect(find.text('Private A goal'), findsOneWidget);
      callback();
      await tester.pump();
      expect(repo.reads, 3);
      expect(repo.saves, 0);
    },
  );
  testWidgets('AK owner replacement during list read never displays old list', (
    tester,
  ) async {
    final gate = Completer<List<LearningGoal>>();
    final repo = _Goals()..read = () => gate.future;
    var owner = 'owner-a';
    await tester.pumpWidget(view(cases(repo, owner: () async => owner)));
    await tester.pump();
    owner = 'owner-b';
    gate.complete([goal()]);
    await tester.pumpAndSettle();
    expect(find.text('Private A goal'), findsNothing);
    expect(key('learning-goals/retry'), findsOneWidget);
    expect(repo.saves, 0);
  });
  for (final exit in ['inactive', 'cover', 'pop', 'dispose']) {
    testWidgets('AK captured delete callback is retired on $exit', (
      tester,
    ) async {
      final repo = _Goals();
      final useCases = cases(repo);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          navigatorObservers: [appRouteObserver],
          home: const Scaffold(body: Text('parent')),
        ),
      );
      var active = true;
      late StateSetter change;
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => StatefulBuilder(
            builder: (_, set) {
              change = set;
              return TickerMode(
                enabled: active,
                child: LearningGoalsScreen(useCases: useCases),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final callback = tester
          .widget<IconButton>(key('learning-goal/goal:recovery/delete'))
          .onPressed!;
      switch (exit) {
        case 'inactive':
          change(() => active = false);
          await tester.pump();
        case 'cover':
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pump();
        case 'pop':
          nav.currentState!.pop();
        case 'dispose':
          await tester.pumpWidget(const SizedBox());
      }
      callback();
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(tester.takeException(), isNull);
    });
  }
  testWidgets('AK status selection is single flight until acknowledgement', (
    tester,
  ) async {
    final repo = _Goals()..writeGate = Completer<void>();
    await tester.pumpWidget(view(cases(repo)));
    await tester.pumpAndSettle();
    final menu = tester.widget<PopupMenuButton<LearningGoalStatus>>(
      key('learning-goal/goal:recovery/status'),
    );
    menu.onSelected!(LearningGoalStatus.completed);
    menu.onSelected!(LearningGoalStatus.completed);
    await tester.pump();
    expect(repo.saves, 1);
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
  });
  testWidgets('AK cancelled editor cannot commit after delayed preparation', (
    tester,
  ) async {
    final repo = _Goals();
    Completer<String>? ownerGate;
    await tester.pumpWidget(
      view(
        cases(repo, owner: () => ownerGate?.future ?? Future.value('owner-a')),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goal/goal:recovery/edit'));
    await tester.pumpAndSettle();
    await tester.enterText(key('learning-goals/title'), 'Revised draft');
    ownerGate = Completer<String>();
    await tester.tap(key('learning-goals/save'));
    await tester.pump();
    await tester.tap(
      find.text('ยกเลิก'),
    ); // No animation pump before completion.
    ownerGate!.complete('owner-a');
    await tester.pumpAndSettle();
    expect(repo.saves, 0);
    expect(find.text('Private A goal'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AK failed read fits Thai 360px at 200 percent', (tester) async {
    tester.view.resetPhysicalSize();
    tester.view.physicalSize = const Size(360, 640);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repo = _Goals()..read = () => Future.error(StateError('read'));
    await tester.pumpWidget(
      MaterialApp(
        builder: (_, child) => MediaQuery(
          data: const MediaQueryData(
            size: Size(360, 640),
            textScaler: TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: LearningGoalsScreen(useCases: cases(repo)),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key('learning-goals/retry'), findsOneWidget);
    await tester.ensureVisible(key('learning-goals/retry'));
  });
  test(
    'AK real Drift retires goal and outbox together before commit',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner-a',
        nowUtc: () => now,
      );
      final owner = await owners.getOrCreateActiveOwner();
      final repo = DriftLearningGoalRepository(db, owners: owners);
      var checks = 0;
      await expectLater(
        repo.save(
          goal(),
          expectedOwnerId: owner.id,
          mutationAllowed: () => ++checks == 1,
        ),
        throwsA(isA<LearningGoalMutationUnavailable>()),
      );
      expect(await db.select(db.learningGoals).get(), isEmpty);
      expect(await db.select(db.outboxOperations).get(), isEmpty);
    },
  );
}

class _Goals implements LearningGoalRepository {
  List<LearningGoal> items = [goal()];
  Future<List<LearningGoal>> Function()? read;
  Completer<void>? writeGate;
  int reads = 0, saves = 0;
  bool lostAck = false;
  @override
  Future<List<LearningGoal>> list() {
    reads++;
    return read?.call() ?? Future.value(List.of(items));
  }

  @override
  Future<void> save(
    LearningGoal value, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
  }) async {
    saves++;
    await writeGate?.future;
    if (mutationAllowed?.call() == false)
      throw const LearningGoalMutationUnavailable();
    items = value.isDeleted ? [] : [value];
    if (lostAck) throw StateError('acknowledgement lost');
  }
}

void additionalTests() {
  testWidgets(
    'AK unrelated dialog cover retires pending preparation after return',
    (tester) async {
      final repo = _Goals();
      Completer<String>? gate;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        view(
          cases(repo, owner: () => gate?.future ?? Future.value('owner-a')),
          navigator: nav,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(key('learning-goal/goal:recovery/edit'));
      await tester.pumpAndSettle();
      gate = Completer<String>();
      await tester.tap(key('learning-goals/save'));
      await tester.pump();
      nav.currentState!.push(
        DialogRoute<void>(
          context: tester.element(find.byType(AlertDialog)),
          builder: (_) => const AlertDialog(title: Text('unrelated dialog')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      gate!.complete('owner-a');
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
    },
  );

  testWidgets('AK owner is revalidated after optional context read completes', (
    tester,
  ) async {
    final repo = _Goals();
    var owner = 'owner-a';
    final optional = _DelayedContextOwner();
    await tester.pumpWidget(
      MaterialApp(
        home: LearningGoalsScreen(
          useCases: cases(repo, owner: () async => owner),
          ownerIdentities: optional,
        ),
      ),
    );
    await tester.pump();
    expect(optional.calls, 2);
    owner = 'owner-b';
    optional.after.complete('owner-a');
    await tester.pumpAndSettle();
    expect(find.text('Private A goal'), findsNothing);
    expect(key('learning-goals/retry'), findsOneWidget);
  });

  testWidgets('AK synchronous read error can retry without unhandled failure', (
    tester,
  ) async {
    final repo = _Goals()..read = () => throw StateError('sync read');
    await tester.pumpWidget(view(cases(repo)));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(key('learning-goals/retry'), findsOneWidget);
  });
  testWidgets('AK own status popup and kind picker remain usable', (
    tester,
  ) async {
    final repo = _Goals();
    await tester.pumpWidget(view(cases(repo)));
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goal/goal:recovery/status'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('สำเร็จแล้ว'));
    await tester.pumpAndSettle();
    expect(repo.items.single.status, LearningGoalStatus.completed);
    await tester.tap(key('learning-goal/goal:recovery/edit'));
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goals/kind'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('รายวิชา').last);
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goals/save'));
    await tester.pumpAndSettle();
    expect(repo.items.single.kind, LearningGoalKind.course);
    expect(repo.saves, 2);
  });
  test(
    'AK real Drift update rollback preserves goal revision and outbox',
    () async {
      final db = AppDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      final owners = DriftLocalOwnerRepository(
        db,
        generateId: () => 'owner-a',
        nowUtc: () => now,
      );
      final owner = await owners.getOrCreateActiveOwner();
      final repo = DriftLearningGoalRepository(db, owners: owners);
      await repo.save(goal(), expectedOwnerId: owner.id);
      var checks = 0;
      await expectLater(
        repo.save(
          goal().copyWith(
            title: 'changed',
            updatedAtUtc: now.add(const Duration(seconds: 1)),
          ),
          expectedOwnerId: owner.id,
          mutationAllowed: () => ++checks == 1,
        ),
        throwsA(isA<LearningGoalMutationUnavailable>()),
      );
      final rows = await db.select(db.learningGoals).get();
      expect(rows.single.title, 'Private A goal');
      expect(rows.single.localRevision, 1);
      expect(await db.select(db.outboxOperations).get(), hasLength(1));
    },
  );

  for (final action in ['edit', 'delete', 'status']) {
    testWidgets('AK displayed $action never acts for replacement owner', (
      tester,
    ) async {
      final repo = _Goals();
      var owner = 'owner-a';
      await tester.pumpWidget(view(cases(repo, owner: () async => owner)));
      await tester.pumpAndSettle();
      final button = key('learning-goal/goal:recovery/$action');
      owner = 'owner-b';
      if (action == 'status') {
        tester.widget<PopupMenuButton<LearningGoalStatus>>(button).onSelected!(
          LearningGoalStatus.completed,
        );
      } else {
        tester.widget<IconButton>(button).onPressed!();
      }
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
      expect(find.byType(AlertDialog), findsNothing);
    });
  }
  testWidgets(
    'AK unrelated cover retires pending editor save even after returning',
    (tester) async {
      final repo = _Goals();
      Completer<String>? gate;
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        view(
          cases(repo, owner: () => gate?.future ?? Future.value('owner-a')),
          navigator: nav,
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(key('learning-goal/goal:recovery/edit'));
      await tester.pumpAndSettle();
      gate = Completer<String>();
      await tester.tap(key('learning-goals/save'));
      await tester.pump();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('unrelated')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pump(const Duration(milliseconds: 400));
      gate!.complete('owner-a');
      await tester.pumpAndSettle();
      expect(repo.saves, 0);
    },
  );
  testWidgets('AK late saved acknowledgement never pops unrelated route', (
    tester,
  ) async {
    final repo = _Goals()..writeGate = Completer<void>();
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(view(cases(repo), navigator: nav));
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goal/goal:recovery/edit'));
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goals/save'));
    await tester.pump();
    await tester.tap(find.text('ยกเลิก'));
    await tester.pumpAndSettle();
    nav.currentState!.push(
      MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: Text('unrelated')),
      ),
    );
    await tester.pumpAndSettle();
    repo.writeGate!.complete();
    await tester.pumpAndSettle();
    expect(find.text('unrelated'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('AK uncertain delete acknowledgement reconciles read only', (
    tester,
  ) async {
    final repo = _Goals()..lostAck = true;
    await tester.pumpWidget(view(cases(repo)));
    await tester.pumpAndSettle();
    await tester.tap(key('learning-goal/goal:recovery/delete'));
    await tester.pumpAndSettle();
    expect(repo.saves, 1);
    expect(repo.reads, 2);
    expect(find.text('Private A goal'), findsNothing);
    expect(find.text('ยังไม่ได้กำหนดเป้าหมายการเรียน'), findsOneWidget);
  });
}

class _DelayedContextOwner implements ReviewOwnerIdentityReader {
  int calls = 0;
  final after = Completer<String>();
  @override
  Future<String> requireSingleActiveOwnerId() =>
      ++calls == 1 ? Future.value('owner-a') : after.future;
}
