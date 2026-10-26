import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../domain/reward_ledger.dart';

final class DriftRewardProjectionRebuilder {
  const DriftRewardProjectionRebuilder(this.database);

  final db.AppDatabase database;

  Future<RewardLedger> readLedger(String ownerId) =>
      database.transaction(() async {
        final evidence = await _materializeCredits(ownerId);
        final rows = await (database.select(
          database.rewardTransactions,
        )..where((r) => r.ownerId.equals(ownerId))).get();
        return foldRewardLedger(
          ownerId: ownerId,
          entries: rows.map(_entry),
          creditEvidence: evidence,
        );
      });

  Future<void> rebuild(String ownerId) => database.transaction(() async {
    final ledger = await readLedger(ownerId);
    await (database.delete(
      database.ownedRewardItems,
    )..where((r) => r.ownerId.equals(ownerId))).go();
    await (database.delete(
      database.equippedRewardItems,
    )..where((r) => r.ownerId.equals(ownerId))).go();
    for (final entry in ledger.purchases.values) {
      await database
          .into(database.ownedRewardItems)
          .insert(
            db.OwnedRewardItemsCompanion.insert(
              id: 'owned:$ownerId:${entry.itemId}',
              ownerId: ownerId,
              itemId: entry.itemId!,
              catalogVersion: entry.catalogVersion,
              acquiredByTransactionId: entry.id,
              acquiredAtUtcMs: entry.occurredAtUtcMs,
            ),
          );
    }
    for (final slot in ledger.equipped.entries) {
      await database
          .into(database.equippedRewardItems)
          .insert(
            db.EquippedRewardItemsCompanion.insert(
              id: 'equipped:$ownerId:${slot.key}',
              ownerId: ownerId,
              slot: slot.key,
              itemId: slot.value.itemId!,
              equippedAtUtcMs: slot.value.occurredAtUtcMs,
            ),
          );
    }
  });

  Future<Map<String, RewardLedgerEntry>> _materializeCredits(
    String ownerId,
  ) async {
    final attempts =
        await (database.select(database.answerAttempts)..where(
              (r) => r.ownerId.equals(ownerId) & r.isCorrect.equals(true),
            ))
            .get();
    final correct = {for (final a in attempts) a.id: a};
    final evidence = <String, RewardLedgerEntry>{};
    for (final a in attempts) {
      final entry = RewardLedgerEntry(
        id: 'coin:quiz:${a.id}',
        ownerId: ownerId,
        idempotencyKey: 'creditQuizCorrectV1:${a.id}',
        type: 'creditQuizCorrectV1',
        amount: 1,
        itemId: null,
        catalogVersion: 0,
        sourceEventId: a.id,
        occurredAtUtcMs: a.occurredAtUtcMs,
      );
      evidence[entry.id] = entry;
    }
    final legacy =
        await (database.select(database.pointsLedgerEntries)
              ..where(
                (r) =>
                    r.ownerId.equals(ownerId) &
                    r.amount.isBiggerThanValue(0) &
                    r.entryType.equals('rewardPurchase').not(),
              )
              ..orderBy([(r) => OrderingTerm.asc(r.id)]))
            .get();
    final covered = <String>{};
    for (final row in legacy) {
      final source = correct[row.sourceEventId];
      if (source != null &&
          row.amount == 1 &&
          row.entryType == 'quizCorrect' &&
          row.idempotencyKey == 'correct-answer:${source.id}') {
        continue;
      }
      final backed = source != null && covered.add(source.id);
      final amount = row.amount - (backed ? 1 : 0);
      if (amount == 0) continue;
      final entry = RewardLedgerEntry(
        id: 'coin:legacy:${row.id}',
        ownerId: ownerId,
        idempotencyKey: 'creditLegacyCarryV1:${row.id}',
        type: 'creditLegacyCarryV1',
        amount: amount,
        itemId: null,
        catalogVersion: 0,
        sourceEventId: row.id,
        occurredAtUtcMs: row.occurredAtUtcMs,
      );
      evidence[entry.id] = entry;
    }
    for (final entry in evidence.values) {
      await database
          .into(database.rewardTransactions)
          .insert(
            db.RewardTransactionsCompanion.insert(
              id: entry.id,
              ownerId: entry.ownerId,
              idempotencyKey: entry.idempotencyKey,
              transactionType: entry.type,
              amount: entry.amount,
              catalogVersion: entry.catalogVersion,
              sourceEventId: Value(entry.sourceEventId),
              occurredAtUtcMs: entry.occurredAtUtcMs,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final existing = await (database.select(
        database.rewardTransactions,
      )..where((r) => r.id.equals(entry.id))).getSingleOrNull();
      if (existing == null || !_entry(existing).sameEvidence(entry)) {
        throw StateError('reward credit provenance conflict');
      }
    }
    return evidence;
  }

  RewardLedgerEntry _entry(db.RewardTransaction r) => RewardLedgerEntry(
    id: r.id,
    ownerId: r.ownerId,
    idempotencyKey: r.idempotencyKey,
    type: r.transactionType,
    amount: r.amount,
    itemId: r.itemId,
    catalogVersion: r.catalogVersion,
    sourceEventId: r.sourceEventId,
    occurredAtUtcMs: r.occurredAtUtcMs,
  );
}
