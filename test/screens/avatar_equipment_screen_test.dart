import 'dart:async';
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_avatar_progression_eligibility.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';

void main() {
  testWidgets(
    'headgear preview changes the avatar then cancel restores it without a transaction',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      var firstDatabaseClosed = false;
      addTearDown(() async {
        if (!firstDatabaseClosed) await database.close();
      });
      final owners = DriftLocalOwnerRepository(
        database,
        generateId: () => 'synthetic-preview-owner',
        nowUtc: () => DateTime.utc(2026, 9, 8),
      );
      final owner = await owners.getOrCreateActiveOwner();
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            PointsLedgerEntriesCompanion.insert(
              id: 'synthetic-preview-xp',
              ownerId: owner.id,
              idempotencyKey: 'synthetic-preview-xp',
              entryType: 'quizCorrect',
              amount: 40,
              occurredAtUtcMs: 1,
            ),
          );
      var sequence = 0;
      final rewards = RewardUseCases(
        owners: owners,
        repository: DriftRewardRepository(database),
        progress: ProgressUseCases(
          owners: owners,
          queries: DriftProgressQueries(database),
          nowUtc: () => DateTime.utc(2026, 9, 8),
        ),
        generateId: () => 'synthetic-preview-${sequence++}',
        nowUtc: () => DateTime.utc(2026, 9, 8),
      );
      await rewards.grantCoins(
        idempotencyKey: 'synthetic-preview-coins',
        amount: 120,
        sourceEventId: 'synthetic-preview-grant',
      );
      final before = await rewards.load();

      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reward-avatar-preview/base')),
        findsOneWidget,
      );

      final preview = find.byKey(const ValueKey('reward-preview/headgear_ipa'));
      await _scrollToCenter(tester, preview, delta: 200);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey('reward-avatar-preview/headgear_ipa')),
        findsOneWidget,
      );
      expect(find.text('กำลังลองหมวก IPA'), findsOneWidget);
      expect(find.text('ลองดูเท่านั้น ยังไม่ได้ซื้อหรือสวม'), findsOneWidget);
      final afterPreview = await rewards.load();
      expect(afterPreview.coinBalance, before.coinBalance);
      expect(afterPreview.transactionCount, before.transactionCount);
      expect(afterPreview.ownedItemIds, isNot(contains('headgear_ipa')));
      expect(afterPreview.equippedBySlot['headgear'], isNull);

      final cancelPreview = find.widgetWithText(TextButton, 'เลิกลอง');
      await _scrollToCenter(tester, cancelPreview, delta: -200);
      await tester.tap(cancelPreview);
      await tester.pump();

      expect(
        find.byKey(const ValueKey('reward-avatar-preview/base')),
        findsOneWidget,
      );
      expect(find.text('กำลังลองหมวก IPA'), findsNothing);
      final afterCancel = await rewards.load();
      expect(afterCancel.coinBalance, before.coinBalance);
      expect(afterCancel.transactionCount, before.transactionCount);

      await _scrollToCenter(tester, preview, delta: 200);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      await database.close();
      firstDatabaseClosed = true;
      final secondDatabase = AppDatabase(NativeDatabase.memory());
      addTearDown(secondDatabase.close);
      final secondOwners = DriftLocalOwnerRepository(
        secondDatabase,
        generateId: () => 'synthetic-preview-second-owner',
        nowUtc: () => DateTime.utc(2026, 9, 8),
      );
      await secondOwners.getOrCreateActiveOwner();
      final secondRewards = RewardUseCases(
        owners: secondOwners,
        repository: DriftRewardRepository(secondDatabase),
        progress: ProgressUseCases(
          owners: secondOwners,
          queries: DriftProgressQueries(secondDatabase),
          nowUtc: () => DateTime.utc(2026, 9, 8),
        ),
        generateId: () => 'synthetic-preview-second-transaction',
        nowUtc: () => DateTime.utc(2026, 9, 8),
      );
      final secondBefore = await secondRewards.load();

      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: secondRewards)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey('reward-avatar-preview/base')),
        findsOneWidget,
      );
      expect(find.text('กำลังลองหมวก IPA'), findsNothing);
      final secondAfter = await secondRewards.load();
      expect(secondAfter.coinBalance, secondBefore.coinBalance);
      expect(secondAfter.transactionCount, secondBefore.transactionCount);
    },
  );

  for (final scenario in [0, 1, 2]) {
    final acknowledgementFails = scenario > 0;
    final readbackFails = scenario == 2;
    testWidgets(
      'real purchase and equip persist once, acknowledgementFails=$acknowledgementFails readbackFails=$readbackFails',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final owners = _BlockingOwners(
          DriftLocalOwnerRepository(
            database,
            generateId: () => 'synthetic-shop-owner',
            nowUtc: () => DateTime.utc(2026, 9, 8),
          ),
        );
        final owner = await owners.getOrCreateActiveOwner();
        await database
            .into(database.pointsLedgerEntries)
            .insert(
              PointsLedgerEntriesCompanion.insert(
                id: 'synthetic-shop-xp',
                ownerId: owner.id,
                idempotencyKey: 'synthetic-shop-xp',
                entryType: 'quizCorrect',
                amount: 40,
                occurredAtUtcMs: 1,
              ),
            );
        var sequence = 0;
        var failNotification = false;
        var reconciliation = Completer<void>();
        final rewards = RewardUseCases(
          owners: owners,
          repository: DriftRewardRepository(database),
          progress: ProgressUseCases(
            owners: owners,
            queries: DriftProgressQueries(database),
            nowUtc: () => DateTime.utc(2026, 9, 8),
          ),
          generateId: () => 'synthetic-shop-${sequence++}',
          nowUtc: () => DateTime.utc(2026, 9, 8),
          onLocalMutation: () {
            if (failNotification) {
              owners.pending = reconciliation.future;
              throw StateError('synthetic acknowledgement lost');
            }
          },
        );
        final initialAccount = await rewards.load();
        await rewards.grantCoins(
          idempotencyKey: 'synthetic-shop-coins',
          amount: 100,
          sourceEventId: 'synthetic-shop-grant',
        );
        await tester.pumpWidget(
          MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
        );
        await tester.pumpAndSettle();
        final purchase = find.byKey(
          const ValueKey('reward-purchase/theme_ocean'),
        );
        await _scrollToCenter(tester, purchase, delta: 200);
        await tester.pump();
        final wait = Completer<void>();
        owners.pending = wait.future;
        failNotification = acknowledgementFails;
        await tester.tap(purchase);
        await tester.tap(purchase);
        await tester.pump();
        expect(find.text('กำลังบันทึกรายการ…'), findsOneWidget);
        expect(
          find.byKey(const ValueKey('reward-equip/theme_ocean')),
          findsNothing,
        );
        owners.pending = null;
        wait.complete();
        if (acknowledgementFails) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(
            find.byKey(const ValueKey('reward-equip/theme_ocean')),
            findsNothing,
          );
          owners.pending = null;
          owners.failNextRead = readbackFails;
          reconciliation.complete();
        }
        await tester.pumpAndSettle();
        if (readbackFails) {
          expect(
            find.text(
              'ยังยืนยันสถานะรายการไม่ได้ ลองอ่านข้อมูลอีกครั้งโดยไม่บันทึกซ้ำ',
            ),
            findsOneWidget,
          );
          expect(purchase, findsNothing);
          final retryRead = Completer<void>();
          owners.pending = retryRead.future;
          await tester.tap(find.widgetWithText(FilledButton, 'ลองใหม่'));
          await tester.pump();
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.widgetWithText(FilledButton, 'ลองใหม่'), findsNothing);
          owners.pending = null;
          retryRead.complete();
          await tester.pumpAndSettle();
        }
        final account = await rewards.load();
        expect(account.coinBalance, initialAccount.coinBalance + 20);
        expect(account.ownedItemIds, contains('theme_ocean'));
        expect(account.transactionCount, initialAccount.transactionCount + 1);
        expect(
          find.text('การบันทึกขัดข้อง กำลังตรวจสอบสถานะรายการล่าสุด'),
          findsNothing,
        );
        final equip = find.byKey(const ValueKey('reward-equip/theme_ocean'));
        await _scrollToCenter(tester, equip, delta: 200);
        reconciliation = Completer<void>();
        failNotification = acknowledgementFails;
        await tester.tap(equip);
        await tester.tap(equip);
        if (acknowledgementFails) {
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 100));
          expect(find.byType(CircularProgressIndicator), findsOneWidget);
          expect(find.text('กำลังตรวจสอบสถานะรายการล่าสุด'), findsOneWidget);
          owners.pending = null;
          reconciliation.complete();
        }
        await tester.pumpAndSettle();
        expect(find.textContaining('กำลังตรวจสอบสถานะ'), findsNothing);
        final equipped = await rewards.load();
        expect(equipped.equippedBySlot['theme'], 'theme_ocean');
        expect(equipped.coinBalance, initialAccount.coinBalance + 20);
        expect(equipped.transactionCount, initialAccount.transactionCount + 2);
        final item = find.byKey(const ValueKey('reward-item/theme_ocean'));
        await _scrollToCenter(tester, item, delta: 200);
        expect(
          find.descendant(of: item, matching: find.text('กำลังใช้')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  }
  testWidgets('equipment surface reads durable reward ownership', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    await owners.getOrCreateActiveOwner();
    await database
        .into(database.pointsLedgerEntries)
        .insert(
          PointsLedgerEntriesCompanion.insert(
            id: 'xp:avatar-screen',
            ownerId: 'local:owner',
            idempotencyKey: 'xp:avatar-screen',
            entryType: 'quizCorrect',
            amount: 40,
            occurredAtUtcMs: 1,
          ),
        );
    final progress = ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      progress: progress,
      generateId: () => 'tx',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );

    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ร้านค้ารางวัล'), findsOneWidget);
    expect(find.text('เลเวลอวาตาร์'), findsOneWidget);
    expect(find.text('เลเวล 3'), findsOneWidget);
    expect(find.text('XP สะสม 40'), findsOneWidget);
    expect(find.text('อีก 20 XP ถึงเลเวล 4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('เลเวลอวาตาร์ 3 จาก XP สะสม 40'),
      findsOneWidget,
    );
    expect(find.text('ธีมมาตรฐาน'), findsOneWidget);
    expect(find.text('เหรียญคงเหลือ'), findsOneWidget);
    expect(find.bySemanticsLabel('เหรียญคงเหลือ 40 เหรียญ'), findsOneWidget);
    await tester.scrollUntilVisible(find.text('80 เหรียญ'), 200);
    expect(find.text('80 เหรียญ'), findsOneWidget);
    expect(find.text('80 คะแนน'), findsNothing);
    expect(find.text('40'), findsWidgets);
    expect(find.textContaining('Damage'), findsNothing);
    await tester.scrollUntilVisible(find.text('ปลดล็อกที่เลเวล 4'), 200);
    expect(find.text('ปลดล็อกที่เลเวล 4'), findsOneWidget);

    final oceanPurchase = find.byKey(
      const ValueKey('reward-purchase/theme_ocean'),
    );
    await _scrollToCenter(tester, oceanPurchase, delta: -200);
    await tester.tap(oceanPurchase);
    await tester.pump();

    await tester.pumpAndSettle();
    final currentOceanItem = find.byKey(
      const ValueKey('reward-item/theme_ocean'),
    );
    await _scrollToCenter(tester, currentOceanItem, delta: 200);
    expect(
      find.descendant(
        of: currentOceanItem,
        matching: find.text('เหรียญไม่เพียงพอ'),
      ),
      findsOneWidget,
    );
  });

  testWidgets('quarantined avatar surface reopens after local repair', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'repair-owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    final owner = await owners.getOrCreateActiveOwner();
    final eligibility = DriftAvatarProgressionEligibility(database);
    await eligibility.establishCutover(owner.id);
    await database.customInsert(
      "INSERT INTO reward_transactions "
      "(id, owner_id, idempotency_key, transaction_type, amount, item_id, "
      "catalog_version, occurred_at_utc_ms) VALUES "
      "('repair-raw-v1', ?, 'repair-raw-v1', 'purchase', -80, "
      "'theme_ocean', 1, 1)",
      variables: [Variable<String>(owner.id)],
    );
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(
        database,
        progressionEligibility: eligibility,
      ),
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 7, 30),
      ),
      generateId: () => 'repair-transaction',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );

    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
    );
    await tester.pumpAndSettle();
    expect(find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'ลองใหม่'), findsOneWidget);

    await (database.delete(
      database.rewardTransactions,
    )..where((row) => row.id.equals('repair-raw-v1'))).go();
    await tester.tap(find.widgetWithText(FilledButton, 'ลองใหม่'));
    await tester.pumpAndSettle();

    expect(find.text('เหรียญคงเหลือ'), findsOneWidget);
    expect(find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'), findsNothing);
  });
}

Future<void> _scrollToCenter(
  WidgetTester tester,
  Finder finder, {
  required double delta,
}) async {
  await tester.scrollUntilVisible(finder, delta);
  await Scrollable.ensureVisible(tester.element(finder), alignment: 0.5);
  await tester.pump();
}

final class _BlockingOwners implements LocalOwnerRepository {
  _BlockingOwners(this.delegate);
  final LocalOwnerRepository delegate;
  Future<void>? pending;
  bool failNextRead = false;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    await pending;
    if (failNextRead) {
      failNextRead = false;
      throw StateError('synthetic readback unavailable');
    }
    return delegate.getOrCreateActiveOwner();
  }

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      delegate.bindFirebaseUid(ownerId, firebaseUid);
}
