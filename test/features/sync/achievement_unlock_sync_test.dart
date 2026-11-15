import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_failure.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_projection_rebuilder.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _ownerId = 'owner-ach-test';

Future<void> _seedOwner(db.AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
    "VALUES ('$_ownerId', 'localGuest', 1722758400000)",
  );
}

SyncEntity _achievementEntity({String id = 'ach-unlock-1', int revision = 1}) =>
    SyncEntity(
      collection: SyncCollection.achievementUnlocks,
      entityId: id,
      revision: revision,
      isDeleted: false,
      payloadVersion: 1,
      clientUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
      serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
      payload: const <String, Object?>{
        'achievementId': 'first-answer',
        'definitionVersion': 1,
        'sourceEventId': 'evt-src-1',
        'unlockedAtUtcMs': 1722758400000,
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
    test(
      'same logical cloud conflict is independently recorded for each owner',
      () async {
        await database.customInsert(
          "INSERT INTO local_owners(id,account_state,created_at_utc_ms,is_active) VALUES ('second-owner','localGuest',1,0)",
        );
        await database.customInsert(
          "INSERT INTO achievement_unlocks VALUES ('first-local','$_ownerId','first_answer',1,'first-source',11)",
        );
        await database.customInsert(
          "INSERT INTO achievement_unlocks VALUES ('second-local','second-owner','first_answer',1,'second-source',22)",
        );
        final entity = SyncEntity(
          collection: SyncCollection.achievementUnlocks,
          entityId: 'same-opaque-cloud-id',
          revision: 1,
          isDeleted: false,
          payloadVersion: 1,
          clientUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10),
          serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
          payload: const {
            'achievementId': 'first_answer',
            'definitionVersion': 1,
            'sourceEventId': 'cloud-source',
            'unlockedAtUtcMs': 33,
          },
        );
        Future<void> pull(String ownerId) => store.applyPullPage(
          ownerId: ownerId,
          collection: SyncCollection.achievementUnlocks,
          page: PullPage(
            changes: [entity],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
              documentId: entity.entityId,
            ),
            hasMore: false,
          ),
        );
        for (final owner in [_ownerId, 'second-owner']) {
          await pull(owner);
          await pull(owner);
        }
        final rows = await database.select(database.achievementUnlocks).get();
        expect(rows.map((r) => r.id).toSet(), {'first-local', 'second-local'});
        final conflicts = await database.select(database.syncConflicts).get();
        expect(conflicts, hasLength(2));
        for (final (owner, source, time) in [
          (_ownerId, 'first-source', 11),
          ('second-owner', 'second-source', 22),
        ]) {
          final conflict = conflicts.singleWhere((row) => row.ownerId == owner);
          expect(
            (conflict.entityType, conflict.entityId, conflict.outcome),
            ('achievementUnlock', entity.entityId, 'quarantined'),
          );
          expect(jsonDecode(conflict.localSnapshotJson!), {
            'achievementId': 'first_answer',
            'definitionVersion': 1,
            'sourceEventId': source,
            'unlockedAtUtcMs': time,
          });
          expect(jsonDecode(conflict.cloudSnapshotJson!), entity.payload);
        }
        expect(conflicts.map((row) => row.id).toSet(), hasLength(2));
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );
    test(
      'physical achievement ID owned by another owner rejects pull atomically',
      () async {
        await database.customInsert(
          "INSERT INTO local_owners(id,account_state,created_at_utc_ms,is_active) VALUES ('other-owner','localGuest',1,0)",
        );
        await database.customInsert(
          "INSERT INTO achievement_unlocks VALUES ('opaque-cross-owner','other-owner','first_answer',1,'other-source',17)",
        );
        await database.customInsert(
          "INSERT INTO sync_checkpoints (id,owner_id,collection_name,server_cursor,last_success_at_utc_ms) VALUES ('$_ownerId:achievement_unlocks','$_ownerId','achievement_unlocks','prior-cursor',5)",
        );
        final before = await database
            .select(database.achievementUnlocks)
            .getSingle();
        final checkpoint = await database
            .select(database.syncCheckpoints)
            .getSingle();
        final entity = _achievementEntity(id: 'opaque-cross-owner');
        await expectLater(
          store.applyPullPage(
            ownerId: _ownerId,
            collection: SyncCollection.achievementUnlocks,
            page: PullPage(
              changes: [entity],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
                documentId: entity.entityId,
              ),
              hasMore: false,
            ),
          ),
          throwsA(isA<InvalidSyncPayloadFailure>()),
        );
        expect(await database.select(database.achievementUnlocks).get(), [
          before,
        ]);
        expect(before.ownerId, 'other-owner');
        expect(await database.select(database.syncCheckpoints).get(), [
          checkpoint,
        ]);
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );
    for (final diverges in [true, false]) {
      test(
        'logical unlock after attempt-first restore with an alternate ID and ${diverges ? 'different' : 'identical'} evidence',
        () async {
          Future<void> pull(SyncEntity entity) => store.applyPullPage(
            ownerId: _ownerId,
            collection: entity.collection,
            page: PullPage(
              changes: [entity],
              nextCursor: SyncCursor(
                serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
                documentId: entity.entityId,
              ),
              hasMore: false,
            ),
          );
          await database.customStatement(
            "INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('c',?,'Travel','travel',1,1)",
            [_ownerId],
          );
          await database.customStatement(
            "INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('w',?,'c','station','station','สถานี','สถานี','noun',1,1)",
            [_ownerId],
          );
          final earlier = DateTime.utc(2026, 8, 4, 9);
          final original = DateTime.utc(2026, 8, 4, 10);
          for (final (id, time) in [
            ('late-arrival', earlier),
            ('original-answer', original),
          ]) {
            await pull(
              SyncEntity(
                collection: SyncCollection.attempts,
                entityId: id,
                revision: 1,
                isDeleted: false,
                payloadVersion: 1,
                clientUpdatedAtUtc: time,
                serverUpdatedAtUtc: time.add(const Duration(hours: 2)),
                payload: {
                  'sessionId': 'synthetic-round',
                  'wordId': 'w',
                  'promptMode': 'meaningChoice',
                  'isCorrect': false,
                  'responseTimeMs': 300,
                  'attemptNumber': 1,
                  'occurredAtUtcMs': time.millisecondsSinceEpoch,
                  'providerProvenance': null,
                },
              ),
            );
          }
          final retained = await database
              .select(database.achievementUnlocks)
              .getSingle();
          final localPayload = {
            'achievementId': 'first_answer',
            'definitionVersion': 1,
            'sourceEventId': 'late-arrival',
            'unlockedAtUtcMs': earlier.millisecondsSinceEpoch,
          };
          expect(
            (
              retained.achievementId,
              retained.sourceEventId,
              retained.unlockedAtUtcMs,
            ),
            ('first_answer', 'late-arrival', earlier.millisecondsSinceEpoch),
          );
          final cloud = SyncEntity(
            collection: SyncCollection.achievementUnlocks,
            entityId: 'opaque-origin-device-unlock',
            revision: 1,
            isDeleted: false,
            payloadVersion: 1,
            clientUpdatedAtUtc: diverges ? original : earlier,
            serverUpdatedAtUtc: original.add(const Duration(hours: 3)),
            payload: {
              ...localPayload,
              if (diverges) 'sourceEventId': 'original-answer',
              if (diverges) 'unlockedAtUtcMs': original.millisecondsSinceEpoch,
            },
          );
          expect(cloud.entityId, isNot(retained.id));
          await pull(cloud);
          await pull(cloud);
          expect(
            await database.select(database.achievementUnlocks).getSingle(),
            retained,
          );
          expect(
            await database.select(database.outboxOperations).get(),
            isEmpty,
          );
          final conflicts = await database.select(database.syncConflicts).get();
          if (diverges) {
            expect(conflicts, hasLength(1));
            final conflict = conflicts.single;
            expect(
              (
                conflict.ownerId,
                conflict.entityType,
                conflict.entityId,
                conflict.outcome,
              ),
              (_ownerId, 'achievementUnlock', cloud.entityId, 'quarantined'),
            );
            expect(jsonDecode(conflict.localSnapshotJson!), localPayload);
            expect(jsonDecode(conflict.cloudSnapshotJson!), cloud.payload);
          } else {
            expect(conflicts, isEmpty);
          }
        },
      );
    }

    test('accepted remote evidence survives answer rebuild and immutable replay', () async {
      final accepted = SyncEntity(
        collection: SyncCollection.achievementUnlocks,
        entityId: 'remote-first',
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10),
        serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
        payload: const {
          'achievementId': 'first_answer',
          'definitionVersion': 1,
          'sourceEventId': 'remote-source',
          'unlockedAtUtcMs': 1722758400000,
        },
      );
      Future<void> pull(SyncEntity entity) => store.applyPullPage(
        ownerId: _ownerId,
        collection: SyncCollection.achievementUnlocks,
        page: PullPage(
          changes: [entity],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
            documentId: entity.entityId,
          ),
          hasMore: false,
        ),
      );
      await pull(accepted);
      await database.customInsert(
        "INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES ('c','$_ownerId','Travel','travel',1,1)",
      );
      await database.customInsert(
        "INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES ('w','$_ownerId','c','station','station','สถานี','สถานี','noun',1,1)",
      );
      await database.customInsert(
        "INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES ('s','$_ownerId','quiz','active',1,'test','test')",
      );
      await database.customInsert(
        "INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,occurred_at_utc_ms) VALUES ('a','$_ownerId','s','w','meaningChoice',0,1,10)",
      );
      await DriftLearningProjectionRebuilder(
        database,
      ).rebuildAchievements(_ownerId);
      await pull(accepted);
      final rows = await database.select(database.achievementUnlocks).get();
      final first = rows.singleWhere((r) => r.achievementId == 'first_answer');
      expect(
        (first.id, first.sourceEventId, first.unlockedAtUtcMs),
        ('remote-first', 'remote-source', 1722758400000),
      );
      await database.customInsert(
        "INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,operation_kind,created_at_utc_ms) VALUES ('retained-op','$_ownerId','achievementUnlock','remote-first','upsert',20)",
      );
      final claims = await store.claimPending(
        ownerId: _ownerId,
        firebaseUid: 'synthetic-uid',
        limit: 10,
        leaseToken: 'synthetic-lease',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: DateTime.utc(2026, 8, 4, 10, 5),
      );
      final claim = claims.singleWhere((c) => c.mutation.entityId == first.id);
      expect(claim.mutation.payload, {
        'achievementId': first.achievementId,
        'definitionVersion': first.definitionVersion,
        'sourceEventId': first.sourceEventId,
        'unlockedAtUtcMs': first.unlockedAtUtcMs,
      });
      final dangling = await database
          .customSelect(
            "SELECT operation_id FROM outbox_operations o WHERE o.entity_type = 'achievementUnlock' AND NOT EXISTS (SELECT 1 FROM achievement_unlocks a WHERE a.id = o.entity_id AND a.owner_id = o.owner_id)",
          )
          .get();
      expect(dangling, isEmpty);
      final altered = SyncEntity(
        collection: accepted.collection,
        entityId: accepted.entityId,
        revision: 1,
        isDeleted: false,
        payloadVersion: 1,
        clientUpdatedAtUtc: accepted.clientUpdatedAtUtc,
        serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 2),
        payload: const {
          'achievementId': 'first_answer',
          'definitionVersion': 1,
          'sourceEventId': 'tampered',
          'unlockedAtUtcMs': 1722758400000,
        },
      );
      await pull(altered);
      final after = await (database.select(
        database.achievementUnlocks,
      )..where((r) => r.id.equals('remote-first'))).getSingle();
      expect(
        (after.sourceEventId, after.unlockedAtUtcMs),
        ('remote-source', 1722758400000),
      );
      expect(await database.select(database.syncConflicts).get(), isNotEmpty);
      expect(
        await database.select(database.pointsLedgerEntries).get(),
        isEmpty,
      );
      expect(await database.select(database.rewardTransactions).get(), isEmpty);
    });
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
