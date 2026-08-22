import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/economy_transaction_policy.dart';
import '../domain/reward_models.dart';

final class DriftRewardProjectionRebuilder {
  const DriftRewardProjectionRebuilder(
    this.database, {
    this.transactionPolicy = const EconomyTransactionPolicy(),
  });

  final db.AppDatabase database;
  final EconomyTransactionPolicy transactionPolicy;

  Future<void> rebuild(String ownerId) async {
    final transactions = await _transactions(ownerId);
    _requireValidSet(transactions);

    await (database.delete(
      database.ownedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();
    await (database.delete(
      database.equippedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).go();

    var balance = transactions
        .where(_isGrant)
        .fold<int>(0, (sum, transaction) => sum + transaction.amount);
    final owned = <String>{};

    for (final transaction in transactions) {
      if (transaction.transactionType != 'purchase') continue;
      final item = RewardCatalog.byId(transaction.itemId!)!;
      if (owned.contains(item.id) || balance < item.price) continue;
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
      balance += transaction.amount;
      owned.add(item.id);
    }

    for (final transaction in transactions) {
      if (transaction.transactionType != 'equip') continue;
      final item = RewardCatalog.byId(transaction.itemId!)!;
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

  Future<int> coinBalance(String ownerId) async {
    final transactions = await _transactions(ownerId);
    _requireValidSet(transactions);
    final acceptedPurchaseIds =
        (await (database.select(
              database.ownedRewardItems,
            )..where((row) => row.ownerId.equals(ownerId))).get())
            .map((row) => row.acquiredByTransactionId)
            .toSet();
    return transactions.fold<int>(0, (balance, transaction) {
      if (_isGrant(transaction) ||
          (transaction.transactionType == 'purchase' &&
              acceptedPurchaseIds.contains(transaction.id))) {
        return balance + transaction.amount;
      }
      return balance;
    });
  }

  Future<List<db.RewardTransaction>> _transactions(String ownerId) {
    return (database.select(database.rewardTransactions)
          ..where((row) => row.ownerId.equals(ownerId))
          ..orderBy([
            (row) => OrderingTerm.asc(row.occurredAtUtcMs),
            (row) => OrderingTerm.asc(row.id),
          ]))
        .get();
  }

  bool _isGrant(db.RewardTransaction transaction) =>
      transaction.transactionType == 'legacyEarningBackfill' ||
      transaction.transactionType == 'coinGrant';

  void _requireValidSet(List<db.RewardTransaction> transactions) {
    final earningSources = <String>{};
    for (final transaction in transactions) {
      _requireValid(transaction);
      if (_isGrant(transaction) &&
          !earningSources.add(transaction.sourceEventId!)) {
        throw StateError(
          'duplicate reward earning source ${transaction.sourceEventId}',
        );
      }
    }
  }

  void _requireValid(db.RewardTransaction transaction) {
    final item = transaction.itemId == null
        ? null
        : RewardCatalog.byId(transaction.itemId!);
    if (!transactionPolicy.isValidPersistedRow(
      idempotencyKey: transaction.idempotencyKey,
      transactionType: transaction.transactionType,
      amount: transaction.amount,
      itemId: transaction.itemId,
      slot: item?.slot,
      catalogVersion: transaction.catalogVersion,
      sourceEventId: transaction.sourceEventId,
      occurredAtUtcMs: transaction.occurredAtUtcMs,
    )) {
      throw StateError('invalid reward transaction ${transaction.id}');
    }
  }
}
