import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reward_models.dart';

enum EconomyTransactionType {
  legacyEarningBackfill,
  coinGrant,
  purchase,
  equip,
}

EconomyTransactionType? economyTransactionTypeFromWire(String value) {
  for (final type in EconomyTransactionType.values) {
    if (type.name == value) return type;
  }
  return null;
}

final class EconomyTransactionPolicy {
  const EconomyTransactionPolicy();

  bool isValidPersistedRow({
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String? itemId,
    required String? slot,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
  }) {
    return _validIdentifier(idempotencyKey) &&
        occurredAtUtcMs >= 0 &&
        isValid(
          transactionType: transactionType,
          amount: amount,
          itemId: itemId,
          slot: slot,
          catalogVersion: catalogVersion,
          sourceEventId: sourceEventId,
        );
  }

  bool isValid({
    required String transactionType,
    required int amount,
    required String? itemId,
    required String? slot,
    required int catalogVersion,
    required String? sourceEventId,
  }) {
    final type = economyTransactionTypeFromWire(transactionType);
    if (type == null) return false;
    final sourceIsValid = _validIdentifier(sourceEventId);

    switch (type) {
      case EconomyTransactionType.legacyEarningBackfill:
      case EconomyTransactionType.coinGrant:
        return amount > 0 &&
            itemId == null &&
            slot == null &&
            catalogVersion == 0 &&
            sourceIsValid;
      case EconomyTransactionType.purchase:
      case EconomyTransactionType.equip:
        final item = itemId == null ? null : RewardCatalog.byId(itemId);
        if (item == null ||
            item.catalogVersion != RewardCatalog.version ||
            catalogVersion != RewardCatalog.version ||
            slot != item.slot ||
            sourceEventId != null) {
          return false;
        }
        return type == EconomyTransactionType.purchase
            ? item.price > 0 && amount == -item.price
            : amount == 0;
    }
  }
}

final class EconomyAwardDecision {
  const EconomyAwardDecision({
    required this.sourceEventId,
    required this.xpAmount,
    required this.coinAmount,
    required this.xpIdempotencyKey,
    required this.coinIdempotencyKey,
  });

  final String sourceEventId;
  final int xpAmount;
  final int coinAmount;
  final String xpIdempotencyKey;
  final String coinIdempotencyKey;
}

final class EconomyAwardPolicyV1 {
  const EconomyAwardPolicyV1();

  static const String version = 'v1';

  EconomyAwardDecision evaluate({
    required String sourceEventId,
    required int amount,
    required bool eligible,
  }) {
    if (!_validIdentifier(sourceEventId)) {
      throw ArgumentError.value(sourceEventId, 'sourceEventId');
    }
    if (amount <= 0) throw ArgumentError.value(amount, 'amount');
    final digest = sha256.convert(utf8.encode(sourceEventId));
    return EconomyAwardDecision(
      sourceEventId: sourceEventId,
      xpAmount: eligible ? amount : 0,
      coinAmount: eligible ? amount : 0,
      xpIdempotencyKey: 'economy:$version:xp:$digest',
      coinIdempotencyKey: 'economy:$version:coins:$digest',
    );
  }
}

bool _validIdentifier(String? value) =>
    value != null &&
    value.isNotEmpty &&
    value.trim() == value &&
    value.runes.length <= 256;
