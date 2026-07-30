import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  late AppDatabase database;
  late RewardUseCases rewards;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    rewards = RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      generateId: () => 'tx-${sequence++}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );
    await owners.getOrCreateActiveOwner();
    await database.customInsert(
      "INSERT INTO points_ledger_entries "
      "(id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) "
      "VALUES ('seed', 'local:owner', 'seed', 'learning', 200, 1)",
    );
  });

  tearDown(() => database.close());

  test('purchase is atomic, durable, and idempotent', () async {
    final first = await rewards.purchase(
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'tap-1',
    );
    final replay = await rewards.purchase(
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'tap-1',
    );

    expect(first.status, PurchaseStatus.purchased);
    expect(first.account.balance, 120);
    expect(first.account.ownedItemIds, contains('theme_ocean'));
    expect(replay.status, PurchaseStatus.replayed);
    expect(replay.account.balance, 120);
    expect(
      await database.select(database.rewardTransactions).get(),
      hasLength(1),
    );
    final outbox = await database.select(database.outboxOperations).getSingle();
    expect(outbox.entityType, 'rewardTransaction');
    expect(outbox.entityId, 'reward:tx-0');
    expect(outbox.state, 'pending');
  });

  test('concurrent purchases cannot create a negative balance', () async {
    final outcomes = await Future.wait(
      [('weapon_cefr', 'a'), ('armor_srs', 'b')].map(
        (request) => rewards
            .purchase(
              itemId: request.$1,
              catalogVersion: RewardCatalog.version,
              idempotencyKey: request.$2,
            )
            .then<Object>((value) => value)
            .catchError((Object error) => error),
      ),
    );

    expect(outcomes.whereType<PurchaseResult>(), hasLength(1));
    expect(
      outcomes.whereType<RewardException>().single.code,
      RewardFailureCode.insufficientBalance,
    );
    expect((await rewards.load()).balance, 80);
  });

  test('equipment requires ownership and keeps one item per slot', () async {
    await expectLater(
      rewards.equip('theme_ocean'),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.notOwned,
        ),
      ),
    );
    await rewards.purchase(
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'theme-buy',
    );
    final account = await rewards.equip('theme_ocean');
    expect(account.equippedBySlot['theme'], 'theme_ocean');
    expect(
      await database.select(database.rewardTransactions).get(),
      hasLength(2),
    );
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(2),
    );
  });

  test('rejects stale price catalog and unknown items', () async {
    await expectLater(
      rewards.purchase(
        itemId: 'theme_ocean',
        catalogVersion: 999,
        idempotencyKey: 'stale',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.staleCatalog,
        ),
      ),
    );
    await expectLater(
      rewards.purchase(
        itemId: 'missing',
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'missing',
      ),
      throwsA(isA<RewardException>()),
    );
  });
}
