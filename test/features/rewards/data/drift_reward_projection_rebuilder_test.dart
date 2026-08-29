import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_avatar_progression_eligibility.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/rewards/domain/avatar_progression_policy.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  late AppDatabase database;
  late DriftRewardProjectionRebuilder rebuilder;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    rebuilder = DriftRewardProjectionRebuilder(
      database,
      progressionEligibility: DriftAvatarProgressionEligibility(
        database,
        nowUtc: () => DateTime.fromMillisecondsSinceEpoch(
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1,
          isUtc: true,
        ),
      ),
    );
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
  });

  tearDown(() => database.close());

  test('reconstructs coins from grants and accepted purchases only', () async {
    await _insertGrant(
      database,
      id: 'legacy-1',
      type: 'legacyEarningBackfill',
      amount: 200,
      source: 'legacy-source',
      time: 1,
    );
    await _insertGrant(
      database,
      id: 'grant-1',
      type: 'coinGrant',
      amount: 20,
      source: 'v2-source',
      time: 2,
    );
    await _insertItemTransaction(
      database,
      id: 'purchase-1',
      type: 'purchase',
      itemId: 'theme_ocean',
      amount: -80,
      time: 3,
    );

    await rebuilder.rebuild('owner-1');

    expect(await rebuilder.coinBalance('owner-1'), 140);
    final owned = await database.select(database.ownedRewardItems).get();
    expect(owned.single.itemId, 'theme_ocean');
  });

  test('insufficient purchase remains unaccepted and does not debit', () async {
    await _insertGrant(
      database,
      id: 'grant-small',
      type: 'coinGrant',
      amount: 10,
      source: 'small-source',
      time: 1,
    );
    await _insertItemTransaction(
      database,
      id: 'purchase-too-large',
      type: 'purchase',
      itemId: 'theme_ocean',
      amount: -80,
      time: 2,
    );

    await rebuilder.rebuild('owner-1');

    expect(await rebuilder.coinBalance('owner-1'), 10);
    expect(await database.select(database.ownedRewardItems).get(), isEmpty);
  });

  test(
    'rebuild is idempotent and never mutates point audit evidence',
    () async {
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            PointsLedgerEntriesCompanion.insert(
              id: 'legacy-purchase-point',
              ownerId: 'owner-1',
              idempotencyKey: 'legacy-purchase-point',
              entryType: 'rewardPurchase',
              amount: -80,
              sourceEventId: const Value('old-purchase'),
              occurredAtUtcMs: 1,
            ),
          );
      await _insertGrant(
        database,
        id: 'grant-1',
        type: 'coinGrant',
        amount: 100,
        source: 'source-1',
        time: 2,
      );
      await _insertItemTransaction(
        database,
        id: 'purchase-1',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -80,
        time: 3,
      );
      await _insertItemTransaction(
        database,
        id: 'equip-1',
        type: 'equip',
        itemId: 'theme_ocean',
        amount: 0,
        time: 4,
      );

      await rebuilder.rebuild('owner-1');
      await rebuilder.rebuild('owner-1');

      expect(await rebuilder.coinBalance('owner-1'), 20);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.ownedRewardItems).get(),
        hasLength(1),
      );
      final equipped = await database
          .select(database.equippedRewardItems)
          .get();
      expect(equipped.single.itemId, 'theme_ocean');
    },
  );

  test(
    'validates every transaction before replacing an existing projection',
    () async {
      await _insertGrant(
        database,
        id: 'grant-before-corruption',
        type: 'coinGrant',
        amount: 100,
        source: 'source-before-corruption',
        time: 1,
      );
      await _insertItemTransaction(
        database,
        id: 'purchase-before-corruption',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -80,
        time: 2,
      );
      await _insertItemTransaction(
        database,
        id: 'equip-before-corruption',
        type: 'equip',
        itemId: 'theme_ocean',
        amount: 0,
        time: 3,
      );
      await rebuilder.rebuild('owner-1');

      await _insertItemTransaction(
        database,
        id: 'corrupt-purchase',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -1,
        time: 4,
      );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

      final owned = await database.select(database.ownedRewardItems).get();
      final equipped = await database
          .select(database.equippedRewardItems)
          .get();
      expect(owned.single.itemId, 'theme_ocean');
      expect(equipped.single.itemId, 'theme_ocean');
    },
  );

  test(
    'rebuild rejects same-type duplicate earning sources before replacing projections',
    () async {
      await _seedExistingProjection(database, rebuilder);
      final before = await _projectionState(database);
      await _insertGrant(
        database,
        id: 'duplicate-coin-a',
        type: 'coinGrant',
        amount: 10,
        source: 'duplicate-source',
        time: 4,
      );
      await _insertGrant(
        database,
        id: 'duplicate-coin-b',
        type: 'coinGrant',
        amount: 10,
        source: 'duplicate-source',
        time: 5,
      );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

      expect(await _projectionState(database), equals(before));
    },
  );

  test(
    'rebuild rejects cross-type duplicate earning sources before replacing projections',
    () async {
      await _seedExistingProjection(database, rebuilder);
      final before = await _projectionState(database);
      await _insertGrant(
        database,
        id: 'duplicate-legacy',
        type: 'legacyEarningBackfill',
        amount: 10,
        source: 'cross-type-duplicate-source',
        time: 4,
      );
      await _insertGrant(
        database,
        id: 'duplicate-canonical',
        type: 'coinGrant',
        amount: 10,
        source: 'cross-type-duplicate-source',
        time: 5,
      );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

      expect(await _projectionState(database), equals(before));
    },
  );

  test(
    'first cutover at the boundary quarantines the complete raw v1 avatar set',
    () async {
      await _insertGrant(
        database,
        id: 'late-upgrader-funding',
        type: 'coinGrant',
        amount: 100,
        source: 'late-upgrader-funding',
        time: 1,
      );
      await _insertItemTransaction(
        database,
        id: 'late-upgrader-purchase',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -80,
        time: 2,
      );
      await _insertItemTransaction(
        database,
        id: 'late-upgrader-equip',
        type: 'equip',
        itemId: 'theme_ocean',
        amount: 0,
        time: 3,
      );
      final eligibility = DriftAvatarProgressionEligibility(
        database,
        nowUtc: () => DateTime.fromMillisecondsSinceEpoch(
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
          isUtc: true,
        ),
      );

      await expectLater(
        eligibility.establishCutover('owner-1'),
        throwsStateError,
      );

      expect(
        await database.select(database.rewardTransactions).get(),
        hasLength(3),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);
    },
  );

  test(
    'pre-cutover marker fingerprints raw equip as well as purchase',
    () async {
      await _insertGrant(
        database,
        id: 'legacy-funding',
        type: 'coinGrant',
        amount: 100,
        source: 'legacy-funding',
        time: 1,
      );
      await _insertItemTransaction(
        database,
        id: 'legacy-purchase',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -80,
        time: 2,
      );
      await _insertItemTransaction(
        database,
        id: 'legacy-equip',
        type: 'equip',
        itemId: 'theme_ocean',
        amount: 0,
        time: 3,
      );
      await rebuilder.rebuild('owner-1');
      final marker = (await database.select(database.eventsV2).get()).single;
      expect(marker.recordedAtUtc.millisecondsSinceEpoch, 1790812799000);

      await _insertItemTransaction(
        database,
        id: 'backdated-equip-after-marker',
        type: 'equip',
        itemId: 'theme_ocean',
        amount: 0,
        time: 4,
      );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);
    },
  );

  test(
    'post-cutover first marker admits only portable carry evidence',
    () async {
      const purchaseId = 'portable-purchase';
      const equipId = 'portable-equip';
      final purchase = RewardCatalog.byIdAtVersion(
        'theme_ocean',
        RewardCatalog.catalogV1Version,
      )!;
      final purchaseSource = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: purchaseId,
            idempotencyKey: 'idem:$purchaseId',
            transactionType: 'purchase',
            amount: -80,
            itemId: purchase.id,
            catalogVersion: purchase.catalogVersion,
            occurredAtUtcMs: 2,
          )
          .sourceEventId;
      final equipSource = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: equipId,
            idempotencyKey: 'idem:$equipId',
            transactionType: 'equip',
            amount: 0,
            itemId: purchase.id,
            catalogVersion: purchase.catalogVersion,
            occurredAtUtcMs: 3,
          )
          .sourceEventId;
      await _insertGrant(
        database,
        id: 'portable-funding',
        type: 'coinGrant',
        amount: 100,
        source: 'portable-funding',
        time: 1,
      );
      await _insertItemTransaction(
        database,
        id: purchaseId,
        type: 'purchase',
        itemId: purchase.id,
        amount: -80,
        time: 2,
        sourceEventId: purchaseSource,
      );
      await _insertItemTransaction(
        database,
        id: equipId,
        type: 'equip',
        itemId: purchase.id,
        amount: 0,
        time: 3,
        sourceEventId: equipSource,
      );
      final lateRebuilder = DriftRewardProjectionRebuilder(
        database,
        progressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => DateTime.fromMillisecondsSinceEpoch(
            AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1,
            isUtc: true,
          ),
        ),
      );

      await lateRebuilder.rebuild('owner-1');

      expect(
        await database.select(database.ownedRewardItems).get(),
        hasLength(1),
      );
      expect(
        await database.select(database.equippedRewardItems).get(),
        hasLength(1),
      );
    },
  );

  test(
    'persisted cutover rejects a late v1 purchase before replacing projections',
    () async {
      await _seedExistingProjection(database, rebuilder);
      final before = await _projectionState(database);
      await _insertItemTransaction(
        database,
        id: 'late-v1-purchase',
        type: 'purchase',
        itemId: 'theme_ocean',
        amount: -80,
        time: AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs,
      );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

      expect(await _projectionState(database), equals(before));
    },
  );

  test(
    'rebuild rejects tampered legacy carry equip before replacing projections',
    () async {
      await _seedExistingProjection(database, rebuilder);
      final before = await _projectionState(database);
      const transactionId = 'tampered-legacy-carry-equip';
      const idempotencyKey = 'tampered-legacy-carry-equip';
      const occurredAtUtcMs = 4;
      final item = RewardCatalog.byIdAtVersion(
        'theme_ocean',
        RewardCatalog.catalogV1Version,
      )!;
      final source = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: transactionId,
            idempotencyKey: idempotencyKey,
            transactionType: 'equip',
            amount: 0,
            itemId: item.id,
            catalogVersion: item.catalogVersion,
            occurredAtUtcMs: occurredAtUtcMs,
          )
          .sourceEventId;
      final tamperedSource =
          '${source.substring(0, source.length - 1)}'
          '${source.endsWith('0') ? '1' : '0'}';
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: transactionId,
              ownerId: 'owner-1',
              idempotencyKey: idempotencyKey,
              transactionType: 'equip',
              amount: 0,
              itemId: Value(item.id),
              catalogVersion: item.catalogVersion,
              sourceEventId: Value(tamperedSource),
              occurredAtUtcMs: occurredAtUtcMs,
            ),
          );

      await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

      expect(await _projectionState(database), equals(before));
    },
  );

  for (final invalidRow
      in <({String name, String idempotencyKey, int occurredAtUtcMs})>[
        (name: 'blank idempotency key', idempotencyKey: '', occurredAtUtcMs: 4),
        (
          name: 'overlong idempotency key',
          idempotencyKey: List<String>.filled(257, 'i').join(),
          occurredAtUtcMs: 4,
        ),
        (
          name: 'negative occurrence',
          idempotencyKey: 'idem:negative-occurrence',
          occurredAtUtcMs: -1,
        ),
      ]) {
    test(
      'rebuild rejects ${invalidRow.name} before replacing projections',
      () async {
        await _seedExistingProjection(database, rebuilder);
        final before = await _projectionState(database);
        await _insertGrant(
          database,
          id: 'invalid-full-row',
          type: 'coinGrant',
          amount: 10,
          source: 'invalid-full-row-source',
          time: invalidRow.occurredAtUtcMs,
          idempotencyKey: invalidRow.idempotencyKey,
        );

        await expectLater(rebuilder.rebuild('owner-1'), throwsStateError);

        expect(await _projectionState(database), equals(before));
      },
    );
  }
}

Future<void> _insertGrant(
  AppDatabase database, {
  required String id,
  required String type,
  required int amount,
  required String source,
  required int time,
  String? idempotencyKey,
}) {
  return database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          idempotencyKey: idempotencyKey ?? 'idem:$id',
          transactionType: type,
          amount: amount,
          catalogVersion: 0,
          sourceEventId: Value(source),
          occurredAtUtcMs: time,
        ),
      );
}

Future<void> _seedExistingProjection(
  AppDatabase database,
  DriftRewardProjectionRebuilder rebuilder,
) async {
  await _insertGrant(
    database,
    id: 'existing-grant',
    type: 'coinGrant',
    amount: 100,
    source: 'existing-source',
    time: 1,
  );
  await _insertItemTransaction(
    database,
    id: 'existing-purchase',
    type: 'purchase',
    itemId: 'theme_ocean',
    amount: -80,
    time: 2,
  );
  await _insertItemTransaction(
    database,
    id: 'existing-equip',
    type: 'equip',
    itemId: 'theme_ocean',
    amount: 0,
    time: 3,
  );
  await rebuilder.rebuild('owner-1');
}

Future<Map<String, Object?>> _projectionState(AppDatabase database) async {
  final owned = await database.select(database.ownedRewardItems).get();
  owned.sort((left, right) => left.id.compareTo(right.id));
  final equipped = await database.select(database.equippedRewardItems).get();
  equipped.sort((left, right) => left.id.compareTo(right.id));
  return <String, Object?>{
    'owned': [
      for (final item in owned)
        <Object?>[
          item.id,
          item.ownerId,
          item.itemId,
          item.catalogVersion,
          item.acquiredByTransactionId,
          item.acquiredAtUtcMs,
        ],
    ],
    'equipped': [
      for (final item in equipped)
        <Object?>[
          item.id,
          item.ownerId,
          item.slot,
          item.itemId,
          item.equippedAtUtcMs,
        ],
    ],
  };
}

Future<void> _insertItemTransaction(
  AppDatabase database, {
  required String id,
  required String type,
  required String itemId,
  required int amount,
  required int time,
  String? sourceEventId,
}) {
  return database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          idempotencyKey: 'idem:$id',
          transactionType: type,
          amount: amount,
          itemId: Value(itemId),
          catalogVersion: RewardCatalog.legacyVersion,
          sourceEventId: Value(sourceEventId),
          occurredAtUtcMs: time,
        ),
      );
}
