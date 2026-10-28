import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/reward_models.dart';

final class DriftRewardProjectionRebuilder {
  const DriftRewardProjectionRebuilder(this.database);

  final db.AppDatabase database;

  Future<void> rebuild(String ownerId) async {
    await (database.delete(database.pointsLedgerEntries)..where(
          (row) =>
              row.ownerId.equals(ownerId) &
              row.entryType.equals('rewardPurchase'),
        ))
        .go();
    await (database.delete(
      database.ownedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    await (database.delete(
      database.equippedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();

    final transactions =
        await (database.select(database.rewardTransactions)
              ..where((row) => row.ownerId.equals(ownerId))
              ..orderBy([
                (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    final balanceExpression = database.pointsLedgerEntries.amount.sum();
    final balanceRow =
        await (database.selectOnly(database.pointsLedgerEntries)
              ..addColumns([balanceExpression])
              ..where(database.pointsLedgerEntries.ownerId.equals(ownerId)))
            .getSingle();
    var balance = balanceRow.read(balanceExpression) ?? 0;
    final owned = <String>{};

    for (final transaction in transactions) {
      if (transaction.transactionType != 'purchase') continue;
      final item = _validatedItem(transaction);
      if (owned.contains(item.id) || balance < item.price) continue;
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            db.PointsLedgerEntriesCompanion.insert(
              id: 'points:${transaction.id}',
              ownerId: ownerId,
              idempotencyKey: 'reward:${transaction.idempotencyKey}',
              entryType: 'rewardPurchase',
              amount: -item.price,
              sourceEventId: Value(transaction.id),
              occurredAtUtcMs: transaction.occurredAtUtcMs,
            ),
          );
      await database
          .into(database.ownedRewardItems)
          .insert(
            db.OwnedRewardItemsCompanion.insert(
              id: 'owned:$ownerId:${item.id}',
              ownerId: ownerId,
              itemId: item.id,
              catalogVersion: item.catalogVersion,
              acquiredByTransactionId: transaction.id,
              acquiredAtUtcMs: transaction.occurredAtUtcMs,
            ),
          );
      balance -= item.price;
      owned.add(item.id);
    }

    for (final transaction in transactions) {
      if (transaction.transactionType != 'equip') continue;
      final item = _validatedItem(transaction);
      if (item.price > 0 && !owned.contains(item.id)) continue;
      await database
          .into(database.equippedRewardItems)
          .insertOnConflictUpdate(
            db.EquippedRewardItemsCompanion.insert(
              id: 'equipped:$ownerId:${item.slot}',
              ownerId: ownerId,
              slot: item.slot,
              itemId: item.id,
              equippedAtUtcMs: transaction.occurredAtUtcMs,
            ),
          );
    }
  }

  RewardCatalogItem _validatedItem(db.RewardTransaction transaction) {
    final itemId = transaction.itemId;
    final item = itemId == null ? null : RewardCatalog.byId(itemId);
    if (item == null ||
        transaction.catalogVersion != RewardCatalog.version ||
        item.catalogVersion != transaction.catalogVersion ||
        (transaction.transactionType == 'purchase' &&
            transaction.amount != -item.price) ||
        (transaction.transactionType == 'equip' && transaction.amount != 0) ||
        (transaction.transactionType != 'purchase' &&
            transaction.transactionType != 'equip')) {
      throw StateError('invalid reward transaction ${transaction.id}');
    }
    return item;
  }
}
