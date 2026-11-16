import 'reward_models.dart';

/// Immutable local evidence; the fold never rewrites a rejected transaction.
final class RewardLedgerEntry {
  const RewardLedgerEntry({
    required this.id,
    required this.ownerId,
    required this.idempotencyKey,
    required this.type,
    required this.amount,
    required this.itemId,
    required this.catalogVersion,
    required this.sourceEventId,
    required this.occurredAtUtcMs,
  });
  final String id, ownerId, idempotencyKey, type;
  final int amount, catalogVersion, occurredAtUtcMs;
  final String? itemId, sourceEventId;
  bool get isCredit =>
      type == 'creditQuizCorrectV1' || type == 'creditLegacyCarryV1';
  bool get localOnly => type == 'creditLegacyCarryV1';
  bool sameEvidence(RewardLedgerEntry other) =>
      id == other.id &&
      ownerId == other.ownerId &&
      idempotencyKey == other.idempotencyKey &&
      type == other.type &&
      amount == other.amount &&
      itemId == other.itemId &&
      catalogVersion == other.catalogVersion &&
      sourceEventId == other.sourceEventId &&
      occurredAtUtcMs == other.occurredAtUtcMs;
}

enum RewardLedgerStatus {
  applied,
  invalid,
  duplicate,
  insufficientBalance,
  notOwned,
}

final class RewardLedgerEffect {
  const RewardLedgerEffect(this.entry, this.effectiveAmount, this.status);
  final RewardLedgerEntry entry;
  final int effectiveAmount;
  final RewardLedgerStatus status;
}

final class RewardLedger {
  const RewardLedger({
    required this.balance,
    required this.effects,
    required this.purchases,
    required this.equipped,
  });
  final int balance;
  final List<RewardLedgerEffect> effects;
  final Map<String, RewardLedgerEntry> purchases;
  final Map<String, RewardLedgerEntry> equipped;
  RewardAccount get account => RewardAccount(
    balance: balance,
    catalogVersion: RewardCatalog.version,
    ownedItemIds: purchases.keys.toSet(),
    equippedBySlot: {for (final e in equipped.entries) e.key: e.value.itemId!},
    transactionCount: effects.where((e) => !e.entry.isCredit).length,
  );
}

/// Credits first, then purchases, then equipment preserves legacy replay order.
RewardLedger foldRewardLedger({
  required String ownerId,
  required Iterable<RewardLedgerEntry> entries,
  required Map<String, RewardLedgerEntry> creditEvidence,
}) {
  final ordered = entries.where((e) => e.ownerId == ownerId).toList()
    ..sort((a, b) {
      final time = a.occurredAtUtcMs.compareTo(b.occurredAtUtcMs);
      return time == 0 ? a.id.compareTo(b.id) : time;
    });
  var balance = 0;
  final effects = <String, RewardLedgerEffect>{};
  final purchases = <String, RewardLedgerEntry>{};
  final equipped = <String, RewardLedgerEntry>{};
  for (final entry in ordered) {
    final evidence = creditEvidence[entry.id];
    if (entry.isCredit &&
        entry.amount > 0 &&
        evidence != null &&
        evidence.sameEvidence(entry)) {
      balance += entry.amount;
      effects[entry.id] = RewardLedgerEffect(
        entry,
        entry.amount,
        RewardLedgerStatus.applied,
      );
    } else {
      effects[entry.id] = RewardLedgerEffect(
        entry,
        0,
        RewardLedgerStatus.invalid,
      );
    }
  }
  for (final entry in ordered.where((e) => e.type == 'purchase')) {
    final item = _item(entry);
    if (item == null) continue;
    if (purchases.containsKey(item.id)) {
      effects[entry.id] = RewardLedgerEffect(
        entry,
        0,
        RewardLedgerStatus.duplicate,
      );
    } else if (balance < item.price) {
      effects[entry.id] = RewardLedgerEffect(
        entry,
        0,
        RewardLedgerStatus.insufficientBalance,
      );
    } else {
      balance -= item.price;
      purchases[item.id] = entry;
      effects[entry.id] = RewardLedgerEffect(
        entry,
        -item.price,
        RewardLedgerStatus.applied,
      );
    }
  }
  for (final entry in ordered.where((e) => e.type == 'equip')) {
    final item = _item(entry);
    if (item == null) continue;
    final owned = item.price == 0 || purchases.containsKey(item.id);
    effects[entry.id] = RewardLedgerEffect(
      entry,
      0,
      owned ? RewardLedgerStatus.applied : RewardLedgerStatus.notOwned,
    );
    if (owned) equipped[item.slot] = entry;
  }
  return RewardLedger(
    balance: balance,
    effects: List.unmodifiable(ordered.map((e) => effects[e.id]!)),
    purchases: Map.unmodifiable(purchases),
    equipped: Map.unmodifiable(equipped),
  );
}

RewardCatalogItem? _item(RewardLedgerEntry entry) {
  final item = entry.itemId == null ? null : RewardCatalog.byId(entry.itemId!);
  if (item == null ||
      entry.catalogVersion != item.catalogVersion ||
      entry.occurredAtUtcMs < 0 ||
      (entry.type == 'purchase' && entry.amount != -item.price) ||
      (entry.type == 'equip' && entry.amount != 0)) {
    return null;
  }
  return item;
}
