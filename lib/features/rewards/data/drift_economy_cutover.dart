import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';

import '../../../data/local/app_database.dart' as db;
import '../../learning/domain/learning_evidence_contract.dart';
import '../domain/economy_transaction_policy.dart';

final class DriftEconomyCutover {
  const DriftEconomyCutover(
    this.database, {
    this.transactionPolicy = const EconomyTransactionPolicy(),
  });

  final db.AppDatabase database;
  final EconomyTransactionPolicy transactionPolicy;

  Future<void> ensureSeparated(String ownerId) {
    if (!_validIdentifier(ownerId)) {
      throw ArgumentError.value(ownerId, 'ownerId');
    }
    return database.transaction(() async {
      final points =
          await (database.select(database.pointsLedgerEntries)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.amount.isBiggerThanValue(0) &
                      row.entryType.isIn(const [
                        'quizCorrect',
                        'questCompletion',
                      ]),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.occurredAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();

      for (final point in points) {
        await _ensurePoint(ownerId, point);
      }
    });
  }

  Future<void> _ensurePoint(String ownerId, db.PointsLedgerEntry point) async {
    final digest = sha256.convert(utf8.encode(point.id));
    final rawSourceEventId = point.sourceEventId;
    final sourceEventId = _validIdentifier(rawSourceEventId)
        ? rawSourceEventId!
        : _validIdentifier(point.id)
        ? point.id
        : 'legacy-point:$digest';
    final transactionId = 'reward:legacy:$digest';
    final idempotencyKey = 'economy:v1:legacy:$digest';
    _requireValidBackfillCandidate(
      idempotencyKey: idempotencyKey,
      amount: point.amount,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: point.occurredAtUtcMs,
    );

    final byId = await (database.select(
      database.rewardTransactions,
    )..where((row) => row.id.equals(transactionId))).getSingleOrNull();
    if (byId != null) {
      _requireExactBackfill(
        byId,
        ownerId: ownerId,
        idempotencyKey: idempotencyKey,
        amount: point.amount,
        sourceEventId: sourceEventId,
        occurredAtUtcMs: point.occurredAtUtcMs,
      );
      await _ensureOutbox(byId);
      return;
    }

    final byIdempotency =
        await (database.select(database.rewardTransactions)..where(
              (row) =>
                  row.ownerId.equals(ownerId) &
                  row.idempotencyKey.equals(idempotencyKey),
            ))
            .getSingleOrNull();
    if (byIdempotency != null) {
      throw StateError(
        'economy backfill idempotency collision for ${point.id}',
      );
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
            .getSingleOrNull();
    if (sameSource != null) {
      if (!_isValidPersistedEarning(sameSource)) {
        throw StateError('invalid same-source coin evidence ${sameSource.id}');
      }
      if (sameSource.amount != point.amount ||
          sameSource.occurredAtUtcMs != point.occurredAtUtcMs) {
        throw StateError('same-source coin evidence mismatch ${sameSource.id}');
      }
      return;
    }

    if (await _isV2OwnedQuizPoint(ownerId, point)) return;

    await database
        .into(database.rewardTransactions)
        .insert(
          db.RewardTransactionsCompanion.insert(
            id: transactionId,
            ownerId: ownerId,
            idempotencyKey: idempotencyKey,
            transactionType: EconomyTransactionType.legacyEarningBackfill.name,
            amount: point.amount,
            catalogVersion: 0,
            sourceEventId: Value(sourceEventId),
            occurredAtUtcMs: point.occurredAtUtcMs,
          ),
        );
    final inserted = await (database.select(
      database.rewardTransactions,
    )..where((row) => row.id.equals(transactionId))).getSingle();
    await _ensureOutbox(inserted);
  }

  Future<bool> _isV2OwnedQuizPoint(
    String ownerId,
    db.PointsLedgerEntry point,
  ) async {
    final sourceEventId = point.sourceEventId;
    if (point.entryType != 'quizCorrect' ||
        sourceEventId == null ||
        !LearningEvidenceContract.validSourceEvidenceId(sourceEventId)) {
      return false;
    }
    final eventId = LearningEvidenceContract.learningEventId(sourceEventId);
    final event = await (database.select(
      database.eventsV2,
    )..where((row) => row.eventId.equals(eventId))).getSingleOrNull();
    if (event == null) return false;
    Object? payload;
    try {
      payload = jsonDecode(event.payloadJson);
    } on FormatException {
      throw StateError('corrupt v2 learning event $eventId');
    }
    if (event.ownerId != ownerId ||
        payload is! Map<String, dynamic> ||
        payload['attemptId'] != sourceEventId) {
      throw StateError('corrupt v2 learning event $eventId');
    }
    if (event.eventVersion == 1) {
      if (event.idempotencyKey != 'learning-attempt:$sourceEventId:v1') {
        throw StateError('corrupt v1 learning event $eventId');
      }
      return false;
    }
    if (event.eventVersion == 2) {
      if (event.idempotencyKey !=
          LearningEvidenceContract.learningAttemptIdempotencyKey(
            sourceEventId,
          )) {
        throw StateError('corrupt v2 learning event $eventId');
      }
      return true;
    }
    throw StateError('unsupported learning event version $eventId');
  }

  void _requireExactBackfill(
    db.RewardTransaction transaction, {
    required String ownerId,
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (!_isValidPersistedEarning(transaction) ||
        transaction.ownerId != ownerId ||
        transaction.idempotencyKey != idempotencyKey ||
        transaction.transactionType != 'legacyEarningBackfill' ||
        transaction.amount != amount ||
        transaction.itemId != null ||
        transaction.catalogVersion != 0 ||
        transaction.sourceEventId != sourceEventId ||
        transaction.occurredAtUtcMs != occurredAtUtcMs) {
      throw StateError('economy backfill identity collision ${transaction.id}');
    }
  }

  void _requireValidBackfillCandidate({
    required String idempotencyKey,
    required int amount,
    required String sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (!transactionPolicy.isValidPersistedRow(
      idempotencyKey: idempotencyKey,
      transactionType: EconomyTransactionType.legacyEarningBackfill.name,
      amount: amount,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: sourceEventId,
      occurredAtUtcMs: occurredAtUtcMs,
    )) {
      throw StateError('invalid economy backfill candidate $sourceEventId');
    }
  }

  bool _isValidPersistedEarning(db.RewardTransaction transaction) {
    return transactionPolicy.isValidPersistedRow(
      idempotencyKey: transaction.idempotencyKey,
      transactionType: transaction.transactionType,
      amount: transaction.amount,
      itemId: transaction.itemId,
      slot: null,
      catalogVersion: transaction.catalogVersion,
      sourceEventId: transaction.sourceEventId,
      occurredAtUtcMs: transaction.occurredAtUtcMs,
    );
  }

  Future<void> _ensureOutbox(db.RewardTransaction transaction) async {
    if (!_isValidPersistedEarning(transaction)) {
      throw StateError('invalid economy backfill ${transaction.id}');
    }
    final operationId = 'rewardTransaction:${transaction.id}:1';
    final existing = await (database.select(
      database.outboxOperations,
    )..where((row) => row.operationId.equals(operationId))).getSingleOrNull();
    if (existing != null) {
      if (existing.ownerId != transaction.ownerId ||
          existing.entityType != 'rewardTransaction' ||
          existing.entityId != transaction.id ||
          existing.operationKind != 'upsert' ||
          existing.payloadVersion != 1 ||
          existing.createdAtUtcMs != transaction.occurredAtUtcMs) {
        throw StateError('economy backfill outbox collision $operationId');
      }
      return;
    }
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId: operationId,
            ownerId: transaction.ownerId,
            entityType: 'rewardTransaction',
            entityId: transaction.id,
            operationKind: 'upsert',
            createdAtUtcMs: transaction.occurredAtUtcMs,
          ),
        );
  }
}

bool _validIdentifier(String? value) =>
    value != null &&
    value.isNotEmpty &&
    value.trim() == value &&
    value.runes.length <= 256;
