import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

void main() {
  late AppDatabase database;
  late DriftSyncStore syncStore;
  final now = DateTime.utc(2026, 7, 30, 12);

  setUp(() async {
    database = AppDatabase(NativeDatabase.memory());
    syncStore = DriftSyncStore(database);
    await database
        .into(database.localOwners)
        .insert(LocalOwnersCompanion.insert(id: 'owner-1', createdAtUtcMs: 1));
    await database.customInsert(
      "INSERT INTO points_ledger_entries "
      "(id, owner_id, idempotency_key, entry_type, amount, occurred_at_utc_ms) "
      "VALUES ('learning-points', 'owner-1', 'learning-points', "
      "'quizCorrect', 200, 1)",
    );
    await database
        .into(database.vocabularyCategories)
        .insert(
          VocabularyCategoriesCompanion.insert(
            id: 'category-1',
            ownerId: 'owner-1',
            name: 'Travel',
            normalizedName: 'travel',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
    await database
        .into(database.vocabularyWords)
        .insert(
          VocabularyWordsCompanion.insert(
            id: 'word-1',
            ownerId: 'owner-1',
            categoryId: 'category-1',
            spelling: 'station',
            normalizedSpelling: 'station',
            meaning: 'สถานี',
            normalizedMeaning: 'สถานี',
            partOfSpeech: 'noun',
            createdAtUtcMs: 1,
            updatedAtUtcMs: 1,
          ),
        );
  });

  tearDown(() => database.close());

  test(
    'attempt pull commits learning when optional coin materialization conflicts',
    () async {
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'coin:legacy:learning-points',
              ownerId: 'owner-1',
              idempotencyKey: 'creditLegacyCarryV1:learning-points',
              transactionType: 'creditLegacyCarryV1',
              amount: 999,
              catalogVersion: 0,
              occurredAtUtcMs: 1,
            ),
          );
      final attempt = SyncEntity(
        collection: SyncCollection.attempts,
        entityId: 'optional-reward-attempt',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now,
        serverUpdatedAtUtc: now,
        payload: {
          'sessionId': 'session',
          'wordId': 'word-1',
          'promptMode': 'meaningChoice',
          'isCorrect': true,
          'responseTimeMs': 100,
          'attemptNumber': 1,
          'occurredAtUtcMs': now.millisecondsSinceEpoch,
          'providerProvenance': null,
        },
      );
      await expectLater(
        syncStore.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.attempts,
          page: _page(attempt),
        ),
        completes,
      );
      expect(
        await database.select(database.answerAttempts).get(),
        hasLength(1),
      );
      expect(await database.select(database.srsStates).get(), hasLength(1));
      expect(
        await database.select(database.rewardTransactions).get(),
        hasLength(1),
      );
    },
  );

  test(
    'accidental local credit outbox is quarantined while purchase still claims',
    () async {
      final rewards = DriftRewardRepository(database);
      await rewards.purchase(
        ownerId: 'owner-1',
        item: RewardCatalog.byId('theme_ocean')!,
        idempotencyKey: 'buy',
        transactionId: 'buy',
        occurredAtUtc: now,
      );
      final credit =
          await (database.select(database.rewardTransactions)
                ..where((r) => r.transactionType.equals('creditLegacyCarryV1')))
              .getSingle();
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'accidental-credit',
              ownerId: 'owner-1',
              entityType: 'rewardTransaction',
              entityId: credit.id,
              operationKind: 'upsert',
              createdAtUtcMs: 0,
            ),
          );
      final claims = await syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'lease',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );
      expect(claims, hasLength(1));
      expect(claims.single.mutation.entityId, 'buy');
      final rejected = await (database.select(
        database.outboxOperations,
      )..where((r) => r.operationId.equals('accidental-credit'))).getSingle();
      expect(rejected.state, 'permanentFailure');
      expect(rejected.failureCode, 'invalidPayload');
    },
  );

  for (final type in [
    'creditQuizCorrectV1',
    'creditLegacyCarryV1',
    'futureRewardType',
  ]) {
    test(
      'remote $type mint is quarantined without poisoning the pull cursor',
      () async {
        await expectLater(
          syncStore.applyPullPage(
            ownerId: 'owner-1',
            collection: SyncCollection.rewardTransactions,
            page: _page(
              _rewardEntity(
                id: 'remote-credit',
                idempotencyKey: 'remote-credit',
                transactionType: type,
                amount: 200,
                occurredAt: now,
              ),
            ),
          ),
          completes,
        );
        expect(
          await database.select(database.rewardTransactions).get(),
          isEmpty,
        );
        final conflicts = await database.select(database.syncConflicts).get();
        expect(conflicts, hasLength(1));
        expect(conflicts.single.outcome, 'quarantined');
        final checkpoint = await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        );
        expect(checkpoint!.documentId, 'remote-credit');
      },
    );
  }

  test(
    'a remote credit echo cannot alter a local credit or block a valid purchase',
    () async {
      final rewards = DriftRewardRepository(database);
      await rewards.load('owner-1');
      final credit = await database
          .select(database.rewardTransactions)
          .getSingle();
      final unsupported = _rewardEntity(
        id: credit.id,
        idempotencyKey: credit.idempotencyKey,
        transactionType: credit.transactionType,
        amount: credit.amount,
        occurredAt: now,
      );
      final valid = _rewardEntity(
        id: 'valid-next',
        idempotencyKey: 'valid-next',
        transactionType: 'purchase',
        amount: -80,
        occurredAt: now.add(const Duration(seconds: 1)),
      );
      final page = PullPage(
        changes: [unsupported, valid],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: valid.serverUpdatedAtUtc,
          documentId: valid.entityId,
        ),
        hasMore: false,
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: page,
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: page,
      );
      expect((await rewards.load('owner-1')).balance, 120);
      expect(
        (await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        ))!.documentId,
        'valid-next',
      );
      expect(
        (await (database.select(
          database.rewardTransactions,
        )..where((r) => r.id.equals(credit.id))).getSingle()).toJson(),
        credit.toJson(),
      );
      expect(await database.select(database.syncConflicts).get(), hasLength(1));
    },
  );

  test('local reward outbox reconstructs immutable catalog evidence', () async {
    await DriftRewardRepository(database).purchase(
      ownerId: 'owner-1',
      item: RewardCatalog.byId('theme_ocean')!,
      idempotencyKey: 'tap-1',
      transactionId: 'reward-local-1',
      occurredAtUtc: now,
    );

    final claim = (await syncStore.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-1',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
    )).single;

    expect(claim.mutation.collection, SyncCollection.rewardTransactions);
    expect(claim.mutation.baseRevision, 0);
    expect(claim.mutation.localRevision, 1);
    expect(claim.mutation.payload['transactionType'], 'purchase');
    expect(claim.mutation.payload['amount'], -80);
    expect(claim.mutation.payload['slot'], 'theme');
  });

  test('pulled purchase and equipment rebuild durable ownership', () async {
    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: _page(
        _rewardEntity(
          id: 'reward-purchase',
          idempotencyKey: 'remote-purchase',
          transactionType: 'purchase',
          amount: -80,
          occurredAt: now,
        ),
      ),
    );
    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: _page(
        _rewardEntity(
          id: 'reward-equip',
          idempotencyKey: 'remote-equip',
          transactionType: 'equip',
          amount: 0,
          occurredAt: now.add(const Duration(seconds: 1)),
        ),
      ),
    );

    final account = await DriftRewardRepository(database).load('owner-1');
    expect(account.balance, 120);
    expect(account.ownedItemIds, contains('theme_ocean'));
    expect(account.equippedBySlot['theme'], 'theme_ocean');
  });

  test('concurrent duplicate purchases debit an item only once', () async {
    final first = _rewardEntity(
      id: 'reward-first',
      idempotencyKey: 'device-a',
      transactionType: 'purchase',
      amount: -80,
      occurredAt: now,
    );
    final second = _rewardEntity(
      id: 'reward-second',
      idempotencyKey: 'device-b',
      transactionType: 'purchase',
      amount: -80,
      occurredAt: now,
    );

    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: PullPage(
        changes: [second, first],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: first.serverUpdatedAtUtc,
          documentId: first.entityId,
        ),
        hasMore: false,
      ),
    );

    final account = await DriftRewardRepository(database).load('owner-1');
    expect(account.balance, 120);
    expect(account.ownedItemIds, {'theme_ocean'});
    expect(
      await (database.select(
        database.rewardTransactions,
      )..where((r) => r.transactionType.equals('purchase'))).get(),
      hasLength(2),
    );
  });

  test(
    'later attempt points activate an earlier unaffordable purchase',
    () async {
      await database.customUpdate(
        "UPDATE points_ledger_entries SET amount = 119 WHERE id = 'learning-points'",
      );
      final purchase = _rewardEntity(
        id: 'reward-weapon',
        idempotencyKey: 'weapon-before-points',
        transactionType: 'purchase',
        amount: -120,
        itemId: 'weapon_cefr',
        slot: 'weapon',
        occurredAt: now,
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(purchase),
      );
      expect(
        (await DriftRewardRepository(database).load('owner-1')).ownedItemIds,
        isNot(contains('weapon_cefr')),
      );

      final attempt = SyncEntity(
        collection: SyncCollection.attempts,
        entityId: 'attempt-later',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: now.add(const Duration(seconds: 1)),
        serverUpdatedAtUtc: now.add(const Duration(seconds: 2)),
        payload: <String, Object?>{
          'sessionId': 'session-later',
          'wordId': 'word-1',
          'promptMode': 'meaningChoice',
          'isCorrect': true,
          'responseTimeMs': 300,
          'attemptNumber': 1,
          'occurredAtUtcMs': now
              .add(const Duration(seconds: 1))
              .millisecondsSinceEpoch,
          'providerProvenance': null,
        },
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.attempts,
        page: _page(attempt),
      );

      final account = await DriftRewardRepository(database).load('owner-1');
      expect(account.balance, 0);
      expect(account.ownedItemIds, contains('weapon_cefr'));
    },
  );
}

SyncEntity _rewardEntity({
  required String id,
  required String idempotencyKey,
  required String transactionType,
  required int amount,
  String itemId = 'theme_ocean',
  String slot = 'theme',
  required DateTime occurredAt,
}) => SyncEntity(
  collection: SyncCollection.rewardTransactions,
  entityId: id,
  revision: 1,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: occurredAt,
  serverUpdatedAtUtc: occurredAt.add(const Duration(milliseconds: 1)),
  payload: <String, Object?>{
    'idempotencyKey': idempotencyKey,
    'transactionType': transactionType,
    'amount': amount,
    'itemId': itemId,
    'slot': slot,
    'catalogVersion': 1,
    'sourceEventId': null,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
  },
);

PullPage _page(SyncEntity entity) => PullPage(
  changes: [entity],
  nextCursor: SyncCursor(
    serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
    documentId: entity.entityId,
  ),
  hasMore: false,
);
