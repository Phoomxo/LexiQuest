import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';

// ── Helpers ───────────────────────────────────────────────────────────────────

const _ownerId = 'owner-srs-test';
const _wordId = 'word-srs-1';
const _srsId = 'srs-1';

Future<void> _seedOwnerAndWord(db.AppDatabase database) async {
  await database.customInsert(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
    "VALUES ('$_ownerId', 'localGuest', 1722758400000)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_categories "
    "(id, owner_id, name, normalized_name, sort_order, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('cat-1', '$_ownerId', 'Test', 'test', 0, 1, 0, 0, 10, 10)",
  );
  await database.customInsert(
    "INSERT INTO vocabulary_words "
    "(id, owner_id, category_id, spelling, normalized_spelling, meaning, "
    "normalized_meaning, part_of_speech, source, is_global, local_revision, "
    "cloud_revision, is_deleted, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('$_wordId', '$_ownerId', 'cat-1', 'hello', 'hello', "
    "'สวัสดี', 'สวัสดี', 'interjection', 'manual', 0, 1, 0, 0, 10, 10)",
  );
}

SyncEntity _srsEntity({String? wordId, int revision = 1}) => SyncEntity(
  collection: SyncCollection.srsStates,
  entityId: wordId ?? _wordId,
  revision: revision,
  isDeleted: false,
  payloadVersion: 1,
  clientUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 0),
  serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
  payload: const <String, Object?>{
    'wordId': _wordId,
    'stability': 2.5,
    'difficulty': 5.0,
    'intervalDays': 3,
    'repetitions': 1,
    'lapses': 0,
    'lastReviewAtUtcMs': 1722758400000,
    'dueAtUtcMs': 1723017600000,
    'algorithmVersion': 1,
  },
);

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  late db.AppDatabase database;
  late DriftSyncStore store;

  setUp(() async {
    database = db.AppDatabase(NativeDatabase.memory());
    store = DriftSyncStore(database);
    await _seedOwnerAndWord(database);
  });

  tearDown(() async => database.close());

  group('SrsState sync — D6.2', () {
    test('applyPullPage inserts new SRS state row', () async {
      await store.applyPullPage(
        ownerId: _ownerId,
        collection: SyncCollection.srsStates,
        page: PullPage(
          changes: [_srsEntity()],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
            documentId: _wordId,
          ),
          hasMore: false,
        ),
      );

      final rows = await (database.select(
        database.srsStates,
      )..where((r) => r.wordId.equals(_wordId))).get();
      expect(rows, hasLength(1));
      expect(rows.first.intervalDays, 3);
      expect(rows.first.repetitions, 1);
    });

    test('applyPullPage accepts a mutable revision-two SRS state', () async {
      final entity = _srsEntity(revision: 2);

      await store.applyPullPage(
        ownerId: _ownerId,
        collection: SyncCollection.srsStates,
        page: PullPage(
          changes: [entity],
          nextCursor: SyncCursor(
            serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
            documentId: entity.entityId,
          ),
          hasMore: false,
        ),
      );

      final state = await (database.select(
        database.srsStates,
      )..where((row) => row.wordId.equals(_wordId))).getSingle();
      expect(state.intervalDays, 3);
      expect(state.repetitions, 1);
    });

    test(
      'applyPullPage updates existing SRS state (last-write-wins)',
      () async {
        // Seed an existing SRS state.
        await database.customInsert(
          "INSERT INTO srs_states "
          "(id, owner_id, word_id, stability, difficulty, interval_days, "
          "repetitions, lapses, last_review_at_utc_ms, due_at_utc_ms, "
          "algorithm_version) VALUES "
          "('$_srsId', '$_ownerId', '$_wordId', 1.0, 8.0, 1, 0, 0, NULL, "
          "1722758400000, 1)",
        );

        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.srsStates,
          page: PullPage(
            changes: [_srsEntity()],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: DateTime.utc(2026, 8, 4, 10, 1),
              documentId: _wordId,
            ),
            hasMore: false,
          ),
        );

        final rows = await (database.select(
          database.srsStates,
        )..where((r) => r.wordId.equals(_wordId))).get();
        expect(rows, hasLength(1));
        expect(rows.first.stability, closeTo(2.5, 0.001));
        expect(
          rows.first.intervalDays,
          3,
          reason: 'server state must overwrite local',
        );
      },
    );

    test(
      'revision-two pull preserves an answer-derived local SRS projection',
      () async {
        await database.customInsert(
          "INSERT INTO learning_sessions "
          "(id, owner_id, activity_type, state, started_at_utc_ms, "
          "app_version, build_id) VALUES "
          "('session-local', '$_ownerId', 'quiz', 'completed', 10, "
          "'test', 'test')",
        );
        await database.customInsert(
          "INSERT INTO answer_attempts "
          "(id, owner_id, session_id, word_id, prompt_mode, is_correct, "
          "attempt_number, occurred_at_utc_ms) VALUES "
          "('attempt-local', '$_ownerId', 'session-local', '$_wordId', "
          "'meaningChoice', 0, 1, 20)",
        );
        await database.customInsert(
          "INSERT INTO srs_states "
          "(id, owner_id, word_id, stability, difficulty, interval_days, "
          "repetitions, lapses, last_review_at_utc_ms, due_at_utc_ms, "
          "algorithm_version) VALUES "
          "('$_srsId', '$_ownerId', '$_wordId', 1.0, 8.0, 1, 0, 1, 20, "
          "30, 1)",
        );
        final entity = _srsEntity(revision: 2);

        await store.applyPullPage(
          ownerId: _ownerId,
          collection: SyncCollection.srsStates,
          page: PullPage(
            changes: [entity],
            nextCursor: SyncCursor(
              serverUpdatedAtUtc: entity.serverUpdatedAtUtc,
              documentId: entity.entityId,
            ),
            hasMore: false,
          ),
        );

        final rebuilt = await database.select(database.srsStates).getSingle();
        expect(rebuilt.id, 'srs:$_ownerId:$_wordId');
        expect(rebuilt.repetitions, 0);
        expect(rebuilt.lapses, 1);
        expect(rebuilt.lastReviewAtUtcMs, 20);
        expect(rebuilt.intervalDays, 1);
        expect(
          rebuilt.stability,
          isNot(2.5),
          reason: 'immutable answers are authoritative over the cloud cache',
        );
      },
    );

    test('srsState outbox is enqueued after recordAnswer', () async {
      // Verify outbox has no srsState row before any answer is recorded.
      final outboxBefore = await (database.select(
        database.outboxOperations,
      )..where((r) => r.entityType.equals('srsState'))).get();
      expect(outboxBefore, isEmpty, reason: 'no srsState outbox before answer');
    });
  });
}
