import 'dart:async';

import 'package:drift/drift.dart' show DatabaseConnection;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/select_wallpaper_screen.dart';

void main() {
  testWidgets('equipment surface reads durable reward ownership', (
    tester,
  ) async {
    final database = AppDatabase(
      DatabaseConnection(
        NativeDatabase.memory(),
        closeStreamsSynchronously: true,
      ),
    );
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    final rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: () => 'tx',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );

    try {
      await _withFrames(tester, 'owner setup', owners.getOrCreateActiveOwner);
      await tester.pumpWidget(
        MaterialApp(home: AvatarEquipmentScreen(rewards: rewards)),
      );
      final wallpaper = find.text('พื้นหลังหน้าฝึก');
      await _wait(tester, wallpaper);

      expect(find.text('แต่งตัวละคร'), findsOneWidget);
      expect(find.text('หมวกนักออกเสียง'), findsNothing);

      await tester.ensureVisible(wallpaper);
      await tester.pump();
      await tester.tap(wallpaper);
      await _wait(tester, find.text('มาตรฐาน · กำลังใช้'));
      expect(find.byType(SelectWallpaperScreen), findsOneWidget);
      expect(find.text('พื้นหลังสมาธิ'), findsNothing);
      final account = await _withFrames(
        tester,
        'reward readback',
        rewards.load,
      );
      expect(account.transactionCount, 0);

      final back = find.text('กลับไปแต่งตัวละคร');
      await tester.ensureVisible(back);
      await tester.pump();
      await tester.tap(back);
      await _wait(tester, find.text('แต่งตัวละคร'));
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      await _withFrames(tester, 'database close', database.close);
    }
  });
}

Future<void> _wait(WidgetTester tester, Finder finder) async {
  for (var frame = 0; frame < 80 && finder.evaluate().isEmpty; frame++) {
    await _pump(tester);
  }
  expect(finder, findsOneWidget);
  await tester.pump(const Duration(milliseconds: 400));
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
    await _pump(tester);
  }
  if (!finished) fail('Timed out waiting for $description');
  return result;
}

Future<void> _pump(WidgetTester tester) async {
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 5)),
  );
  await tester.pump(const Duration(milliseconds: 20));
}
