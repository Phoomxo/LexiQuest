import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_appearance_preferences.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/screens/appearance_settings_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

void main() {
  testWidgets('owned appearance previews only equip on confirmation', (
    tester,
  ) async {
    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final appearance = AppAppearanceController.system();
    final now = DateTime.utc(2026, 11, 13);
    var id = 0;
    String nextId() => 'synthetic-appearance-${++id}';
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: nextId,
      nowUtc: () => now,
    );
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: nextId,
      nowUtc: () => now,
    );
    final dependencies = AppDependencies(
      runtimeStatus: const AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: RuntimeAvailability.unavailable,
        supabase: RuntimeAvailability.unavailable,
        backends: RuntimeAvailability.unavailable,
      ),
      config: null,
      guestSessionService: _GuestSession(),
      database: database,
      localOwners: owners,
      rewards: rewards,
      progress: ProgressUseCases(
        owners: owners,
        queries: DriftProgressQueries(database),
        nowUtc: () => now,
      ),
    );

    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.resetDevicePixelRatio);
    addTearDown(tester.view.resetPhysicalSize);
    try {
      final baseline = await _withFrames(
        tester,
        'reward fixture setup',
        () async {
          final owner = await owners.getOrCreateActiveOwner();
          await database
              .into(database.pointsLedgerEntries)
              .insert(
                PointsLedgerEntriesCompanion.insert(
                  id: 'synthetic-appearance-seed',
                  ownerId: owner.id,
                  idempotencyKey: 'synthetic-appearance-seed',
                  entryType: 'learning',
                  amount: 200,
                  occurredAtUtcMs: now.millisecondsSinceEpoch,
                ),
              );
          for (final item in ['headgear_ipa', 'wallpaper_focus']) {
            final purchase = await rewards.purchase(
              expectedOwnerId: owner.id,
              itemId: item,
              catalogVersion: RewardCatalog.version,
              idempotencyKey: 'synthetic-purchase-$item',
            );
            expect(purchase.status, PurchaseStatus.purchased);
          }
          return rewards.load();
        },
      );
      Future<void> expectAccount(
        int equipCount,
        Map<String, String> worn,
      ) async {
        final account = await _withFrames(
          tester,
          'reward account readback',
          rewards.load,
        );
        expect(account.balance, baseline.balance);
        expect(account.ownedItemIds, baseline.ownedItemIds);
        expect(
          account.transactionCount,
          baseline.transactionCount + equipCount,
        );
        expect(account.equippedBySlot, worn);
      }

      await tester.pumpWidget(
        AppAppearanceScope(
          controller: appearance,
          child: AppDependenciesScope(
            dependencies: dependencies,
            child: MaterialApp(
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(textScaler: const TextScaler.linear(2)),
                child: child!,
              ),
              home: const MainNavigationScreen(),
            ),
          ),
        ),
      );
      await _tap(tester, 'บัญชี');
      await _tap(tester, 'ของสะสม');
      await _tap(tester, 'ของตกแต่งของฉัน');
      await _tap(tester, 'หมวกนักออกเสียง');
      await _wait(tester, find.text('ลองสวมหมวก'));
      await expectAccount(0, {});
      await _tap(tester, 'ยกเลิก');
      await expectAccount(0, {});
      await _tap(tester, 'หมวกนักออกเสียง');
      await _tap(tester, 'ใช้หมวกใบนี้');
      await _wait(tester, find.text('สวมหมวกแล้ว'));
      const hat = {'headgear': 'headgear_ipa'};
      await expectAccount(1, hat);
      await _tap(tester, 'กลับไปดูของสะสม');
      await _wait(tester, find.text('ของตกแต่งของฉัน'));
      await _tapFinder(tester, find.byType(BackButton));
      await _wait(tester, find.text('โปรไฟล์'));
      await _tapFinder(
        tester,
        find.byKey(const ValueKey('shell-drawer-button')),
      );
      await _tap(tester, 'ตั้งค่า');
      await _tap(tester, 'การแสดงผล');
      await _tap(tester, 'พื้นหลังหน้าฝึก');
      await _wait(tester, find.text('มาตรฐาน · กำลังใช้'));
      await _tap(tester, 'พื้นหลังสมาธิ');
      await _wait(tester, find.text('ลองพื้นหลังสมาธิ'));
      await expectAccount(1, hat);
      await _tap(tester, 'เก็บพื้นหลังเดิม');
      await _wait(tester, find.text('มาตรฐาน · กำลังใช้'));
      await expectAccount(1, hat);
      await _tap(tester, 'พื้นหลังสมาธิ');
      await _tap(tester, 'ใช้พื้นหลังนี้');
      await _wait(tester, find.text('ใช้พื้นหลังสมาธิแล้ว'));
      await expectAccount(2, {...hat, 'wallpaper': 'wallpaper_focus'});
      await _tap(tester, 'กลับไปที่การแสดงผล');
      await _wait(tester, find.byType(AppearanceSettingsScreen));
      await _wait(tester, find.text('พื้นหลังสมาธิ · กำลังใช้'));
      await _tap(tester, 'พื้นหลังหน้าฝึก');
      await _wait(tester, find.text('พื้นหลังสมาธิ · กำลังใช้'));
      await _tapFinder(
        tester,
        find.widgetWithText(ListTile, 'พื้นหลังมาตรฐาน'),
      );
      await _tap(tester, 'ใช้พื้นหลังนี้');
      await _wait(tester, find.text('มาตรฐาน · กำลังใช้'));
      await expectAccount(3, {...hat, 'wallpaper': 'wallpaper_default'});
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _withFrames(tester, 'database close', database.close);
      appearance.dispose();
    }
  });
}

Future<void> _tap(WidgetTester tester, String label) =>
    _tapFinder(tester, find.text(label));

Future<void> _tapFinder(WidgetTester tester, Finder target) async {
  await _wait(tester, target);
  await tester.ensureVisible(target.first);
  await tester.pump();
  if (target.hitTestable().evaluate().isEmpty) {
    await tester.scrollUntilVisible(
      target.hitTestable(),
      150,
      scrollable: find.byType(Scrollable).hitTestable().last,
    );
  }
  await tester.tap(target.hitTestable().first);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _wait(WidgetTester tester, Finder target) async {
  for (var frame = 0; frame < 72; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
    if (target.evaluate().isNotEmpty) return;
    final candidates = find.byType(Scrollable).hitTestable();
    if (frame.isOdd && candidates.evaluate().isNotEmpty) {
      await tester.drag(candidates.last, const Offset(0, -150));
      await tester.pump();
    }
  }
  fail('Timed out waiting for $target');
}

Future<T> _withFrames<T>(
  WidgetTester tester,
  String description,
  Future<T> Function() operation,
) async {
  var finished = false;
  final result = operation().whenComplete(() => finished = true);
  unawaited(result.then<void>((_) {}, onError: (Object _, StackTrace _) {}));
  for (var frame = 0; frame < 80 && !finished; frame++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 5)),
    );
    await tester.pump(const Duration(milliseconds: 20));
  }
  if (!finished) fail('Timed out waiting for $description');
  return result;
}

final class _GuestSession extends Fake implements GuestSessionService {}
