import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/motivation/presentation/quest_screen.dart';
import 'package:vocab_learning_app/features/motivation/presentation/today_motivation_panel.dart';
import 'package:vocab_learning_app/features/quest/application/quest_catalog_provider.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );
  for (final dark in [false, true]) {
    testWidgets(
      'Quest review is reachable at 320px 200 percent ${dark ? 'dark' : 'light'} with keyboard',
      (tester) async {
        final fixture = await tester.runAsync(() => _UiFixture.open());
        addTearDown(() => _close(tester, fixture!));
        tester.view.physicalSize = const Size(320, 900);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final semantics = tester.ensureSemantics();
        try {
          final before = await tester.runAsync(
            () => fixture!.h.storage.snapshot(),
          );
          await tester.pumpWidget(
            _app(
              QuestScreen(
                runtime: fixture!.runtime,
                ownerId: configuredOwnerId,
              ),
              dark: dark,
              scale: 2,
            ),
          );
          await _ready(tester, 'quest-review-freeze');
          expect(tester.takeException(), isNull);
          expect(find.text('ภารกิจและวันพัก'), findsOneWidget);
          await _keyboardActivate(tester, 'quest-review-freeze');
          await _wait(
            tester,
            () => find
                .byKey(const ValueKey('quest-freeze-review'))
                .evaluate()
                .isNotEmpty,
          );
          expect(find.textContaining('2026-10-27'), findsWidgets);
          expect(find.text('ยืนยันใช้ 1 สิทธิ์'), findsOneWidget);
          expect(
            await _real(tester, () => fixture.h.storage.snapshot()),
            before,
          );
          final cancel = find.widgetWithText(TextButton, 'ยกเลิกคำขอนี้');
          await _reveal(tester, cancel);
          await tester.tap(cancel);
          await tester.pump(const Duration(milliseconds: 16));
          await _ready(tester, 'quest-review-freeze');
          expect(
            await _real(tester, () => fixture.h.storage.snapshot()),
            before,
          );
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
        }
      },
    );
  }

  testWidgets(
    'protection retries the same committed intent after a lost acknowledgement',
    (tester) async {
      final fixture = await tester.runAsync(() => _UiFixture.open());
      addTearDown(() => _close(tester, fixture!));
      await tester.pumpWidget(
        _app(
          QuestScreen(runtime: fixture!.runtime, ownerId: configuredOwnerId),
        ),
      );
      await _tap(tester, 'quest-review-freeze');
      await _ready(tester, 'quest-confirm-freeze');
      await _wait(tester, () => !fixture.runtime.isActivating);
      fixture.loseProtectionAck = true;
      await tester.tap(find.byKey(const ValueKey('quest-confirm-freeze')));
      await _wait(tester, () => fixture.lostProtectionAcks == 1);
      expect(fixture.lostProtectionAcks, 1);
      expect(fixture.loseProtectionAck, isFalse);
      final first = await _real(tester, fixture.protections);
      expect(first, hasLength(1));
      expect(await _real(tester, () => fixture.lostAckReceipt!), first);
      await _wait(
        tester,
        () => find.text('ลองคำขอเดิมอีกครั้ง').evaluate().isNotEmpty,
      );
      final notificationsAfterLostAck = fixture.protectionNotifications;
      expect(
        await _real(tester, () => fixture.h.storage.count('learning_day_log')),
        1,
      );
      await _tap(tester, 'quest-confirm-freeze');
      await _wait(
        tester,
        () => find
            .byKey(const ValueKey('quest-freeze-review'))
            .evaluate()
            .isEmpty,
      );
      final scrollable = find
          .descendant(
            of: find.byKey(const ValueKey('quest-content')),
            matching: find.byType(Scrollable),
          )
          .first;
      tester.state<ScrollableState>(scrollable).position.jumpTo(0);
      await _wait(
        tester,
        () => find.byKey(const ValueKey('quest-status')).evaluate().isNotEmpty,
      );
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('quest-status'))).data,
        'คุ้มครองสตรีกวันที่ 2026-10-27 แล้ว',
      );
      expect(await _real(tester, fixture.protections), first);
      expect(fixture.lostProtectionAcks, 1);
      expect(fixture.protectionNotifications, notificationsAfterLostAck + 1);
      expect(
        await _real(tester, () => fixture.h.storage.count('learning_day_log')),
        1,
      );
      final view = await _real(
        tester,
        () => fixture.runtime.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
      );
      expect(view.motivation.state.freezeCount, 0);
      expect(view.motivation.learningDays, hasLength(1));
      expect(view.motivation.protectedDays, {'2026-10-27'});
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('retained confirmation is inert across background and resume', (
    tester,
  ) async {
    final fixture = await tester.runAsync(() => _UiFixture.open());
    addTearDown(() => _close(tester, fixture!));
    await tester.pumpWidget(
      _app(QuestScreen(runtime: fixture!.runtime, ownerId: configuredOwnerId)),
    );
    await _tap(tester, 'quest-review-freeze');
    await _ready(tester, 'quest-confirm-freeze');
    final confirm = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('quest-confirm-freeze')),
        )
        .onPressed!;
    fixture.runtime.setForeground(false);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump(const Duration(milliseconds: 16));
    confirm();
    expect(await _real(tester, fixture.protections), isEmpty);
    await _real(tester, () async {
      fixture.runtime.setForeground(true);
      await fixture.runtime.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
    });
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await _ready(tester, 'quest-review-freeze');
    confirm();
    expect(await _real(tester, fixture.protections), isEmpty);
  });

  testWidgets('retained confirmation is inert after actual owner A-B-A', (
    tester,
  ) async {
    final fixture = await tester.runAsync(
      () => _UiFixture.open(observeOwners: true),
    );
    addTearDown(() => _close(tester, fixture!));
    await tester.pumpWidget(
      _app(QuestScreen(runtime: fixture!.runtime, ownerId: configuredOwnerId)),
    );
    await _tap(tester, 'quest-review-freeze');
    await _ready(tester, 'quest-confirm-freeze');
    final confirm = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('quest-confirm-freeze')),
        )
        .onPressed!;
    await _real(tester, () async {
      await fixture.h.storage.switchOwner(configuredOtherOwnerId);
      fixture.ownerChanges!.add(configuredOtherOwnerId);
      await fixture.h.storage.switchOwner(configuredOwnerId);
      fixture.ownerChanges!.add(configuredOwnerId);
      await fixture.runtime.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
    });
    await tester.pump(const Duration(milliseconds: 16));
    confirm();
    expect(await _real(tester, fixture.protections), isEmpty);
  });

  testWidgets('runtime replacement retires an already rendered confirmation', (
    tester,
  ) async {
    final fixture = await tester.runAsync(() => _UiFixture.open());
    addTearDown(() => _close(tester, fixture!));
    final key = GlobalKey();
    await tester.pumpWidget(
      _app(
        QuestScreen(
          key: key,
          runtime: fixture!.runtime,
          ownerId: configuredOwnerId,
        ),
      ),
    );
    await _tap(tester, 'quest-review-freeze');
    await _ready(tester, 'quest-confirm-freeze');
    final confirm = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('quest-confirm-freeze')),
        )
        .onPressed!;
    final replacement = await _real(tester, () async {
      final runtime = MotivationRuntime(
        database: fixture.h.database,
        ownerWrites: fixture.h.storage.ownerWrites,
        owners: fixture.h.storage.owners,
        nowUtc: () => fixture.h.now,
        generateId: () => 'synthetic-replacement-runtime',
      );
      runtime.setForeground(true);
      await runtime.activate(
        ownerId: configuredOwnerId,
        stillCurrent: () => true,
      );
      return runtime;
    });
    addTearDown(
      () => _finishClose(
        tester,
        replacement.dispose,
        () => 'replacement.dispose',
      ),
    );
    await tester.pumpWidget(
      _app(
        QuestScreen(key: key, runtime: replacement, ownerId: configuredOwnerId),
      ),
    );
    await tester.pump(const Duration(milliseconds: 16));
    confirm();
    expect(await _real(tester, fixture.protections), isEmpty);
    expect(find.textContaining('โปรดเปิดภารกิจใหม่'), findsOneWidget);
  });

  testWidgets('leaving the Quest route retires an unsent review', (
    tester,
  ) async {
    final fixture = await tester.runAsync(() => _UiFixture.open());
    addTearDown(() => _close(tester, fixture!));
    await tester.pumpWidget(
      _app(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => QuestScreen(
                    runtime: fixture!.runtime,
                    ownerId: configuredOwnerId,
                  ),
                ),
              ),
              child: const Text('open synthetic quest'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open synthetic quest'));
    await _tap(tester, 'quest-review-freeze');
    await _ready(tester, 'quest-confirm-freeze');
    final confirm = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('quest-confirm-freeze')),
        )
        .onPressed!;
    await tester.pageBack();
    await tester.pump(const Duration(milliseconds: 400));
    confirm();
    expect(await _real(tester, fixture!.protections), isEmpty);
    expect(find.text('open synthetic quest'), findsOneWidget);
  });

  testWidgets(
    'Quest shows Thai built-in objective labels with pinned counts and preserves custom copy',
    (tester) async {
      final fixture = (await tester.runAsync(() => _UiFixture.open()))!;
      addTearDown(() => _close(tester, fixture));
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(420, 2400);
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final before = await _real(tester, fixture.h.storage.snapshot);
      await tester.pumpWidget(
        _app(QuestScreen(runtime: fixture.runtime, ownerId: configuredOwnerId)),
      );
      await _ready(tester, 'quest-review-freeze');
      expect(find.text('ตอบถูกวันนี้: 0/5'), findsOneWidget);
      expect(find.text('ตอบถูกวันนี้: 1/5'), findsOneWidget);
      expect(find.text('ตอบถูกสัปดาห์นี้: 1/20'), findsOneWidget);
      expect(find.text('Correct answers: 1/1'), findsOneWidget);
      expect(await _real(tester, fixture.h.storage.snapshot), before);
    },
  );

  testWidgets(
    'Today reads actual progress without writes and guards its navigation callback',
    (tester) async {
      final fixture = await tester.runAsync(() => _UiFixture.open());
      addTearDown(() => _close(tester, fixture!));
      var opens = 0;
      final before = await tester.runAsync(() => fixture!.h.storage.snapshot());
      await tester.pumpWidget(
        _app(
          Scaffold(
            body: SingleChildScrollView(
              child: TodayMotivationPanel(
                runtime: fixture!.runtime,
                ownerId: configuredOwnerId,
                onOpenQuests: () => opens++,
              ),
            ),
          ),
        ),
      );
      await _ready(tester, 'today-open-quests');
      expect(find.text('เป้าหมายถัดไป: ตอบถูกสัปดาห์นี้ 1/20'), findsOneWidget);
      final old = tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('today-open-quests')),
          )
          .onPressed!;
      expect(await _real(tester, () => fixture.h.storage.snapshot()), before);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump(const Duration(milliseconds: 16));
      old();
      expect(opens, 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await _ready(tester, 'today-open-quests');
      await _tap(tester, 'today-open-quests');
      expect(opens, 1);
      expect(await _real(tester, () => fixture.h.storage.snapshot()), before);
    },
  );
}

Widget _app(Widget child, {bool dark = false, double scale = 1}) => MaterialApp(
  theme: dark ? M3Theme.darkTheme : M3Theme.lightTheme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(scale), disableAnimations: true),
    child: child!,
  ),
  home: child,
);

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var index = 0; index < 150; index++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump(const Duration(milliseconds: 16));
    if (ready()) return;
  }
  fail(
    'The actual motivation view did not reach its expected state. '
    'Lifecycle: ${tester.binding.lifecycleState}. '
    'Rendered: ${tester.widgetList<Text>(find.byType(Text)).map((text) => text.data).whereType<String>().take(24).join(' | ')}',
  );
}

Future<void> _ready(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  final content = find.byKey(const ValueKey('quest-content'));
  if (content.evaluate().isNotEmpty) {
    final scrollable = find
        .descendant(of: content, matching: find.byType(Scrollable))
        .first;
    tester.state<ScrollableState>(scrollable).position.jumpTo(0);
    await tester.pump(const Duration(milliseconds: 16));
    await _wait(
      tester,
      () => find.byType(MotivationTotals).evaluate().isNotEmpty,
    );
    for (var step = 0; step < 60 && finder.evaluate().isEmpty; step++) {
      await tester.drag(scrollable, const Offset(0, -150));
      await tester.pump(const Duration(milliseconds: 16));
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      );
    }
    expect(
      finder,
      findsOneWidget,
      reason: 'Actual action $key must remain reachable',
    );
  }
  await _wait(tester, () {
    final elements = finder.evaluate();
    return elements.length == 1 &&
        elements.single.widget is ButtonStyleButton &&
        (elements.single.widget as ButtonStyleButton).onPressed != null;
  });
  await _reveal(tester, finder);
}

Future<void> _tap(WidgetTester tester, String key) async {
  await _ready(tester, key);
  final finder = find.byKey(ValueKey(key));
  await tester.tap(finder);
  await tester.pump(const Duration(milliseconds: 16));
}

Future<void> _reveal(WidgetTester tester, Finder finder) async {
  await tester.pump(const Duration(milliseconds: 16));
  await tester.ensureVisible(finder);
  await tester.pump(const Duration(milliseconds: 16));
  await _wait(tester, () => finder.hitTestable().evaluate().isNotEmpty);
}

Future<T> _real<T>(
  WidgetTester tester,
  Future<T> Function() operation, {
  String Function()? stage,
}) async {
  var done = false;
  T? value;
  Object? failure;
  StackTrace? stack;
  await tester.runAsync(() async {
    unawaited(
      Future<T>.sync(operation).then<void>(
        (result) {
          value = result;
          done = true;
        },
        onError: (Object error, StackTrace trace) {
          failure = error;
          stack = trace;
          done = true;
        },
      ),
    );
  });
  for (var frame = 0; frame < 240 && !done; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  if (!done) {
    fail(
      'Synthetic motivation IO did not finish: ${stage?.call() ?? 'operation'}',
    );
  }
  if (failure != null) Error.throwWithStackTrace(failure!, stack!);
  return value as T;
}

Future<void> _keyboardActivate(WidgetTester tester, String key) async {
  final finder = find.byKey(ValueKey(key));
  await tester.ensureVisible(finder);
  for (var index = 0; index < 20; index++) {
    final focused = FocusManager.instance.primaryFocus?.context;
    var within = false;
    focused?.visitAncestorElements((element) {
      if (identical(element, finder.evaluate().single)) {
        within = true;
        return false;
      }
      return true;
    });
    if (within) {
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      return;
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 16));
  }
  fail('The visible motivation action was not reachable by keyboard.');
}

Future<void> _close(WidgetTester tester, _UiFixture fixture) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 16));
  var stage = 'runtime.dispose';
  await _finishClose(tester, () async {
    await fixture.runtime.dispose();
    stage = 'ownerChanges.close';
    await fixture.ownerChanges?.close();
    stage = 'database.close';
    await fixture.h.close();
    stage = 'closed';
  }, () => stage);
  tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
}

Future<void> _finishClose(
  WidgetTester tester,
  Future<void> Function() close,
  String Function() stage,
) async {
  await _real(tester, close, stage: stage);
}

final class _UiFixture {
  _UiFixture(this.h);
  final QuestHarness h;
  late final MotivationRuntime runtime;
  StreamController<String?>? ownerChanges;
  var loseProtectionAck = false;
  var lostProtectionAcks = 0;
  var protectionNotifications = 0;
  Future<List<Map<String, Object?>>>? lostAckReceipt;
  var _ids = 0;

  static Future<_UiFixture> open({bool observeOwners = false}) async {
    final fixture = _UiFixture(await QuestHarness.open());
    fixture.h.now = DateTime.utc(2026, 10, 26, 12);
    if (observeOwners) {
      fixture.ownerChanges = StreamController<String?>.broadcast(sync: true);
    }
    fixture.runtime = MotivationRuntime(
      database: fixture.h.database,
      ownerWrites: fixture.h.storage.ownerWrites,
      owners: fixture.h.storage.owners,
      ownerChanges: fixture.ownerChanges?.stream,
      nowUtc: () => fixture.h.now,
      generateId: () => 'synthetic-motivation-ui-${++fixture._ids}',
      onLocalMutation: () {
        if (fixture.runtime.isActivating) return;
        fixture.protectionNotifications++;
        if (fixture.loseProtectionAck) {
          fixture.loseProtectionAck = false;
          fixture.lostProtectionAcks++;
          fixture.lostAckReceipt = fixture.protections();
          throw StateError('synthetic-lost-acknowledgement');
        }
      },
    );
    fixture.ownerChanges?.add(configuredOwnerId);
    fixture.runtime.setForeground(true);
    await fixture.runtime.activate(
      ownerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    final base = questDefinition(id: 'synthetic-ui-weekly', target: 1);
    final weekly = QuestDefinition(
      questId: base.questId,
      catalogVersion: base.catalogVersion,
      title: base.title,
      description: base.description,
      type: QuestType.weekly,
      objectives: base.objectives,
      reward: const RewardSpec(xpAmount: 200),
    );
    await fixture.runtime.quest.startQuest(
      weekly,
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    fixture.h.now = fixture.h.now.add(const Duration(seconds: 1));
    final answer = await fixture.h.answer(
      id: 'synthetic-ui-ordinary-answer',
      sessionId: 'synthetic-ui-ordinary-session',
    );
    await fixture.runtime.quest.processEvent(answer, [
      ...QuestCatalogProvider.allQuests,
      weekly,
    ]);
    await fixture.runtime.streak.reconcileRewards(
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    fixture.h.now = DateTime.utc(2026, 10, 28, 12);
    await fixture.runtime.activate(
      ownerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    final view = await fixture.runtime.load(
      expectedOwnerId: configuredOwnerId,
      stillCurrent: () => true,
    );
    expect(view.protectableDay, '2026-10-27');
    return fixture;
  }

  Future<List<Map<String, Object?>>> protections() async =>
      (await h.database
              .customSelect(
                "SELECT * FROM reward_transactions WHERE transaction_type='consumeFreezeProtectionV1' ORDER BY id",
              )
              .get())
          .map((row) => row.data)
          .toList();
}
