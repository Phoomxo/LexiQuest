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
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/word_report_owner_fixture.dart';

const _source = 'synthetic-report-guest';
const _target = 'synthetic-report-account';
const _third = 'synthetic-report-third';
const _targetUid = 'synthetic-report-target-uid';
final _now = DateTime.utc(2026, 10, 30, 12, 0, 0, 123);

void main() {
  test(
    'duplicate word hard-delete preserves original nine historical report fields and other owners',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final original = await insertOwnerWordReport(
        f.db,
        _source,
        wordId: 'source-word',
        reason: ReportReason.partOfSpeech,
      );
      final target = await insertOwnerWordReport(
        f.db,
        _target,
        wordId: 'target-word',
      );
      final third = await insertOwnerWordReport(
        f.db,
        _third,
        wordId: 'third-word',
      );
      final result = await f.merge();
      expect(result.mode, OwnerUpgradeMode.mergedExisting);
      expect(result.conflictCount, 2);
      expect(await f.word('source-word'), isNull);
      expect(await f.category('source-category'), isNull);
      final survivor = (await f.word('target-word'))!;
      expect(survivor['spelling'], 'cat');
      expect(survivor['local_revision'], 9);
      final rows = await wordReportOwnerRows(f.db);
      final moved = rows.singleWhere((row) => row.id == original.id);
      expect(moved.ownerId, _target);
      expect(moved.sameHistoricalPayload(original), isTrue);
      expect(moved.target.wordId, 'source-word');
      expect(moved.target.categoryId, 'source-category');
      expect(moved.target.wordRevision, 5);
      expect(moved.target.spelling, 'Cat');
      expect(moved.target.partOfSpeech, 'noun');
      expect(moved.target.snapshotSha256, original.target.snapshotSha256);
      expect(
        rows.singleWhere((row) => row.id == target.id).sameFacts(target),
        isTrue,
      );
      expect(
        rows.singleWhere((row) => row.id == third.id).sameFacts(third),
        isTrue,
      );
      expect(
        await f.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final beforeReplay = await f.snapshot();
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _target,
          firebaseUid: _targetUid,
        )).mode,
        OwnerUpgradeMode.alreadyBound,
      );
      expect(await f.snapshot(), beforeReplay);
    },
  );

  test(
    'historical report with already missing word and category may move without reattachment',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final report = await insertOwnerWordReport(f.db, _source);
      await f.db.customStatement('DELETE FROM vocabulary_words WHERE id = ?', [
        report.target.wordId,
      ]);
      await f.db.customStatement(
        'DELETE FROM vocabulary_categories WHERE id = ?',
        [report.target.categoryId],
      );
      expect(await f.word(report.target.wordId), isNull);
      expect(await f.category(report.target.categoryId), isNull);
      await f.merge();
      final moved = (await wordReportOwnerRows(f.db)).single;
      expect(moved.ownerId, _target);
      expect(moved.sameHistoricalPayload(report), isTrue);
      expect(await f.word(report.target.wordId), isNull);
      expect(await f.category(report.target.categoryId), isNull);
    },
  );

  test(
    'same-owner bind and already-bound replay leave complete report bytes unchanged',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerWordReport(f.db, _source, wordId: 'source-word');
      await insertOwnerWordReport(f.db, _target, wordId: 'target-word');
      final before = await _reportBytes(f.db);
      const uid = 'synthetic-report-fresh-namespace';
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _source,
          firebaseUid: uid,
        )).mode,
        OwnerUpgradeMode.anonymousBound,
      );
      expect(await _reportBytes(f.db), before);
      expect(
        (await f.repository.upgrade(
          activeOwnerId: _source,
          firebaseUid: uid,
        )).mode,
        OwnerUpgradeMode.alreadyBound,
      );
      expect(await _reportBytes(f.db), before);
    },
  );

  test(
    'logout retains prior reports and report-only guest state prevents destructive rollback after word deletion',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerWordReport(f.db, _source, wordId: 'source-word');
      final previous = await _reportBytes(f.db);
      final guest = await f.repository.createLocalGuestAfterLogout();
      expect(await _reportBytes(f.db), previous);
      final report = await insertOwnerWordReport(f.db, guest.targetOwnerId);
      await f.db.customStatement('DELETE FROM vocabulary_words WHERE id = ?', [
        report.target.wordId,
      ]);
      await f.db.customStatement(
        'DELETE FROM vocabulary_categories WHERE id = ?',
        [report.target.categoryId],
      );
      for (final table in ownerUpgradeInventory) {
        final rows = await f.db
            .customSelect(
              'SELECT * FROM $table WHERE owner_id = ?',
              variables: [drift.Variable<String>(guest.targetOwnerId)],
            )
            .get();
        expect(rows.length, table == 'word_reports' ? 1 : 0, reason: table);
      }
      final before = await f.snapshot();
      await expectLater(
        f.repository.rollbackLocalGuestLogout(
          previousOwnerId: _source,
          guestOwnerId: guest.targetOwnerId,
        ),
        throwsA(isA<Object>()),
      );
      expect(await f.snapshot(), before);
      expect(
        (await wordReportOwnerRows(
          f.db,
          ownerId: guest.targetOwnerId,
        )).single.sameFacts(report),
        isTrue,
      );
    },
  );

  for (final corruption in [
    'json',
    'hash',
    'word-pin',
    'revision',
    'comment',
    'id',
    'target-reason',
  ]) {
    test(
      'strict $corruption preflight fails before category remap and preserves full owner/vocabulary/reward/outbox graph',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await insertOwnerWordReport(f.db, _source, wordId: 'source-word');
        await insertOwnerWordReport(f.db, _target, wordId: 'target-word');
        await f.db.customStatement('PRAGMA ignore_check_constraints = ON');
        switch (corruption) {
          case 'json':
            await f.db.customStatement(
              "UPDATE word_reports SET snapshot_json = '{}' WHERE owner_id = ?",
              [_source],
            );
          case 'hash':
            await f.db.customStatement(
              'UPDATE word_reports SET snapshot_sha256 = ? WHERE owner_id = ?',
              ['0' * 64, _source],
            );
          case 'word-pin':
            await f.db.customStatement(
              "UPDATE word_reports SET word_id = 'target-word' WHERE owner_id = ?",
              [_source],
            );
          case 'revision':
            await f.db.customStatement(
              'UPDATE word_reports SET word_revision = 0 WHERE owner_id = ?',
              [_source],
            );
          case 'comment':
            await f.db.customStatement(
              "UPDATE word_reports SET comment = ' noncanonical ' WHERE owner_id = ?",
              [_source],
            );
          case 'id':
            await f.db.customStatement(
              "UPDATE word_reports SET id = 'not-a-report-id' WHERE owner_id = ?",
              [_source],
            );
          case 'target-reason':
            await f.db.customStatement(
              "UPDATE word_reports SET reason = 'synthetic-unknown-reason' WHERE owner_id = ?",
              [_target],
            );
        }
        await f.db.customStatement('PRAGMA ignore_check_constraints = OFF');
        final before = await f.snapshot();
        await expectLater(f.merge(), throwsFormatException);
        expect(await f.snapshot(), before);
        expect(await f.category('source-category'), isNotNull);
        expect(await f.word('source-word'), isNotNull);
      },
    );
  }

  for (final change in [
    'valid-payload',
    'foreign-owner-row',
    'ignored-owner-move',
    'missing-row',
  ]) {
    test(
      'final report readback rejects $change introduced during actual owner update and rolls back all tables',
      () async {
        final f = await _Fixture.open();
        addTearDown(f.close);
        await insertOwnerWordReport(f.db, _source, wordId: 'source-word');
        await insertOwnerWordReport(f.db, _target, wordId: 'target-word');
        await insertOwnerWordReport(f.db, _third, wordId: 'third-word');
        final body = switch (change) {
          'valid-payload' =>
            "UPDATE word_reports SET comment = 'synthetic changed history' WHERE id = NEW.id;",
          'foreign-owner-row' =>
            "UPDATE word_reports SET owner_id = '$_target' WHERE owner_id = '$_third';",
          'ignored-owner-move' => 'SELECT RAISE(IGNORE);',
          'missing-row' => 'DELETE FROM word_reports WHERE id = NEW.id;',
          _ => throw StateError('Unknown synthetic corruption'),
        };
        await f.db.customStatement(
          "CREATE TRIGGER synthetic_report_history_guard "
          "${change == 'ignored-owner-move' ? 'BEFORE' : 'AFTER'} UPDATE OF owner_id ON word_reports "
          "WHEN OLD.owner_id = '$_source' AND NEW.owner_id = '$_target' "
          'BEGIN $body END',
        );
        final before = await f.snapshot();
        await expectLater(f.merge(), throwsStateError);
        expect(await f.snapshot(), before);
      },
    );
  }

  test(
    'report verification follows the final ordinary owner-state write',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      await insertOwnerWordReport(f.db, _source, wordId: 'source-word');
      await f.db.customStatement("""
      CREATE TRIGGER synthetic_late_report_history
      AFTER UPDATE OF account_state ON local_owners
      WHEN NEW.id = '$_source' AND NEW.account_state = 'mergedInto:$_target'
      BEGIN
        UPDATE word_reports SET comment = 'synthetic final-write tamper'
        WHERE owner_id = '$_target';
      END
    """);
      final before = await f.snapshot();
      await expectLater(f.merge(), throwsStateError);
      expect(await f.snapshot(), before);
    },
  );

  test(
    'reports change only their ownership; every other36 tables match an otherwise identical merge',
    () async {
      final control = await _Fixture.open();
      final reported = await _Fixture.open();
      addTearDown(control.close);
      addTearDown(reported.close);
      await insertOwnerWordReport(reported.db, _source, wordId: 'source-word');
      await insertOwnerWordReport(reported.db, _target, wordId: 'target-word');
      await insertOwnerWordReport(reported.db, _third, wordId: 'third-word');
      await control.merge();
      await reported.merge();
      final expected = await control.snapshot()
        ..remove('word_reports');
      final actual = await reported.snapshot()
        ..remove('word_reports');
      expect(actual, hasLength(36));
      expect(actual, expected);
    },
  );

  test(
    'personal export contains exact ten historical fields and cloud-confirmed purge preserves other owners',
    () async {
      final f = await _Fixture.open();
      addTearDown(f.close);
      final source = await insertOwnerWordReport(f.db, _source);
      await insertOwnerWordReport(f.db, _target, wordId: 'target-word');
      await insertOwnerWordReport(f.db, _third, wordId: 'third-word');
      await f.db.customStatement('DELETE FROM vocabulary_words WHERE id = ?', [
        source.target.wordId,
      ]);
      await f.db.customStatement(
        'DELETE FROM vocabulary_categories WHERE id = ?',
        [source.target.categoryId],
      );
      const uid = 'synthetic-report-source-bound-uid';
      await f.repository.upgrade(activeOwnerId: _source, firebaseUid: uid);
      final retained = {
        _target: await _ownerSnapshot(f.db, _target),
        _third: await _ownerSnapshot(f.db, _third),
      };
      final exported = await DriftAccountSnapshotBuilder(
        f.db,
        nowUtc: () => _now,
      ).build(ownerId: _source);
      final json =
          jsonDecode(utf8.decode(exported.bytes)) as Map<String, dynamic>;
      final reports = (json['data'] as Map)['word_reports'] as List;
      expect(reports, [source.toStorage()]);
      expect(reports.single, hasLength(10));
      const operation = 'synthetic-report-deletion-operation';
      final cloud = CloudDeletionReceipt(
        receiptId: 'synthetic-report-cloud-receipt',
        ownerId: _source,
        firebaseUid: uid,
        idempotencyKey: operation,
        completedAtUtc: _now,
      ).durableMarker();
      final token = await f.ownerWrites.beginDeletion(
        ownerId: _source,
        firebaseUid: uid,
        idempotencyKey: operation,
      );
      await f.ownerWrites.markPending(token);
      await f.ownerWrites.markCloud(token, cloud);
      final local = await DriftLocalAccountDeletionGateway(
        f.db,
        nowUtc: () => _now,
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {},
      ).deleteAfterCloud(ownerId: _source, cloudReceipt: cloud);
      expect(await wordReportOwnerRows(f.db, ownerId: _source), isEmpty);
      for (final owner in retained.keys) {
        expect(await _ownerSnapshot(f.db, owner), retained[owner]);
      }
      await f.ownerWrites.markLocal(token, cloud, local);
      await f.ownerWrites.clearCompleted(token);
      expect(await f.ownerWrites.inspect(), isNull);
      expect(
        await f.db.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

Future<List<Map<String, Object?>>> _reportBytes(AppDatabase db) async =>
    (await db.customSelect('SELECT * FROM word_reports ORDER BY id').get())
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
      generateConflictId: () => 'synthetic-report-conflict-${++_sequence}',
      generateOwnerId: () => 'synthetic-report-created-guest',
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
      "INSERT INTO local_owners (id, firebase_uid, account_state, is_active, created_at_utc_ms) VALUES (?, NULL, 'localGuest', 1, 1), (?, ?, 'firebaseBound', 0, 2), (?, 'synthetic-report-third-uid', 'firebaseBound', 0, 3)",
      [_source, _target, _targetUid, _third],
    );
    for (final row in [
      ['source-category', _source, 'Shared', 'shared'],
      ['target-category', _target, 'Shared', 'shared'],
      ['third-category', _third, 'Third', 'third'],
    ]) {
      await db.customStatement(
        'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
        row,
      );
    }
    for (final row in [
      ['source-word', _source, 'source-category', 'Cat', 'Animal', 'noun', 5],
      ['target-word', _target, 'target-category', 'cat', 'animal', 'verb', 9],
      [
        'third-word',
        _third,
        'third-category',
        'unrelated',
        'third gloss',
        'noun',
        2,
      ],
    ]) {
      await db.customStatement(
        'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, local_revision, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
        [
          row[0],
          row[1],
          row[2],
          row[3],
          (row[3] as String).toLowerCase(),
          row[4],
          (row[4] as String).toLowerCase(),
          row[5],
          row[6],
        ],
      );
    }
    await db.customStatement(
      "INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms, correct_count, wrong_count, score, app_version, build_id) VALUES ('report-ordinary-session', ?, 'quiz', 'completed', 1, 3, 1, 0, 100, 'synthetic', 'synthetic')",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms, attempt_number, occurred_at_utc_ms) VALUES ('report-ordinary-attempt', ?, 'report-ordinary-session', 'source-word', 'meaning', 1, 10, 1, 2)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO reward_transactions (id, owner_id, idempotency_key, transaction_type, amount, catalog_version, occurred_at_utc_ms) VALUES ('report-ordinary-credit', ?, 'report-ordinary-credit-key', 'creditLegacyCarryV1', 7, 1, 3)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO points_ledger_entries (id, owner_id, idempotency_key, entry_type, amount, source_event_id, occurred_at_utc_ms) VALUES ('report-ordinary-points', ?, 'report-ordinary-points-key', 'quiz', 7, 'report-ordinary-attempt', 3)",
      [_source],
    );
    await db.customStatement(
      "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms) VALUES ('report-ordinary-operation', ?, 'word', 'source-word', 'upsert', 2)",
      [_source],
    );
    return _Fixture(db);
  }

  Future<OwnerUpgradeResult> merge() =>
      repository.upgrade(activeOwnerId: _source, firebaseUid: _targetUid);
  Future<Map<String, Object?>?> word(String id) async =>
      (await db
              .customSelect(
                'SELECT * FROM vocabulary_words WHERE id = ?',
                variables: [drift.Variable<String>(id)],
              )
              .getSingleOrNull())
          ?.data;
  Future<Map<String, Object?>?> category(String id) async =>
      (await db
              .customSelect(
                'SELECT * FROM vocabulary_categories WHERE id = ?',
                variables: [drift.Variable<String>(id)],
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
