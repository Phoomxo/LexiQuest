import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart';
import '../../learning/data/drift_learning_projection_rebuilder.dart';
import '../../quest/data/drift_quest_progress_reader.dart';
import '../../quest/data/drift_quest_repository.dart';
import 'drift_reward_projection_rebuilder.dart';
import '../domain/reward_models.dart';

final class DriftRewardRepository {
  DriftRewardRepository(
    this.database, {
    this.questCatalog,
    this.questVisible,
    DateTime Function()? nowUtc,
  }) : nowUtc = nowUtc ?? _systemUtc,
       projections = DriftRewardProjectionRebuilder(database);

  final AppDatabase database;
  final DriftRewardProjectionRebuilder projections;
  final TrustedQuestAnswerCatalog? questCatalog;
  final bool Function()? questVisible;
  final DateTime Function() nowUtc;
  Future<void> _writeGate = Future<void>.value();

  Future<RewardAccount> load(String ownerId) async {
    return (await projections.readLedger(ownerId)).account;
  }

  Future<QuestClaimResult> claimQuest({
    required String expectedOwnerId,
    required String instanceId,
  }) => _serialized(
    () => database.transaction(() async {
      final active = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).get();
      if (active.length != 1 || active.single.id != expectedOwnerId) {
        throw const RewardException(RewardFailureCode.ownerChanged);
      }
      if (questCatalog == null || !(questVisible?.call() ?? false)) {
        throw const RewardException(RewardFailureCode.questUnavailable);
      }
      if (instanceId.trim().isEmpty) {
        throw const RewardException(RewardFailureCode.questNotClaimable);
      }
      final issuedAt = nowUtc();
      if (!issuedAt.isUtc || issuedAt.millisecondsSinceEpoch < 0) {
        throw ArgumentError('Quest claim time must be nonnegative UTC');
      }
      final period =
          await DriftQuestProgressReader(
            database,
            catalog: questCatalog,
          ).qualify(
            ownerId: expectedOwnerId,
            instanceId: instanceId,
            asOfUtc: issuedAt,
          );
      final issuer = DriftLearningProjectionRebuilder(
        database,
        questCatalog: questCatalog,
      );
      if (period.receipts.isNotEmpty) {
        await issuer.rebuildQuestXp(expectedOwnerId);
        final receipt = period.receipts.first;
        return QuestClaimResult(
          ownerId: expectedOwnerId,
          receiptId: receipt.id,
          canonicalInstanceId: period.instanceId,
          xpAmount: receipt.xpAmount,
          issuedAtUtc: DateTime.fromMillisecondsSinceEpoch(
            receipt.issuedAtUtcMs,
            isUtc: true,
          ),
          replayed: true,
        );
      }
      await _materializeQuestPeriod(expectedOwnerId, period);
      final issuedAtMs = issuedAt.millisecondsSinceEpoch;
      await database
          .into(database.questClaimReceipts)
          .insert(
            QuestClaimReceiptsCompanion.insert(
              id: period.receiptId,
              ownerId: expectedOwnerId,
              originOwnerId: period.originOwnerId,
              instanceId: period.instanceId,
              issuedAtUtcMs: issuedAtMs,
              completedAtUtcMs: period.completedAtUtcMs,
              xpAmount: period.xpAmount,
              evidenceJson: period.evidenceJson,
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final receipt = await (database.select(
        database.questClaimReceipts,
      )..where((row) => row.id.equals(period.receiptId))).getSingleOrNull();
      if (receipt == null ||
          receipt.ownerId != expectedOwnerId ||
          receipt.originOwnerId != period.originOwnerId ||
          receipt.instanceId != period.instanceId ||
          receipt.issuedAtUtcMs != issuedAtMs ||
          receipt.completedAtUtcMs != period.completedAtUtcMs ||
          receipt.xpAmount != period.xpAmount ||
          receipt.evidenceJson != period.evidenceJson) {
        throw StateError('Conflicting immutable Quest receipt provenance');
      }
      await issuer.rebuildQuestXp(expectedOwnerId);
      return QuestClaimResult(
        ownerId: expectedOwnerId,
        receiptId: receipt.id,
        canonicalInstanceId: period.instanceId,
        xpAmount: receipt.xpAmount,
        issuedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          receipt.issuedAtUtcMs,
          isUtc: true,
        ),
        replayed: false,
      );
    }),
  );

  Future<void> _materializeQuestPeriod(
    String ownerId,
    QualifiedQuestPeriod period,
  ) async {
    final definition = period.definition;
    await database
        .into(database.questDefinitions)
        .insert(
          QuestDefinitionsCompanion.insert(
            questId: definition.questId,
            catalogVersion: definition.catalogVersion,
            title: definition.title,
            description: definition.description,
            type: definition.type.name,
            objectivesJson: jsonEncode([
              for (final objective in definition.objectives)
                {
                  'objectiveId': objective.objectiveId,
                  'description': objective.description,
                  'targetCount': objective.targetCount,
                  'eventType': objective.criteria.eventType,
                  'filters': objective.criteria.filters,
                },
            ]),
            rewardJson: jsonEncode({
              'xpAmount': definition.reward.xpAmount,
              'rewardItemId': definition.reward.rewardItemId,
            }),
            expiresInMs: Value(definition.expiresIn?.inMilliseconds),
            tagsJson: Value(jsonEncode(definition.tags)),
          ),
          mode: InsertMode.insertOrIgnore,
        );
    for (final member in period.members) {
      final canonical = member.instanceId == period.instanceId;
      final kind = canonical ? 'canonical' : 'alias';
      final target = canonical ? null : period.instanceId;
      await database
          .into(database.questInstances)
          .insert(
            QuestInstancesCompanion.insert(
              instanceId: member.instanceId,
              questId: period.pin.questId,
              ownerId: ownerId,
              catalogVersion: period.pin.catalogVersion,
              assignedAtUtcMs: member.assignedAtUtcMs,
              state: 'completed',
              completedAtUtcMs: Value(period.completedAtUtcMs),
              originOwnerId: Value(member.originOwnerId),
              periodKey: Value(member.periodKey),
              calendarRuleId: Value(member.calendarRuleId),
              civilLabel: Value(member.civilLabel),
              segmentsJson: Value(member.segmentsJson),
              definitionDigest: Value(period.pin.definitionDigest),
              canonicalInstanceId: Value(target),
              recordKind: Value(kind),
            ),
            mode: InsertMode.insertOrIgnore,
          );
      final row =
          await (database.select(database.questInstances)
                ..where((row) => row.instanceId.equals(member.instanceId)))
              .getSingleOrNull();
      if (row == null ||
          row.ownerId != ownerId ||
          row.questId != period.pin.questId ||
          row.catalogVersion != period.pin.catalogVersion ||
          row.assignedAtUtcMs != member.assignedAtUtcMs ||
          row.originOwnerId != member.originOwnerId ||
          row.periodKey != member.periodKey ||
          row.calendarRuleId != member.calendarRuleId ||
          row.civilLabel != member.civilLabel ||
          row.segmentsJson != member.segmentsJson ||
          row.definitionDigest != period.pin.definitionDigest ||
          row.recordKind != kind ||
          row.canonicalInstanceId != target) {
        throw StateError('Conflicting immutable Quest occurrence provenance');
      }
    }
  }

  static DateTime _systemUtc() => DateTime.now().toUtc();

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
