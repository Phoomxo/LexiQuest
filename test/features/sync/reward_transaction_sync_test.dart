import 'package:drift/drift.dart' show OrderingTerm, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_avatar_progression_eligibility.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/rewards/domain/avatar_progression_policy.dart';
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

    const quarantinedAvatarIds = <String>{
      'purchase-with-source',
      'timestamp-drift',
      'wrong-catalog-price',
    };
    for (final entity in cases) {
      final operation = syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(entity),
      );
      if (quarantinedAvatarIds.contains(entity.entityId)) {
        await operation;
        expect(
          await (database.select(
            database.syncConflicts,
          )..where((row) => row.entityId.equals(entity.entityId))).get(),
          hasLength(1),
          reason: entity.entityId,
        );
      } else {
        await expectLater(
          operation,
          throwsA(isA<InvalidSyncPayloadFailure>()),
          reason: entity.entityId,
        );
      }
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
    'outbound cloud cutover attests a grandfathered catalog-v1 row',
    () async {
      await _insertRewardOutbox(
        database,
        id: 'unsynced-legacy-purchase',
        idempotencyKey: 'unsynced-legacy-purchase',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV1Version,
        occurredAt: now,
      );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'legacy-outbound-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      final claims = await syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'legacy-outbound-lease',
        ownerGateToken: 'legacy-outbound-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );

      expect(claims, hasLength(1));
      final source = claims.single.mutation.payload['sourceEventId'];
      expect(source, startsWith('avatar-legacy:v1:c1:p:'));
      expect(
        await (database.select(database.rewardTransactions)
              ..where((row) => row.id.equals('unsynced-legacy-purchase')))
            .getSingle()
            .then((row) => row.sourceEventId),
        source,
      );
    },
  );

  test(
    'rules-first marker immediately recovers one raw v1 permission failure',
    () async {
      final rulesFirstStore = DriftSyncStore(
        database,
        avatarProgressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => now,
        ),
      );
      final item = RewardCatalog.byIdAtVersion(
        'theme_ocean',
        RewardCatalog.catalogV1Version,
      )!;
      final carriedSource = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: 'app-first-v1-purchase',
            idempotencyKey: 'app-first-v1-purchase',
            transactionType: 'purchase',
            amount: -item.price,
            itemId: item.id,
            catalogVersion: item.catalogVersion,
            occurredAtUtcMs: now.millisecondsSinceEpoch,
          )
          .sourceEventId;
      const v2IdempotencyKey = 'app-first-v2-purchase';
      final v2Item = RewardCatalog.byId('theme_ocean')!;
      final v2Source = const AvatarProgressionEligibilityContract()
          .issue(
            idempotencyKey: v2IdempotencyKey,
            item: v2Item,
            lifetimeXp: 200,
            occurredAtUtcMs: now.millisecondsSinceEpoch,
          )
          .sourceEventId;
      const exhaustedV2IdempotencyKey = 'exhausted-v2-purchase';
      final exhaustedV2Item = RewardCatalog.byId('wallpaper_focus')!;
      final exhaustedV2Source = const AvatarProgressionEligibilityContract()
          .issue(
            idempotencyKey: exhaustedV2IdempotencyKey,
            item: exhaustedV2Item,
            lifetimeXp: 200,
            occurredAtUtcMs: now.millisecondsSinceEpoch,
          )
          .sourceEventId;
      await _insertRewardOutbox(
        database,
        id: 'rules-first-v1-purchase',
        idempotencyKey: 'rules-first-v1-purchase',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'app-first-v1-purchase',
        idempotencyKey: 'app-first-v1-purchase',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        sourceEventId: carriedSource,
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'unrelated-permission-failure',
        idempotencyKey: 'unrelated-permission-failure',
        transactionType: 'coinGrant',
        amount: 1,
        catalogVersion: 0,
        sourceEventId: 'unrelated-permission-failure',
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'app-first-v2-purchase',
        idempotencyKey: v2IdempotencyKey,
        transactionType: 'purchase',
        amount: -v2Item.price,
        itemId: v2Item.id,
        catalogVersion: v2Item.catalogVersion,
        sourceEventId: v2Source,
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'exhausted-v2-purchase',
        idempotencyKey: exhaustedV2IdempotencyKey,
        transactionType: 'purchase',
        amount: -exhaustedV2Item.price,
        itemId: exhaustedV2Item.id,
        catalogVersion: exhaustedV2Item.catalogVersion,
        sourceEventId: exhaustedV2Source,
        occurredAt: now,
      );
      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'permanentFailure', "
        "attempt_count = 1, failure_code = 'permissionDenied'",
      );
      await database.customUpdate(
        "UPDATE outbox_operations SET attempt_count = 5 "
        "WHERE entity_id = 'exhausted-v2-purchase'",
      );
      final gate = DriftOwnerOperationGate(database);
      final recoveryAt = now;
      expect(
        await gate.tryAcquire(
          token: 'legacy-permission-recovery-gate',
          nowUtc: recoveryAt,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      final claims = await rulesFirstStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'legacy-permission-recovery-lease',
        ownerGateToken: 'legacy-permission-recovery-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: recoveryAt,
      );

      expect(claims, hasLength(1));
      expect(claims.single.mutation.entityId, 'rules-first-v1-purchase');
      expect(
        claims.single.mutation.payload['sourceEventId'],
        startsWith('avatar-legacy:v1:c1:p:'),
      );
      final attempted = await rulesFirstStore.beginAttempt(
        claim: claims.single,
        ownerGateToken: 'legacy-permission-recovery-gate',
        nowUtc: recoveryAt,
      );
      expect(attempted, isNotNull);
      expect(attempted!.attemptCount, 2);
      final retryAt = recoveryAt.add(const Duration(seconds: 1));
      expect(
        await rulesFirstStore.markRetry(
          operationId: attempted.localOperationId,
          leaseToken: attempted.leaseToken,
          ownerGateToken: 'legacy-permission-recovery-gate',
          nowUtc: recoveryAt,
          nextAttemptAtUtc: retryAt,
          failure: const OfflineSyncFailure(),
        ),
        isTrue,
      );
      await gate.release(token: 'legacy-permission-recovery-gate');
      expect(
        await gate.tryAcquire(
          token: 'legacy-permission-offline-retry-gate',
          nowUtc: retryAt,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final retried = await rulesFirstStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'legacy-permission-offline-retry-lease',
        ownerGateToken: 'legacy-permission-offline-retry-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: retryAt,
      );
      expect(retried, hasLength(1));
      expect(retried.single.mutation.entityId, 'rules-first-v1-purchase');
      final unrelated =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals(
                  'rewardTransaction:unrelated-permission-failure:1',
                ),
              ))
              .getSingle();
      expect(unrelated.state, 'permanentFailure');
      expect(unrelated.failureCode, 'permissionDenied');
      for (final entityId in [
        'app-first-v1-purchase',
        'app-first-v2-purchase',
      ]) {
        final appFirst = await (database.select(
          database.outboxOperations,
        )..where((row) => row.entityId.equals(entityId))).getSingle();
        expect(appFirst.state, 'permanentFailure', reason: entityId);
        expect(appFirst.attemptCount, 1, reason: entityId);
        expect(appFirst.failureCode, 'permissionDenied', reason: entityId);
      }
      final exhausted =
          await (database.select(database.outboxOperations)..where(
                (row) => row.operationId.equals(
                  'rewardTransaction:exhausted-v2-purchase:1',
                ),
              ))
              .getSingle();
      expect(exhausted.state, 'permanentFailure');
      expect(exhausted.attemptCount, 5);
      expect(exhausted.failureCode, 'permissionDenied');
    },
  );

  test(
    'late f32 launch carries pre-cutoff raw failure and quarantines late raw',
    () async {
      final cutover = AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs;
      final legacyAt = DateTime.fromMillisecondsSinceEpoch(
        cutover - 1000,
        isUtc: true,
      );
      final lateAt = DateTime.fromMillisecondsSinceEpoch(
        cutover + 1000,
        isUtc: true,
      );
      final lateStore = DriftSyncStore(
        database,
        avatarProgressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => lateAt,
        ),
      );
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(id: 'owner-2', createdAtUtcMs: 1),
          );
      await _insertRewardOutbox(
        database,
        id: 'late-upgrade-legitimate-v1',
        idempotencyKey: 'late-upgrade-legitimate-v1',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV1Version,
        occurredAt: legacyAt,
      );
      await _insertRewardOutbox(
        database,
        ownerId: 'owner-2',
        id: 'post-cutover-raw-v1',
        idempotencyKey: 'post-cutover-raw-v1',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV1Version,
        occurredAt: lateAt,
      );
      await database.customUpdate(
        "UPDATE outbox_operations SET state = 'permanentFailure', "
        "attempt_count = 1, failure_code = 'permissionDenied' "
        "WHERE entity_id IN "
        "('late-upgrade-legitimate-v1', 'post-cutover-raw-v1')",
      );

      final gate = DriftOwnerOperationGate(database);
      expect(
        await gate.tryAcquire(
          token: 'late-upgrade-legacy-gate',
          nowUtc: lateAt,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final legitimate = await lateStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'late-upgrade-legacy-lease',
        ownerGateToken: 'late-upgrade-legacy-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: lateAt,
      );
      expect(legitimate, hasLength(1));
      expect(legitimate.single.mutation.entityId, 'late-upgrade-legitimate-v1');
      expect(
        legitimate.single.mutation.payload['sourceEventId'],
        startsWith('avatar-legacy:v1:c1:p:'),
      );
      await gate.release(token: 'late-upgrade-legacy-gate');

      expect(
        await gate.tryAcquire(
          token: 'post-cutover-raw-gate',
          nowUtc: lateAt,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      expect(
        await lateStore.claimPending(
          ownerId: 'owner-2',
          firebaseUid: 'firebase-2',
          limit: 10,
          leaseToken: 'post-cutover-raw-lease',
          ownerGateToken: 'post-cutover-raw-gate',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: lateAt,
        ),
        isEmpty,
      );
      final quarantined =
          await (database.select(database.outboxOperations)
                ..where((row) => row.entityId.equals('post-cutover-raw-v1')))
              .getSingle();
      expect(quarantined.state, 'permanentFailure');
      expect(quarantined.failureCode, 'permissionDenied');
      expect(quarantined.attemptCount, 1);
    },
  );

  test(
    'avatar cutover mismatch quarantines rewards but not learning sync',
    () async {
      await DriftAvatarProgressionEligibility(
        database,
      ).establishCutover('owner-1');
      await _insertRewardOutbox(
        database,
        id: 'mismatched-avatar-purchase',
        idempotencyKey: 'mismatched-avatar-purchase',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV1Version,
        occurredAt: now,
      );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'category:category-1:1',
              ownerId: 'owner-1',
              entityType: SyncCollection.categories.entityType,
              entityId: 'category-1',
              operationKind: 'upsert',
              createdAtUtcMs: now
                  .add(const Duration(milliseconds: 1))
                  .millisecondsSinceEpoch,
            ),
          );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'avatar-quarantine-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      final claims = await syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'avatar-quarantine-lease',
        ownerGateToken: 'avatar-quarantine-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );

      expect(claims, hasLength(1));
      expect(claims.single.mutation.collection, SyncCollection.categories);
      final quarantined =
          await (database.select(database.outboxOperations)..where(
                (row) => row.entityId.equals('mismatched-avatar-purchase'),
              ))
              .getSingle();
      expect(quarantined.state, 'pending');
      expect(quarantined.failureCode, isNull);
    },
  );

  test(
    'invalid avatar outbox stays pending while coin and category claim',
    () async {
      await DriftAvatarProgressionEligibility(
        database,
      ).establishCutover('owner-1');
      await _insertRewardOutbox(
        database,
        id: 'tampered-v2-outbound',
        idempotencyKey: 'tampered-v2-outbound',
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV2Version,
        sourceEventId: 'avatar-xp:v1:p1:c2:l3:x200:${'0' * 64}',
        occurredAt: now,
      );
      await _insertRewardOutbox(
        database,
        id: 'tampered-v1-equip-outbound',
        idempotencyKey: 'tampered-v1-equip-outbound',
        transactionType: 'equip',
        amount: 0,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV1Version,
        sourceEventId: 'avatar-legacy:v1:c1:e:${'0' * 64}',
        occurredAt: now.add(const Duration(milliseconds: 1)),
      );
      await _insertRewardOutbox(
        database,
        id: 'safe-coin-during-avatar-quarantine',
        idempotencyKey: 'coin:safe-during-avatar-quarantine',
        transactionType: 'coinGrant',
        amount: 3,
        catalogVersion: 0,
        sourceEventId: 'safe-during-avatar-quarantine',
        occurredAt: now.add(const Duration(milliseconds: 2)),
      );
      await database
          .into(database.outboxOperations)
          .insert(
            OutboxOperationsCompanion.insert(
              operationId: 'category:category-1:avatar-quarantine',
              ownerId: 'owner-1',
              entityType: SyncCollection.categories.entityType,
              entityId: 'category-1',
              operationKind: 'upsert',
              createdAtUtcMs: now
                  .add(const Duration(milliseconds: 3))
                  .millisecondsSinceEpoch,
            ),
          );
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'invalid-avatar-outbox-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );

      final claims = await syncStore.claimPending(
        ownerId: 'owner-1',
        firebaseUid: 'firebase-1',
        limit: 10,
        leaseToken: 'invalid-avatar-outbox-lease',
        ownerGateToken: 'invalid-avatar-outbox-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );

      expect(claims.map((claim) => claim.mutation.collection).toSet(), {
        SyncCollection.rewardTransactions,
        SyncCollection.categories,
      });
      expect(
        claims
            .singleWhere(
              (claim) =>
                  claim.mutation.collection ==
                  SyncCollection.rewardTransactions,
            )
            .mutation
            .entityId,
        'safe-coin-during-avatar-quarantine',
      );
      for (final id in const [
        'tampered-v2-outbound',
        'tampered-v1-equip-outbound',
      ]) {
        final operation = await (database.select(
          database.outboxOperations,
        )..where((row) => row.entityId.equals(id))).getSingle();
        expect(operation.state, 'pending', reason: id);
        expect(operation.failureCode, isNull, reason: id);
      }
    },
  );

  test(
    'avatar quarantine persists self-contained v2 and coin authorities',
    () async {
      await DriftAvatarProgressionEligibility(
        database,
      ).establishCutover('owner-1');
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'local-avatar-cutover-mismatch',
              ownerId: 'owner-1',
              idempotencyKey: 'local-avatar-cutover-mismatch',
              transactionType: 'purchase',
              amount: -80,
              itemId: const Value('theme_ocean'),
              catalogVersion: RewardCatalog.catalogV1Version,
              occurredAtUtcMs: 2,
            ),
          );
      final purchaseAt = now.add(const Duration(milliseconds: 2));
      final item = RewardCatalog.byId('theme_ocean')!;
      final eligibility = const AvatarProgressionEligibilityContract().issue(
        idempotencyKey: 'cloud-avatar-during-quarantine',
        item: item,
        lifetimeXp: 200,
        occurredAtUtcMs: purchaseAt.millisecondsSinceEpoch,
      );
      final avatar = _rewardEntity(
        id: 'cloud-avatar-during-quarantine',
        idempotencyKey: 'cloud-avatar-during-quarantine',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        sourceEventId: eligibility.sourceEventId,
        occurredAt: purchaseAt,
      );
      final coin = _rewardEntity(
        id: 'cloud-coin-during-avatar-quarantine',
        idempotencyKey: 'coin:cloud-avatar-quarantine',
        transactionType: 'coinGrant',
        amount: 7,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'cloud-avatar-quarantine',
        occurredAt: now.add(const Duration(milliseconds: 3)),
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [avatar, coin],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
            documentId: coin.entityId,
          ),
          hasMore: false,
        ),
      );

      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(coin.entityId))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(avatar.entityId))).getSingleOrNull(),
        isNotNull,
      );
      expect(await database.select(database.syncConflicts).get(), isEmpty);
      expect(
        await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        ),
        SyncCursor(
          serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
          documentId: coin.entityId,
        ),
      );
    },
  );

  test(
    'tampered v2 avatar pull is quarantined while coin and cursor converge',
    () async {
      final item = RewardCatalog.byId('theme_ocean')!;
      final purchaseAt = now.add(const Duration(milliseconds: 10));
      final validSource = const AvatarProgressionEligibilityContract()
          .issue(
            idempotencyKey: 'tampered-v2-inbound',
            item: item,
            lifetimeXp: 200,
            occurredAtUtcMs: purchaseAt.millisecondsSinceEpoch,
          )
          .sourceEventId;
      final avatar = _rewardEntity(
        id: 'tampered-v2-inbound',
        idempotencyKey: 'tampered-v2-inbound',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        sourceEventId: _tamperedDigest(validSource),
        occurredAt: purchaseAt,
      );
      final coin = _rewardEntity(
        id: 'coin-after-tampered-v2',
        idempotencyKey: 'coin-after-tampered-v2',
        transactionType: 'coinGrant',
        amount: 7,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'coin-after-tampered-v2',
        occurredAt: purchaseAt.add(const Duration(milliseconds: 1)),
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [avatar, coin],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
            documentId: coin.entityId,
          ),
          hasMore: false,
        ),
      );

      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(avatar.entityId))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(coin.entityId))).getSingleOrNull(),
        isNotNull,
      );
      final conflict = await (database.select(
        database.syncConflicts,
      )..where((row) => row.entityId.equals(avatar.entityId))).getSingle();
      expect(conflict.resolutionPolicy, 'immutableEventId');
      expect(conflict.outcome, 'quarantined');
      expect(
        await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        ),
        SyncCursor(
          serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
          documentId: coin.entityId,
        ),
      );
    },
  );

  test(
    'tampered v1 carry pull is quarantined while coin and cursor converge',
    () async {
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
        isUtc: true,
      );
      final serverUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      final validSource = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: 'tampered-v1-carry-inbound',
            idempotencyKey: 'tampered-v1-carry-inbound',
            transactionType: 'purchase',
            amount: -80,
            itemId: 'theme_ocean',
            catalogVersion: RewardCatalog.catalogV1Version,
            occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
          )
          .sourceEventId;
      final avatar = _rewardEntity(
        id: 'tampered-v1-carry-inbound',
        idempotencyKey: 'tampered-v1-carry-inbound',
        transactionType: 'purchase',
        amount: -80,
        catalogVersion: RewardCatalog.catalogV1Version,
        sourceEventId: _tamperedDigest(validSource),
        occurredAt: occurredAt,
        serverUpdatedAt: serverUpdatedAt,
      );
      final coin = _rewardEntity(
        id: 'coin-after-tampered-v1-carry',
        idempotencyKey: 'coin-after-tampered-v1-carry',
        transactionType: 'coinGrant',
        amount: 7,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'coin-after-tampered-v1-carry',
        occurredAt: serverUpdatedAt.add(const Duration(milliseconds: 1)),
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [avatar, coin],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
            documentId: coin.entityId,
          ),
          hasMore: false,
        ),
      );

      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(avatar.entityId))).getSingleOrNull(),
        isNull,
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(coin.entityId))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        (await (database.select(database.syncConflicts)
                  ..where((row) => row.entityId.equals(avatar.entityId)))
                .getSingle())
            .outcome,
        'quarantined',
      );
      expect(
        await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        ),
        SyncCursor(
          serverUpdatedAtUtc: coin.serverUpdatedAtUtc,
          documentId: coin.entityId,
        ),
      );
    },
  );

  test(
    'avatar quarantine retries v1 carry and converges after marker repair',
    () async {
      await DriftAvatarProgressionEligibility(
        database,
      ).establishCutover('owner-1');
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'local-v1-marker-mismatch',
              ownerId: 'owner-1',
              idempotencyKey: 'local-v1-marker-mismatch',
              transactionType: 'purchase',
              amount: -80,
              itemId: const Value('theme_ocean'),
              catalogVersion: RewardCatalog.catalogV1Version,
              occurredAtUtcMs: 2,
            ),
          );
      const transactionId = 'cloud-v1-carry-after-repair';
      const idempotencyKey = 'cloud-v1-carry-after-repair';
      final occurredAtUtcMs =
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000;
      final sourceEventId = const AvatarLegacyCarryForwardContract()
          .issue(
            transactionId: transactionId,
            idempotencyKey: idempotencyKey,
            transactionType: 'purchase',
            amount: -80,
            itemId: 'theme_ocean',
            catalogVersion: RewardCatalog.catalogV1Version,
            occurredAtUtcMs: occurredAtUtcMs,
          )
          .sourceEventId;
      final carry = _rewardEntity(
        id: transactionId,
        idempotencyKey: idempotencyKey,
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        slot: 'theme',
        catalogVersion: RewardCatalog.catalogV1Version,
        sourceEventId: sourceEventId,
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          occurredAtUtcMs,
          isUtc: true,
        ),
        serverUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
          isUtc: true,
        ),
      );
      final coin = _rewardEntity(
        id: 'coin-after-deferred-v1',
        idempotencyKey: 'coin:after-deferred-v1',
        transactionType: 'coinGrant',
        amount: 5,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'after-deferred-v1',
        occurredAt: DateTime.fromMillisecondsSinceEpoch(
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 2000,
          isUtc: true,
        ),
      );
      final v2Item = RewardCatalog.byId('wallpaper_focus')!;
      final v2At = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 3000,
        isUtc: true,
      );
      final v2Eligibility = const AvatarProgressionEligibilityContract().issue(
        idempotencyKey: 'v2-after-deferred-v1',
        item: v2Item,
        lifetimeXp: 200,
        occurredAtUtcMs: v2At.millisecondsSinceEpoch,
      );
      final v2 = _rewardEntity(
        id: 'v2-after-deferred-v1',
        idempotencyKey: 'v2-after-deferred-v1',
        transactionType: 'purchase',
        amount: -v2Item.price,
        itemId: v2Item.id,
        slot: v2Item.slot,
        catalogVersion: v2Item.catalogVersion,
        sourceEventId: v2Eligibility.sourceEventId,
        occurredAt: v2At,
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [carry, coin, v2],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: v2.serverUpdatedAtUtc,
            documentId: v2.entityId,
          ),
          hasMore: false,
        ),
      );
      expect(
        await syncStore.readCheckpoint(
          'owner-1',
          SyncCollection.rewardTransactions,
        ),
        SyncCursor(
          serverUpdatedAtUtc: v2.serverUpdatedAtUtc,
          documentId: v2.entityId,
        ),
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.isIn([coin.entityId, v2.entityId]))).get(),
        hasLength(2),
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(carry.entityId))).getSingleOrNull(),
        isNull,
      );
      final deferred = await (database.select(
        database.syncConflicts,
      )..where((row) => row.entityId.equals(carry.entityId))).getSingle();
      expect(deferred.resolutionPolicy, 'avatarV1MarkerDeferred');
      expect(deferred.outcome, 'pending');

      await (database.delete(
        database.rewardTransactions,
      )..where((row) => row.id.equals('local-v1-marker-mismatch'))).go();
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: const [],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: v2.serverUpdatedAtUtc,
            documentId: v2.entityId,
          ),
          hasMore: false,
        ),
      );

      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(transactionId))).getSingleOrNull(),
        isNotNull,
      );
      expect(
        (await (database.select(
          database.syncConflicts,
        )..where((row) => row.id.equals(deferred.id))).getSingle()).outcome,
        'replayed',
      );
    },
  );

  test(
    'outbound canonical transaction payloads use one exact wire shape',
    () async {
      const purchaseKey = 'purchase-1';
      final purchaseAt = now.add(const Duration(milliseconds: 2));
      final purchaseItem = RewardCatalog.byId('theme_ocean')!;
      final purchaseEligibility = const AvatarProgressionEligibilityContract()
          .issue(
            idempotencyKey: purchaseKey,
            item: purchaseItem,
            lifetimeXp: 200,
            occurredAtUtcMs: purchaseAt.millisecondsSinceEpoch,
          );
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
        idempotencyKey: purchaseKey,
        transactionType: 'purchase',
        amount: -80,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV2Version,
        sourceEventId: purchaseEligibility.sourceEventId,
        occurredAt: purchaseAt,
      );
      await _insertRewardOutbox(
        database,
        id: 'outbound-equip',
        idempotencyKey: 'equip-1',
        transactionType: 'equip',
        amount: 0,
        itemId: 'theme_ocean',
        catalogVersion: RewardCatalog.catalogV2Version,
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

  test(
    'post-cutover v1 purchase at xp zero fails closed despite enough coins',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
      );
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      final grant = _rewardEntity(
        id: 'post-cutover-funding',
        idempotencyKey: 'post-cutover-funding',
        transactionType: 'coinGrant',
        amount: 200,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'post-cutover-funding',
        occurredAt: occurredAt.subtract(const Duration(milliseconds: 1)),
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(grant),
      );

      final bypass = _rewardEntity(
        id: 'post-cutover-v1-bypass',
        idempotencyKey: 'post-cutover-v1-bypass',
        transactionType: 'purchase',
        amount: -80,
        catalogVersion: RewardCatalog.legacyVersion,
        occurredAt: occurredAt,
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(bypass),
      );

      final account = await DriftRewardRepository(database).load('owner-1');
      expect(account.coinBalance, 200);
      expect(account.ownedItemIds, isNot(contains('theme_ocean')));
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.id.equals(bypass.entityId))).get(),
        isEmpty,
      );
      expect(
        await (database.select(
          database.syncConflicts,
        )..where((row) => row.entityId.equals(bypass.entityId))).get(),
        hasLength(1),
      );
    },
  );

  test(
    'pre-cutover v1 purchase is explicitly grandfathered at xp zero',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
      );
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
        isUtc: true,
      );
      final grant = _rewardEntity(
        id: 'legacy-funding',
        idempotencyKey: 'legacy-funding',
        transactionType: 'coinGrant',
        amount: 200,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'legacy-funding',
        occurredAt: occurredAt.subtract(const Duration(milliseconds: 1)),
      );
      final purchase = _rewardEntity(
        id: 'legacy-grandfathered-purchase',
        idempotencyKey: 'legacy-grandfathered-purchase',
        transactionType: 'purchase',
        amount: -80,
        catalogVersion: RewardCatalog.legacyVersion,
        occurredAt: occurredAt,
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [grant, purchase],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: purchase.serverUpdatedAtUtc,
            documentId: purchase.entityId,
          ),
          hasMore: false,
        ),
      );

      final account = await DriftRewardRepository(database).load('owner-1');
      expect(account.coinBalance, 120);
      expect(account.ownedItemIds, contains('theme_ocean'));
    },
  );

  test(
    'backdated v1 purchase first received by cloud after cutover fails closed',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
      );
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
        isUtc: true,
      );
      final lateServerReceipt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      final purchase = _rewardEntity(
        id: 'backdated-v1-after-cutover',
        idempotencyKey: 'backdated-v1-after-cutover',
        transactionType: 'purchase',
        amount: -80,
        catalogVersion: RewardCatalog.legacyVersion,
        occurredAt: occurredAt,
        serverUpdatedAt: lateServerReceipt,
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(purchase),
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
      expect(
        await (database.select(
          database.syncConflicts,
        )..where((row) => row.entityId.equals(purchase.entityId))).get(),
        hasLength(1),
      );
    },
  );

  test(
    'trusted pre-cutover cloud echo promotes an exact late-upgrader raw row',
    () async {
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 2000,
        isUtc: true,
      );
      final serverUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
        isUtc: true,
      );
      final lateNow = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      syncStore = DriftSyncStore(
        database,
        avatarProgressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => lateNow,
        ),
      );
      await database
          .into(database.rewardTransactions)
          .insert(
            RewardTransactionsCompanion.insert(
              id: 'late-upgrader-local-raw',
              ownerId: 'owner-1',
              idempotencyKey: 'late-upgrader-local-raw',
              transactionType: 'purchase',
              amount: -80,
              itemId: const Value('theme_ocean'),
              catalogVersion: RewardCatalog.catalogV1Version,
              occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
            ),
          );
      final cloudEcho = _rewardEntity(
        id: 'late-upgrader-local-raw',
        idempotencyKey: 'late-upgrader-local-raw',
        transactionType: 'purchase',
        amount: -80,
        catalogVersion: RewardCatalog.catalogV1Version,
        occurredAt: occurredAt,
        serverUpdatedAt: serverUpdatedAt,
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(cloudEcho),
      );

      final promoted = await (database.select(
        database.rewardTransactions,
      )..where((row) => row.id.equals(cloudEcho.entityId))).getSingle();
      expect(
        const AvatarLegacyCarryForwardContract().isValidPersistedTransaction(
          transactionId: promoted.id,
          idempotencyKey: promoted.idempotencyKey,
          transactionType: promoted.transactionType,
          amount: promoted.amount,
          itemId: promoted.itemId,
          catalogVersion: promoted.catalogVersion,
          sourceEventId: promoted.sourceEventId,
          occurredAtUtcMs: promoted.occurredAtUtcMs,
        ),
        isTrue,
      );
      final marker = (await database.select(database.eventsV2).get()).single;
      expect(
        marker.recordedAtUtc.millisecondsSinceEpoch,
        lateNow.millisecondsSinceEpoch,
      );
    },
  );

  test(
    'two trusted echoes durably promote a late-upgrader raw set before opening',
    () async {
      final lateNow = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      syncStore = DriftSyncStore(
        database,
        avatarProgressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => lateNow,
        ),
      );
      final echoes = <SyncEntity>[];
      for (var index = 0; index < 2; index += 1) {
        final id = 'late-upgrader-raw-$index';
        final occurredAt = DateTime.fromMillisecondsSinceEpoch(
          AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs -
              4000 +
              index * 1000,
          isUtc: true,
        );
        await database
            .into(database.rewardTransactions)
            .insert(
              RewardTransactionsCompanion.insert(
                id: id,
                ownerId: 'owner-1',
                idempotencyKey: id,
                transactionType: 'purchase',
                amount: -80,
                itemId: const Value('theme_ocean'),
                catalogVersion: RewardCatalog.catalogV1Version,
                occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
              ),
            );
        echoes.add(
          _rewardEntity(
            id: id,
            idempotencyKey: id,
            transactionType: 'purchase',
            amount: -80,
            catalogVersion: RewardCatalog.catalogV1Version,
            occurredAt: occurredAt,
            serverUpdatedAt: DateTime.fromMillisecondsSinceEpoch(
              AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs -
                  2000 +
                  index * 1000,
              isUtc: true,
            ),
          ),
        );
      }

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(echoes.first),
      );

      expect(
        (await (database.select(database.rewardTransactions)
                  ..where((row) => row.id.equals(echoes.first.entityId)))
                .getSingle())
            .sourceEventId,
        startsWith('avatar-legacy:v1:c1:p:'),
      );
      expect(await database.select(database.eventsV2).get(), isEmpty);

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(echoes.last),
      );

      final rows = await database.select(database.rewardTransactions).get();
      expect(rows, hasLength(2));
      expect(rows.every((row) => row.sourceEventId != null), isTrue);
      expect(await database.select(database.eventsV2).get(), hasLength(1));
      await DriftRewardProjectionRebuilder(
        database,
        progressionEligibility: DriftAvatarProgressionEligibility(
          database,
          nowUtc: () => lateNow,
        ),
      ).validate('owner-1');
    },
  );

  test(
    'post-cutover pull accepts exact legacy carry purchase and equip',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
      );
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
        isUtc: true,
      );
      final serverUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
        isUtc: true,
      );
      final item = RewardCatalog.byIdAtVersion(
        'theme_ocean',
        RewardCatalog.catalogV1Version,
      )!;
      const carry = AvatarLegacyCarryForwardContract();
      final purchaseSource = carry.issue(
        transactionId: 'carried-v1-purchase',
        idempotencyKey: 'carried-v1-purchase',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      );
      final equipAt = occurredAt.add(const Duration(milliseconds: 1));
      final equipSource = carry.issue(
        transactionId: 'carried-v1-equip',
        idempotencyKey: 'carried-v1-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        catalogVersion: item.catalogVersion,
        occurredAtUtcMs: equipAt.millisecondsSinceEpoch,
      );
      final grant = _rewardEntity(
        id: 'carried-v1-funding',
        idempotencyKey: 'carried-v1-funding',
        transactionType: 'coinGrant',
        amount: 200,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'carried-v1-funding',
        occurredAt: occurredAt.subtract(const Duration(milliseconds: 1)),
        serverUpdatedAt: serverUpdatedAt,
      );
      final purchase = _rewardEntity(
        id: 'carried-v1-purchase',
        idempotencyKey: 'carried-v1-purchase',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        sourceEventId: purchaseSource.sourceEventId,
        occurredAt: occurredAt,
        serverUpdatedAt: serverUpdatedAt.add(const Duration(milliseconds: 1)),
      );
      final equip = _rewardEntity(
        id: 'carried-v1-equip',
        idempotencyKey: 'carried-v1-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        sourceEventId: equipSource.sourceEventId,
        occurredAt: equipAt,
        serverUpdatedAt: serverUpdatedAt.add(const Duration(milliseconds: 2)),
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [grant, purchase, equip],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: equip.serverUpdatedAtUtc,
            documentId: equip.entityId,
          ),
          hasMore: false,
        ),
      );

      final account = await DriftRewardRepository(database).load('owner-1');
      expect(account.coinBalance, 120);
      expect(account.ownedItemIds, contains(item.id));
      expect(account.equippedBySlot[item.slot], item.id);
    },
  );

  test('raw and tampered v1 equip pulls after cutover fail closed', () async {
    final occurredAt = DateTime.fromMillisecondsSinceEpoch(
      AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs - 1000,
      isUtc: true,
    );
    final serverUpdatedAt = DateTime.fromMillisecondsSinceEpoch(
      AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 1000,
      isUtc: true,
    );
    final item = RewardCatalog.byIdAtVersion(
      'theme_ocean',
      RewardCatalog.catalogV1Version,
    )!;
    final validSource = const AvatarLegacyCarryForwardContract()
        .issue(
          transactionId: 'tampered-v1-equip',
          idempotencyKey: 'tampered-v1-equip',
          transactionType: 'equip',
          amount: 0,
          itemId: item.id,
          catalogVersion: item.catalogVersion,
          occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
        )
        .sourceEventId;
    final tamperedSource =
        '${validSource.substring(0, validSource.length - 1)}'
        '${validSource.endsWith('0') ? '1' : '0'}';
    final cases = <SyncEntity>[
      _rewardEntity(
        id: 'raw-v1-equip',
        idempotencyKey: 'raw-v1-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        occurredAt: occurredAt,
        serverUpdatedAt: serverUpdatedAt,
      ),
      _rewardEntity(
        id: 'tampered-v1-equip',
        idempotencyKey: 'tampered-v1-equip',
        transactionType: 'equip',
        amount: 0,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: item.catalogVersion,
        sourceEventId: tamperedSource,
        occurredAt: occurredAt,
        serverUpdatedAt: serverUpdatedAt,
      ),
    ];

    for (final entity in cases) {
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(entity),
      );
      expect(
        await (database.select(
          database.syncConflicts,
        )..where((row) => row.entityId.equals(entity.entityId))).get(),
        hasLength(1),
        reason: entity.entityId,
      );
    }
    expect(await database.select(database.rewardTransactions).get(), isEmpty);
  });

  test(
    'eligible v2 purchase converges from durable source-device xp evidence',
    () async {
      await database.customUpdate(
        "DELETE FROM points_ledger_entries WHERE owner_id = 'owner-1'",
      );
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 2000,
        isUtc: true,
      );
      const idempotencyKey = 'eligible-v2-purchase';
      final item = RewardCatalog.byId('theme_ocean')!;
      final eligibility = const AvatarProgressionEligibilityContract().issue(
        idempotencyKey: idempotencyKey,
        item: item,
        lifetimeXp: 200,
        occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      );
      final grant = _rewardEntity(
        id: 'v2-funding',
        idempotencyKey: 'v2-funding',
        transactionType: 'coinGrant',
        amount: 200,
        itemId: null,
        slot: null,
        catalogVersion: 0,
        sourceEventId: 'v2-funding',
        occurredAt: occurredAt.subtract(const Duration(milliseconds: 1)),
      );
      final purchase = _rewardEntity(
        id: 'eligible-v2-purchase',
        idempotencyKey: idempotencyKey,
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: RewardCatalog.version,
        sourceEventId: eligibility.sourceEventId,
        occurredAt: occurredAt,
      );

      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: PullPage(
          changes: [grant, purchase],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: purchase.serverUpdatedAtUtc,
            documentId: purchase.entityId,
          ),
          hasMore: false,
        ),
      );

      final account = await DriftRewardRepository(database).load('owner-1');
      expect(account.coinBalance, 120);
      expect(account.ownedItemIds, contains(item.id));
      expect(
        await (database.select(
          database.pointsLedgerEntries,
        )..where((row) => row.ownerId.equals('owner-1'))).get(),
        isEmpty,
      );
    },
  );

  test(
    'v2 threshold xp and same-source payload tampering fail closed',
    () async {
      final occurredAt = DateTime.fromMillisecondsSinceEpoch(
        AvatarProgressionEligibilityContract.legacyV1CutoverUtcMs + 3000,
        isUtc: true,
      );
      const idempotencyKey = 'tamper-evident-v2-purchase';
      final item = RewardCatalog.byId('theme_ocean')!;
      final issued = const AvatarProgressionEligibilityContract().issue(
        idempotencyKey: idempotencyKey,
        item: item,
        lifetimeXp: 200,
        occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
      );
      final tamperedSources = <String>[
        issued.sourceEventId.replaceFirst(':l3:', ':l2:'),
        issued.sourceEventId.replaceFirst(':x200:', ':x40:'),
      ];
      for (var index = 0; index < tamperedSources.length; index += 1) {
        final entity = _rewardEntity(
          id: 'tampered-v2-$index',
          idempotencyKey: idempotencyKey,
          transactionType: 'purchase',
          amount: -item.price,
          itemId: item.id,
          slot: item.slot,
          catalogVersion: RewardCatalog.version,
          sourceEventId: tamperedSources[index],
          occurredAt: occurredAt,
          serverUpdatedAt: occurredAt.add(Duration(milliseconds: index)),
        );
        await syncStore.applyPullPage(
          ownerId: 'owner-1',
          collection: SyncCollection.rewardTransactions,
          page: _page(entity),
        );
        expect(
          await (database.select(
            database.syncConflicts,
          )..where((row) => row.entityId.equals(entity.entityId))).get(),
          hasLength(1),
        );
      }

      final changedIdempotency = _rewardEntity(
        id: 'same-source-mismatched-idempotency',
        idempotencyKey: '$idempotencyKey-mismatch',
        transactionType: 'purchase',
        amount: -item.price,
        itemId: item.id,
        slot: item.slot,
        catalogVersion: RewardCatalog.version,
        sourceEventId: issued.sourceEventId,
        occurredAt: occurredAt,
        serverUpdatedAt: occurredAt.add(const Duration(milliseconds: 2)),
      );
      await syncStore.applyPullPage(
        ownerId: 'owner-1',
        collection: SyncCollection.rewardTransactions,
        page: _page(changedIdempotency),
      );
      expect(
        await (database.select(
          database.rewardTransactions,
        )..where((row) => row.transactionType.equals('purchase'))).get(),
        isEmpty,
      );
    },
  );

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

String _tamperedDigest(String source) =>
    '${source.substring(0, source.length - 1)}'
    '${source.endsWith('0') ? '1' : '0'}';

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
  String ownerId = 'owner-1',
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
          ownerId: ownerId,
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
          ownerId: ownerId,
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
