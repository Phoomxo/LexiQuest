import 'dart:async';
import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../domain/economy_transaction_policy.dart';
import '../domain/reward_models.dart';
import 'drift_economy_cutover.dart';
import 'drift_reward_projection_rebuilder.dart';

final class DriftRewardRepository {
  DriftRewardRepository(
    this.database, {
    DriftEconomyCutover? cutover,
    this.awardPolicy = const EconomyAwardPolicyV1(),
  }) : cutover = cutover ?? DriftEconomyCutover(database),
       projections = DriftRewardProjectionRebuilder(database);

  final AppDatabase database;
  final DriftEconomyCutover cutover;
  final EconomyAwardPolicyV1 awardPolicy;
  final DriftRewardProjectionRebuilder projections;
  static const EconomyTransactionPolicy _transactionPolicy =
      EconomyTransactionPolicy();
  Future<void> _writeGate = Future<void>.value();

  Future<RewardAccount> load(String ownerId) {
    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      return database.transaction(() async {
        await projections.rebuild(ownerId);
        return _loadSeparated(ownerId);
      });
    });
  }

  Future<PurchaseResult> purchase({
    required String ownerId,
    required RewardCatalogItem item,
    required String idempotencyKey,
    required String transactionId,
    required DateTime occurredAtUtc,
  }) {
    _requireIdentifier(ownerId, 'ownerId');
    _requireIdentifier(idempotencyKey, 'idempotencyKey');
    _requireIdentifier(transactionId, 'transactionId');
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    final epoch = occurredAtUtc.millisecondsSinceEpoch;
    _requireValidPersistedRewardTransaction(
      idempotencyKey: idempotencyKey,
      transactionType: EconomyTransactionType.purchase.name,
      amount: -item.price,
      itemId: item.id,
      slot: item.slot,
      catalogVersion: item.catalogVersion,
      sourceEventId: null,
      occurredAtUtcMs: epoch,
    );
    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      return database.transaction(() async {
        await projections.rebuild(ownerId);
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
              replay.catalogVersion != item.catalogVersion ||
              replay.sourceEventId != null) {
            throw const RewardException(
              RewardFailureCode.invalidIdempotencyKey,
            );
          }
          return PurchaseResult(
            status: PurchaseStatus.replayed,
            account: await _loadSeparated(ownerId),
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
            account: await _loadSeparated(ownerId),
          );
        }
        final account = await _loadSeparated(ownerId);
        if (account.coinBalance < item.price) {
          throw const RewardException(RewardFailureCode.insufficientBalance);
        }
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: EconomyTransactionType.purchase.name,
                amount: -item.price,
                itemId: Value(item.id),
                catalogVersion: item.catalogVersion,
                occurredAtUtcMs: epoch,
              ),
            );
        await _ensureOutbox(
          ownerId: ownerId,
          transactionId: transactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return PurchaseResult(
          status: PurchaseStatus.purchased,
          account: await _loadSeparated(ownerId),
        );
      });
    });
  }

  Future<RewardAccount> equip({
    required String ownerId,
    required RewardCatalogItem item,
    required String transactionId,
    required DateTime occurredAtUtc,
  }) {
    _requireIdentifier(ownerId, 'ownerId');
    _requireIdentifier(transactionId, 'transactionId');
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    final idempotencyKey = 'equip:$transactionId';
    final epoch = occurredAtUtc.millisecondsSinceEpoch;
    _requireValidPersistedRewardTransaction(
      idempotencyKey: idempotencyKey,
      transactionType: EconomyTransactionType.equip.name,
      amount: 0,
      itemId: item.id,
      slot: item.slot,
      catalogVersion: item.catalogVersion,
      sourceEventId: null,
      occurredAtUtcMs: epoch,
    );
    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      return database.transaction(() async {
        await projections.rebuild(ownerId);
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
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: EconomyTransactionType.equip.name,
                amount: 0,
                itemId: Value(item.id),
                catalogVersion: item.catalogVersion,
                occurredAtUtcMs: epoch,
              ),
            );
        await _ensureOutbox(
          ownerId: ownerId,
          transactionId: transactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return _loadSeparated(ownerId);
      });
    });
  }

  Future<CoinGrantResult> grantCoins({
    required String ownerId,
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
    required DateTime occurredAtUtc,
  }) {
    _requireIdentifier(ownerId, 'ownerId');
    _requireIdentifier(idempotencyKey, 'idempotencyKey');
    _requireIdentifier(sourceEventId, 'sourceEventId');
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    final epoch = occurredAtUtc.millisecondsSinceEpoch;
    final transactionId = _coinTransactionId(ownerId, idempotencyKey);
    _requireIdentifier(transactionId, 'transactionId');
    _requireValidPersistedRewardTransaction(
      idempotencyKey: idempotencyKey,
      transactionType: EconomyTransactionType.coinGrant.name,
      amount: amount,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: epoch,
    );

    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      return database.transaction(() async {
        final byId = await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(transactionId))).getSingleOrNull();
        if (byId != null) {
          _requireExactCoinGrant(
            byId,
            ownerId: ownerId,
            idempotencyKey: idempotencyKey,
            amount: amount,
            sourceEventId: sourceEventId,
            occurredAtUtcMs: epoch,
          );
          await _ensureOutbox(
            ownerId: ownerId,
            transactionId: byId.id,
            occurredAtUtcMs: byId.occurredAtUtcMs,
          );
          await projections.rebuild(ownerId);
          return CoinGrantResult.replayed;
        }
        final byIdempotency =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(idempotencyKey),
                ))
                .getSingleOrNull();
        if (byIdempotency != null) {
          throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
        }
        final sameSource =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.sourceEventId.equals(sourceEventId) &
                      row.transactionType.isIn(const [
                        'legacyEarningBackfill',
                        'coinGrant',
                      ]),
                ))
                .get();
        if (sameSource.length > 1) {
          throw StateError('duplicate coin evidence for $sourceEventId');
        }
        if (sameSource.isNotEmpty) {
          final existing = sameSource.single;
          if (!_isValidPersistedRewardTransaction(existing) ||
              existing.ownerId != ownerId ||
              existing.amount != amount ||
              existing.sourceEventId != sourceEventId ||
              existing.occurredAtUtcMs != epoch) {
            throw const RewardException(
              RewardFailureCode.invalidIdempotencyKey,
            );
          }
          if (existing.transactionType == 'legacyEarningBackfill') {
            return CoinGrantResult.capturedByLegacyBackfill;
          }
          return CoinGrantResult.replayed;
        }

        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: transactionId,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                transactionType: EconomyTransactionType.coinGrant.name,
                amount: amount,
                catalogVersion: 0,
                sourceEventId: Value(sourceEventId),
                occurredAtUtcMs: epoch,
              ),
            );
        await _ensureOutbox(
          ownerId: ownerId,
          transactionId: transactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return CoinGrantResult.inserted;
      });
    });
  }

  Future<QuestEconomyGrantResult> grantQuestXpAndCoins({
    required String ownerId,
    required String sourceEventId,
    required int xpAmount,
    required DateTime occurredAtUtc,
  }) {
    _requireIdentifier(ownerId, 'ownerId');
    _requireIdentifier(sourceEventId, 'sourceEventId');
    if (xpAmount <= 0) throw ArgumentError.value(xpAmount, 'xpAmount');
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    final award = awardPolicy.evaluate(
      sourceEventId: sourceEventId,
      amount: xpAmount,
      eligible: true,
    );
    final epoch = occurredAtUtc.millisecondsSinceEpoch;
    final pointId = _questPointId(ownerId, award.xpIdempotencyKey);
    final coinTransactionId = _coinTransactionId(
      ownerId,
      award.coinIdempotencyKey,
    );
    _requireIdentifier(pointId, 'pointId');
    _requireIdentifier(coinTransactionId, 'transactionId');
    _requireValidPersistedRewardTransaction(
      idempotencyKey: award.coinIdempotencyKey,
      transactionType: EconomyTransactionType.coinGrant.name,
      amount: award.coinAmount,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: epoch,
    );

    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      return database.transaction(() async {
        final xp =
            await (database.select(database.pointsLedgerEntries)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(award.xpIdempotencyKey),
                ))
                .getSingleOrNull();
        final coins =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(award.coinIdempotencyKey),
                ))
                .getSingleOrNull();
        if (xp != null || coins != null) {
          if (xp == null || coins == null) {
            throw StateError('partial quest economy grant for $sourceEventId');
          }
          _requireExactQuestXp(
            xp,
            ownerId: ownerId,
            idempotencyKey: award.xpIdempotencyKey,
            amount: award.xpAmount,
            sourceEventId: sourceEventId,
            occurredAtUtcMs: epoch,
          );
          _requireExactCoinGrant(
            coins,
            ownerId: ownerId,
            idempotencyKey: award.coinIdempotencyKey,
            amount: award.coinAmount,
            sourceEventId: sourceEventId,
            occurredAtUtcMs: epoch,
          );
          await _ensureOutbox(
            ownerId: ownerId,
            transactionId: coins.id,
            occurredAtUtcMs: coins.occurredAtUtcMs,
          );
          await projections.rebuild(ownerId);
          return QuestEconomyGrantResult.replayed;
        }

        final legacyXp =
            await (database.select(database.pointsLedgerEntries)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.entryType.equals('questCompletion') &
                      row.sourceEventId.equals(sourceEventId),
                ))
                .get();
        final legacyCoins =
            await (database.select(database.rewardTransactions)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.sourceEventId.equals(sourceEventId) &
                      row.transactionType.isIn(const [
                        'legacyEarningBackfill',
                        'coinGrant',
                      ]),
                ))
                .get();
        if (legacyXp.isNotEmpty || legacyCoins.isNotEmpty) {
          if (legacyXp.length != 1 ||
              legacyCoins.length != 1 ||
              legacyXp.single.amount != award.xpAmount ||
              legacyCoins.single.amount != award.coinAmount) {
            throw StateError(
              'invalid legacy quest economy grant $sourceEventId',
            );
          }
          await projections.rebuild(ownerId);
          return QuestEconomyGrantResult.replayed;
        }

        await database
            .into(database.pointsLedgerEntries)
            .insert(
              PointsLedgerEntriesCompanion.insert(
                id: pointId,
                ownerId: ownerId,
                idempotencyKey: award.xpIdempotencyKey,
                entryType: 'questCompletion',
                amount: award.xpAmount,
                sourceEventId: Value(sourceEventId),
                occurredAtUtcMs: epoch,
              ),
            );
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: coinTransactionId,
                ownerId: ownerId,
                idempotencyKey: award.coinIdempotencyKey,
                transactionType: EconomyTransactionType.coinGrant.name,
                amount: award.coinAmount,
                catalogVersion: 0,
                sourceEventId: Value(sourceEventId),
                occurredAtUtcMs: epoch,
              ),
            );
        await _ensureOutbox(
          ownerId: ownerId,
          transactionId: coinTransactionId,
          occurredAtUtcMs: epoch,
        );
        await projections.rebuild(ownerId);
        return QuestEconomyGrantResult.inserted;
      });
    });
  }

  @Deprecated('Use grantQuestXpAndCoins for new quest completion writes.')
  Future<void> grantQuestXp({
    required String ownerId,
    required String idempotencyKey,
    required int xpAmount,
  }) {
    _requireIdentifier(idempotencyKey, 'idempotencyKey');
    if (xpAmount < 0) throw ArgumentError.value(xpAmount, 'xpAmount');
    return _serialized(() async {
      await cutover.ensureSeparated(ownerId);
      if (xpAmount == 0) return;
      await database.transaction(() async {
        final existing =
            await (database.select(database.pointsLedgerEntries)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.idempotencyKey.equals(idempotencyKey),
                ))
                .getSingleOrNull();
        if (existing != null) {
          if (existing.entryType != 'questCompletion' ||
              existing.amount != xpAmount ||
              existing.sourceEventId != idempotencyKey) {
            throw StateError('quest xp idempotency collision $idempotencyKey');
          }
          return;
        }
        await database
            .into(database.pointsLedgerEntries)
            .insert(
              PointsLedgerEntriesCompanion.insert(
                id: idempotencyKey,
                ownerId: ownerId,
                idempotencyKey: idempotencyKey,
                entryType: 'questCompletion',
                amount: xpAmount,
                sourceEventId: Value(idempotencyKey),
                occurredAtUtcMs: DateTime.now().toUtc().millisecondsSinceEpoch,
              ),
            );
      });
    });
  }

  Future<RewardAccount> _loadSeparated(String ownerId) async {
    final ownedRows = await (database.select(
      database.ownedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    final equippedRows = await (database.select(
      database.equippedRewardItems,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    final transactionRows = await (database.select(
      database.rewardTransactions,
    )..where((row) => row.ownerId.equals(ownerId))).get();
    return RewardAccount(
      coinBalance: await projections.coinBalance(ownerId),
      catalogVersion: RewardCatalog.version,
      ownedItemIds: ownedRows.map((row) => row.itemId).toSet(),
      equippedBySlot: {for (final row in equippedRows) row.slot: row.itemId},
      transactionCount: transactionRows
          .where(
            (row) =>
                row.transactionType == 'purchase' ||
                row.transactionType == 'equip',
          )
          .length,
    );
  }

  Future<void> _ensureOutbox({
    required String ownerId,
    required String transactionId,
    required int occurredAtUtcMs,
  }) async {
    final operationId = 'rewardTransaction:$transactionId:1';
    final existing = await (database.select(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (existing != null) {
      if (existing.ownerId != ownerId ||
          existing.entityType != 'rewardTransaction' ||
          existing.entityId != transactionId ||
          existing.operationKind != 'upsert' ||
          existing.payloadVersion != 1 ||
          existing.createdAtUtcMs != occurredAtUtcMs) {
        throw StateError('reward outbox identity collision $operationId');
      }
      return;
    }
    await database
        .into(database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: operationId,
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

  void _requireValidPersistedRewardTransaction({
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String? itemId,
    required String? slot,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (!_transactionPolicy.isValidPersistedRow(
      idempotencyKey: idempotencyKey,
      transactionType: transactionType,
      amount: amount,
      itemId: itemId,
      slot: slot,
      catalogVersion: catalogVersion,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: occurredAtUtcMs,
    )) {
      throw ArgumentError('invalid persisted reward transaction');
    }
  }

  bool _isValidPersistedRewardTransaction(RewardTransaction transaction) {
    final item = transaction.itemId == null
        ? null
        : RewardCatalog.byId(transaction.itemId!);
    return _transactionPolicy.isValidPersistedRow(
      idempotencyKey: transaction.idempotencyKey,
      transactionType: transaction.transactionType,
      amount: transaction.amount,
      itemId: transaction.itemId,
      slot: item?.slot,
      catalogVersion: transaction.catalogVersion,
      sourceEventId: transaction.sourceEventId,
      occurredAtUtcMs: transaction.occurredAtUtcMs,
    );
  }

  void _requireExactCoinGrant(
    RewardTransaction transaction, {
    required String ownerId,
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (!_isValidPersistedRewardTransaction(transaction) ||
        transaction.ownerId != ownerId ||
        transaction.idempotencyKey != idempotencyKey ||
        transaction.transactionType != 'coinGrant' ||
        transaction.amount != amount ||
        transaction.itemId != null ||
        transaction.catalogVersion != 0 ||
        transaction.sourceEventId != sourceEventId ||
        transaction.occurredAtUtcMs != occurredAtUtcMs) {
      throw const RewardException(RewardFailureCode.invalidIdempotencyKey);
    }
  }

  void _requireExactQuestXp(
    PointsLedgerEntry point, {
    required String ownerId,
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (point.ownerId != ownerId ||
        point.idempotencyKey != idempotencyKey ||
        point.entryType != 'questCompletion' ||
        point.amount != amount ||
        point.sourceEventId != sourceEventId ||
        point.occurredAtUtcMs != occurredAtUtcMs) {
      throw StateError('quest xp identity collision ${point.id}');
    }
  }

  String _coinTransactionId(String ownerId, String idempotencyKey) =>
      'reward:coin:${sha256.convert(utf8.encode('$ownerId\u0000$idempotencyKey'))}';

  String _questPointId(String ownerId, String idempotencyKey) =>
      'points:quest:${sha256.convert(utf8.encode('$ownerId\u0000$idempotencyKey'))}';

  void _requireIdentifier(String value, String name) {
    if (value.isEmpty || value.trim() != value || value.runes.length > 256) {
      throw ArgumentError.value(value, name);
    }
  }

  void _requireUtc(DateTime value, String name) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        value,
        name,
        'must be UTC at or after the Unix epoch',
      );
    }
  }
}
