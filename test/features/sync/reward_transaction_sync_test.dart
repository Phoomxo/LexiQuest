import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/domain/reward_models.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
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

  test('local reward outbox reconstructs immutable catalog evidence', () async {
    await DriftRewardRepository(database).purchase(
      ownerId: 'owner-1',
      item: RewardCatalog.byId('theme_ocean')!,
      idempotencyKey: 'tap-1',
      transactionId: 'reward-local-1',
      occurredAtUtc: now,
    );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'reward-claim-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );

    final claims = await syncStore.claimPending(
      ownerId: 'owner-1',
      firebaseUid: 'firebase-1',
      limit: 10,
      leaseToken: 'lease-1',
      ownerGateToken: 'reward-claim-gate',
      leaseDuration: const Duration(minutes: 5),
      nowUtc: now,
    );
    final claim = claims.singleWhere(
      (candidate) =>
          candidate.mutation.payload['transactionType'] == 'purchase',
    );

    expect(claim.mutation.collection, SyncCollection.rewardTransactions);
    expect(claim.mutation.baseRevision, 0);
    expect(claim.mutation.localRevision, 1);
    expect(claim.mutation.payload['transactionType'], 'purchase');
    expect(claim.mutation.payload['amount'], -80);
    expect(claim.mutation.payload['slot'], 'theme');
  });

  test(
    'sync accepts both canonical earning shapes without mutating Points',
    () async {
      await database.customInsert(
        "INSERT INTO points_ledger_entries "
        "(id, owner_id, idempotency_key, entry_type, amount, "
        "source_event_id, occurred_at_utc_ms) VALUES "
        "('legacy-purchase-audit', 'owner-1', 'legacy-purchase-audit', "
        "'rewardPurchase', -80, 'old-purchase', 2)",
      );
      final pointsBefore = await _pointEvidence(database);
      final backfill = _rewardEntity(
        id: 'reward-backfill',
        idempotencyKey: 'legacy-earning:learning-points',
        transactionType: 'legacyEarningBackfill',
        amount: 200,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'learning-points',
        occurredAt: now,
      );
      final grant = _rewardEntity(
        id: 'reward-grant',
        idempotencyKey: 'coin:event-1',
        transactionType: 'coinGrant',
        amount: 10,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'event-1',
        occurredAt: now.add(const Duration(milliseconds: 1)),
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [backfill, grant],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: grant.serverUpdatedAtUtc,
            documentId: grant.entityId,
          ),
          hasMore: false,
        ),
      );

      final transactions =
          await (database.select(database.rewardTransactions)..where(
                (row) => row.id.isIn(['reward-backfill', 'reward-grant']),
              ))
              .get();
      expect(transactions.map((row) => row.transactionType).toSet(), {
        'legacyEarningBackfill',
        'coinGrant',
      });
      expect(transactions.every((row) => row.itemId == null), isTrue);
      expect(await _pointEvidence(database), pointsBefore);
    },
  );

  test('sync rejects non-canonical payloads and timestamp drift', () async {
    final cases = <SyncEntity>[
      _rewardEntity(
        id: 'missing-explicit-item',
        idempotencyKey: 'invalid-1',
        transactionType: 'coinGrant',
        amount: 1,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'event-invalid-1',
        occurredAt: now,
        omitPayloadKeys: {'itemId'},
      ),
      _rewardEntity(
        id: 'extra-key',
        idempotencyKey: 'invalid-2',
        transactionType: 'coinGrant',
        amount: 1,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'event-invalid-2',
        occurredAt: now.add(const Duration(milliseconds: 2)),
        extraPayload: const {'unexpected': true},
      ),
      _rewardEntity(
        id: 'missing-grant-source',
        idempotencyKey: 'invalid-3',
        transactionType: 'coinGrant',
        amount: 1,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: null,
        occurredAt: now.add(const Duration(milliseconds: 3)),
      ),
      _rewardEntity(
        id: 'purchase-with-source',
        idempotencyKey: 'invalid-4',
        transactionType: 'purchase',
        amount: -80,
        sourceEventId: 'must-be-null',
        occurredAt: now.add(const Duration(milliseconds: 4)),
      ),
      _rewardEntity(
        id: 'timestamp-drift',
        idempotencyKey: 'invalid-5',
        transactionType: 'equip',
        amount: 0,
        occurredAt: now.add(const Duration(milliseconds: 5)),
        clientUpdatedAt: now.add(const Duration(milliseconds: 6)),
      ),
      _rewardEntity(
        id: 'unknown-type',
        idempotencyKey: 'invalid-6',
        transactionType: 'refund',
        amount: 80,
        occurredAt: now.add(const Duration(milliseconds: 7)),
      ),
      _rewardEntity(
        id: 'non-canonical-idempotency',
        idempotencyKey: ' invalid-7',
        transactionType: 'coinGrant',
        amount: 1,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'event-invalid-7',
        occurredAt: now.add(const Duration(milliseconds: 8)),
      ),
      _rewardEntity(
        id: 'wrong-catalog-price',
        idempotencyKey: 'invalid-8',
        transactionType: 'purchase',
        amount: -79,
        occurredAt: now.add(const Duration(milliseconds: 9)),
      ),
    ];

    for (final entity in cases) {
      await expectLater(
        syncStore.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.rewardTransactions,
          page: _page(entity),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
        reason: entity.entityId,
      );
    }
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
  });

  test('outbound reward evidence is validated before it is claimed', () async {
    await database
        .into(database.rewardTransactions)
        .insert(
          RewardTransactionsCompanion.insert(
            id: 'invalid-outbound',
            ownerId: 'owner-1',
            idempotencyKey: 'invalid-outbound',
            transactionType: 'coinGrant',
            amount: 10,
            itemId: const Value('theme_ocean'),
            catalogVersion: 1,
            sourceEventId: const Value('event-outbound'),
            occurredAtUtcMs: now.millisecondsSinceEpoch,
          ),
        );
    await database
        .into(database.outboxOperations)
        .insert(
          OutboxOperationsCompanion.insert(
            operationId: 'rewardTransaction:invalid-outbound:1',
            ownerId: 'owner-1',
            entityType: 'rewardTransaction',
            entityId: 'invalid-outbound',
            operationKind: 'upsert',
            createdAtUtcMs: now.millisecondsSinceEpoch,
          ),
        );
    expect(
      await DriftOwnerOperationGate(database).tryAcquire(
        token: 'invalid-outbound-gate',
        nowUtc: now,
        leaseDuration: const Duration(minutes: 10),
      ),
      isTrue,
    );

    await expectLater(
      syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'invalid-outbound-lease',
        ownerGateToken: 'invalid-outbound-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      ),
      throwsA(isA<InvalidSyncPayloadFailure>()),
    );
  });

  test(
    'outbound canonical transaction payloads use one exact wire shape',
    () async {
      await _insertRewardOutbox(
        database,
        id: 'outbound-backfill',
        idempotencyKey: 'legacy:points-1',
        transactionType: 'legacyEarningBackfill',
        amount: 30,
        catalogVersion: 0,
        sourceEventId: 'points-1',
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'outbound-grant',
        idempotencyKey: 'coin:event-2',
        transactionType: 'coinGrant',
        amount: 10,
        catalogVersion: 0,
        sourceEventId: 'event-2',
        occurredAt: now.add(const Duration(milliseconds: 1)),
      );
      await _insertRewardOutbox(
        database,
        id: 'outbound-purchase',
        idempotencyKey: 'purchase-1',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: 1,
        occurredAt: now.add(const Duration(milliseconds: 2)),
      );
      await _insertRewardOutbox(
        database,
        id: 'outbound-equip',
        idempotencyKey: 'equip-1',
        transactionType: 'equip',
        amount: 0,
        itemId: 'theme_ocean',
        catalogVersion: 1,
        occurredAt: now.add(const Duration(milliseconds: 3)),
      );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'canonical-outbound-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      final claims = await syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'canonical-outbound-lease',
        ownerGateToken: 'canonical-outbound-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );

      expect(claims, hasLength(4));
      for (final claim in claims) {
        expect(claim.mutation.payload.keys.toSet(), _rewardPayloadKeys);
        expect(
          claim.mutation.clientUpdatedAtUtc.millisecondsSinceEpoch,
          claim.mutation.payload['occurredAtUtcMs'],
        );
      }
      final byType = {
        for (final claim in claims)
          claim.mutation.payload['transactionType']! as String:
              claim.mutation.payload,
      };
      expect(byType.keys.toSet(), {
        'legacyEarningBackfill',
        'coinGrant',
        'purchase',
        'equip',
      });
      expect(byType['legacyEarningBackfill']!['itemId'], isNull);
      expect(byType['legacyEarningBackfill']!['slot'], isNull);
      expect(byType['coinGrant']!['itemId'], isNull);
      expect(byType['coinGrant']!['slot'], isNull);
      expect(byType['purchase']!['slot'], 'theme');
      expect(byType['equip']!['slot'], 'theme');
    },
  );

  test('same earning source cannot be minted through a second type', () async {
    final grant = _rewardEntity(
      id: 'source-authority-grant',
      idempotencyKey: 'coin:shared-source',
      transactionType: 'coinGrant',
      amount: 15,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: 'shared-source',
      occurredAt: now,
    );
    final backfill = _rewardEntity(
      id: 'source-authority-backfill',
      idempotencyKey: 'legacy:shared-source',
      transactionType: 'legacyEarningBackfill',
      amount: 15,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: 'shared-source',
      occurredAt: now.add(const Duration(milliseconds: 2)),
    );

    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: _page(grant),
    );
    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: _page(backfill),
    );

    final rows = await database.select(database.rewardTransactions).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, grant.entityId);
    expect(await database.select(database.syncConflicts).get(), hasLength(1));
  });

  test(
    'exact replay is idempotent and same-id mutation records conflict',
    () async {
      final original = _rewardEntity(
        id: 'reward-replay',
        idempotencyKey: 'remote-replay',
        transactionType: 'coinGrant',
        amount: 12,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'event-replay',
        occurredAt: now,
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(original),
      );
      final replay = _rewardEntity(
        id: original.entityId,
        idempotencyKey: original.payload['idempotencyKey']! as String,
        transactionType: 'coinGrant',
        amount: 12,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: original.payload['sourceEventId']! as String,
        occurredAt: original.clientUpdatedAtUtc,
        serverUpdatedAt: original.serverUpdatedAtUtc.add(
          const Duration(milliseconds: 1),
        ),
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(replay),
      );
      expect(
        await database.select(database.rewardTransactions).get(),
        hasLength(1),
      );
      expect(await database.select(database.syncConflicts).get(), isEmpty);

      final mutation = _rewardEntity(
        id: original.entityId,
        idempotencyKey: original.payload['idempotencyKey']! as String,
        transactionType: 'coinGrant',
        amount: 13,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: original.payload['sourceEventId']! as String,
        occurredAt: original.clientUpdatedAtUtc,
        serverUpdatedAt: replay.serverUpdatedAtUtc.add(
          const Duration(milliseconds: 1),
        ),
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(mutation),
      );

      expect(
        (await database.select(database.rewardTransactions).get())
            .single
            .amount,
        12,
      );
      expect(await database.select(database.syncConflicts).get(), hasLength(1));
    },
  );

  test('pulled purchase and equipment rebuild durable ownership', () async {
    await database.customUpdate(
      "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
    );
    await syncStore.applyPullPage(
      ownerId: 'owner-1',
      collection: SyncCollection.rewardTransactions,
      page: _page(
        _rewardEntity(
          id: 'reward-funding-grant',
          idempotencyKey: 'coin:funding-grant',
          transactionType: 'coinGrant',
          amount: 200,
          itemId: null,
          slot: null,
          catalogVersion: 0,
          sourceEventId: 'funding-grant',
          occurredAt: now.subtract(const Duration(seconds: 1)),
        ),
      ),
    );
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
    await database.customUpdate(
      "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
    );
    final grant = _rewardEntity(
      id: 'reward-grant-before-concurrent',
      idempotencyKey: 'coin:grant-before-concurrent',
      transactionType: 'coinGrant',
      amount: 200,
      itemId: null,
      slot: null,
      catalogVersion: 0,
      sourceEventId: 'grant-before-concurrent',
      occurredAt: now.subtract(const Duration(seconds: 1)),
    );
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
        changes: [grant, first, second],
        nextCursor: SyncCursor(
          serverUpdatedAtUtc: second.serverUpdatedAtUtc,
          documentId: second.entityId,
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
      )..where((row) => row.transactionType.equals('purchase'))).get(),
      hasLength(2),
    );
  });

  test(
    'later canonical coin grant activates an earlier accepted purchase',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
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

      final grant = _rewardEntity(
        id: 'reward-grant-after-purchase',
        idempotencyKey: 'coin:grant-after-purchase',
        transactionType: 'coinGrant',
        amount: 120,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'grant-after-purchase',
        occurredAt: now.add(const Duration(seconds: 1)),
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(grant),
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
  String? itemId = 'theme_ocean',
  String? slot = 'theme',
  int catalogVersion = 1,
  String? sourceEventId,
  required DateTime occurredAt,
  DateTime? clientUpdatedAt,
  DateTime? serverUpdatedAt,
  Map<String, Object?> extraPayload = const {},
  Set<String> omitPayloadKeys = const {},
}) {
  final payload = <String, Object?>{
    'idempotencyKey': idempotencyKey,
    'transactionType': transactionType,
    'amount': amount,
    'itemId': itemId,
    'slot': slot,
    'catalogVersion': catalogVersion,
    'sourceEventId': sourceEventId,
    'occurredAtUtcMs': occurredAt.millisecondsSinceEpoch,
    ...extraPayload,
  };
  for (final key in omitPayloadKeys) {
    payload.remove(key);
  }
  return SyncEntity(
    collection: SyncCollection.rewardTransactions,
    entityId: id,
    revision: 1,
    isDeleted: false,
    payloadVersion: 1,
    clientUpdatedAtUtc: clientUpdatedAt ?? occurredAt,
    serverUpdatedAtUtc:
        serverUpdatedAt ?? occurredAt.add(const Duration(milliseconds: 1)),
    payload: payload,
  );
}

Future<List<Map<String, Object?>>> _pointEvidence(AppDatabase database) async {
  final rows = await (database.select(
    database.pointsLedgerEntries,
  )..orderBy([(row) => OrderingTerm.asc(row.id)])).get();
  return rows
      .map(
        (row) => <String, Object?>{
          'id': row.id,
          'idempotencyKey': row.idempotencyKey,
          'entryType': row.entryType,
          'amount': row.amount,
          'sourceEventId': row.sourceEventId,
          'occurredAtUtcMs': row.occurredAtUtcMs,
        },
      )
      .toList(growable: false);
}

const Set<String> _rewardPayloadKeys = <String>{
  'idempotencyKey',
  'transactionType',
  'amount',
  'itemId',
  'slot',
  'catalogVersion',
  'sourceEventId',
  'occurredAtUtcMs',
};

Future<void> _insertRewardOutbox(
  AppDatabase database, {
  required String id,
  required String idempotencyKey,
  required String transactionType,
  required int amount,
  String? itemId,
  required int catalogVersion,
  String? sourceEventId,
  required DateTime occurredAt,
}) async {
  await database
      .into(database.rewardTransactions)
      .insert(
        RewardTransactionsCompanion.insert(
          id: id,
          ownerId: 'owner-1',
          idempotencyKey: idempotencyKey,
          transactionType: transactionType,
          amount: amount,
          itemId: Value(itemId),
          catalogVersion: catalogVersion,
          sourceEventId: Value(sourceEventId),
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
      );
  await database
      .into(database.outboxOperations)
      .insert(
        OutboxOperationsCompanion.insert(
          operationId: 'rewardTransaction:$id:1',
          ownerId: 'owner-1',
          entityType: 'rewardTransaction',
          entityId: id,
          operationKind: 'upsert',
          createdAtUtcMs: occurredAt.millisecondsSinceEpoch,
        ),
      );
}

PullPage _page(SyncEntity entity) => PullPage(
  changes: [entity],
  nextCursor: SyncCursor(
    serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
    documentId: entity.entityId,
  ),
  hasMore: false,
);
