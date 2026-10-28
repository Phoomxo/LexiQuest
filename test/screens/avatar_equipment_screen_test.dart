import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
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
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: () => 'tx',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );

    await tester.pumpWidget(
      MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ร้านค้ารางวัล'), findsOneWidget);
    expect(find.text('ธีมมาตรฐาน'), findsOneWidget);
    expect(find.text('0'), findsWidgets);
    expect(find.textContaining('Damage'), findsNothing);
  });
}
