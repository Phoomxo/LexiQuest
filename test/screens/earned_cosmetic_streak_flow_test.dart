import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/m3_theme.dart';
import 'package:vocab_learning_app/features/motivation/presentation/today_motivation_panel.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/runtime/motivation_runtime.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';

import '../features/quest/support/quest_repository_harness.dart';
import '../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets('canonical learning days appear in Today and reset after a gap', (
    tester,
  ) async {
    final h = await motivationPresentationIo(tester, QuestHarness.open);
    var ids = 0;
    final runtime = MotivationRuntime(
      database: h.database,
      ownerWrites: h.storage.ownerWrites,
      owners: h.storage.owners,
      nowUtc: () => h.now,
      generateId: () => 'synthetic-streak-ui-${++ids}',
    );
    runtime.setForeground(true);
    try {
      await motivationPresentationIo(tester, () async {
        await runtime.activate(
          ownerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        await h.answer(id: 'day-one', sessionId: 'day-one-session');
      });
      Future<void> showDay(String expected) async {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pumpWidget(
          _app(
            Scaffold(
              body: SingleChildScrollView(
                child: TodayMotivationPanel(
                  runtime: runtime,
                  ownerId: configuredOwnerId,
                  onOpenQuests: () {},
                ),
              ),
            ),
          ),
        );
        await _ready(tester, find.text(expected));
        expect(find.text('วันที่เรียนต่อเนื่อง'), findsOneWidget);
        expect(find.text(expected), findsOneWidget);
        expect(tester.takeException(), isNull);
      }

      await showDay('1 วัน');
      await motivationPresentationIo(tester, () async {
        h.now = h.now.add(const Duration(days: 1));
        await h.answer(id: 'day-two', sessionId: 'day-two-session');
      });
      await showDay('2 วัน');
      h.now = h.now.add(const Duration(days: 3));
      await showDay('0 วัน');
      final view = await motivationPresentationIo(
        tester,
        () => runtime.load(
          expectedOwnerId: configuredOwnerId,
          stillCurrent: () => true,
        ),
      );
      expect(view.motivation.state.longestStreakDays, 2);
      expect(view.motivation.learningDays, hasLength(2));
      expect(view.motivation.protectedDays, isEmpty);
      expect(
        (await motivationPresentationIo(
          tester,
          h.storage.researchCounts,
        )).values,
        everyElement(0),
      );
    } finally {
      await closeMotivationPresentation(tester, () async {
        await runtime.dispose();
        await h.close();
      });
    }
  });

  testWidgets('canonical earned coins buy and equip a cosmetic across reopen', (
    tester,
  ) async {
    final directory = await motivationPresentationIo(
      tester,
      () => Directory.systemTemp.createTemp('lexiquest-earned-cosmetic-'),
    );
    QuestHarness? h;
    var ids = 0;
    RewardUseCases rewards(QuestHarness fixture) => RewardUseCases(
      owners: fixture.storage.owners,
      repository: DriftRewardRepository(
        fixture.database,
        ownerWrites: fixture.storage.ownerWrites,
      ),
      generateId: () => 'synthetic-earned-shop-${++ids}',
      nowUtc: () => fixture.now,
    );
    try {
      final file = File('${directory.path}/earned.sqlite');
      final fixture = await motivationPresentationIo(
        tester,
        () => QuestHarness.open(file: file),
      );
      h = fixture;
      final shop = rewards(fixture);
      expect((await motivationPresentationIo(tester, shop.load)).balance, 0);
      for (var index = 0; index < 80; index++) {
        await motivationPresentationIo(
          tester,
          () => fixture.answer(
            id: 'earned-answer-$index',
            sessionId: 'earned-session-$index',
          ),
        );
      }
      expect((await motivationPresentationIo(tester, shop.load)).balance, 80);
      await tester.pumpWidget(_app(ShopPage(rewards: shop)));
      final purchase = find.byKey(
        const ValueKey('reward-purchase-theme_ocean'),
      );
      await _ready(tester, purchase);
      await _tap(tester, purchase);
      final confirm = find.byKey(const ValueKey('confirm-purchase'));
      await _ready(tester, confirm);
      expect(find.text('80 → 0 เหรียญ'), findsOneWidget);
      await _tap(tester, confirm);
      final equip = find.byKey(const ValueKey('reward-equip-theme_ocean'));
      await _ready(tester, equip);
      await _tap(tester, equip);
      await _ready(tester, find.text('ใช้งานรายการนี้แล้ว'));
      final before = await motivationPresentationIo(tester, shop.load);
      expect(before.balance, 0);
      expect(before.ownedItemIds, contains('theme_ocean'));
      expect(before.equippedBySlot['theme'], 'theme_ocean');
      final at = fixture.now;
      await closeMotivationPresentation(tester, fixture.close);
      final reopened = await motivationPresentationIo(
        tester,
        () => QuestHarness.open(file: file, seed: false),
      );
      h = reopened;
      reopened.now = at;
      final restoredShop = rewards(reopened);
      await tester.pumpWidget(_app(ShopPage(rewards: restoredShop)));
      await _ready(tester, find.text('เหรียญคงเหลือ'));
      final after = await motivationPresentationIo(tester, restoredShop.load);
      expect(after.balance, before.balance);
      expect(after.ownedItemIds, before.ownedItemIds);
      expect(after.equippedBySlot, before.equippedBySlot);
      final provenance = await motivationPresentationIo(tester, () async {
        final credits =
            await (reopened.database.select(
                  reopened.database.rewardTransactions,
                )..where(
                  (row) => row.transactionType.equals('creditQuizCorrectV1'),
                ))
                .get();
        final points = await reopened.database
            .select(reopened.database.pointsLedgerEntries)
            .get();
        final answers = await reopened.database
            .select(reopened.database.answerAttempts)
            .get();
        return (
          credits: credits,
          points: points,
          answers: answers,
          research: await reopened.storage.researchCounts(),
        );
      });
      expect(provenance.credits, hasLength(80));
      expect(provenance.points, hasLength(80));
      expect(provenance.answers, hasLength(80));
      final answerIds = provenance.answers.map((row) => row.id).toSet();
      expect(
        provenance.credits.map((row) => row.sourceEventId).toSet(),
        answerIds,
      );
      expect(
        provenance.points.map((row) => row.sourceEventId).toSet(),
        answerIds,
      );
      expect(provenance.research.values, everyElement(0));
      expect(tester.takeException(), isNull);
    } finally {
      await closeMotivationPresentation(tester, () async {
        await h?.close();
        await directory.delete(recursive: true);
      });
    }
  });
}

Widget _app(Widget home) => MaterialApp(theme: M3Theme.lightTheme, home: home);

Future<void> _ready(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 300 && finder.evaluate().isEmpty; frame++) {
    await tester.pump(const Duration(milliseconds: 16));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
  }
  expect(finder, findsWidgets);
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  expect(finder.hitTestable(), findsOneWidget);
  await tester.tap(finder.hitTestable());
  await tester.pump();
}
