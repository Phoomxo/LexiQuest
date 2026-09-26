import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_definition_codec.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';

void main() {
  setUpAll(timezone_data.initializeTimeZones);

  testWidgets(
    'AG notification just after uncover does not duplicate reactivation read',
    (tester) async {
      final repo = _QuestRepositoryFake();
      final quest = _useCases(repo);
      addTearDown(quest.dispose);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: QuestStatusScreen(quest: quest),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(repo.readCalls, 2);
    },
  );

  testWidgets(
    'AG initially inactive tab reads once after activation with replacement',
    (tester) async {
      final repo = _QuestRepositoryFake();
      final nextRepo = _QuestRepositoryFake();
      final quest = _useCases(repo);
      final next = _useCases(nextRepo);
      addTearDown(quest.dispose);
      addTearDown(next.dispose);
      Widget app(bool active, QuestUseCases q) => MaterialApp(
        home: TickerMode(
          enabled: active,
          child: QuestStatusScreen(quest: q),
        ),
      );
      await tester.pumpWidget(app(false, quest));
      await tester.pumpAndSettle();
      await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(repo.readCalls, 0);
      await tester.pumpWidget(app(true, next));
      await tester.pumpAndSettle();
      expect(repo.readCalls, 0);
      expect(nextRepo.readCalls, 1);
    },
  );

  for (final failOld in [false, true]) {
    testWidgets(
      'AG old completion after reactivation cannot release pending guard fail=$failOld',
      (tester) async {
        final old = Completer<List<QuestInstance>>();
        final latest = Completer<List<QuestInstance>>();
        final repo = _QuestRepositoryFake()..pending = old;
        final quest = _useCases(repo);
        addTearDown(quest.dispose);
        Widget app(bool active) => MaterialApp(
          home: TickerMode(
            enabled: active,
            child: QuestStatusScreen(quest: quest),
          ),
        );
        await tester.pumpWidget(app(true));
        await tester.pump();
        await tester.pumpWidget(app(false));
        repo.pending = latest;
        await tester.pumpWidget(app(true));
        await tester.pump();
        expect(repo.readCalls, 2);
        if (failOld) {
          old.completeError(StateError('retired'));
        } else {
          old.complete([_instance(QuestInstanceState.active, 'retired')]);
        }
        await tester.pump();
        await quest.refreshDaily(expectedOwnerId: 'owner-secret');
        await tester.pump();
        expect(repo.readCalls, 2);
        expect(find.text('กำลังทำ'), findsNothing);
        repo.pending = null;
        repo.instances = [_instance(QuestInstanceState.completed, 'fresh')];
        latest.complete(const []);
        await tester.pumpAndSettle();
        expect(repo.readCalls, 3);
        expect(find.text('สำเร็จแล้ว'), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'AG retry is bounded and retired after immediate repeated failure',
    (tester) async {
      final repo = _QuestRepositoryFake()..failure = StateError('private');
      final quest = _useCases(repo);
      addTearDown(quest.dispose);
      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: quest)),
      );
      await tester.pumpAndSettle();
      final retry = tester
          .widget<QuestStatusFailure>(find.byType(QuestStatusFailure))
          .onRetry!;
      retry();
      retry();
      await tester.pumpAndSettle();
      expect(repo.readCalls, 2);
      retry();
      await tester.pumpAndSettle();
      expect(repo.readCalls, 2, reason: 'old failed-view callback retired');
      repo.failure = null;
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.byType(QuestStatusEmpty), findsOneWidget);
      expect(repo.readCalls, 3);
      expect(repo.lastLimit, 50);
      expect(repo.mutations, 0);
      expect(tester.takeException(), isNull);
    },
  );

  for (final retirement in [
    'replacement',
    'dispose',
    'pop',
    'covered',
    'tab',
  ]) {
    testWidgets('AG stale retry cannot read after $retirement', (tester) async {
      final repo = _QuestRepositoryFake()..failure = StateError('private');
      final nextRepo = _QuestRepositoryFake();
      final quest = _useCases(repo);
      final nextQuest = _useCases(nextRepo);
      addTearDown(quest.dispose);
      addTearDown(nextQuest.dispose);
      final nav = GlobalKey<NavigatorState>();
      Widget page(QuestUseCases q, {bool active = true}) => TickerMode(
        enabled: active,
        child: QuestStatusScreen(key: const ValueKey('stable'), quest: q),
      );
      if (retirement == 'pop') {
        await tester.pumpWidget(
          MaterialApp(
            navigatorKey: nav,
            home: const Scaffold(body: Text('parent')),
          ),
        );
        nav.currentState!.push(
          MaterialPageRoute<void>(builder: (_) => page(quest)),
        );
      } else {
        await tester.pumpWidget(
          MaterialApp(navigatorKey: nav, home: page(quest)),
        );
      }
      await tester.pumpAndSettle();
      final retry = tester
          .widget<QuestStatusFailure>(find.byType(QuestStatusFailure))
          .onRetry!;
      switch (retirement) {
        case 'replacement':
          await tester.pumpWidget(
            MaterialApp(navigatorKey: nav, home: page(nextQuest)),
          );
          await tester.pumpAndSettle();
        case 'dispose':
          await tester.pumpWidget(const SizedBox.shrink());
        case 'pop':
          nav.currentState!
              .pop(); // callback must retire before exit animation/disposal
        case 'covered':
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
        case 'tab':
          await tester.pumpWidget(
            MaterialApp(navigatorKey: nav, home: page(quest, active: false)),
          );
          await tester.pumpAndSettle();
      }
      retry();
      await tester.pumpAndSettle();
      expect(repo.readCalls, 1);
      expect(nextRepo.readCalls, retirement == 'replacement' ? 1 : 0);
      expect(repo.mutations, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox.shrink());
    });
  }

  testWidgets(
    'AG durable notifications coalesce during a pending read then load fresh status',
    (tester) async {
      final pending = Completer<List<QuestInstance>>();
      final repo = _QuestRepositoryFake()..pending = pending;
      final quest = _useCases(repo);
      addTearDown(quest.dispose);
      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: quest)),
      );
      await tester.pump();
      for (var i = 0; i < 3; i++) {
        await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      }
      await tester.pump();
      expect(
        repo.readCalls,
        1,
        reason: 'notifications must not overlap the pending read',
      );
      repo.pending = null;
      repo.instances = [_instance(QuestInstanceState.completed, 'fresh')];
      final mutations =
          repo.mutations; // scheduling above is the external durable authority
      pending.complete([_instance(QuestInstanceState.active, 'old')]);
      await tester.pumpAndSettle();
      expect(
        repo.readCalls,
        2,
        reason: 'one trailing read preserves notifications',
      );
      expect(find.text('สำเร็จแล้ว'), findsOneWidget);
      expect(find.text('กำลังทำ'), findsNothing);
      expect(repo.mutations, mutations, reason: 'UI performs reads only');
    },
  );

  for (final hidden in ['tab', 'covered']) {
    testWidgets('AG notification while $hidden waits for reactivation', (
      tester,
    ) async {
      final repo = _QuestRepositoryFake();
      final quest = _useCases(repo);
      addTearDown(quest.dispose);
      final nav = GlobalKey<NavigatorState>();
      Widget app(bool active) => MaterialApp(
        navigatorKey: nav,
        home: TickerMode(
          enabled: active,
          child: QuestStatusScreen(quest: quest),
        ),
      );
      await tester.pumpWidget(app(true));
      await tester.pumpAndSettle();
      if (hidden == 'tab') {
        await tester.pumpWidget(app(false));
      } else {
        nav.currentState!.push(
          MaterialPageRoute<void>(
            builder: (_) => const Scaffold(body: Text('cover')),
          ),
        );
      }
      await tester.pumpAndSettle();
      await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(repo.readCalls, 1);
      repo.instances = [_instance(QuestInstanceState.completed, 'fresh')];
      final mutations = repo.mutations;
      if (hidden == 'tab') {
        await tester.pumpWidget(app(true));
      } else {
        nav.currentState!.pop();
      }
      await tester.pumpAndSettle();
      expect(repo.readCalls, 2);
      expect(find.text('สำเร็จแล้ว'), findsOneWidget);
      expect(repo.mutations, mutations);
    });
  }

  testWidgets(
    'AG late obsolete failure cannot trigger queued reads after replacement',
    (tester) async {
      final pending = Completer<List<QuestInstance>>();
      final repo = _QuestRepositoryFake()..pending = pending;
      final quest = _useCases(repo);
      final nextRepo = _QuestRepositoryFake();
      final next = _useCases(nextRepo);
      addTearDown(quest.dispose);
      addTearDown(next.dispose);
      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: quest)),
      );
      await tester.pump();
      await quest.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: next)),
      );
      await tester.pumpAndSettle();
      pending.completeError(StateError('retired'));
      await tester.pumpAndSettle();
      expect(repo.readCalls, 1);
      expect(nextRepo.readCalls, 1);
      expect(find.byType(QuestStatusEmpty), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'AG owner change during status read remains failed and read only',
    (tester) async {
      final pending = Completer<List<QuestInstance>>();
      final repo = _QuestRepositoryFake()..pending = pending;
      final owners = _OwnerFake();
      final quest = QuestUseCases(
        repository: repo,
        owners: owners,
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 8, 11),
        timezoneId: 'Asia/Bangkok',
      );
      addTearDown(quest.dispose);
      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: quest)),
      );
      await tester.pump();
      owners.current = LocalOwner(
        id: 'other',
        createdAtUtc: DateTime.utc(2026),
      );
      pending.complete([_instance(QuestInstanceState.active, 'old-owner')]);
      await tester.pumpAndSettle();
      expect(find.byType(QuestStatusFailure), findsOneWidget);
      expect(find.text('กำลังทำ'), findsNothing);
      expect(repo.mutations, 0);
    },
  );

  testWidgets(
    'AG Thai failure scrolls at 360px and 200 percent with semantic retry',
    (tester) async {
      tester.view.physicalSize = const Size(360, 220);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = _QuestRepositoryFake()
        ..failure = StateError('private-error');
      final quest = _useCases(repo);
      addTearDown(quest.dispose);
      final semantics = tester.ensureSemantics();
      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: const TextScaler.linear(2)),
            child: child!,
          ),
          home: QuestStatusScreen(quest: quest),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      await tester.ensureVisible(find.text('ลองใหม่'));
      expect(
        tester.getSemantics(find.widgetWithText(FilledButton, 'ลองใหม่')),
        matchesSemantics(
          label: 'ลองใหม่',
          isButton: true,
          hasTapAction: true,
          hasEnabledState: true,
          isEnabled: true,
          isFocusable: true,
          hasFocusAction: true,
        ),
      );
      expect(find.textContaining('private-error'), findsNothing);
      repo.failure = null;
      await tester.tap(find.text('ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.byType(QuestStatusEmpty), findsOneWidget);
      semantics.dispose();
    },
  );

  testWidgets('visible quest page reloads Day2 after durable refresh completes', (
    tester,
  ) async {
    final database = db.AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement(
      "INSERT INTO local_owners (id,account_state,created_at_utc_ms,is_active) VALUES ('owner-secret','localGuest',1,1)",
    );
    var clock = DateTime.utc(2026, 8, 4, 10);
    var ids = 0;
    final subject = QuestUseCases(
      repository: DriftQuestRepository(database),
      owners: _OwnerFake(),
      generateId: () => 'visible-${++ids}',
      nowUtc: () => clock,
      timezoneId: 'Asia/Bangkok',
    );
    addTearDown(subject.dispose);
    await subject.refreshDaily(expectedOwnerId: 'owner-secret');
    String? aiOwner = 'owner-secret';
    final registry = MenuActionRegistry(currentOwner: () => aiOwner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(home: QuestStatusScreen(quest: subject)),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    final context = registry.snapshot()['context'] as List;
    final data = jsonDecode(context.single['value'] as String);
    expect(data['state'], 'active');
    expect(data['definitionAvailable'], true);
    expect(data['rewardMeaning'], 'conditional-not-earned-balance');
    expect(data['progress'], isNotEmpty);
    expect(registry.snapshot()['actions'], isEmpty);
    aiOwner = 'other';
    expect(registry.snapshot()['context'], isEmpty);
    aiOwner = 'owner-secret';

    expect(find.text('ทำได้ในครั้งถัดไป'), findsNothing);
    clock = clock.add(const Duration(days: 1));
    await subject.refreshDaily(expectedOwnerId: 'owner-secret');
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(find.text('ทำได้ในครั้งถัดไป'), findsOneWidget);
    expect(await database.select(database.questInstances).get(), hasLength(2));
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets(
    'refresh listeners detach on quest replacement and page disposal',
    (tester) async {
      final firstRepo = _QuestRepositoryFake();
      final secondRepo = _QuestRepositoryFake();
      final first = _useCases(firstRepo);
      final second = _useCases(secondRepo);
      await tester.pumpWidget(
        MaterialApp(
          home: QuestStatusScreen(
            key: const ValueKey('same-page'),
            quest: first,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.pumpWidget(
        MaterialApp(
          home: QuestStatusScreen(
            key: const ValueKey('same-page'),
            quest: second,
          ),
        ),
      );
      await tester.pumpAndSettle();
      final oldReads = firstRepo.readCalls;
      final newReads = secondRepo.readCalls;
      await first.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(firstRepo.readCalls, oldReads);
      expect(secondRepo.readCalls, newReads);
      await second.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(secondRepo.readCalls, newReads + 1);
      await tester.pumpWidget(const SizedBox.shrink());
      final disposedReads = secondRepo.readCalls;
      await second.refreshDaily(expectedOwnerId: 'owner-secret');
      await tester.pumpAndSettle();
      expect(secondRepo.readCalls, disposedReads);
      expect(tester.takeException(), isNull);
      first.dispose();
      second.dispose();
    },
  );

  for (final disposePage in [false, true]) {
    testWidgets(
      'old pending status future cannot replace a retired view disposed=$disposePage',
      (tester) async {
        final pending = Completer<List<QuestInstance>>();
        final oldRepo = _QuestRepositoryFake()..pending = pending;
        final oldQuest = _useCases(oldRepo);
        final newRepo = _QuestRepositoryFake()
          ..instances = [
            _instance(QuestInstanceState.completed, 'new-owner-state'),
          ];
        final newQuest = _useCases(newRepo);
        await tester.pumpWidget(
          MaterialApp(
            home: QuestStatusScreen(
              key: const ValueKey('stable-status'),
              quest: oldQuest,
            ),
          ),
        );
        await tester.pump();
        expect(find.byType(QuestStatusLoading), findsOneWidget);
        await tester.pumpWidget(
          disposePage
              ? const SizedBox.shrink()
              : MaterialApp(
                  home: QuestStatusScreen(
                    key: const ValueKey('stable-status'),
                    quest: newQuest,
                  ),
                ),
        );
        await tester.pumpAndSettle();
        pending.complete([
          _instance(QuestInstanceState.active, 'retired-owner-state'),
        ]);
        await tester.pumpAndSettle();
        expect(find.text('กำลังทำ'), findsNothing);
        expect(
          find.text('สำเร็จแล้ว'),
          disposePage ? findsNothing : findsOneWidget,
        );
        expect(oldRepo.readCalls, 1);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox.shrink());
        oldQuest.dispose();
        newQuest.dispose();
      },
    );
  }

  testWidgets('quest shows its pinned authored goal and objective progress', (
    tester,
  ) async {
    final repository = _QuestRepositoryFake()
      ..definition = QuestDefinition(
        questId: 'quest-secret',
        catalogVersion: 1,
        title: 'ภารกิจคำศัพท์ที่กำหนด',
        description: 'ตอบคำถามตามเป้าหมายที่บันทึกไว้',
        type: QuestType.daily,
        objectives: [
          QuestObjective(
            objectiveId: 'objective-secret',
            description: 'คำตอบถูก',
            targetCount: 2,
            criteria: ObjectiveCriteria(eventType: 'QuizCompleted'),
          ),
        ],
        reward: RewardSpec(xpAmount: 8),
      );
    repository.instances = [
      _instance(
        QuestInstanceState.active,
        'instance-one',
        definition: repository.definition,
      ),
    ];
    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();
    expect(find.text('ภารกิจคำศัพท์ที่กำหนด'), findsOneWidget);
    expect(find.text('ตอบคำถามตามเป้าหมายที่บันทึกไว้'), findsOneWidget);
    expect(find.textContaining('คำตอบถูก'), findsOneWidget);
    expect(find.textContaining('1 จาก 2'), findsOneWidget);
    expect(repository.mutations, 0);
  });

  testWidgets('failed quest load retries only the read', (tester) async {
    final repository = _QuestRepositoryFake()
      ..failure = StateError('synthetic');
    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();
    repository.failure = null;
    await tester.tap(find.text('ลองใหม่'));
    await tester.pumpAndSettle();
    expect(find.byType(QuestStatusEmpty), findsOneWidget);
    expect(repository.readCalls, 2);
    expect(repository.mutations, 0);
  });
  testWidgets(
    'loads exactly once with limit 50 and renders loading then empty',
    (tester) async {
      final repository = _QuestRepositoryFake();
      final pending = Completer<List<QuestInstance>>();
      repository.pending = pending;

      await tester.pumpWidget(
        MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
      );
      await tester.pump();

      expect(find.byType(QuestStatusLoading), findsOneWidget);
      expect(repository.readCalls, 1);
      expect(repository.lastLimit, 50);

      await tester.pump();
      expect(repository.readCalls, 1);

      pending.complete(const []);
      await tester.pump();
      expect(find.byType(QuestStatusEmpty), findsOneWidget);
      expect(repository.readCalls, 1);
    },
  );

  testWidgets('renders all lifecycle states without internal identifiers', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final repository = _QuestRepositoryFake()
      ..instances = [
        _instance(QuestInstanceState.active, 'instance-active-secret'),
        _instance(QuestInstanceState.completed, 'instance-done-secret'),
        _instance(QuestInstanceState.expired, 'instance-expired-secret'),
        _instance(QuestInstanceState.abandoned, 'instance-abandoned-secret'),
      ];

    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();

    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(find.text('สำเร็จแล้ว'), findsOneWidget);
    expect(find.text('ทำได้ในครั้งถัดไป'), findsOneWidget);
    expect(find.text('พักไว้'), findsOneWidget);
    expect(find.text('ความคืบหน้าที่บันทึกไว้: 1 จาก 2'), findsNWidgets(4));

    final renderedText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .join('|');
    for (final internalValue in <String>[
      'owner-secret',
      'quest-secret',
      'instance-active-secret',
      'instance-done-secret',
      'instance-expired-secret',
      'instance-abandoned-secret',
      'objective-secret',
      'source-event-secret',
    ]) {
      expect(renderedText, isNot(contains(internalValue)));
    }
    expect(find.byType(FilledButton), findsNothing);
    expect(find.byType(ElevatedButton), findsNothing);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(find.byType(TextButton), findsNothing);
    expect(find.textContaining('lost'), findsNothing);
    expect(find.textContaining('failed'), findsNothing);
    expect(find.textContaining('XP'), findsNothing);
    expect(find.textContaining('Coins'), findsNothing);
  });

  testWidgets('renders typed failure with a read-only retry affordance', (
    tester,
  ) async {
    final repository = _QuestRepositoryFake()
      ..failure = StateError('database-secret');

    await tester.pumpWidget(
      MaterialApp(home: QuestStatusScreen(quest: _useCases(repository))),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QuestStatusFailure), findsOneWidget);
    expect(find.textContaining('database-secret'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('ลองใหม่'), findsOneWidget);
    expect(repository.readCalls, 1);
  });

  testWidgets('missing quest dependency is a typed unavailable state', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuestStatusScreen()));
    await tester.pump();

    expect(find.byType(QuestStatusUnavailable), findsOneWidget);
  });

  testWidgets('reloads once when the mounted quest dependency changes', (
    tester,
  ) async {
    final repositoryA = _QuestRepositoryFake()
      ..instances = [_instance(QuestInstanceState.active, 'owner-a-instance')];
    final repositoryB = _QuestRepositoryFake()
      ..instances = [
        _instance(QuestInstanceState.completed, 'owner-b-instance'),
      ];

    await tester.pumpWidget(
      MaterialApp(
        home: QuestStatusScreen(
          key: const ValueKey<String>('quest-status'),
          quest: _useCases(repositoryA),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('กำลังทำ'), findsOneWidget);
    expect(repositoryA.readCalls, 1);

    await tester.pumpWidget(
      MaterialApp(
        home: QuestStatusScreen(
          key: const ValueKey<String>('quest-status'),
          quest: _useCases(repositoryB),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('สำเร็จแล้ว'), findsOneWidget);
    expect(find.text('กำลังทำ'), findsNothing);
    expect(repositoryA.readCalls, 1);
    expect(repositoryB.readCalls, 1);
    expect(repositoryB.lastLimit, 50);
  });
}

QuestUseCases _useCases(_QuestRepositoryFake repository) {
  return QuestUseCases(
    repository: repository,
    owners: _OwnerFake(),
    generateId: () => 'unused',
    nowUtc: () => DateTime.utc(2026, 8, 11),
    timezoneId: 'Asia/Bangkok',
  );
}

QuestInstance _instance(
  QuestInstanceState state,
  String instanceId, {
  QuestDefinition? definition,
}) {
  return QuestInstance(
    instanceId: instanceId,
    questId: 'quest-secret',
    ownerId: 'owner-secret',
    catalogVersion: 1,
    assignedAtUtc: DateTime.utc(2026, 8, 10),
    state: state,
    definitionSnapshot: definition == null
        ? null
        : QuestDefinitionSnapshot(
            definition: definition,
            origin: QuestDefinitionSnapshotOrigin.capturedAssignment,
          ),
    progress: const [
      ObjectiveProgress(
        objectiveId: 'objective-secret',
        currentCount: 1,
        targetCount: 2,
        sourceEventIds: ['source-event-secret'],
      ),
    ],
  );
}

final class _OwnerFake implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'owner-secret',
    createdAtUtc: DateTime.utc(2026, 8, 1),
  );

  LocalOwner current = owner;

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => current;

  @override
  Future<LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) async => owner;
}

final class _QuestRepositoryFake implements QuestRepository {
  @override
  Future<bool> assignForPeriod({
    required QuestDefinition definition,
    required QuestInstance instance,
    required DateTime nowUtc,
  }) async {
    mutations++;
    return false;
  }

  @override
  Future<void> expireStaleInstances({
    required String ownerId,
    required DateTime nowUtc,
  }) async {
    mutations++;
  }

  @override
  Future<List<QuestInstance>> getProjectionCandidates({
    required String ownerId,
    required DateTime occurredAtUtc,
    required Iterable<String> questIds,
  }) async => instances
      .where(
        (instance) =>
            instance.ownerId == ownerId &&
            instance.isCanonical &&
            questIds.contains(instance.questId) &&
            (instance.state == QuestInstanceState.active ||
                instance.state == QuestInstanceState.expired) &&
            !occurredAtUtc.isBefore(instance.assignedAtUtc) &&
            (instance.period?.deadlineAtUtc == null ||
                occurredAtUtc.isBefore(instance.period!.deadlineAtUtc!)),
      )
      .toList(growable: false);
  QuestDefinition? definition;
  int mutations = 0;
  List<QuestInstance> instances = const [];
  Completer<List<QuestInstance>>? pending;
  Object? failure;
  int readCalls = 0;
  int? lastLimit;

  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) async {
    readCalls += 1;
    lastLimit = limit;
    final error = failure;
    if (error != null) throw error;
    final wait = pending;
    if (wait != null) return wait.future;
    return instances;
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) async =>
      instances
          .where((instance) => instance.state == QuestInstanceState.active)
          .toList(growable: false);

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) async => const [];

  @override
  Future<QuestDefinition?> getDefinition(String questId) async => definition;

  @override
  Future<void> markAbandoned(String instanceId) async {
    mutations++;
  }

  @override
  Future<void> markCompleted(String instanceId, DateTime completedAtUtc) async {
    mutations++;
  }

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) async {
    mutations++;
  }

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {
    mutations++;
  }

  @override
  Future<void> startInstance(QuestInstance instance) async {
    mutations++;
  }

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {
    mutations++;
  }
}
