import 'package:drift/drift.dart' show Value;
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
  late DriftRewardRepository repository;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'owner',
      nowUtc: () => DateTime.utc(2026, 7, 30),
    );
    repository = DriftRewardRepository(database);
    rewards = RewardUseCases(
      owners: owners,
      repository: repository,
      generateId: () => 'tx-${sequence++}',
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );
    await owners.getOrCreateActiveOwner();
    await database.customInsert(
      "INSERT INTO points_ledger_entries "
      "(id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) "
      "VALUES ('seed', 'local:owner', 'seed', 'quizCorrect', 200, 1)",
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
    expect(first.account.coinBalance, 120);
    expect(first.account.transactionCount, 1);
    expect(first.account.ownedItemIds, contains('theme_ocean'));
    expect(replay.status, PurchaseStatus.replayed);
    expect(replay.account.coinBalance, 120);
    expect(replay.account.transactionCount, 1);
    expect(
      (await database.select(database.rewardTransactions).get()).where(
        (row) => row.transactionType == 'purchase',
      ),
      hasLength(1),
    );
    final outbox = (await database.select(database.outboxOperations).get())
        .singleWhere((row) => row.entityId == 'reward:tx-0');
    expect(outbox.entityType, 'rewardTransaction');
    expect(outbox.entityId, 'reward:tx-0');
    expect(outbox.state, 'pending');
    final points = await database.select(database.pointsLedgerEntries).get();
    expect(points, hasLength(1));
    expect(points.single.amount, 200);
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
    expect((await rewards.load()).coinBalance, 80);
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
    expect(account.transactionCount, 2);
    expect(
      await database.select(database.rewardTransactions).get(),
      hasLength(3),
    );
    expect(
      await database.select(database.outboxOperations).get(),
      hasLength(3),
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

  test('coin grant inserts once and exact replay is idempotent', () async {
    final first = await rewards.grantCoins(
      idempotencyKey: 'coins:new-answer',
      amount: 7,
      sourceEventId: 'learning-event:new-answer',
    );
    final replay = await rewards.grantCoins(
      idempotencyKey: 'coins:new-answer',
      amount: 7,
      sourceEventId: 'learning-event:new-answer',
    );

    expect(first, CoinGrantResult.inserted);
    expect(replay, CoinGrantResult.replayed);
    expect((await rewards.load()).coinBalance, 207);
    expect(
      (await database.select(database.rewardTransactions).get()).where(
        (row) => row.transactionType == 'coinGrant',
      ),
      hasLength(1),
    );

    await expectLater(
      rewards.grantCoins(
        idempotencyKey: 'coins:new-answer',
        amount: 8,
        sourceEventId: 'learning-event:new-answer',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.invalidIdempotencyKey,
        ),
      ),
    );
  });

  test(
    'legacy backfill captures an exact later coin grant for the same source',
    () async {
      final before = await _rewardState(database, repository);
      final result = await repository.grantCoins(
        ownerId: 'local:owner',
        idempotencyKey: 'coins:legacy-seed',
        amount: 200,
        sourceEventId: 'seed',
        occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
      );

      expect(result, CoinGrantResult.capturedByLegacyBackfill);
      expect(await _rewardState(database, repository), equals(before));
    },
  );

  test(
    'legacy backfill rejects a same-source amount mismatch without mutation',
    () async {
      final before = await _rewardState(database, repository);

      await expectLater(
        repository.grantCoins(
          ownerId: 'local:owner',
          idempotencyKey: 'coins:legacy-seed-amount-mismatch',
          amount: 201,
          sourceEventId: 'seed',
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(1, isUtc: true),
        ),
        _throwsInvalidRewardIdentity,
      );
      expect(await _rewardState(database, repository), equals(before));
    },
  );

  test(
    'legacy backfill rejects a same-source occurrence mismatch without mutation',
    () async {
      final before = await _rewardState(database, repository);

      await expectLater(
        repository.grantCoins(
          ownerId: 'local:owner',
          idempotencyKey: 'coins:legacy-seed-occurrence-mismatch',
          amount: 200,
          sourceEventId: 'seed',
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(2, isUtc: true),
        ),
        _throwsInvalidRewardIdentity,
      );
      expect(await _rewardState(database, repository), equals(before));
    },
  );

  test(
    'coin grant rejects a same-source occurrence mismatch under another key',
    () async {
      final occurredAt = DateTime.utc(2026, 7, 30, 12);
      await repository.grantCoins(
        ownerId: 'local:owner',
        idempotencyKey: 'coins:source-first',
        amount: 7,
        sourceEventId: 'learning-event:shared-source',
        occurredAtUtc: occurredAt,
      );
      final before = await _rewardState(database, repository);

      await expectLater(
        repository.grantCoins(
          ownerId: 'local:owner',
          idempotencyKey: 'coins:source-collision',
          amount: 7,
          sourceEventId: 'learning-event:shared-source',
          occurredAtUtc: occurredAt.add(const Duration(milliseconds: 1)),
        ),
        _throwsInvalidRewardIdentity,
      );
      expect(await _rewardState(database, repository), equals(before));
    },
  );

  test(
    'repository purchase rejects a blank idempotency key without mutation',
    () async {
      await _expectRejectedWithoutRewardMutation(
        database: database,
        repository: repository,
        operation: () => repository.purchase(
          ownerId: 'local:owner',
          item: RewardCatalog.byId('theme_ocean')!,
          idempotencyKey: '',
          transactionId: 'reward:invalid-purchase',
          occurredAtUtc: DateTime.utc(2026, 7, 30, 12),
        ),
      );
    },
  );

  test(
    'repository equip rejects an overlong derived idempotency key without mutation',
    () async {
      await _expectRejectedWithoutRewardMutation(
        database: database,
        repository: repository,
        operation: () => repository.equip(
          ownerId: 'local:owner',
          item: RewardCatalog.byId('theme_default')!,
          transactionId: List<String>.filled(251, 'e').join(),
          occurredAtUtc: DateTime.utc(2026, 7, 30, 12),
        ),
      );
    },
  );

  test(
    'repository grant rejects a pre-epoch occurrence without mutation',
    () async {
      await _expectRejectedWithoutRewardMutation(
        database: database,
        repository: repository,
        operation: () => repository.grantCoins(
          ownerId: 'local:owner',
          idempotencyKey: 'coins:pre-epoch',
          amount: 7,
          sourceEventId: 'learning-event:pre-epoch',
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(-1, isUtc: true),
        ),
      );
    },
  );

  test(
    'quest xp and paired coins commit atomically with distinct keys',
    () async {
      final first = await repository.grantQuestXpAndCoins(
        ownerId: 'local:owner',
        sourceEventId: 'quest-completion:daily-1',
        xpAmount: 50,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 13),
      );
      final replay = await repository.grantQuestXpAndCoins(
        ownerId: 'local:owner',
        sourceEventId: 'quest-completion:daily-1',
        xpAmount: 50,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 13),
      );

      expect(first, QuestEconomyGrantResult.inserted);
      expect(replay, QuestEconomyGrantResult.replayed);
      final questXp =
          (await database.select(database.pointsLedgerEntries).get())
              .singleWhere((row) => row.entryType == 'questCompletion');
      final questCoins =
          (await database.select(database.rewardTransactions).get())
              .singleWhere(
                (row) =>
                    row.transactionType == 'coinGrant' &&
                    row.sourceEventId == 'quest-completion:daily-1',
              );
      expect(questXp.amount, 50);
      expect(questCoins.amount, 50);
      expect(questXp.idempotencyKey, isNot(questCoins.idempotencyKey));
      expect((await repository.load('local:owner')).coinBalance, 250);
    },
  );

  test('identical idempotency keys remain isolated between owners', () async {
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2));
    final at = DateTime.utc(2026, 7, 30, 14);

    final first = await repository.grantCoins(
      ownerId: 'local:owner',
      idempotencyKey: 'shared-key',
      amount: 3,
      sourceEventId: 'shared-source',
      occurredAtUtc: at,
    );
    final second = await repository.grantCoins(
      ownerId: 'owner-2',
      idempotencyKey: 'shared-key',
      amount: 3,
      sourceEventId: 'shared-source',
      occurredAtUtc: at,
    );

    expect(first, CoinGrantResult.inserted);
    expect(second, CoinGrantResult.inserted);
    expect(
      (await database.select(database.rewardTransactions).get()).where(
        (row) => row.transactionType == 'coinGrant',
      ),
      hasLength(2),
    );
  });

  test(
    'identical quest source identities remain isolated between owners',
    () async {
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 2),
          );
      final at = DateTime.utc(2026, 7, 30, 15);

      final first = await repository.grantQuestXpAndCoins(
        ownerId: 'local:owner',
        sourceEventId: 'shared-quest-source',
        xpAmount: 4,
        occurredAtUtc: at,
      );
      final second = await repository.grantQuestXpAndCoins(
        ownerId: 'owner-2',
        sourceEventId: 'shared-quest-source',
        xpAmount: 4,
        occurredAtUtc: at,
      );

      expect(first, QuestEconomyGrantResult.inserted);
      expect(second, QuestEconomyGrantResult.inserted);
      expect(
        (await database.select(database.pointsLedgerEntries).get()).where(
          (row) => row.entryType == 'questCompletion',
        ),
        hasLength(2),
      );
    },
  );

  test(
    'atomic quest grant recognizes the deployed legacy source identity',
    () async {
      await database
          .into(database.pointsLedgerEntries)
          .insert(
            PointsLedgerEntriesCompanion.insert(
              id: 'legacy-quest-point',
              ownerId: 'local:owner',
              idempotencyKey: 'quest_complete_daily-legacy',
              entryType: 'questCompletion',
              amount: 50,
              sourceEventId: const Value('quest_complete_daily-legacy'),
              occurredAtUtcMs: 10,
            ),
          );

      final result = await repository.grantQuestXpAndCoins(
        ownerId: 'local:owner',
        sourceEventId: 'quest_complete_daily-legacy',
        xpAmount: 50,
        occurredAtUtc: DateTime.utc(2026, 7, 30, 16),
      );

      expect(result, QuestEconomyGrantResult.replayed);
      expect(
        (await database.select(database.pointsLedgerEntries).get()).where(
          (row) => row.sourceEventId == 'quest_complete_daily-legacy',
        ),
        hasLength(1),
      );
      final legacyCoins =
          (await database.select(database.rewardTransactions).get()).where(
            (row) => row.sourceEventId == 'quest_complete_daily-legacy',
          );
      expect(legacyCoins, hasLength(1));
      expect(legacyCoins.single.transactionType, 'legacyEarningBackfill');
    },
  );

  test(
    'deprecated zero quest grant still runs the incremental cutover',
    () async {
      await repository.grantQuestXp(
        ownerId: 'local:owner',
        idempotencyKey: 'no-op-quest',
        xpAmount: 0,
      );

      final transactions = await database
          .select(database.rewardTransactions)
          .get();
      expect(transactions, hasLength(1));
      expect(transactions.single.transactionType, 'legacyEarningBackfill');
    },
  );
}

Matcher get _throwsInvalidRewardIdentity => throwsA(
  isA<RewardException>().having(
    (error) => error.code,
    'code',
    RewardFailureCode.invalidIdempotencyKey,
  ),
);

Future<void> _expectRejectedWithoutRewardMutation({
  required AppDatabase database,
  required DriftRewardRepository repository,
  required Future<Object?> Function() operation,
}) async {
  final before = await _rewardState(database, repository);

  await expectLater(operation, throwsArgumentError);

  expect(await _rewardState(database, repository), equals(before));
}

Future<Map<String, Object?>> _rewardState(
  AppDatabase database,
  DriftRewardRepository repository,
) async {
  final account = await repository.load('local:owner');
  final transactions = await database.select(database.rewardTransactions).get();
  transactions.sort((left, right) => left.id.compareTo(right.id));
  final outbox = await database.select(database.outboxOperations).get();
  outbox.sort((left, right) => left.operationId.compareTo(right.operationId));
  final owned = account.ownedItemIds.toList()..sort();
  final equipped =
      account.equippedBySlot.entries
          .map((entry) => '${entry.key}:${entry.value}')
          .toList()
        ..sort();

  return <String, Object?>{
    'transactions': [
      for (final transaction in transactions)
        <Object?>[
          transaction.id,
          transaction.ownerId,
          transaction.idempotencyKey,
          transaction.transactionType,
          transaction.amount,
          transaction.itemId,
          transaction.catalogVersion,
          transaction.sourceEventId,
          transaction.occurredAtUtcMs,
        ],
    ],
    'outbox': [
      for (final operation in outbox)
        <Object?>[
          operation.operationId,
          operation.ownerId,
          operation.entityType,
          operation.entityId,
          operation.operationKind,
          operation.payloadVersion,
          operation.createdAtUtcMs,
          operation.state,
        ],
    ],
    'coinBalance': account.coinBalance,
    'catalogVersion': account.catalogVersion,
    'ownedItemIds': owned,
    'equippedBySlot': equipped,
    'transactionCount': account.transactionCount,
  };
}
