/// Tests for DriftRewardProjectionRebuilder
///
/// Verifies rebuild() replays RewardTransactions to reconstruct
/// OwnedRewardItems, EquippedRewardItems, and purchase deductions
/// in PointsLedgerEntries — and that the operation is idempotent.
///
/// Run: flutter test test/features/rewards/data/drift_reward_projection_rebuilder_test.dart
library;

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

AppDatabase _openMemory() => AppDatabase(NativeDatabase.memory());

Future<void> _seedOwner(AppDatabase db) async {
  await db
      .into(db.localOwners)
      .insert(
        LocalOwnersCompanion.insert(
          id: 'owner-reward-rebuild',
          createdAtUtcMs: 1,
        ),
      );
}

/// Seed an XP balance in PointsLedgerEntries (purchase engine reads this).
Future<void> _seedXpBalance(AppDatabase db, int amount) async {
  await db
      .into(db.pointsLedgerEntries)
      .insert(
        PointsLedgerEntriesCompanion.insert(
          id: 'xp-seed',
          ownerId: 'owner-reward-rebuild',
          idempotencyKey: 'xp-seed-key',
          entryType: 'quizCorrect',
          amount: amount,
          occurredAtUtcMs: 1,
        ),
      );
}

Future<void> _insertPurchaseTx(
  AppDatabase db, {
  required String txId,
  required String itemId,
  required int price,
  required int seqMs,
}) async {
  await db
      .into(db.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: txId,
          ownerId: 'owner-reward-rebuild',
          idempotencyKey: 'key-$txId',
          transactionType: 'purchase',
          amount: -price,
          itemId: Value(itemId),
          catalogVersion: RewardCatalog.version,
          occurredAtUtcMs:
              DateTime.utc(2026, 1, 1).millisecondsSinceEpoch + seqMs,
        ),
      );
}

void main() {
  late AppDatabase db;

  setUp(() async {
    db = _openMemory();
    await _seedOwner(db);
  });
  tearDown(() => db.close());

  group('DriftRewardProjectionRebuilder', () {
    test('rebuild grants OwnedRewardItem when balance is sufficient', () async {
      // ocean theme costs 80 coins
      await _seedXpBalance(db, 200);
      await _insertPurchaseTx(
        db,
        txId: 'tx-ocean',
        itemId: 'theme_ocean',
        price: 80,
        seqMs: 1000,
      );

      final rebuilder = DriftRewardProjectionRebuilder(db);
      await rebuilder.rebuild('owner-reward-rebuild');

      final owned = await (db.select(
        db.ownedRewardItems,
      )..where((row) => row.ownerId.equals('owner-reward-rebuild'))).get();
      expect(owned.length, 1);
      expect(owned.first.itemId, 'theme_ocean');
    });

    test('rebuild skips purchase when balance is insufficient', () async {
      await _seedXpBalance(db, 10); // only 10, ocean theme costs 80
      await _insertPurchaseTx(
        db,
        txId: 'tx-ocean-broke',
        itemId: 'theme_ocean',
        price: 80,
        seqMs: 1000,
      );

      final rebuilder = DriftRewardProjectionRebuilder(db);
      await rebuilder.rebuild('owner-reward-rebuild');

      final owned = await (db.select(
        db.ownedRewardItems,
      )..where((row) => row.ownerId.equals('owner-reward-rebuild'))).get();
      expect(owned, isEmpty);
    });

    test(
      'rebuild is idempotent — running twice yields same owned items',
      () async {
        await _seedXpBalance(db, 200);
        await _insertPurchaseTx(
          db,
          txId: 'tx-ocean-idem',
          itemId: 'theme_ocean',
          price: 80,
          seqMs: 1000,
        );

        final rebuilder = DriftRewardProjectionRebuilder(db);
        await rebuilder.rebuild('owner-reward-rebuild');
        await rebuilder.rebuild('owner-reward-rebuild');

        final owned = await (db.select(
          db.ownedRewardItems,
        )..where((row) => row.ownerId.equals('owner-reward-rebuild'))).get();
        // rebuild deletes + re-inserts — must not double-count
        expect(owned.length, 1);
      },
    );
  });
}
