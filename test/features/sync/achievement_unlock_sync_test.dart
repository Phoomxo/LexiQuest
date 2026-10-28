import 'dart:io';

import 'package:drift/drift.dart' show Variable, driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_store.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _ownerId = 'owner-ach-test';

Future<void> _seedOwner(db.AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
    "VALUES ('$_ownerId', 'localGuest', 1722758400000)",
  );
}

SyncEntity _achievementEntity({
  String id = 'ach-unlock-1',
  int revision = 1,
  String achievementId = 'first-answer',
  int definitionVersion = 1,
  String sourceEventId = 'evt-src-1',
  int unlockedAtUtcMs = 1722758400000,
}) => SyncEntity(
  collection: SyncCollection.achievementUnlocks,
  entityId: id,
  revision: revision,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
    unlockedAtUtcMs,
    isUtc: true,
  ),
  serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
  payload: <String, Object?>{
    'achievementId': achievementId,
    'definitionVersion': definitionVersion,
    'sourceEventId': sourceEventId,
    'unlockedAtUtcMs': unlockedAtUtcMs,
  },
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late db.AppDatabase database;
  late DriftSyncStore store;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    await _seedOwner(database);
  });

  tearDown(() async => database.close());

  group('AchievementUnlock sync — D6.2', () {
    test('applyPullPage inserts new achievement unlock', () async {
      await store.applyPullPage(
        ownerId: _ownerId,
        collection: SyncCollection.achievementUnlocks,
        page: PullPage(
          changes: [_achievementEntity()],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
            documentId: 'ach-unlock-1',
          ),
          hasMore: false,
        ),
      );

      final rows = await (database.select(
        database.achievementUnlocks,
      )..where((r) => r.ownerId.equals(_ownerId))).get();
      expect(rows, hasLength(1));
      expect(rows.first.id, 'achievement:$_ownerId:first-answer:1');
      expect(rows.first.achievementId, 'first-answer');
      expect(rows.first.definitionVersion, 1);
    });

    test(
      'applyPullPage is idempotent — duplicate pull is insertOrIgnore',
      () async {
        // First pull.
        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [_achievementEntity()],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
              documentId: 'ach-unlock-1',
            ),
            hasMore: false,
          ),
        );
        // Second pull with same entity — must not duplicate.
        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [_achievementEntity()],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
              documentId: 'ach-unlock-1',
            ),
            hasMore: false,
          ),
        );

        final rows = await (database.select(
          database.achievementUnlocks,
        )..where((r) => r.ownerId.equals(_ownerId))).get();
        expect(
          rows,
          hasLength(1),
          reason: 'idempotent pull must not create duplicate unlock',
        );
      },
    );

    test(
      'legacy definition zero pull survives restart rebuild and canonical claim',
      () async {
        final previousWarningSetting =
            driftRuntimeOptions.dontWarnAboutMultipleDatabases;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-achievement-v0-',
        );
        final path = '${directory.path}${Platform.pathSeparator}legacy-v0.db';
        const ownerId = 'legacy-v0-owner';
        const firebaseUid = 'legacy-v0-firebase';
        final nowUtc = DateTime.utc(2026, 8, 29, 9);
        db.AppDatabase? device;
        try {
          device = db.AppDatabase(NativeDatabase(File(path)));
          await device.customSelect('SELECT 1').getSingle();
          await device.customInsert(
            'INSERT INTO local_owners '
            '(id, firebase_uid, account_state, created_at_utc_ms) '
            'VALUES (?, ?, ?, ?)',
            variables: const [
              Variable<String>(ownerId),
              Variable<String>(firebaseUid),
              Variable<String>('boundAccount'),
              Variable<int>(1),
            ],
          );
          final legacy = _achievementEntity(
            id: 'legacy-v0-physical-id',
            achievementId: 'legacy_zero',
            definitionVersion: 0,
            sourceEventId: 'legacy-v0-source',
            unlockedAtUtcMs: 9,
          );
          await DriftSyncStore(device).applyPullPage(
            ownerId: ownerId,
            collection: SyncCollection.achievementUnlocks,
            page: PullPage(
              changes: [legacy],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: legacy.serverUpdatedAtUtc,
                documentId: legacy.entityId,
              ),
              hasMore: false,
            ),
          );
          await device.close();
          device = null;

          device = db.AppDatabase(NativeDatabase(File(path)));
          await DriftLearningProjectionRebuilder(
            device,
          ).rebuildAchievements(ownerId);
          final unlock = await device
              .select(device.achievementUnlocks)
              .getSingle();
          expect(unlock.id, 'achievement:$ownerId:legacy_zero:0');
          expect(unlock.definitionVersion, 0);
          expect(unlock.sourceEventId, 'legacy-v0-source');
          final localOutbox = await device
              .select(device.outboxOperations)
              .getSingle();
          expect(localOutbox.entityId, unlock.id);
          expect(localOutbox.createdAtUtcMs, unlock.unlockedAtUtcMs);

          expect(
            await DriftOwnerOperationGate(device).tryAcquire(
              token: 'legacy-v0-gate',
              nowUtc: nowUtc,
              leaseDuration: const Duration(minutes: 10),
            ),
            isTrue,
          );
          final claims = await DriftSyncStore(device).claimPending(
            ownerId: ownerId,
            firebaseUid: firebaseUid,
            limit: 1,
            leaseToken: 'legacy-v0-lease',
            ownerGateToken: 'legacy-v0-gate',
            leaseDuration: const Duration(minutes: 5),
            nowUtc: nowUtc,
          );
          expect(claims, hasLength(1));
          final claim = await DriftSyncStore(device).beginAttempt(
            claim: claims.single,
            ownerGateToken: 'legacy-v0-gate',
            nowUtc: nowUtc,
          );
          expect(claim, isNotNull);
          expect(
            claim!.mutation.entityId,
            AchievementUnlockSyncPayloadContract.canonicalEntityId(
              achievementId: 'legacy_zero',
              definitionVersion: 0,
            ),
          );
          expect(
            claim.mutation.operationId,
            AchievementUnlockSyncPayloadContract.canonicalOperationId(
              achievementId: 'legacy_zero',
              definitionVersion: 0,
              sourceEventId: 'legacy-v0-source',
              unlockedAtUtcMs: 9,
            ),
          );
        } finally {
          await device?.close();
          await directory.delete(recursive: true);
          driftRuntimeOptions.dontWarnAboutMultipleDatabases =
              previousWarningSetting;
        }
      },
    );

    test('negative definition version pull fails closed', () async {
      final invalid = _achievementEntity(
        id: 'negative-version',
        achievementId: 'invalid_negative',
        definitionVersion: -1,
        sourceEventId: 'negative-source',
        unlockedAtUtcMs: 10,
      );

      await expectLater(
        store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [invalid],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: invalid.serverUpdatedAtUtc,
              documentId: invalid.entityId,
            ),
            hasMore: false,
          ),
        ),
        throwsA(isA<InvalidSyncPayloadFailure>()),
      );
      expect(await database.select(database.achievementUnlocks).get(), isEmpty);
      expect(await database.select(database.outboxOperations).get(), isEmpty);
    });

    test(
      'definition-version pulls retain audit rows but project one unlock',
      () async {
        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [_achievementEntity()],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
              documentId: 'ach-unlock-1',
            ),
            hasMore: false,
          ),
        );

        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [
              _achievementEntity(
                id: 'ach-unlock-v2',
                definitionVersion: 2,
                sourceEventId: 'evt-src-v2',
              ),
            ],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
              documentId: 'ach-unlock-v2',
            ),
            hasMore: false,
          ),
        );

        final rows = await (database.select(
          database.achievementUnlocks,
        )..where((row) => row.achievementId.equals('first-answer'))).get();
        expect(rows, hasLength(2));
        final progress = await DriftProgressQueries(
          database,
        ).load(ownerId: _ownerId, nowUtc: DateTime.utc(2026, 8, 4, 11));
        expect(progress.achievementCount, 1);
        expect(progress.achievements, hasLength(1));
        expect(progress.achievements.single.sourceEventId, 'evt-src-1');
      },
    );

    test(
      'two offline devices converge through one canonical cloud unlock after restart',
      () async {
        final previousWarningSetting =
            driftRuntimeOptions.dontWarnAboutMultipleDatabases;
        driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
        final directory = await Directory.systemTemp.createTemp(
          'lexiquest-achievement-convergence-',
        );
        final firstPath = '${directory.path}${Platform.pathSeparator}first.db';
        final secondPath =
            '${directory.path}${Platform.pathSeparator}second.db';
        const firebaseUid = 'firebase-achievement-account';
        const firstOwner = 'device-one-owner';
        const secondOwner = 'device-two-owner';
        final pushedAt = DateTime.utc(2026, 8, 28, 9);

        Future<db.AppDatabase> openDevice(
          String path,
          String ownerId, {
          required String sourceEventId,
          required int unlockedAtUtcMs,
        }) async {
          final device = db.AppDatabase(NativeDatabase(File(path)));
          await device.customSelect('SELECT 1').getSingle();
          await device.customInsert(
            'INSERT INTO local_owners '
            '(id, firebase_uid, account_state, created_at_utc_ms) '
            'VALUES (?, ?, ?, ?)',
            variables: [
              Variable<String>(ownerId),
              const Variable<String>(firebaseUid),
              const Variable<String>('boundAccount'),
              const Variable<int>(1),
            ],
          );
          final unlockId = 'achievement:$ownerId:first_answer:1';
          await device.customInsert(
            'INSERT INTO achievement_unlocks '
            '(id, owner_id, achievement_id, definition_version, '
            'source_event_id, unlocked_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
            variables: [
              Variable<String>(unlockId),
              Variable<String>(ownerId),
              const Variable<String>('first_answer'),
              const Variable<int>(1),
              Variable<String>(sourceEventId),
              Variable<int>(unlockedAtUtcMs),
            ],
          );
          await device.customInsert(
            'INSERT INTO outbox_operations '
            '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
            'created_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
            variables: [
              Variable<String>('achievementUnlock:$unlockId:1'),
              Variable<String>(ownerId),
              const Variable<String>('achievementUnlock'),
              Variable<String>(unlockId),
              const Variable<String>('upsert'),
              Variable<int>(unlockedAtUtcMs),
            ],
          );
          return device;
        }

        Future<ClaimedSyncOperation> claim(
          db.AppDatabase device,
          String ownerId,
          String gateToken,
          String leaseToken,
        ) async {
          expect(
            await DriftOwnerOperationGate(device).tryAcquire(
              token: gateToken,
              nowUtc: pushedAt,
              leaseDuration: const Duration(minutes: 10),
            ),
            isTrue,
          );
          final claims = await DriftSyncStore(device).claimPending(
            ownerId: ownerId,
            firebaseUid: firebaseUid,
            limit: 10,
            leaseToken: leaseToken,
            ownerGateToken: gateToken,
            leaseDuration: const Duration(minutes: 5),
            nowUtc: pushedAt,
          );
          expect(claims, hasLength(1));
          return claims.single;
        }

        Future<void> pullWinner(
          db.AppDatabase device,
          String ownerId,
          SyncEntity cloudWinner,
        ) => DriftSyncStore(device).applyPullPage(
          ownerId: ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [cloudWinner],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: cloudWinner.serverUpdatedAtUtc,
              documentId: cloudWinner.entityId,
            ),
            hasMore: false,
          ),
        );

        db.AppDatabase? first;
        db.AppDatabase? second;
        try {
          first = await openDevice(
            firstPath,
            firstOwner,
            sourceEventId: 'device-one-evidence',
            unlockedAtUtcMs: 100,
          );
          second = await openDevice(
            secondPath,
            secondOwner,
            sourceEventId: 'device-two-evidence',
            unlockedAtUtcMs: 200,
          );
          final firstLease = await claim(
            first,
            firstOwner,
            'first-gate',
            'first-lease',
          );
          final secondLease = await claim(
            second,
            secondOwner,
            'second-gate',
            'second-lease',
          );
          final firstClaim = await DriftSyncStore(first).beginAttempt(
            claim: firstLease,
            ownerGateToken: 'first-gate',
            nowUtc: pushedAt,
          );
          final secondClaim = await DriftSyncStore(second).beginAttempt(
            claim: secondLease,
            ownerGateToken: 'second-gate',
            nowUtc: pushedAt,
          );
          expect(firstClaim, isNotNull);
          expect(secondClaim, isNotNull);
          final exactFirstClaim = firstClaim!;
          final exactSecondClaim = secondClaim!;

          expect(
            exactFirstClaim.mutation.entityId,
            exactSecondClaim.mutation.entityId,
          );
          expect(
            exactFirstClaim.mutation.entityId,
            AchievementUnlockSyncPayloadContract.canonicalEntityId(
              achievementId: 'first_answer',
              definitionVersion: 1,
            ),
          );
          expect(
            exactFirstClaim.mutation.operationId,
            isNot(exactSecondClaim.mutation.operationId),
            reason: 'different immutable evidence must not share an ack key',
          );

          final cloudWinner = SyncEntity(
            collection: SyncCollection.achievementUnlocks,
            entityId: exactFirstClaim.mutation.entityId,
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: exactFirstClaim.mutation.clientUpdatedAtUtc,
            serverUpdatedAtUtc: pushedAt.add(const Duration(seconds: 1)),
            payload: exactFirstClaim.mutation.payload,
          );
          expect(
            await DriftSyncStore(first).acknowledge(
              operationId: exactFirstClaim.localOperationId,
              leaseToken: exactFirstClaim.leaseToken,
              ownerGateToken: 'first-gate',
              nowUtc: pushedAt,
              acknowledgement: PushAcknowledged(
                operationId: exactFirstClaim.localOperationId,
                resultingRevision: 1,
                acknowledgedAtUtc: pushedAt,
              ),
            ),
            isTrue,
          );
          expect(
            await DriftSyncStore(second).resolvePushConflict(
              claim: exactSecondClaim,
              ownerGateToken: 'second-gate',
              cloudEntity: cloudWinner,
              resolvedAtUtc: pushedAt.add(const Duration(seconds: 2)),
            ),
            isTrue,
          );

          await pullWinner(first, firstOwner, cloudWinner);
          await pullWinner(second, secondOwner, cloudWinner);
          await first.close();
          first = null;
          await second.close();
          second = null;

          first = db.AppDatabase(NativeDatabase(File(firstPath)));
          second = db.AppDatabase(NativeDatabase(File(secondPath)));
          final firstUnlock = await first
              .select(first.achievementUnlocks)
              .getSingle();
          final secondUnlock = await second
              .select(second.achievementUnlocks)
              .getSingle();
          expect(firstUnlock.sourceEventId, 'device-one-evidence');
          expect(secondUnlock.sourceEventId, firstUnlock.sourceEventId);
          expect(secondUnlock.unlockedAtUtcMs, firstUnlock.unlockedAtUtcMs);
          expect(firstUnlock.id, contains(firstOwner));
          expect(secondUnlock.id, contains(secondOwner));

          final firstOutbox = await first
              .select(first.outboxOperations)
              .getSingle();
          final secondOutbox = await second
              .select(second.outboxOperations)
              .getSingle();
          expect(firstOutbox.state, 'acknowledged');
          expect(secondOutbox.state, 'conflictResolved');
          expect(secondOutbox.failureCode, 'canonicalAchievementCloudWins');
          await DriftLearningProjectionRebuilder(
            second,
          ).rebuildAchievements(secondOwner);
          final rebuiltOutbox = await second
              .select(second.outboxOperations)
              .getSingle();
          expect(rebuiltOutbox.createdAtUtcMs, firstUnlock.unlockedAtUtcMs);

          final corruptReplay = SyncEntity(
            collection: SyncCollection.achievementUnlocks,
            entityId: cloudWinner.entityId,
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
              300,
              isUtc: true,
            ),
            serverUpdatedAtUtc: cloudWinner.serverUpdatedAtUtc.add(
              const Duration(seconds: 1),
            ),
            payload: const <String, Object?>{
              'achievementId': 'first_answer',
              'definitionVersion': 1,
              'sourceEventId': 'corrupt-replayed-cloud-evidence',
              'unlockedAtUtcMs': 300,
            },
          );
          await pullWinner(second, secondOwner, corruptReplay);
          final protected = await second
              .select(second.achievementUnlocks)
              .getSingle();
          expect(protected.sourceEventId, firstUnlock.sourceEventId);
          expect(protected.unlockedAtUtcMs, firstUnlock.unlockedAtUtcMs);
          expect(await second.select(second.syncConflicts).get(), hasLength(2));
        } finally {
          await first?.close();
          await second?.close();
          await directory.delete(recursive: true);
          driftRuntimeOptions.dontWarnAboutMultipleDatabases =
              previousWarningSetting;
        }
      },
    );

    test(
      'canonical pull never rewrites an already acknowledged durable unlock',
      () async {
        const localId = 'legacy-acknowledged-unlock';
        await database.customInsert(
          'INSERT INTO achievement_unlocks '
          '(id, owner_id, achievement_id, definition_version, '
          'source_event_id, unlocked_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?)',
          variables: const [
            Variable<String>(localId),
            Variable<String>(_ownerId),
            Variable<String>('first-answer'),
            Variable<int>(1),
            Variable<String>('acknowledged-local-source'),
            Variable<int>(100),
          ],
        );
        await database.customInsert(
          'INSERT INTO outbox_operations '
          '(operation_id, owner_id, entity_type, entity_id, operation_kind, '
          'state, acknowledged_at_utc_ms, created_at_utc_ms) '
          'VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
          variables: const [
            Variable<String>('legacy-acknowledged-operation'),
            Variable<String>(_ownerId),
            Variable<String>('achievementUnlock'),
            Variable<String>(localId),
            Variable<String>('upsert'),
            Variable<String>('acknowledged'),
            Variable<int>(101),
            Variable<int>(100),
          ],
        );
        final canonicalId =
            AchievementUnlockSyncPayloadContract.canonicalEntityId(
              achievementId: 'first-answer',
              definitionVersion: 1,
            );
        final cloud = _achievementEntity(
          id: canonicalId,
          sourceEventId: 'competing-cloud-source',
          unlockedAtUtcMs: 200,
        );

        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [cloud],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: cloud.serverUpdatedAtUtc,
              documentId: cloud.entityId,
            ),
            hasMore: false,
          ),
        );

        final unlock = await database
            .select(database.achievementUnlocks)
            .getSingle();
        expect(unlock.id, localId);
        expect(unlock.sourceEventId, 'acknowledged-local-source');
        expect(unlock.unlockedAtUtcMs, 100);
        final operation = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(operation.state, 'acknowledged');
        final conflict = await database
            .select(database.syncConflicts)
            .getSingle();
        expect(conflict.outcome, 'quarantined');
        expect(conflict.resolutionPolicy, 'immutableEventId');
      },
    );

    test('achievement unlock wire name is correct', () {
      expect(SyncCollection.achievementUnlocks.wireName, 'achievement_unlocks');
      expect(SyncCollection.achievementUnlocks.entityType, 'achievementUnlock');
    });

    test('srsStates wire name is correct', () {
      expect(SyncCollection.srsStates.wireName, 'srs_states');
      expect(SyncCollection.srsStates.entityType, 'srsState');
    });
  });
}
