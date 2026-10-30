import 'dart:convert';

import 'package:drift/drift.dart' as drift;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_account_snapshot.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_upgrade.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

import '../../support/saved_word_owner_fixture.dart';

const _source = 'synthetic-saved-guest';
const _target = 'synthetic-saved-account';
const _uid = 'synthetic-saved-firebase-uid';
final _now = DateTime.utc(2026, 10, 30, 12, 0, 0, 123);

void main() {
  for (final sourceSaved in [false, true]) {
    for (final targetSaved in [false, true]) {
      test(
        'duplicate word coalesces saved union $sourceSaved/$targetSaved before physical deletion and fences stale CAS',
        () async {
          final f = await _Fixture.open();
          addTearDown(f.close);
          final source = await insertOwnerSavedWord(
            f.db,
            _source,
            wordId: 'source-word',
            isSaved: sourceSaved,
            localRevision: 4,
            firstSavedAtUtcMs: 15,
            mutationId: 'source-last',
          );
          final target = await insertOwnerSavedWord(
            f.db,
            _target,
            wordId: 'target-word',
            isSaved: targetSaved,
            localRevision: 7,
            firstSavedAtUtcMs: 5,
            mutationId: 'target-last',
          );
          final staleSource = _command(source, 'frozen-source-command');
          final staleTarget = _command(target, 'frozen-target-command');
          final result = await f.upgrade();
          expect(result.mode, OwnerUpgradeMode.mergedExisting);
          expect(result.conflictCount, 2);
          expect(await f.word('source-word'), isNull);
          expect((await f.word('target-word'))!['owner_id'], _target);
          final rows = await savedWordOwnerRows(f.db);
          expect(rows, hasLength(1));
          final merged = StoredSavedWordState.fromStorage(rows.single);
          expect(merged.ownerId, _target);
          expect(merged.wordId, 'target-word');
          expect(merged.isSaved, sourceSaved || targetSaved);
          expect(merged.localRevision, 8);
          expect(merged.firstSavedAtUtc.millisecondsSinceEpoch, 5);
          expect(merged.updatedAtUtc, _now);
          expect(merged.lastMutationId, startsWith('saved-merge:'));
          expect(
            merged.lastMutationId,
            isNot(anyOf('source-last', 'target-last')),
          );
          final beforeRetry = await f.snapshot();
          final saved = DriftSavedWordsRepository(
            f.db,
            ownerWrites: f.ownerWrites,
          );
          final conflict = await saved.apply(staleTarget);
          expect(conflict.status, SavedWordApplyStatus.conflict);
          expect(conflict.state.sameFacts(merged), isTrue);
          await expectLater(
            saved.apply(staleSource),
            throwsA(
              isA<AccountDeletionException>().having(
                (error) => error.code,
                'owner denial',
                AccountDeletionFailureCode.ownerChanged,
              ),
            ),
          );
          expect(await f.snapshot(), beforeRetry);
          final beforeReplay = await f.snapshot();
          expect(
            (await f.repository.upgrade(
              activeOwnerId: _target,
              firebaseUid: _uid,
            )).mode,
            OwnerUpgradeMode.alreadyBound,
          );
          expect(await f.snapshot(), beforeReplay);
        },
      );
    }
  }

  test(
    'nonduplicate tombstone moves with original word ID; unrelated target receipt stays byte-for-byte',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final original = await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-only-word',
        isSaved: false,
        localRevision: 2,
        firstSavedAtUtcMs: 30,
      );
      final target = await insertOwnerSavedWord(
        f.db,
        _target,
        wordId: 'target-only-word',
        localRevision: 9,
        firstSavedAtUtcMs: 7,
      );
      await f.upgrade();
      expect(await savedWordOwnerRows(f.db, ownerId: _source), isEmpty);
      final rows = await savedWordOwnerRows(f.db, ownerId: _target);
      expect(rows, hasLength(2));
      expect(
        rows.singleWhere((row) => row['word_id'] == 'target-only-word'),
        target,
      );
      final moved = rows.singleWhere(
        (row) => row['word_id'] == 'source-only-word',
      );
      expect(moved['is_saved'], 0);
      expect(moved['local_revision'], 3);
      expect(moved['first_saved_at_utc_ms'], original['first_saved_at_utc_ms']);
      expect(moved['last_mutation_id'], isNot(original['last_mutation_id']));
      expect((await f.word('source-only-word'))!['owner_id'], _target);
      expect(
        await f.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'source tombstone remaps to a surviving duplicate word even without target saved state',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-word',
        isSaved: false,
        localRevision: 6,
      );
      await f.upgrade();
      final row = (await savedWordOwnerRows(f.db)).single;
      expect(row['owner_id'], _target);
      expect(row['word_id'], 'target-word');
      expect(row['is_saved'], 0);
      expect(row['local_revision'], 7);
      expect(await f.word('source-word'), isNull);
    },
  );

  test(
    'same-owner bind and already-bound replay preserve all seven saved facts',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(f.db, _source, wordId: 'source-word');
      await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-only-word',
        isSaved: false,
      );
      await insertOwnerSavedWord(f.db, _target, wordId: 'target-only-word');
      final before = await savedWordOwnerRows(f.db);
      const freshUid = 'synthetic-new-bound-uid';
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _source,
          firebaseUid: freshUid,
        )).mode,
        OwnerUpgradeMode.anonymousBound,
      );
      expect(await savedWordOwnerRows(f.db), before);
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _source,
          firebaseUid: freshUid,
        )).mode,
        OwnerUpgradeMode.alreadyBound,
      );
      expect(await savedWordOwnerRows(f.db), before);
    },
  );

  for (final saved in [false, true]) {
    test(
      'logout preserves old saved bytes; guest rollback with new saved=$saved is atomic and restrictive',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await insertOwnerSavedWord(f.db, _source, wordId: 'source-only-word');
        final oldRows = await savedWordOwnerRows(f.db, ownerId: _source);
        final guest = await f.repository.createLocalGuestAfterLogout();
        expect(await savedWordOwnerRows(f.db, ownerId: _source), oldRows);
        await insertOwnerSavedWord(f.db, guest.targetOwnerId, isSaved: saved);
        final before = await f.snapshot();
        await expectLater(
          f.repository.rollbackLocalGuestLogout(
            previousOwnerId: _source,
            guestOwnerId: guest.targetOwnerId,
          ),
          throwsA(isA<Object>()),
        );
        expect(await f.snapshot(), before);
        expect(await savedWordOwnerRows(f.db, ownerId: _source), oldRows);
      },
    );
  }

  for (final corruption in [
    'foreign-word',
    'foreign-category',
    'invalid-revision',
    'invalid-bool',
    'oversized-receipt',
    'target-invalid-receipt',
    'orphan-word',
  ]) {
    test(
      'preflight rejects $corruption before remapping categories and rolls back every business row',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await insertOwnerSavedWord(f.db, _source, wordId: 'source-word');
        await insertOwnerSavedWord(f.db, _target, wordId: 'target-only-word');
        await f.db.customStatement('PRAGMA ignore_check_constraints = ON');
        await f.db.customStatement('PRAGMA foreign_keys = OFF');
        switch (corruption) {
          case 'foreign-word':
            await f.db.customStatement(
              "UPDATE saved_words SET word_id = 'target-word' WHERE owner_id = ?",
              [_source],
            );
          case 'foreign-category':
            await f.db.customStatement(
              "UPDATE vocabulary_words SET category_id = 'target-category' WHERE id = 'source-word'",
            );
          case 'invalid-revision':
            await f.db.customStatement(
              'UPDATE saved_words SET local_revision = 0 WHERE owner_id = ?',
              [_source],
            );
          case 'invalid-bool':
            await f.db.customStatement(
              'UPDATE saved_words SET is_saved = 2 WHERE owner_id = ?',
              [_source],
            );
          case 'oversized-receipt':
            await f.db.customStatement(
              'UPDATE saved_words SET last_mutation_id = ? WHERE owner_id = ?',
              [List.filled(86, '界').join(), _source],
            );
          case 'target-invalid-receipt':
            await f.db.customStatement(
              "UPDATE saved_words SET last_mutation_id = '' WHERE owner_id = ?",
              [_target],
            );
          case 'orphan-word':
            await f.db.customStatement(
              "UPDATE saved_words SET word_id = 'synthetic-missing-word' WHERE owner_id = ?",
              [_source],
            );
        }
        await f.db.customStatement('PRAGMA foreign_keys = ON');
        await f.db.customStatement('PRAGMA ignore_check_constraints = OFF');
        final before = await f.snapshot();
        await expectLater(f.upgrade(), throwsA(isA<Object>()));
        expect(await f.snapshot(), before);
        expect((await f.word('source-word'))!['owner_id'], _source);
        expect(
          await f.db.customSelect('SELECT * FROM outbox_operations').get(),
          isNotEmpty,
        );
        expect(
          await f.db.customSelect('SELECT * FROM reward_transactions').get(),
          isNotEmpty,
        );
      },
    );
  }

  test(
    'exhausted revision rolls back earlier category/word and ordinary reward/outbox work',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-word',
        localRevision: savedWordsMaxRevision,
      );
      final before = await f.snapshot();
      await expectLater(f.upgrade(), throwsStateError);
      expect(await f.snapshot(), before);
    },
  );

  for (final receipt in ['reused', 'oversized-utf8']) {
    test(
      'invalid $receipt internal merge identity rolls back the complete upgrade',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await insertOwnerSavedWord(
          f.db,
          _source,
          wordId: 'source-word',
          mutationId: 'saved-merge:fixed',
        );
        final before = await f.snapshot();
        final repository = DriftOwnerUpgradeRepository(
          f.db,
          nowUtc: () => _now,
          generateConflictId: () =>
              receipt == 'reused' ? 'fixed' : List.filled(86, '界').join(),
          generateOwnerId: () => 'synthetic-unused-owner',
        );
        await expectLater(
          repository.upgrade(activeOwnerId: _source, firebaseUid: _uid),
          throwsA(isA<Object>()),
        );
        expect(await f.snapshot(), before);
      },
    );
  }

  test(
    'source CAS changed by the actual target mutation cannot be discarded',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(f.db, _source, wordId: 'source-word');
      await insertOwnerSavedWord(f.db, _target, wordId: 'target-word');
      await f.db.customStatement("""
      CREATE TRIGGER synthetic_saved_source_cas
      BEFORE UPDATE OF is_saved ON saved_words
      WHEN OLD.owner_id = '$_target'
      BEGIN
        UPDATE saved_words SET local_revision = local_revision + 1
        WHERE owner_id = '$_source';
      END
    """);
      final before = await f.snapshot();
      await expectLater(f.upgrade(), throwsStateError);
      expect(await f.snapshot(), before);
    },
  );

  test(
    'final parent-owner validation rejects corruption introduced during ordinary word movement',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(f.db, _source, wordId: 'source-only-word');
      await f.db.customStatement("""
      CREATE TRIGGER synthetic_saved_parent_drift
      AFTER UPDATE OF owner_id ON vocabulary_words
      WHEN NEW.id = 'source-only-word' AND NEW.owner_id = '$_target'
      BEGIN
        UPDATE vocabulary_words SET category_id = 'third-category' WHERE id = NEW.id;
      END
    """);
      final before = await f.snapshot();
      await expectLater(f.upgrade(), throwsStateError);
      expect(await f.snapshot(), before);
    },
  );

  test(
    'saved merge adds no Research events or extra ordinary outbox operations',
    () async {
      final control = await _Fixture.open();
      final f = await _Fixture.open();
      addTearDown(control.close);
      addTearDown(f.close);
      await insertOwnerSavedWord(f.db, _source, wordId: 'source-word');
      await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-only-word',
        isSaved: false,
      );
      await insertOwnerSavedWord(
        f.db,
        _target,
        wordId: 'target-word',
        isSaved: false,
      );
      await control.upgrade();
      await f.upgrade();
      expect(await _outboxFacts(f.db), await _outboxFacts(control.db));
      for (final table in [
        'research_consents',
        'experiment_assignments',
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'assessment_runs',
        'events_v2',
      ]) {
        expect(
          await f.db.customSelect('SELECT * FROM $table').get(),
          isEmpty,
          reason: table,
        );
      }
    },
  );

  test(
    'personal export and durable cloud-confirmed purge cover all seven fields and preserve the other owner',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerSavedWord(
        f.db,
        _source,
        wordId: 'source-only-word',
        isSaved: false,
        localRevision: 5,
      );
      await insertOwnerSavedWord(
        f.db,
        _target,
        wordId: 'target-only-word',
        localRevision: 8,
      );
      const sourceUid = 'synthetic-export-owner-uid';
      await f.repository.upgrade(
        activeOwnerId: _source,
        firebaseUid: sourceUid,
      );
      final savedBefore = await savedWordOwnerRows(f.db);
      final targetBefore = await _ownerSnapshot(f.db, _target);
      final export = await DriftAccountSnapshotBuilder(
        f.db,
        nowUtc: () => _now,
      ).build(ownerId: _source);
      final json =
          jsonDecode(utf8.decode(export.bytes)) as Map<String, dynamic>;
      final exported = (json['data'] as Map)['saved_words'] as List;
      expect(exported, [
        savedBefore.singleWhere((row) => row['owner_id'] == _source),
      ]);
      expect(exported.single, hasLength(7));
      final cloud = CloudDeletionReceipt(
        receiptId: 'synthetic-saved-cloud-receipt',
        ownerId: _source,
        firebaseUid: sourceUid,
        idempotencyKey: 'synthetic-saved-delete-operation',
        completedAtUtc: _now,
      ).durableMarker();
      final intent = await f.ownerWrites.beginDeletion(
        ownerId: _source,
        firebaseUid: sourceUid,
        idempotencyKey: 'synthetic-saved-delete-operation',
      );
      await f.ownerWrites.markPending(intent);
      await f.ownerWrites.markCloud(intent, cloud);
      final local = await DriftLocalAccountDeletionGateway(
        f.db,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
      ).deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
      expect(await savedWordOwnerRows(f.db, ownerId: _source), isEmpty);
      expect(await _ownerSnapshot(f.db, _target), targetBefore);
      await f.ownerWrites.markLocal(intent, cloud, local);
      await f.ownerWrites.clearCompleted(intent);
      expect(await f.ownerWrites.inspect(), isNull);
      expect(await _ownerSnapshot(f.db, _target), targetBefore);
      expect(
        await f.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

SavedWordMutation _command(Map<String, Object?> state, String id) =>
    SavedWordMutation(
      mutationId: id,
      expectedOwnerId: state['owner_id']! as String,
      wordId: state['word_id']! as String,
      desiredIsSaved: state['is_saved'] == 0,
      expectedRevision: state['local_revision']! as int,
      occurredAtUtc: _now,
    );

Future<List<Map<String, Object?>>> _outboxFacts(AppDatabase db) async =>
    (await db
            .customSelect(
              'SELECT owner_id, entity_type, entity_id, operation_kind, base_revision, state FROM outbox_operations ORDER BY owner_id, entity_type, entity_id, operation_kind, base_revision, state',
            )
            .get())
        .map((row) => row.data)
        .toList();

Future<Map<String, List<String>>> _ownerSnapshot(
  AppDatabase db,
  String ownerId,
) async => {
  for (final table in ownerUpgradeInventory)
    table:
        (await db
                .customSelect(
                  'SELECT * FROM $table WHERE owner_id = ?',
                  variables: [drift.Variable<String>(ownerId)],
                )
                .get())
            .map((row) => jsonEncode(row.data))
            .toList()
          ..sort(),
  'local_owners':
      (await db
              .customSelect(
                'SELECT * FROM local_owners WHERE id = ?',
                variables: [drift.Variable<String>(ownerId)],
              )
              .get())
          .map((row) => jsonEncode(row.data))
          .toList(),
};

final class _Fixture {
  _Fixture(this.db) {
    ownerWrites = DriftOwnerWriteCoordinator(db, nowUtc: () => _now);
    repository = DriftOwnerUpgradeRepository(
      db,
      nowUtc: () => _now,
      generateConflictId: () => 'synthetic-saved-merge-${++_sequence}',
      generateOwnerId: () => 'synthetic-saved-created-guest',
    );
  }
  final AppDatabase db;
  late final DriftOwnerWriteCoordinator ownerWrites;
  late final DriftOwnerUpgradeRepository repository;
  int _sequence = 0;
  static Future<_Fixture> open() async {
    final db = AppDatabase(NativeDatabase.memory());
    await db.customStatement('PRAGMA foreign_keys = ON');
    await db.customStatement(
      "INSERT INTO local_owners (id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES (?, NULL, 'localGuest', 1, 1), (?, ?, 'firebaseBound', 0, 2), ('synthetic-saved-third', NULL, 'localGuest', 0, 3)",
      [_source, _target, _uid],
    );
    for (final row in [
      ['source-category', _source, 'Shared', 'shared'],
      ['target-category', _target, 'Shared', 'shared'],
      ['third-category', 'synthetic-saved-third', 'Third', 'third'],
    ]) {
      await db.customStatement(
        'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
        row,
      );
    }
    for (final row in [
      ['source-word', _source, 'source-category', 'cat', 'animal'],
      ['target-word', _target, 'target-category', 'cat', 'animal'],
      ['source-only-word', _source, 'source-category', 'dog', 'dog gloss'],
      ['target-only-word', _target, 'target-category', 'tree', 'tree gloss'],
    ]) {
      await db.customStatement(
        'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
        [row[0], row[1], row[2], row[3], row[3], row[4], row[4], 'noun'],
      );
    }
    await db.customStatement(
      "INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, app_version, build_id) VALUES ('saved-ordinary-session', ?, 'quiz', 'completed', 1, 3, 1, 0, 100, 'synthetic', 'synthetic')",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms, attempt_number, occurred_at_utc_ms) VALUES ('saved-ordinary-attempt', ?, 'saved-ordinary-session', 'source-word', 'meaning', 1, 10, 1, 2)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO reward_transactions (id, owner_id, idempotency_key, transaction_type, amount, catalog_version, occurred_at_utc_ms) VALUES ('saved-ordinary-credit', ?, 'saved-ordinary-credit-key', 'creditLegacyCarryV1', 7, 1, 3)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO points_ledger_entries (id, owner_id, idempotency_key, entry_type, amount, source_event_id, occurred_at_utc_ms) VALUES ('saved-ordinary-points', ?, 'saved-ordinary-points-key', 'quiz', 7, 'saved-ordinary-attempt', 3)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) VALUES ('saved-ordinary-operation', ?, 'word', 'source-word', 'upsert', 2)",
      [_source],
    );
    return _Fixture(db);
  }

  Future<OwnerUpgradeResult> upgrade() =>
      repository.upgrade(activeOwnerId: _source, firebaseUid: _uid);
  Future<Map<String, Object?>?> word(String wordId) async =>
      (await db
              .customSelect(
                'SELECT * FROM vocabulary_words WHERE id = ?',
                variables: [drift.Variable<String>(wordId)],
              )
              .getSingleOrNull())
          ?.data;
  Future<Map<String, List<String>>> snapshot() async => {
    for (final table in db.allTables)
      table.actualTableName:
          (await db
                  .customSelect('SELECT * FROM ${table.actualTableName}')
                  .get())
              .map((row) => jsonEncode(row.data))
              .toList()
            ..sort(),
  };
  Future<void> close() => db.close();
}
