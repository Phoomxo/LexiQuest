import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'reward_models.dart';

final class AvatarProgression {
  const AvatarProgression._({
    required this.policyVersion,
    required this.lifetimeXp,
    required this.level,
    required this.xpIntoLevel,
    required this.nextLevelAtLifetimeXp,
    required this.xpUntilNextLevel,
    required this.unlockedItemIds,
    required this._requiredLifetimeXpByItemId,
  });

  final int policyVersion;
  final int lifetimeXp;
  final int level;
  final int xpIntoLevel;
  final int nextLevelAtLifetimeXp;
  final int xpUntilNextLevel;
  final Set<String> unlockedItemIds;
  final Map<String, int> _requiredLifetimeXpByItemId;

  bool isItemUnlocked(String itemId) {
    if (!_requiredLifetimeXpByItemId.containsKey(itemId)) {
      throw StateError('unknown avatar cosmetic $itemId');
    }
    return unlockedItemIds.contains(itemId);
  }

  int requiredLifetimeXpFor(String itemId) {
    final requiredXp = _requiredLifetimeXpByItemId[itemId];
    if (requiredXp == null) {
      throw StateError('unknown avatar cosmetic $itemId');
    }
    return requiredXp;
  }
}

final class AvatarRewardState {
  const AvatarRewardState({required this.account, required this.progression});

  final RewardAccount account;
  final AvatarProgression progression;
}

/// Frozen progression-policy v1 semantics used by durable p1 receipts.
final class AvatarProgressionPolicyV1 {
  const AvatarProgressionPolicyV1();

  static const int version = 1;
  static const int lifetimeXpPerLevel = 20;

  AvatarProgression evaluate({
    required int lifetimeXp,
    Iterable<RewardCatalogItem> catalog = RewardCatalog.items,
  }) {
    if (lifetimeXp < 0) {
      throw ArgumentError.value(lifetimeXp, 'lifetimeXp');
    }

    final requiredXpByItemId = <String, int>{};
    for (final item in catalog) {
      if (item.catalogVersion != RewardCatalog.catalogV2Version ||
          item.requiredAvatarLevel < 1 ||
          item.price < 0 ||
          requiredXpByItemId.containsKey(item.id)) {
        throw StateError('invalid avatar cosmetic definition ${item.id}');
      }
      requiredXpByItemId[item.id] = _minimumXpForLevel(
        item.requiredAvatarLevel,
      );
    }

    final level = (lifetimeXp ~/ lifetimeXpPerLevel) + 1;
    final nextLevelAtLifetimeXp = level * lifetimeXpPerLevel;
    final unlockedItemIds = requiredXpByItemId.entries
        .where((entry) => lifetimeXp >= entry.value)
        .map((entry) => entry.key)
        .toSet();
    return AvatarProgression._(
      policyVersion: version,
      lifetimeXp: lifetimeXp,
      level: level,
      xpIntoLevel: lifetimeXp % lifetimeXpPerLevel,
      nextLevelAtLifetimeXp: nextLevelAtLifetimeXp,
      xpUntilNextLevel: nextLevelAtLifetimeXp - lifetimeXp,
      unlockedItemIds: Set<String>.unmodifiable(unlockedItemIds),
      requiredLifetimeXpByItemId: Map<String, int>.unmodifiable(
        requiredXpByItemId,
      ),
    );
  }

  int _minimumXpForLevel(int level) => (level - 1) * lifetimeXpPerLevel;
}

/// Current app-facing progression policy. Future policies may replace this
/// facade without changing how persisted p1 receipts are interpreted.
final class AvatarProgressionPolicy {
  const AvatarProgressionPolicy();

  static const int version = AvatarProgressionPolicyV1.version;
  static const int lifetimeXpPerLevel =
      AvatarProgressionPolicyV1.lifetimeXpPerLevel;

  AvatarProgression evaluate({
    required int lifetimeXp,
    Iterable<RewardCatalogItem> catalog = RewardCatalog.items,
  }) => const AvatarProgressionPolicyV1().evaluate(
    lifetimeXp: lifetimeXp,
    catalog: catalog,
  );
}

final class AvatarProgressionEligibilityReceipt {
  const AvatarProgressionEligibilityReceipt({
    required this.contractVersion,
    required this.progressionPolicyVersion,
    required this.catalogVersion,
    required this.requiredAvatarLevel,
    required this.lifetimeXp,
    required this.sourceEventId,
  });

  final int contractVersion;
  final int progressionPolicyVersion;
  final int catalogVersion;
  final int requiredAvatarLevel;
  final int lifetimeXp;
  final String sourceEventId;
}

/// Versioned durable proof that a catalog-v2 purchase was admitted against
/// canonical lifetime XP. The proof is carried in RewardTransaction's existing
/// sourceEventId column, so f32 does not add a second ownership authority or a
/// database schema migration. The source writer checks its canonical XP once;
/// receivers and rebuilders validate this self-contained proof so Quest XP that
/// is not a SyncCollection cannot strand an otherwise valid cross-device row.
/// Account isolation remains the responsibility of the owner-scoped local row
/// and authenticated Firestore envelope; device-local owner IDs are therefore
/// intentionally not embedded in this portable proof.
final class AvatarProgressionEligibilityContract {
  const AvatarProgressionEligibilityContract();

  static const int version = 1;
  // Receipt v1 is permanently bound to progression-policy v1. A later current
  // policy must introduce a new receipt contract rather than reinterpret p1.
  static const int eligibleProgressionPolicyVersion = 1;
  static const int eligibleCatalogVersion = RewardCatalog.catalogV2Version;
  // Rules-first release horizon: the matching Firestore rules must be live
  // before 2026-10-01T00:00:00Z. Moving this boundary requires a new reviewed
  // rules/app contract; an already elapsed boundary must never ship.
  static const int legacyV1CutoverUtcMs = 1790812800000;
  static const String sourcePrefix = 'avatar-xp';

  AvatarProgressionEligibilityReceipt issue({
    required String idempotencyKey,
    required RewardCatalogItem item,
    required int lifetimeXp,
    required int occurredAtUtcMs,
  }) {
    final receipt = _evaluate(
      idempotencyKey: idempotencyKey,
      item: item,
      amount: -item.price,
      lifetimeXp: lifetimeXp,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    if (receipt == null) {
      throw StateError('avatar purchase is not progression eligible');
    }
    return receipt;
  }

  AvatarProgressionEligibilityReceipt? validatePersistedPurchase({
    required String idempotencyKey,
    required String itemId,
    required int amount,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (!_validIdentifier(idempotencyKey) || sourceEventId == null) {
      return null;
    }
    final parts = sourceEventId.split(':');
    if (parts.length != 7 ||
        parts[0] != sourcePrefix ||
        parts[1] != 'v$version') {
      return null;
    }
    final progressionVersion = _canonicalInt(parts[2], 'p');
    final encodedCatalogVersion = _canonicalInt(parts[3], 'c');
    final requiredLevel = _canonicalInt(parts[4], 'l');
    final claimedLifetimeXp = _canonicalInt(parts[5], 'x');
    final digest = parts[6];
    if (progressionVersion == null ||
        encodedCatalogVersion == null ||
        requiredLevel == null ||
        claimedLifetimeXp == null ||
        digest.length != 64 ||
        !RegExp(r'^[0-9a-f]{64}$').hasMatch(digest) ||
        catalogVersion != encodedCatalogVersion) {
      return null;
    }
    final item = RewardCatalog.byIdAtVersion(itemId, catalogVersion);
    if (item == null ||
        catalogVersion != eligibleCatalogVersion ||
        progressionVersion != eligibleProgressionPolicyVersion ||
        requiredLevel != item.requiredAvatarLevel ||
        amount != -item.price ||
        item.price <= 0 ||
        occurredAtUtcMs < 0) {
      return null;
    }
    final progression = const AvatarProgressionPolicyV1().evaluate(
      lifetimeXp: claimedLifetimeXp,
      catalog: RewardCatalog.catalogV2Items,
    );
    if (!progression.isItemUnlocked(item.id)) return null;
    final prefix = _sourcePrefix(
      progressionPolicyVersion: progressionVersion,
      catalogVersion: catalogVersion,
      requiredAvatarLevel: requiredLevel,
      lifetimeXp: claimedLifetimeXp,
    );
    final expectedDigest = _digest(
      idempotencyKey: idempotencyKey,
      itemId: item.id,
      amount: amount,
      catalogVersion: catalogVersion,
      progressionPolicyVersion: progressionVersion,
      requiredAvatarLevel: requiredLevel,
      lifetimeXp: claimedLifetimeXp,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    if (sourceEventId != '$prefix:$expectedDigest') return null;
    return AvatarProgressionEligibilityReceipt(
      contractVersion: version,
      progressionPolicyVersion: progressionVersion,
      catalogVersion: catalogVersion,
      requiredAvatarLevel: requiredLevel,
      lifetimeXp: claimedLifetimeXp,
      sourceEventId: sourceEventId,
    );
  }

  AvatarProgressionEligibilityReceipt? _evaluate({
    required String idempotencyKey,
    required RewardCatalogItem item,
    required int amount,
    required int lifetimeXp,
    required int occurredAtUtcMs,
  }) {
    if (!_validIdentifier(idempotencyKey) ||
        item.catalogVersion != eligibleCatalogVersion ||
        item.price <= 0 ||
        lifetimeXp < 0 ||
        occurredAtUtcMs < 0) {
      return null;
    }
    final progression = const AvatarProgressionPolicyV1().evaluate(
      lifetimeXp: lifetimeXp,
      catalog: RewardCatalog.catalogV2Items,
    );
    if (!progression.isItemUnlocked(item.id)) return null;
    final prefix = _sourcePrefix(
      progressionPolicyVersion: eligibleProgressionPolicyVersion,
      catalogVersion: item.catalogVersion,
      requiredAvatarLevel: item.requiredAvatarLevel,
      lifetimeXp: lifetimeXp,
    );
    final digest = _digest(
      idempotencyKey: idempotencyKey,
      itemId: item.id,
      amount: amount,
      catalogVersion: item.catalogVersion,
      progressionPolicyVersion: eligibleProgressionPolicyVersion,
      requiredAvatarLevel: item.requiredAvatarLevel,
      lifetimeXp: lifetimeXp,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    return AvatarProgressionEligibilityReceipt(
      contractVersion: version,
      progressionPolicyVersion: eligibleProgressionPolicyVersion,
      catalogVersion: item.catalogVersion,
      requiredAvatarLevel: item.requiredAvatarLevel,
      lifetimeXp: lifetimeXp,
      sourceEventId: '$prefix:$digest',
    );
  }

  String _sourcePrefix({
    required int progressionPolicyVersion,
    required int catalogVersion,
    required int requiredAvatarLevel,
    required int lifetimeXp,
  }) =>
      '$sourcePrefix:v$version:p$progressionPolicyVersion:'
      'c$catalogVersion:l$requiredAvatarLevel:x$lifetimeXp';

  String _digest({
    required String idempotencyKey,
    required String itemId,
    required int amount,
    required int catalogVersion,
    required int progressionPolicyVersion,
    required int requiredAvatarLevel,
    required int lifetimeXp,
    required int occurredAtUtcMs,
  }) => sha256
      .convert(
        utf8.encode(
          'avatar-purchase-eligibility-v$version\u0000'
          '$idempotencyKey\u0000$itemId\u0000$amount\u0000'
          '$catalogVersion\u0000$progressionPolicyVersion\u0000'
          '$requiredAvatarLevel\u0000$lifetimeXp\u0000$occurredAtUtcMs',
        ),
      )
      .toString();

  int? _canonicalInt(String value, String prefix) {
    if (!value.startsWith(prefix)) return null;
    final raw = value.substring(prefix.length);
    final parsed = int.tryParse(raw);
    if (parsed == null || parsed < 0 || raw != '$parsed') return null;
    return parsed;
  }
}

final class AvatarLegacyCarryForwardReceipt {
  const AvatarLegacyCarryForwardReceipt({required this.sourceEventId});

  final String sourceEventId;
}

/// Portable proof emitted only after the durable v1 grandfather marker has
/// admitted an exact legacy row. It lets an authorized owner-namespace
/// transition carry that row forward without reopening raw/backdated v1 cloud
/// writes. As with the v2 XP receipt, authentication and owner isolation live
/// in the surrounding RewardTransaction/Firestore envelope.
final class AvatarLegacyCarryForwardContract {
  const AvatarLegacyCarryForwardContract();

  static const int version = 1;
  static const String sourcePrefix = 'avatar-legacy';

  AvatarLegacyCarryForwardReceipt issue({
    required String transactionId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String itemId,
    required int catalogVersion,
    required int occurredAtUtcMs,
  }) {
    final tag = _transactionTag(transactionType);
    final item = RewardCatalog.byIdAtVersion(itemId, catalogVersion);
    if (!_validIdentifier(transactionId) ||
        !_validIdentifier(idempotencyKey) ||
        tag == null ||
        item == null ||
        catalogVersion != RewardCatalog.catalogV1Version ||
        occurredAtUtcMs < 0 ||
        occurredAtUtcMs >=
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs ||
        !_amountMatches(transactionType, amount, item)) {
      throw StateError('legacy avatar carry-forward row is invalid');
    }
    final digest = _digest(
      transactionId: transactionId,
      idempotencyKey: idempotencyKey,
      transactionType: transactionType,
      amount: amount,
      itemId: itemId,
      catalogVersion: catalogVersion,
      occurredAtUtcMs: occurredAtUtcMs,
    );
    return AvatarLegacyCarryForwardReceipt(
      sourceEventId: '$sourcePrefix:v$version:c1:$tag:$digest',
    );
  }

  bool isValidPersistedTransaction({
    required String transactionId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String? itemId,
    required int catalogVersion,
    required String? sourceEventId,
    required int occurredAtUtcMs,
  }) {
    if (itemId == null || sourceEventId == null) return false;
    try {
      return issue(
            transactionId: transactionId,
            idempotencyKey: idempotencyKey,
            transactionType: transactionType,
            amount: amount,
            itemId: itemId,
            catalogVersion: catalogVersion,
            occurredAtUtcMs: occurredAtUtcMs,
          ).sourceEventId ==
          sourceEventId;
    } on StateError {
      return false;
    }
  }

  String? _transactionTag(String transactionType) => switch (transactionType) {
    'purchase' => 'p',
    'equip' => 'e',
    _ => null,
  };

  bool _amountMatches(
    String transactionType,
    int amount,
    RewardCatalogItem item,
  ) => switch (transactionType) {
    'purchase' => item.price > 0 && amount == -item.price,
    'equip' => amount == 0,
    _ => false,
  };

  String _digest({
    required String transactionId,
    required String idempotencyKey,
    required String transactionType,
    required int amount,
    required String itemId,
    required int catalogVersion,
    required int occurredAtUtcMs,
  }) => sha256
      .convert(
        utf8.encode(
          'avatar-legacy-carry-forward-v$version\u0000'
          '$transactionId\u0000$idempotencyKey\u0000'
          '$transactionType\u0000$amount\u0000'
          '$itemId\u0000$catalogVersion\u0000$occurredAtUtcMs',
        ),
      )
      .toString();
}

bool _validIdentifier(String value) =>
    value.isNotEmpty && value.trim() == value && value.runes.length <= 256;
