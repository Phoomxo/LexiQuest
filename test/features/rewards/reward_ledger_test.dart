import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_ledger.dart';

void main() {
  test(
    'one deterministic fold reconciles raw, duplicate, invalid, and unaffordable effects',
    () {
      final credit = _row(
        'credit',
        'creditLegacyCarryV1',
        200,
        source: 'legacy',
        version: 0,
      );
      final rows = [
        credit,
        _row('a', 'purchase', -80, item: 'theme_ocean'),
        _row('b', 'purchase', -80, item: 'theme_ocean'),
        _row('c', 'purchase', -1, item: 'theme_ocean'),
        _row('d', 'purchase', -120, item: 'weapon_cefr'),
        _row('e', 'purchase', -120, item: 'armor_srs'),
        _row('f', 'equip', 0, item: 'theme_ocean'),
      ];
      final forward = foldRewardLedger(
        ownerId: 'a',
        entries: rows,
        creditEvidence: {'credit': credit},
      );
      final reverse = foldRewardLedger(
        ownerId: 'a',
        entries: rows.reversed,
        creditEvidence: {'credit': credit},
      );
      expect(forward.balance, 0);
      expect(
        forward.balance,
        forward.effects.fold<int>(0, (sum, e) => sum + e.effectiveAmount),
      );
      expect(forward.account.ownedItemIds, {'theme_ocean', 'weapon_cefr'});
      expect(forward.account.equippedBySlot, {'theme': 'theme_ocean'});
      expect(
        forward.effects.map((e) => (e.entry.id, e.effectiveAmount, e.status)),
        reverse.effects.map((e) => (e.entry.id, e.effectiveAmount, e.status)),
      );
      expect(
        forward.effects.singleWhere((e) => e.entry.id == 'b').status,
        RewardLedgerStatus.duplicate,
      );
      expect(
        forward.effects.singleWhere((e) => e.entry.id == 'c').status,
        RewardLedgerStatus.invalid,
      );
      expect(
        forward.effects.singleWhere((e) => e.entry.id == 'e').status,
        RewardLedgerStatus.insufficientBalance,
      );
    },
  );

  test(
    'unbacked positive credit and foreign-owner rows cannot change a balance',
    () {
      final expected = _row(
        'credit',
        'creditQuizCorrectV1',
        1,
        source: 'correct',
        version: 0,
      );
      final forged = _row(
        'credit',
        'creditQuizCorrectV1',
        999,
        source: 'correct',
        version: 0,
      );
      final foreign = RewardLedgerEntry(
        id: 'foreign',
        ownerId: 'b',
        idempotencyKey: 'foreign',
        type: 'creditQuizCorrectV1',
        amount: 10,
        itemId: null,
        catalogVersion: 0,
        sourceEventId: 'foreign',
        occurredAtUtcMs: 1,
      );
      final result = foldRewardLedger(
        ownerId: 'a',
        entries: [forged, foreign],
        creditEvidence: {'credit': expected},
      );
      expect(result.balance, 0);
      expect(result.effects, hasLength(1));
      expect(result.effects.single.status, RewardLedgerStatus.invalid);
    },
  );
}

RewardLedgerEntry _row(
  String id,
  String type,
  int amount, {
  String? item,
  String? source,
  int version = 1,
}) => RewardLedgerEntry(
  id: id,
  ownerId: 'a',
  idempotencyKey: id,
  type: type,
  amount: amount,
  itemId: item,
  catalogVersion: version,
  sourceEventId: source,
  occurredAtUtcMs: 1,
);
