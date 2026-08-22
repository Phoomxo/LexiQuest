import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/rewards/domain/economy_transaction_policy.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  const transactions = EconomyTransactionPolicy();

  group('EconomyTransactionPolicy', () {
    test('accepts exactly the four supported transaction shapes', () {
      expect(
        transactions.isValid(
          transactionType: 'legacyEarningBackfill',
          amount: 10,
          itemId: null,
          slot: null,
          catalogVersion: 0,
          sourceEventId: 'legacy:answer-1',
        ),
        isTrue,
      );
      expect(
        transactions.isValid(
          transactionType: 'coinGrant',
          amount: 10,
          itemId: null,
          slot: null,
          catalogVersion: 0,
          sourceEventId: 'learning-event:answer-2',
        ),
        isTrue,
      );
      expect(
        transactions.isValid(
          transactionType: 'purchase',
          amount: -RewardCatalog.byId('theme_ocean')!.price,
          itemId: 'theme_ocean',
          slot: 'theme',
          catalogVersion: RewardCatalog.version,
          sourceEventId: null,
        ),
        isTrue,
      );
      expect(
        transactions.isValid(
          transactionType: 'equip',
          amount: 0,
          itemId: 'theme_ocean',
          slot: 'theme',
          catalogVersion: RewardCatalog.version,
          sourceEventId: null,
        ),
        isTrue,
      );
    });

    test('rejects type amount item catalog source cross-shapes', () {
      final invalid =
          <
            ({
              String type,
              int amount,
              String? item,
              String? slot,
              int catalog,
              String? source,
            })
          >[
            (
              type: 'unknown',
              amount: 1,
              item: null,
              slot: null,
              catalog: 0,
              source: 'source',
            ),
            (
              type: 'coinGrant',
              amount: 0,
              item: null,
              slot: null,
              catalog: 0,
              source: 'source',
            ),
            (
              type: 'coinGrant',
              amount: 1,
              item: 'theme_ocean',
              slot: 'theme',
              catalog: 0,
              source: 'source',
            ),
            (
              type: 'legacyEarningBackfill',
              amount: 1,
              item: null,
              slot: null,
              catalog: 1,
              source: 'source',
            ),
            (
              type: 'purchase',
              amount: -1,
              item: 'theme_ocean',
              slot: 'theme',
              catalog: RewardCatalog.version,
              source: null,
            ),
            (
              type: 'purchase',
              amount: -80,
              item: 'theme_ocean',
              slot: 'weapon',
              catalog: RewardCatalog.version,
              source: null,
            ),
            (
              type: 'purchase',
              amount: 0,
              item: 'theme_default',
              slot: 'theme',
              catalog: RewardCatalog.version,
              source: null,
            ),
            (
              type: 'equip',
              amount: 0,
              item: 'theme_ocean',
              slot: 'theme',
              catalog: RewardCatalog.version,
              source: 'source',
            ),
          ];

      for (final shape in invalid) {
        expect(
          transactions.isValid(
            transactionType: shape.type,
            amount: shape.amount,
            itemId: shape.item,
            slot: shape.slot,
            catalogVersion: shape.catalog,
            sourceEventId: shape.source,
          ),
          isFalse,
          reason: '$shape',
        );
      }
    });
  });

  group('EconomyAwardPolicyV1', () {
    test('eligible source receives equal independent deterministic awards', () {
      const policy = EconomyAwardPolicyV1();
      final first = policy.evaluate(
        sourceEventId: 'learning-event:answer-1',
        amount: 7,
        eligible: true,
      );
      final replay = policy.evaluate(
        sourceEventId: 'learning-event:answer-1',
        amount: 7,
        eligible: true,
      );

      expect(first.xpAmount, 7);
      expect(first.coinAmount, 7);
      expect(first.xpIdempotencyKey, replay.xpIdempotencyKey);
      expect(first.coinIdempotencyKey, replay.coinIdempotencyKey);
      expect(first.xpIdempotencyKey, isNot(first.coinIdempotencyKey));
    });

    test('ineligible source grants neither xp nor coins', () {
      final decision = const EconomyAwardPolicyV1().evaluate(
        sourceEventId: 'assessment-event:1',
        amount: 10,
        eligible: false,
      );

      expect(decision.xpAmount, 0);
      expect(decision.coinAmount, 0);
    });
  });
}
