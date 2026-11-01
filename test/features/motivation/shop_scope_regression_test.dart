import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';

import '../quest/support/quest_repository_harness.dart';
import '../../support/motivation_presentation_io.dart';

void main() {
  setUp(
    () => TestWidgetsFlutterBinding.ensureInitialized()
        .handleAppLifecycleStateChanged(AppLifecycleState.resumed),
  );

  testWidgets('same-owner external equip refreshes the actual catalog state', (
    tester,
  ) async {
    final h = (await motivationPresentationDeadline(
      tester,
      'fixture/open',
      () => tester.runAsync(QuestHarness.open),
    ))!;
    Future<void>? closing;
    Future<void> finish() =>
        closing ??= closeMotivationPresentation(tester, h.close);
    try {
      final rewards = _rewards(h);
      await motivationPresentationDeadline(
        tester,
        'fixture/mount',
        () => tester.pumpWidget(MaterialApp(home: ShopPage(rewards: rewards))),
      );
      await _wait(
        tester,
        () => find
            .byKey(const ValueKey('reward-equip-theme_default'))
            .evaluate()
            .isNotEmpty,
      );
      await motivationPresentationIo(
        tester,
        () => rewards.equip(
          expectedOwnerId: configuredOwnerId,
          itemId: 'theme_default',
          idempotencyKey: 'synthetic-same-owner-external-equip',
        ),
        stage: 'external-equip',
      );
      await _wait(
        tester,
        () => find.widgetWithText(Chip, 'กำลังใช้').evaluate().isNotEmpty,
      );
      expect(
        find.byKey(const ValueKey('reward-equip-theme_default')),
        findsNothing,
      );
      final receipts = await motivationPresentationIo(
        tester,
        () => h.database.select(h.database.rewardTransactions).get(),
        stage: 'external-equip-receipts',
      );
      expect(receipts, hasLength(1));
    } finally {
      await finish();
    }
  });

  testWidgets(
    'unrelated runtime flag refresh cannot leave the real shop waiting forever',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'runtime-flag/open',
        () => tester.runAsync(QuestHarness.open),
      ))!;
      Future<void>? closing;
      Future<void> finish() =>
          closing ??= closeMotivationPresentation(tester, h.close);
      try {
        final rewards = _rewards(h);
        await motivationPresentationDeadline(
          tester,
          'runtime-flag/mount',
          () =>
              tester.pumpWidget(MaterialApp(home: ShopPage(rewards: rewards))),
        );
        await _wait(
          tester,
          () => find.text('เหรียญคงเหลือ').evaluate().isNotEmpty,
        );
        await motivationPresentationIo(
          tester,
          () => h.database.customUpdate(
            "INSERT INTO runtime_flags (key,bool_value,source,updated_at_utc_ms) VALUES ('synthetic-unrelated-sync-lease',1,'synthetic',1)",
            updates: {h.database.runtimeFlags},
          ),
        );
        await tester.pump(const Duration(milliseconds: 16));
        await _wait(
          tester,
          () => find.text('เหรียญคงเหลือ').evaluate().isNotEmpty,
        );
        expect(find.byType(CircularProgressIndicator), findsNothing);
      } finally {
        await finish();
      }
    },
  );

  testWidgets(
    'avatar delayed canonical level recovers after its own preview closes',
    (tester) async {
      final h = (await motivationPresentationDeadline(
        tester,
        'delayed-avatar/open',
        () => tester.runAsync(QuestHarness.open),
      ))!;
      Future<void>? closing;
      Future<void> finish() =>
          closing ??= closeMotivationPresentation(tester, h.close);
      try {
        final progress = ProgressUseCases(
          owners: h.storage.owners,
          queries: DriftProgressQueries(h.database),
          nowUtc: () => h.now,
        );
        final canonical = await motivationPresentationIo(
          tester,
          progress.load,
          stage: 'delayed-avatar/progress',
        );
        final pending = Completer<ProgressSnapshot>();
        await motivationPresentationDeadline(
          tester,
          'delayed-avatar/mount',
          () => tester.pumpWidget(
            MaterialApp(
              home: AvatarEquipmentScreen(
                rewards: _rewards(h),
                progressLoader: () => pending.future,
              ),
            ),
          ),
        );
        final detail = find.byKey(
          const ValueKey('reward-detail-theme_default'),
        );
        await _wait(
          tester,
          () => find.text('เหรียญคงเหลือ').evaluate().isNotEmpty,
        );
        await tester.scrollUntilVisible(
          detail,
          200,
          scrollable: find.byType(Scrollable).first,
        );
        await motivationPresentationIo(
          tester,
          () =>
              Scrollable.ensureVisible(tester.element(detail), alignment: 0.5),
          stage: 'delayed-avatar-detail',
        );
        await tester.pumpAndSettle();
        expect(detail.hitTestable(), findsOneWidget);
        await tester.tap(detail.hitTestable());
        await tester.pumpAndSettle();
        pending.complete(canonical);
        await tester.pump();
        final close = find.text('ปิดตัวอย่าง');
        await tester.ensureVisible(close);
        await tester.pumpAndSettle();
        expect(close.hitTestable(), findsOneWidget);
        await tester.tap(close.hitTestable());
        await tester.pumpAndSettle();
        final scrollable = find.byType(Scrollable).first;
        tester.state<ScrollableState>(scrollable).position.jumpTo(0);
        await _wait(
          tester,
          () => find
              .text('ระดับอวตาร ${canonical.gameLevel}')
              .evaluate()
              .isNotEmpty,
        );
      } finally {
        await finish();
      }
    },
  );
}

RewardUseCases _rewards(QuestHarness h) {
  var ids = 0;
  return RewardUseCases(
    owners: h.storage.owners,
    repository: DriftRewardRepository(h.database),
    generateId: () => 'synthetic-shop-regression-${++ids}',
    nowUtc: () => h.now,
  );
}

Future<void> _wait(WidgetTester tester, bool Function() done) async {
  for (var i = 0; i < 100; i++) {
    await motivationPresentationDeadline(
      tester,
      'shop-ready/io-$i',
      () => tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 10)),
      ),
    );
    await motivationPresentationDeadline(
      tester,
      'shop-ready/pump-$i',
      () => tester.pump(const Duration(milliseconds: 16)),
    );
    if (done()) return;
  }
  fail('Actual shop did not restore its ready state');
}
