import 'dart:async';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';

void main() {
  late AppDatabase database;
  late DriftLocalOwnerRepository owners;
  late RewardUseCases rewards;
  var sequence = 0;

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    owners = DriftLocalOwnerRepository(
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
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'tap-1',
    );
    final replay = await rewards.purchase(
      expectedOwnerId: 'local:owner',
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
      await (database.select(
        database.rewardTransactions,
      )..where((r) => r.transactionType.equals('purchase'))).get(),
      hasLength(1),
    );
    final outbox = await database.select(database.outboxOperations).getSingle();
    expect(outbox.entityType, 'rewardTransaction');
    expect(outbox.entityId, 'reward:tx-0');
    expect(outbox.state, 'pending');
  });

  test(
    'committed purchase acknowledgement loss replays without duplicate debit',
    () async {
      var loseAcknowledgement = true;
      final retryRewards = RewardUseCases(
        owners: owners,
        repository: DriftRewardRepository(database),
        generateId: () => 'lost-ack-tx-${sequence++}',
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
        onLocalMutation: () {
          if (!loseAcknowledgement) return;
          loseAcknowledgement = false;
          throw StateError('synthetic acknowledgement loss');
        },
      );

      await expectLater(
        retryRewards.purchase(
          expectedOwnerId: 'local:owner',
          itemId: 'theme_ocean',
          catalogVersion: RewardCatalog.version,
          idempotencyKey: 'stable-lost-ack-intent',
        ),
        throwsA(isA<StateError>()),
      );
      final replay = await retryRewards.purchase(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'stable-lost-ack-intent',
      );

      final purchases = await (database.select(
        database.rewardTransactions,
      )..where((row) => row.transactionType.equals('purchase'))).get();
      final outbox = await database.select(database.outboxOperations).get();
      expect(replay.status, PurchaseStatus.replayed);
      expect(replay.account.balance, 120);
      expect(replay.account.ownedItemIds, contains('theme_ocean'));
      expect(purchases, hasLength(1));
      expect(purchases.single.amount, -80);
      expect(outbox, hasLength(1));
      expect(outbox.single.entityId, purchases.single.id);
    },
  );

  test('concurrent purchases cannot create a negative balance', () async {
    final outcomes = await Future.wait(
      [('weapon_cefr', 'a'), ('armor_srs', 'b')].map(
        (request) => rewards
            .purchase(
              expectedOwnerId: 'local:owner',
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
      rewards.equip(
        itemId: 'theme_ocean',
        idempotencyKey: 'equip-missing',
        expectedOwnerId: 'local:owner',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.notOwned,
        ),
      ),
    );
    await rewards.purchase(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'theme-buy',
    );
    final result = await rewards.equip(
      itemId: 'theme_ocean',
      idempotencyKey: 'equip-theme',
      expectedOwnerId: 'local:owner',
    );
    expect(result.status, EquipStatus.equipped);
    expect(result.account.equippedBySlot['theme'], 'theme_ocean');
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((r) => r.transactionType.isIn(['purchase', 'equip']))).get(),
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
        expectedOwnerId: 'local:owner',
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
        expectedOwnerId: 'local:owner',
        itemId: 'missing',
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'missing',
      ),
      throwsA(isA<RewardException>()),
    );
  });

  test('equip replay and already-equipped requests add no evidence', () async {
    await rewards.purchase(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      catalogVersion: RewardCatalog.version,
      idempotencyKey: 'buy-ocean',
    );

    final first = await rewards.equip(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      idempotencyKey: 'equip-ocean',
    );
    final replay = await rewards.equip(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      idempotencyKey: 'equip-ocean',
    );
    final alreadyEquipped = await rewards.equip(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_ocean',
      idempotencyKey: 'equip-ocean-again',
    );

    expect(first.status, EquipStatus.equipped);
    expect(replay.status, EquipStatus.replayed);
    expect(alreadyEquipped.status, EquipStatus.alreadyEquipped);
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((row) => row.transactionType.equals('equip'))).get(),
      hasLength(1),
    );
    expect(
      await (database.select(
        database.outboxOperations,
      )..where((row) => row.entityType.equals('rewardTransaction'))).get(),
      hasLength(2),
    );
  });

  test('equip rejects reuse of an intent key for another item', () async {
    final first = await rewards.equip(
      expectedOwnerId: 'local:owner',
      itemId: 'theme_default',
      idempotencyKey: 'equip-conflict',
    );
    expect(first.status, EquipStatus.equipped);

    await expectLater(
      rewards.equip(
        expectedOwnerId: 'local:owner',
        itemId: 'wallpaper_focus',
        idempotencyKey: 'equip-conflict',
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
    'appearance follows active owner and never leaks the previous owner',
    () async {
      await rewards.purchase(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'buy-appearance',
      );
      await rewards.equip(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_ocean',
        idempotencyKey: 'equip-appearance',
      );
      final appearances = StreamIterator(rewards.watchAppearance());
      addTearDown(appearances.cancel);

      expect(await appearances.moveNext(), isTrue);
      expect(appearances.current.ownerId, 'local:owner');
      expect(appearances.current.equippedBySlot['theme'], 'theme_ocean');

      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('local:owner')))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
            );
      });

      expect(await appearances.moveNext(), isTrue);
      expect(appearances.current.ownerId, 'owner-b');
      expect(appearances.current.equippedBySlot, isEmpty);
    },
  );

  test('owner transition during purchase never debits the new owner', () async {
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: 'owner-b',
            createdAtUtcMs: 2,
            isActive: const Value(false),
          ),
        );
    final transitioningRewards = RewardUseCases(
      owners: _SequencedOwnerRepository(<String>['local:owner', 'owner-b']),
      repository: DriftRewardRepository(database),
      generateId: () => 'transition-tx',
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );

    await expectLater(
      transitioningRewards.purchase(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'transition-buy',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.ownerChanged,
        ),
      ),
    );

    final transactions = await (database.select(
      database.rewardTransactions,
    )..where((row) => row.transactionType.equals('purchase'))).get();
    expect(
      transactions.where((row) => row.ownerId == 'local:owner'),
      hasLength(1),
    );
    expect(transactions.where((row) => row.ownerId == 'owner-b'), isEmpty);
  });

  test('owner transition during equip never equips the new owner', () async {
    final transitioningRewards = RewardUseCases(
      owners: _SequencedOwnerRepository(<String>['local:owner', 'owner-b']),
      repository: DriftRewardRepository(database),
      generateId: () => 'transition-equip-tx',
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );

    await expectLater(
      transitioningRewards.equip(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_default',
        idempotencyKey: 'transition-equip',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.ownerChanged,
        ),
      ),
    );

    final transactions = await (database.select(
      database.rewardTransactions,
    )..where((row) => row.transactionType.equals('equip'))).get();
    expect(
      transactions.where((row) => row.ownerId == 'local:owner'),
      hasLength(1),
    );
    expect(transactions.where((row) => row.ownerId == 'owner-b'), isEmpty);
  });

  test('queued equip refuses an owner no longer active at the write', () async {
    final switchStarted = Completer<void>();
    final allowSwitchCommit = Completer<void>();
    final equipAcceptedByApplication = Completer<void>();
    final switching = database.transaction(() async {
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals('local:owner')))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-b', createdAtUtcMs: 2),
          );
      switchStarted.complete();
      await allowSwitchCommit.future;
    });
    await switchStarted.future;
    final transitioningRewards = RewardUseCases(
      owners: _SequencedOwnerRepository(['local:owner', 'owner-b']),
      repository: DriftRewardRepository(database),
      generateId: () {
        equipAcceptedByApplication.complete();
        return 'queued-equip';
      },
      nowUtc: () => DateTime.utc(2026, 7, 30, 12),
    );
    final equip = expectLater(
      transitioningRewards.equip(
        expectedOwnerId: 'local:owner',
        itemId: 'theme_default',
        idempotencyKey: 'old-owner-equip',
      ),
      throwsA(
        isA<RewardException>().having(
          (error) => error.code,
          'code',
          RewardFailureCode.ownerChanged,
        ),
      ),
    );
    await equipAcceptedByApplication.future;
    allowSwitchCommit.complete();
    await switching;
    await equip;

    expect(await database.select(database.rewardTransactions).get(), isEmpty);
    expect(await database.select(database.outboxOperations).get(), isEmpty);
    expect(await database.select(database.equippedRewardItems).get(), isEmpty);
  });

  test(
    'built-in wallpaper replaces focus without a purchase or debit',
    () async {
      const standard = 'wallpaper_default';
      const focus = 'wallpaper_focus';
      const owner = 'local:owner';
      await rewards.purchase(
        expectedOwnerId: owner,
        itemId: focus,
        catalogVersion: RewardCatalog.version,
        idempotencyKey: 'buy-focus',
      );
      final focused = await rewards.equip(
        expectedOwnerId: owner,
        itemId: focus,
        idempotencyKey: 'equip-focus',
      );
      expect(focused.account.equippedBySlot['wallpaper'], focus);

      final standardRewards = RewardUseCases(
        owners: owners,
        repository: DriftRewardRepository(database),
        generateId: () => 'standard-tx-${sequence++}',
        nowUtc: () => DateTime.utc(2026, 7, 30, 13),
      );
      final reset = await standardRewards.equip(
        expectedOwnerId: owner,
        itemId: standard,
        idempotencyKey: 'reset-wallpaper',
      );
      final replay = await standardRewards.equip(
        expectedOwnerId: owner,
        itemId: standard,
        idempotencyKey: 'reset-wallpaper',
      );
      expect(reset.status, EquipStatus.equipped);
      expect(replay.status, EquipStatus.replayed);
      expect(replay.account.equippedBySlot['wallpaper'], standard);
      expect(replay.account.balance, focused.account.balance);
      expect(replay.account.ownedItemIds, {focus});

      final actualStandard = await (database.select(
        database.rewardTransactions,
      )..where((row) => row.itemId.equals(standard))).getSingle();
      expect(actualStandard.ownerId, owner);
      expect(actualStandard.transactionType, 'equip');
      expect(actualStandard.amount, 0);
      final appearance = await standardRewards.watchAppearance().first;
      expect(appearance.equippedBySlot['wallpaper'], standard);
    },
  );

  test(
    'built-in wallpaper cannot be purchased through either writer',
    () async {
      const standard = 'wallpaper_default';
      const owner = 'local:owner';
      await expectLater(
        rewards.purchase(
          expectedOwnerId: owner,
          itemId: standard,
          catalogVersion: RewardCatalog.version,
          idempotencyKey: 'buy-standard',
        ),
        throwsA(isA<RewardException>()),
      );
      expect(
        RewardCatalog.items.map((item) => item.id),
        isNot(contains(standard)),
      );
      await expectLater(
        rewards.repository.purchase(
          ownerId: owner,
          item: RewardCatalog.byId(standard)!,
          idempotencyKey: 'buy-direct',
          transactionId: 'buy-direct',
          occurredAtUtc: DateTime.utc(2026, 7, 30),
        ),
        throwsA(isA<RewardException>()),
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    },
  );

  test('a raw default wallpaper purchase has no ownership effect', () async {
    await database.customInsert(
      "INSERT INTO reward_transactions "
      "(id, owner_id, idempotency_key, transaction_type, amount, item_id, "
      "catalog_version, occurred_at_utc_ms) "
      "VALUES ('raw-default', 'local:owner', 'raw-default', 'purchase', "
      "0, 'wallpaper_default', 1, 2)",
    );
    final account = await rewards.load();
    expect(account.ownedItemIds, isEmpty);
    expect(account.equippedBySlot, isEmpty);
    expect(account.balance, 200);
  });

  test(
    'loadSession rejects an owner snapshot that changed during load',
    () async {
      final transitioningRewards = RewardUseCases(
        owners: _SequencedOwnerRepository(<String>['local:owner', 'owner-b']),
        repository: DriftRewardRepository(database),
        generateId: () => 'unused',
        nowUtc: () => DateTime.utc(2026, 7, 30, 12),
      );

      await expectLater(
        transitioningRewards.loadSession(),
        throwsA(
          isA<RewardException>().having(
            (error) => error.code,
            'code',
            RewardFailureCode.ownerChanged,
          ),
        ),
      );
    },
  );
}

final class _SequencedOwnerRepository implements LocalOwnerRepository {
  _SequencedOwnerRepository(this._ownerIds);

  final List<String> _ownerIds;
  var _index = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    final ownerId = _ownerIds[_index.clamp(0, _ownerIds.length - 1)];
    _index += 1;
    return identity.LocalOwner(
      id: ownerId,
      createdAtUtc: DateTime.utc(2026, 7, 30),
    );
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) {
    throw UnimplementedError();
  }
}
