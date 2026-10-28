import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

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
