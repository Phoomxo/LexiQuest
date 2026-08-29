import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_avatar_progression_eligibility.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';

void main() {
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
    expect(find.text('Level 3'), findsOneWidget);
    expect(find.text('XP สะสม 40'), findsOneWidget);
    expect(find.text('อีก 20 XP ถึง Level 4'), findsOneWidget);
    expect(
      find.bySemanticsLabel('เลเวลอวาตาร์ 3 จาก XP สะสม 40'),
      findsOneWidget,
    );
    expect(find.text('ธีมมาตรฐาน'), findsOneWidget);
    expect(find.text('เหรียญคงเหลือ'), findsOneWidget);
    expect(find.bySemanticsLabel('เหรียญคงเหลือ 40 เหรียญ'), findsOneWidget);
    expect(find.text('80 เหรียญ'), findsOneWidget);
    expect(find.text('80 คะแนน'), findsNothing);
    expect(find.text('40'), findsWidgets);
    expect(find.textContaining('Damage'), findsNothing);
    expect(find.text('ปลดล็อกที่ Level 4'), findsOneWidget);

    final oceanThemeCard = find.ancestor(
      of: find.text('ธีมมหาสมุทร'),
      matching: find.byType(Card),
    );
    expect(oceanThemeCard, findsOneWidget);
    await tester.tap(
      find.descendant(of: oceanThemeCard, matching: find.byType(FilledButton)),
    );
    await tester.pump();

    expect(find.text('เหรียญไม่เพียงพอ'), findsOneWidget);
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
