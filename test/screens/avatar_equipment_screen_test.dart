import 'dart:convert';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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
  recoveryTests();
  testWidgets('F02 replacement retires old shop command and busy state', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'swap-owner',
      nowUtc: () => DateTime.utc(2026),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.pointsLedgerEntries)
        .insert(
          PointsLedgerEntriesCompanion.insert(
            id: 'xp',
            ownerId: owner.id,
            idempotencyKey: 'xp',
            entryType: 'quizCorrect',
            amount: 200,
            occurredAtUtcMs: 1,
          ),
        );
    final blocked = _BlockingOwners(owners);
    var sequence = 0;
    RewardUseCases make(LocalOwnerRepository o) => RewardUseCases(
      owners: o,
      repository: DriftRewardRepository(database),
      progress: ProgressUseCases(
        owners: o,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026),
      ),
      generateId: () => 'swap-${sequence++}',
      nowUtc: () => DateTime.utc(2026),
    );
    final old = make(blocked);
    final replacement = make(owners);
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: old)),
    );
    await tester.pumpAndSettle();
    final beforeTransactions =
        (await database.select(database.rewardTransactions).get())
            .map((row) => row.toJson())
            .toList();
    final purchase = find.byKey(const ValueKey('reward-purchase/theme_ocean'));
    await _scrollToCenter(tester, purchase, delta: 200);
    final release = Completer<void>();
    blocked.pending = release.future;
    await tester.tap(purchase);
    await tester.pump();
    expect(find.text('กำลังบันทึกรายการ…'), findsOneWidget);
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: replacement)),
    );
    for (var i = 0; i < 20; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    // Capture before settling the old callback, then always drain it.
    final staleBusy = find.text('กำลังบันทึกรายการ…').evaluate().length;
    blocked.pending = null;
    release.complete();
    await tester.pumpAndSettle();
    expect(staleBusy, 0);
    expect(
      (await database.select(database.rewardTransactions).get())
          .map((row) => row.toJson())
          .toList(),
      beforeTransactions,
    );
    expect(find.text('ซื้อรายการและบันทึกในเครื่องแล้ว'), findsNothing);
  });

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
      String? aiOwner = owner.id;
      final registry = MenuActionRegistry(currentOwner: () => aiOwner);
      Map<String, dynamic> accountContext() =>
          jsonDecode(
                (registry.snapshot()['context'] as List).singleWhere(
                      (e) => e['id'] == 'rewards/account',
                    )['value']
                    as String,
              )
              as Map<String, dynamic>;

      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
        ),
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
      final context = accountContext();
      expect(context['previewItemId'], 'headgear_ipa');
      final entries = registry.snapshot()['context'] as List;
      final hat = jsonDecode(
        entries.singleWhere(
              (item) => item['id'] == 'rewards/item/headgear_ipa',
            )['value']
            as String,
      );
      expect(hat['previewing'], true);
      expect(hat['owned'], false);
      expect(hat['equipped'], false);
      expect(hat['priceCoins'], 100);
      expect(context['catalogScope'], 'complete-current-catalog');
      expect(
        entries.any((item) => item['id'] == 'rewards/item/wallpaper_focus'),
        true,
      );
      aiOwner = 'foreign-owner';
      expect(registry.snapshot()['context'], isEmpty);
      aiOwner = owner.id;

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
      expect(accountContext()['previewItemId'], isNull);

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

    String? aiOwner = 'local:owner';
    final registry = MenuActionRegistry(currentOwner: () => aiOwner);
    await tester.pumpWidget(
      MenuActionScope(
        registry: registry,
        child: MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('ร้านค้ารางวัล'), findsOneWidget);
    final entries = registry.snapshot()['context'] as List;
    final summary = jsonDecode(
      entries.singleWhere((e) => e['id'] == 'rewards/account')['value']
          as String,
    );
    expect(summary['coinBalance'], 40);
    expect(summary['lifetimeXp'], 40);
    expect(summary['level'], 3);
    expect(summary['previewIsEquipped'], false);
    final ocean = jsonDecode(
      entries.singleWhere((e) => e['id'] == 'rewards/item/theme_ocean')['value']
          as String,
    );
    expect(ocean['priceCoins'], 80);
    expect(ocean['owned'], false);
    expect(ocean['equipped'], false);
    expect(ocean['previewing'], false);
    expect(registry.snapshot()['actions'], isEmpty);
    aiOwner = 'other';
    expect(registry.snapshot()['context'], isEmpty);
    aiOwner = 'local:owner';

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
  int reads = 0;
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async {
    reads++;
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

void recoveryTests() {
  testWidgets('AI review old cancel cannot cancel a subsequent preview operation', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
    );
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('reward-preview/headgear_ipa'));
    await _scrollToCenter(tester, preview, delta: 200);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    final cancel = tester
        .widget<TextButton>(find.widgetWithText(TextButton, 'เลิกลอง'))
        .onPressed!;
    cancel();
    await tester.pumpAndSettle();
    await _scrollToCenter(tester, preview, delta: 200);
    await tester.tap(preview);
    await tester.pumpAndSettle();
    cancel();
    await tester.pump();
    expect(find.text('กำลังลองหมวก IPA'), findsOneWidget);
  });
  testWidgets('AI review overlapping item operations cannot leave a retired busy tile', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
    );
    await tester.pumpAndSettle();
    final first = find.byKey(const ValueKey('reward-purchase/theme_ocean'));
    await _scrollToCenter(tester, first, delta: 200);
    final firstAction = tester.widget<FilledButton>(first).onPressed!;
    final second = find.byKey(
      const ValueKey('reward-purchase/wallpaper_focus'),
    );
    await _scrollToCenter(tester, second, delta: 200);
    final secondAction = tester.widget<FilledButton>(second).onPressed!;
    final wait = Completer<void>();
    f.owners.pending = wait.future;
    firstAction();
    secondAction();
    await tester.pump();
    f.owners.pending = null;
    wait.complete();
    // Bounded pumps permit inspection of a spinner regression without settle timeout.
    for (var i = 0; i < 60; i++) {
      await tester.pump(const Duration(milliseconds: 20));
    }
    await _scrollToCenter(
      tester,
      find.byKey(const ValueKey('reward-item/wallpaper_focus')),
      delta: 200,
    );
    expect(find.text('กำลังบันทึกรายการ…'), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI retry is bounded and retired callbacks cannot restart reads',
    (tester) async {
      final f = await _RecoveryFixture.create();
      addTearDown(f.database.close);
      f.owners.failNextRead = true;
      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
      );
      await tester.pumpAndSettle();
      final retry = tester
          .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองใหม่'))
          .onPressed!;
      final wait = Completer<void>();
      f.owners.pending = wait.future;
      final before = f.owners.reads;
      retry();
      retry();
      retry();
      await tester.pump();
      final started = f.owners.reads - before;
      f.owners.pending = null;
      wait.complete();
      await tester.pumpAndSettle();
      expect(started, 1);
      final completed = f.owners.reads;
      retry();
      await tester.pumpAndSettle();
      expect(f.owners.reads, completed);
    },
  );

  for (final boundary in [
    'covered',
    'pop',
    'inactive',
    'replacement',
    'dispose',
  ]) {
    for (final pending in [false, true]) {
      testWidgets(
        'AI $boundary retires ${pending ? "pending" : "retained"} explicit purchase',
        (tester) async {
          final f = await _RecoveryFixture.create();
          addTearDown(f.database.close);
          final nav = GlobalKey<NavigatorState>();
          var active = true;
          var rewards = f.rewards;
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Text('home')),
            ),
          );
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => StatefulBuilder(
                builder: (context, set) {
                  update = set;
                  return TickerMode(
                    enabled: active,
                    child: AvatarEquipmentScreen(rewards: rewards),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final purchase = find.byKey(
            const ValueKey('reward-purchase/theme_ocean'),
          );
          await _scrollToCenter(tester, purchase, delta: 200);
          final action = tester.widget<FilledButton>(purchase).onPressed!;
          final before =
              (await f.database.select(f.database.rewardTransactions).get())
                  .map((r) => r.toJson())
                  .toList();
          final wait = Completer<void>();
          if (pending) {
            f.owners.pending = wait.future;
            action();
          }
          if (boundary == 'covered')
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
          if (boundary == 'pop') nav.currentState!.pop();
          if (boundary == 'inactive') {
            update(() => active = false);
            await tester.pump();
          }
          if (boundary == 'replacement') {
            update(() => rewards = f.makeRewards());
            await tester.pump();
          }
          if (boundary == 'dispose')
            await tester.pumpWidget(const SizedBox.shrink());
          if (!pending) action();
          f.owners.pending = null;
          wait.complete();
          await tester.pumpAndSettle();
          expect(
            (await f.database.select(f.database.rewardTransactions).get())
                .map((r) => r.toJson())
                .toList(),
            before,
          );
          expect(find.text('ซื้อรายการและบันทึกในเครื่องแล้ว'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final boundary in [
    'covered',
    'pop',
    'inactive',
    'replacement',
    'dispose',
  ]) {
    for (final pending in [false, true]) {
      testWidgets(
        'AI $boundary retires ${pending ? "pending" : "retained"} explicit equip',
        (tester) async {
          final f = await _RecoveryFixture.create();
          addTearDown(f.database.close);
          await f.rewards.purchase(
            itemId: 'theme_ocean',
            catalogVersion: 2,
            idempotencyKey: 'fixture-owned',
          );
          final nav = GlobalKey<NavigatorState>();
          var active = true;
          var rewards = f.rewards;
          late StateSetter update;
          await tester.pumpWidget(
            MaterialApp(
              navigatorKey: nav,
              home: const Scaffold(body: Text('home')),
            ),
          );
          nav.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => StatefulBuilder(
                builder: (context, set) {
                  update = set;
                  return TickerMode(
                    enabled: active,
                    child: AvatarEquipmentScreen(rewards: rewards),
                  );
                },
              ),
            ),
          );
          await tester.pumpAndSettle();
          final purchase = find.byKey(
            const ValueKey('reward-equip/theme_ocean'),
          );
          await _scrollToCenter(tester, purchase, delta: 200);
          final action = tester.widget<OutlinedButton>(purchase).onPressed!;
          final before =
              (await f.database.select(f.database.rewardTransactions).get())
                  .map((r) => r.toJson())
                  .toList();
          final wait = Completer<void>();
          if (pending) {
            f.owners.pending = wait.future;
            action();
          }
          if (boundary == 'covered')
            nav.currentState!.push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('cover')),
              ),
            );
          if (boundary == 'pop') nav.currentState!.pop();
          if (boundary == 'inactive') {
            update(() => active = false);
            await tester.pump();
          }
          if (boundary == 'replacement') {
            update(() => rewards = f.makeRewards());
            await tester.pump();
          }
          if (boundary == 'dispose')
            await tester.pumpWidget(const SizedBox.shrink());
          if (!pending) action();
          f.owners.pending = null;
          wait.complete();
          await tester.pumpAndSettle();
          expect(
            (await f.database.select(f.database.rewardTransactions).get())
                .map((r) => r.toJson())
                .toList(),
            before,
          );
          expect(find.text('ซื้อรายการและบันทึกในเครื่องแล้ว'), findsNothing);
          expect(tester.takeException(), isNull);
        },
      );
    }
  }

  for (final pending in [false, true]) {
    testWidgets('AI displayed owner change retires purchase pending=$pending', (
      tester,
    ) async {
      final f = await _RecoveryFixture.create();
      addTearDown(f.database.close);
      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
      );
      await tester.pumpAndSettle();
      final purchase = find.byKey(
        const ValueKey('reward-purchase/theme_ocean'),
      );
      await _scrollToCenter(tester, purchase, delta: 200);
      final action = tester.widget<FilledButton>(purchase).onPressed!;
      final wait = Completer<void>();
      if (pending) {
        f.owners.pending = wait.future;
        action();
      }
      // Real committed owner switch; both synthetic owners have sufficient coins/XP.
      await f.database.customStatement('UPDATE local_owners SET is_active = 0');
      await f.database.customStatement(
        "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('local:second', 1, 1)",
      );
      await f.database
          .into(f.database.pointsLedgerEntries)
          .insert(
            PointsLedgerEntriesCompanion.insert(
              id: 'second-xp',
              ownerId: 'local:second',
              idempotencyKey: 'second-xp',
              entryType: 'quizCorrect',
              amount: 200,
              occurredAtUtcMs: 1,
            ),
          );
      final direct = f.makeRewards();
      f.owners.pending = null;
      await direct.grantCoins(
        idempotencyKey: 'second-coins',
        amount: 100,
        sourceEventId: 'second-grant',
      );
      final before =
          (await f.database.select(f.database.rewardTransactions).get())
              .map((r) => r.toJson())
              .toList();
      if (!pending) action();
      wait.complete();
      await tester.pumpAndSettle();
      expect(
        (await f.database.select(f.database.rewardTransactions).get())
            .map((r) => r.toJson())
            .toList(),
        before,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets(
    'AI committed owner signal retires displayed preview and old cancel',
    (tester) async {
      final f = await _RecoveryFixture.create();
      addTearDown(f.database.close);
      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
      );
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('reward-preview/headgear_ipa'));
      await _scrollToCenter(tester, preview, delta: 200);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      final cancel = tester
          .widget<TextButton>(find.widgetWithText(TextButton, 'เลิกลอง'))
          .onPressed!;
      await f.database.transaction(() async {
        await f.database.customUpdate(
          'UPDATE local_owners SET is_active = 0',
          updates: {f.database.localOwners},
        );
        await f.database.customUpdate(
          "INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES ('local:second', 1, 1)",
          updates: {f.database.localOwners},
        );
      });
      await tester.pumpAndSettle();
      expect(find.text('กำลังลองหมวก IPA'), findsNothing);
      expect(find.text('XP สะสม 0'), findsOneWidget);
      await _scrollToCenter(tester, preview, delta: 200);
      await tester.tap(preview);
      await tester.pumpAndSettle();
      cancel();
      await tester.pump();
      expect(find.text('กำลังลองหมวก IPA'), findsOneWidget);
    },
  );

  testWidgets(
    'AI preview scroll scheduled before cover cannot move covered page',
    (tester) async {
      final f = await _RecoveryFixture.create();
      addTearDown(f.database.close);
      final nav = GlobalKey<NavigatorState>();
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: nav,
          home: AvatarEquipmentScreen(rewards: f.rewards),
        ),
      );
      await tester.pumpAndSettle();
      final preview = find.byKey(const ValueKey('reward-preview/headgear_ipa'));
      await _scrollToCenter(tester, preview, delta: 200);
      final controller = tester
          .widget<ListView>(find.byType(ListView))
          .controller!;
      final offset = controller.offset;
      tester.widget<OutlinedButton>(preview).onPressed!();
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('cover')),
        ),
      );
      await tester.pump();
      if (controller.hasClients) expect(controller.offset, offset);
      await tester.pumpAndSettle();
      nav.currentState!.pop();
      await tester.pumpAndSettle();
      expect(find.text('กำลังลองหมวก IPA'), findsNothing);
    },
  );

  testWidgets('AI retired failed retry after pop or disposal does nothing', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    f.owners.failNextRead = true;
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
    );
    await tester.pumpAndSettle();
    final retry = tester
        .widget<FilledButton>(find.widgetWithText(FilledButton, 'ลองใหม่'))
        .onPressed!;
    await tester.pumpWidget(const SizedBox.shrink());
    final reads = f.owners.reads;
    retry();
    await tester.pump();
    expect(f.owners.reads, reads);
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'AI immediate repeated owner read failure stays observed and can recover',
    (tester) async {
      final f = await _RecoveryFixture.create();
      addTearDown(f.database.close);
      f.owners.failNextRead = true;
      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
      );
      await tester.pumpAndSettle();
      f.owners.failNextRead = true;
      await tester.tap(find.widgetWithText(FilledButton, 'ลองใหม่'));
      await tester.pumpAndSettle();
      expect(
        find.text('ไม่สามารถอ่านข้อมูลรางวัลในเครื่องได้'),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.widgetWithText(FilledButton, 'ลองใหม่'));
      await tester.pumpAndSettle();
      expect(find.text('เหรียญคงเหลือ'), findsOneWidget);
    },
  );
  testWidgets('AI inactive initial destination does not read rewards', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    final before = f.owners.reads;
    await tester.pumpWidget(
      MaterialApp(
        home: TickerMode(
          enabled: false,
          child: AvatarEquipmentScreen(rewards: f.rewards),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(f.owners.reads, before);
  });
  testWidgets('AI failure fits Thai narrow screen with large text', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    f.owners.failNextRead = true;
    tester.view.physicalSize = const Size(360, 220);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      MaterialApp(
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(
            c,
          ).copyWith(textScaler: const TextScaler.linear(2)),
          child: child!,
        ),
        home: AvatarEquipmentScreen(rewards: f.rewards),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.byType(SingleChildScrollView), findsOneWidget);
  });
  testWidgets('AI old preview callback cannot change replacement display', (
    tester,
  ) async {
    final f = await _RecoveryFixture.create();
    addTearDown(f.database.close);
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: f.rewards)),
    );
    await tester.pumpAndSettle();
    final preview = find.byKey(const ValueKey('reward-preview/headgear_ipa'));
    await _scrollToCenter(tester, preview, delta: 200);
    final action = tester.widget<OutlinedButton>(preview).onPressed!;
    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: f.makeRewards())),
    );
    await tester.pumpAndSettle();
    action();
    await tester.pumpAndSettle();
    expect(find.text('กำลังลองหมวก IPA'), findsNothing);
  });
}

class _RecoveryFixture {
  _RecoveryFixture(this.database, this.owners);
  final AppDatabase database;
  final _BlockingOwners owners;
  late RewardUseCases rewards;
  int sequence = 0;
  RewardUseCases makeRewards() => RewardUseCases(
    owners: owners,
    repository: DriftRewardRepository(database),
    progress: ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.utc(2026),
    ),
    generateId: () => 'recovery-${sequence++}',
    nowUtc: () => DateTime.utc(2026),
  );
  static Future<_RecoveryFixture> create() async {
    final database = AppDatabase(NativeDatabase.memory());
    final owners = _BlockingOwners(
      DriftLocalOwnerRepository(
        database,
        generateId: () => 'recovery-owner',
        nowUtc: () => DateTime.utc(2026),
      ),
    );
    final owner = await owners.getOrCreateActiveOwner();
    await database
        .into(database.pointsLedgerEntries)
        .insert(
          PointsLedgerEntriesCompanion.insert(
            id: 'recovery-xp',
            ownerId: owner.id,
            idempotencyKey: 'recovery-xp',
            entryType: 'quizCorrect',
            amount: 200,
            occurredAtUtcMs: 1,
          ),
        );
    final f = _RecoveryFixture(database, owners);
    f.rewards = f.makeRewards();
    await f.rewards.grantCoins(
      idempotencyKey: 'recovery-coins',
      amount: 100,
      sourceEventId: 'recovery-grant',
    );
    return f;
  }
}
