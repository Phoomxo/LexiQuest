import 'dart:async';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import 'drift_reward_projection_rebuilder.dart';
import '../domain/reward_models.dart';

final class DriftRewardRepository {
  DriftRewardRepository(this.database)
    : projections = DriftRewardProjectionRebuilder(database);

  final AppDatabase database;
  final DriftRewardProjectionRebuilder projections;
  Future<void> _writeGate = Future<void>.value();

  Future<RewardAccount> load(String ownerId) async {
    final balanceExpression = database.pointsLedgerEntries.amount.sum();
    final balanceRow =
        await (database.selectOnly(database.pointsLedgerEntries)
              ..addColumns([balanceExpression])
              ..where(database.pointsLedgerEntries.ownerId.equals(ownerId)))
            .getSingle();
    final ownedRows = await (database.select(
      database.ownedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    final equippedRows = await (database.select(
      database.equippedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    final transactionCountExpression = database.rewardTransactions.id.count();
    final transactionRow =
        await (database.selectOnly(database.rewardTransactions)
              ..addColumns([transactionCountExpression])
              ..where(database.rewardTransactions.ownerId.equals(ownerId)))
            .getSingle();
    return RewardAccount(
      balance: balanceRow.read(balanceExpression) ?? 0,
      catalogVersion: RewardCatalog.version,
      ownedItemIds: ownedRows.map((row) => row.itemId).toSet(),
      equippedBySlot: {for (final row in equippedRows) row.slot: row.itemId},
      transactionCount: transactionRow.read(transactionCountExpression) ?? 0,
    );
  }

  Future<PurchaseResult> purchase({
    required String ownerId,
    required RewardCatalogItem item,
    required String idempotencyKey,
    required String transactionId,
    required DateTime occurredAtUtc,
  }) {
    return _serialized(
      () => database.transaction(() async {
        final replay =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(idempotencyKey),
                ))
                .getSingleOrNull();
        if (replay != null) {
          if (replay.itemId != item.id ||
              replay.amount != -item.price ||
              replay.catalogVersion != item.catalogVersion) {
            throw const RewardException(
              RewardFailureCode.invalidIdempotencyKey,
            );
          }
          return PurchaseResult(
            status: PurchaseStatus.replayed,
            account: await load(ownerId),
          );
        }
        final owned =
            await (database.select(database.ownedRewardItems)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.itemId.equals(item.id),
                ))
                .getSingleOrNull();
        if (owned != null) {
          return PurchaseResult(
            status: PurchaseStatus.alreadyOwned,
            account: await load(ownerId),
          );
        }
        final account = await load(ownerId);
        if (account.balance < item.price) {
          throw const RewardException(RewardFailureCode.insufficientBalance);
        }
        final epoch = occurredAtUtc.millisecondsSinceEpoch;
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: 'purchase',
                amount: -item.price,
                itemId: Value(item.id),
                catalogVersion: item.catalogVersion,
                occurredAtUtcMs: epoch,
              ),
            );
        await _insertOutbox(
          ownerId: ownerId,
          transactionId: transactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return PurchaseResult(
          status: PurchaseStatus.purchased,
          account: await load(ownerId),
        );
      }),
    );
  }

  Future<RewardAccount> equip({
    required String ownerId,
    required RewardCatalogItem item,
    required String transactionId,
    required DateTime occurredAtUtc,
  }) {
    return _serialized(
      () => database.transaction(() async {
        if (item.price > 0) {
          final owned =
              await (database.select(database.ownedRewardItems)..where(
                    (row) =>
                        row.ownerId.equals(ownerId) &
                        row.itemId.equals(item.id),
                  ))
                  .getSingleOrNull();
          if (owned == null) {
            throw const RewardException(RewardFailureCode.notOwned);
          }
        }
        final epoch = occurredAtUtc.millisecondsSinceEpoch;
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: 'equip:$transactionId',
                transactionType: 'equip',
                amount: 0,
                itemId: Value(item.id),
                catalogVersion: item.catalogVersion,
                occurredAtUtcMs: epoch,
              ),
            );
        await _insertOutbox(
          ownerId: ownerId,
          transactionId: transactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return load(ownerId);
      }),
    );
  }

  Future<void> _insertOutbox({
    required String ownerId,
    required String transactionId,
    required int occurredAtUtcMs,
  }) {
    return database
        .into(database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: 'rewardTransaction:$transactionId:1',
            ownerId: ownerId,
            entityType: 'rewardTransaction',
            entityId: transactionId,
            operationKind: 'upsert',
            createdAtUtcMs: occurredAtUtcMs,
          ),
        );
  }

  Future<T> _serialized<T>(Future<T> Function() operation) async {
    final previous = _writeGate;
    final completer = Completer<void>();
    _writeGate = completer.future;
    try {
      await previous;
      return await operation();
    } finally {
      completer.complete();
    }
  }

  /// Grants XP for quest completion. Idempotent by [idempotencyKey] —
  /// uses insertOrIgnore so duplicate grants are silently skipped.
  Future<void> grantQuestXp({
    required String ownerId,
    required String idempotencyKey,
    required int xpAmount,
  }) async {
    if (xpAmount == 0) return;
    return _serialized(() async {
      await database.into(database.pointsLedgerEntries).insert(
            PointsLedgerEntriesCompanion.insert(
              id: idempotencyKey,
              ownerId: ownerId,
              idempotencyKey: idempotencyKey,
              entryType: 'questCompletion',
              amount: xpAmount,
              sourceEventId: Value(idempotencyKey),
              occurredAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
            ),
            mode: InsertMode.insertOrIgnore,
          );
    });
  }
}
