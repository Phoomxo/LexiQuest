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
    return (await projections.readLedger(ownerId)).account;
  }

  Stream<RewardAppearance> watchAppearance() {
    final query = database.select(database.localOwners).join([
      leftOuterJoin(
        database.equippedRewardItems,
        database.equippedRewardItems.ownerId.equalsExp(database.localOwners.id),
      ),
    ])..where(database.localOwners.isActive.equals(true));
    return query.watch().map((rows) {
      if (rows.isEmpty) return const RewardAppearance.empty();
      final ownerId = rows.first.readTable(database.localOwners).id;
      final equipped = <String, String>{};
      for (final row in rows) {
        final item = row.readTableOrNull(database.equippedRewardItems);
        if (item != null) equipped[item.slot] = item.itemId;
      }
      return RewardAppearance(ownerId: ownerId, equippedBySlot: equipped);
    });
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
        _validateItem(item, occurredAtUtc);
        final replay =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(idempotencyKey),
                ))
                .getSingleOrNull();
        if (replay != null) {
          if (replay.transactionType != 'purchase' ||
              replay.itemId != item.id ||
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
        final account = await load(ownerId);
        if (account.ownedItemIds.contains(item.id)) {
          return PurchaseResult(
            status: PurchaseStatus.alreadyOwned,
            account: await load(ownerId),
          );
        }
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

  Future<EquipResult> equip({
    required String ownerId,
    required RewardCatalogItem item,
    required String idempotencyKey,
    required String transactionId,
    required DateTime occurredAtUtc,
  }) {
    return _serialized(
      () => database.transaction(() async {
        _validateItem(item, occurredAtUtc);
        final replay =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(idempotencyKey),
                ))
                .getSingleOrNull();
        if (replay != null) {
          if (replay.transactionType != 'equip' ||
              replay.itemId != item.id ||
              replay.amount != 0 ||
              replay.catalogVersion != item.catalogVersion) {
            throw const RewardException(
              RewardFailureCode.invalidIdempotencyKey,
            );
          }
          return EquipResult(
            status: EquipStatus.replayed,
            account: await load(ownerId),
          );
        }
        final account = await load(ownerId);
        if (item.price > 0) {
          if (!account.ownedItemIds.contains(item.id)) {
            throw const RewardException(RewardFailureCode.notOwned);
          }
        }
        if (account.equippedBySlot[item.slot] == item.id) {
          return EquipResult(
            status: EquipStatus.alreadyEquipped,
            account: account,
          );
        }
        final epoch = occurredAtUtc.millisecondsSinceEpoch;
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
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
        return EquipResult(
          status: EquipStatus.equipped,
          account: await load(ownerId),
        );
      }),
    );
  }

  void _validateItem(RewardCatalogItem item, DateTime occurredAtUtc) {
    final canonical = RewardCatalog.byId(item.id);
    if (canonical == null ||
        canonical.price != item.price ||
        canonical.catalogVersion != item.catalogVersion ||
        canonical.slot != item.slot) {
      throw const RewardException(RewardFailureCode.staleCatalog);
    }
    if (!occurredAtUtc.isUtc || occurredAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError('reward time must be nonnegative UTC');
    }
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
}
