import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/rewards/domain/avatar_progression_policy.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  const policy = AvatarProgressionPolicy();

  test('level boundaries are derived only from lifetime xp', () {
    expect(policy.evaluate(lifetimeXp: 0).level, 1);
    expect(policy.evaluate(lifetimeXp: 19).level, 1);
    expect(policy.evaluate(lifetimeXp: 20).level, 2);
    expect(policy.evaluate(lifetimeXp: 39).level, 2);
    expect(policy.evaluate(lifetimeXp: 40).level, 3);

    final atBoundary = policy.evaluate(lifetimeXp: 40);
    expect(atBoundary.lifetimeXp, 40);
    expect(atBoundary.xpIntoLevel, 0);
    expect(atBoundary.nextLevelAtLifetimeXp, 60);
    expect(atBoundary.xpUntilNextLevel, 20);
  });

  test('cosmetic unlocks switch on at the exact level threshold', () {
    final item = RewardCatalog.byId('theme_ocean')!;
    expect(item.requiredAvatarLevel, 3);

    final before = policy.evaluate(lifetimeXp: 39);
    final exact = policy.evaluate(lifetimeXp: 40);

    expect(before.isItemUnlocked(item.id), isFalse);
    expect(before.requiredLifetimeXpFor(item.id), 40);
    expect(exact.isItemUnlocked(item.id), isTrue);
    expect(exact.requiredLifetimeXpFor(item.id), 40);
  });

  test('coin balance is not an avatar progression policy input', () {
    final progression = policy.evaluate(lifetimeXp: 40);

    expect(progression.level, 3);
    expect(progression.isItemUnlocked('theme_ocean'), isTrue);
  });

  test('catalog v1 and v2 snapshots remain explicitly reconstructible', () {
    final legacy = RewardCatalog.byIdAtVersion(
      'theme_ocean',
      RewardCatalog.catalogV1Version,
    );
    final f32 = RewardCatalog.byIdAtVersion(
      'theme_ocean',
      RewardCatalog.catalogV2Version,
    );

    expect(legacy?.catalogVersion, RewardCatalog.catalogV1Version);
    expect(f32?.catalogVersion, RewardCatalog.catalogV2Version);
    expect(f32?.requiredAvatarLevel, 3);
    expect(RewardCatalog.byIdAtVersion('theme_ocean', 3), isNull);
  });

  test('invalid xp and mismatched catalog definitions fail closed', () {
    expect(() => policy.evaluate(lifetimeXp: -1), throwsArgumentError);

    const mismatched = RewardCatalogItem(
      id: 'future-item',
      catalogVersion: RewardCatalog.version + 1,
      kind: RewardItemKind.relic,
      name: 'Future item',
      description: 'Not in the active catalog.',
      price: 1,
      requiredAvatarLevel: 1,
    );
    expect(
      () => policy.evaluate(lifetimeXp: 0, catalog: const [mismatched]),
      throwsStateError,
    );
  });

  test('purchase eligibility binds catalog level xp key and occurrence', () {
    final item = RewardCatalog.byId('theme_ocean')!;
    const eligibility = AvatarProgressionEligibilityContract();
    final receipt = eligibility.issue(
      idempotencyKey: 'purchase:theme-ocean',
      item: item,
      lifetimeXp: 40,
      occurredAtUtcMs: 100,
    );

    final validated = eligibility.validatePersistedPurchase(
      idempotencyKey: 'purchase:theme-ocean',
      itemId: item.id,
      amount: -item.price,
      catalogVersion: item.catalogVersion,
      sourceEventId: receipt.sourceEventId,
      occurredAtUtcMs: 100,
    );
    expect(
      validated?.progressionPolicyVersion,
      AvatarProgressionEligibilityContract.eligibleProgressionPolicyVersion,
    );
    expect(validated?.requiredAvatarLevel, 3);
    expect(validated?.lifetimeXp, 40);
  });

  test('purchase eligibility rejects threshold xp and payload tampering', () {
    final item = RewardCatalog.byId('theme_ocean')!;
    const eligibility = AvatarProgressionEligibilityContract();
    final receipt = eligibility.issue(
      idempotencyKey: 'purchase:tamper-evident',
      item: item,
      lifetimeXp: 40,
      occurredAtUtcMs: 100,
    );

    expect(
      eligibility.validatePersistedPurchase(
        idempotencyKey: 'purchase:tamper-evident',
        itemId: item.id,
        amount: -item.price,
        catalogVersion: item.catalogVersion,
        sourceEventId: receipt.sourceEventId.replaceFirst(':l3:', ':l2:'),
        occurredAtUtcMs: 100,
      ),
      isNull,
    );
    expect(
      eligibility.validatePersistedPurchase(
        idempotencyKey: 'purchase:changed-key',
        itemId: item.id,
        amount: -item.price,
        catalogVersion: item.catalogVersion,
        sourceEventId: receipt.sourceEventId,
        occurredAtUtcMs: 100,
      ),
      isNull,
    );
    expect(
      eligibility.validatePersistedPurchase(
        idempotencyKey: 'purchase:tamper-evident',
        itemId: item.id,
        amount: -item.price,
        catalogVersion: item.catalogVersion,
        sourceEventId: receipt.sourceEventId.replaceFirst(':x40:', ':x41:'),
        occurredAtUtcMs: 100,
      ),
      isNull,
    );
  });

  test('legacy carry-forward binds the exact purchase and equip rows', () {
    const carry = AvatarLegacyCarryForwardContract();
    final item = RewardCatalog.byIdAtVersion(
      'theme_ocean',
      RewardCatalog.catalogV1Version,
    )!;
    final purchase = carry.issue(
      transactionId: 'legacy-purchase-id',
      idempotencyKey: 'legacy-purchase',
      transactionType: 'purchase',
      amount: -item.price,
      itemId: item.id,
      catalogVersion: item.catalogVersion,
      occurredAtUtcMs: 100,
    );
    final equip = carry.issue(
      transactionId: 'legacy-equip-id',
      idempotencyKey: 'legacy-equip',
      transactionType: 'equip',
      amount: 0,
      itemId: item.id,
      catalogVersion: item.catalogVersion,
      occurredAtUtcMs: 101,
    );

    expect(
      carry.isValidPersistedTransaction(
        transactionId: 'legacy-purchase-id',
        idempotencyKey: 'legacy-purchase',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        sourceEventId: purchase.sourceEventId,
        occurredAtUtcMs: 100,
      ),
      isTrue,
    );
    expect(
      carry.isValidPersistedTransaction(
        transactionId: 'legacy-equip-id',
        idempotencyKey: 'legacy-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        sourceEventId: equip.sourceEventId,
        occurredAtUtcMs: 101,
      ),
      isTrue,
    );
    expect(
      carry.isValidPersistedTransaction(
        transactionId: 'legacy-purchase-id',
        idempotencyKey: 'legacy-purchase-changed',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        sourceEventId: purchase.sourceEventId,
        occurredAtUtcMs: 100,
      ),
      isFalse,
    );
    expect(
      () => carry.issue(
        transactionId: 'late-legacy-equip-id',
        idempotencyKey: 'late-legacy-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        occurredAtUtcMs:
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
      ),
      throwsStateError,
    );
  });

  test('legacy boundary is pinned to the rules-first release horizon', () {
    expect(
      AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
      DateTime.utc(2026, 10, 1).millisecondsSinceEpoch,
    );
  });
}
