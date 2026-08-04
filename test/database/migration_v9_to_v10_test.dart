import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  group('Schema v9→v10 migration — D8.3 Associative Learning persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('association_records table exists after fresh onCreate', () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='association_records'",
          )
          .get();
      expect(tables, hasLength(1));
    });

    test('associative_memory_states table exists after fresh onCreate',
        () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='associative_memory_states'",
          )
          .get();
      expect(tables, hasLength(1));
    });

    test('fresh database reports schema version 10', () async {
      await db.customSelect('SELECT 1').get();
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(version, 10);
    });

    test('can insert and retrieve an association_records row', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-assoc', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db.into(db.associationRecords).insert(
            AssociationRecordsCompanion.insert(
              id: 'assoc-1',
              ownerId: 'owner-assoc',
              wordKey: 'banana',
              type: 'keyword',
              content: 'yellow fruit',
              createdAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );

      final rows = await (db.select(db.associationRecords)
            ..where((t) => t.ownerId.equals('owner-assoc')))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.content, 'yellow fruit');
    });

    test('unique(owner_id, word_key, type) upserts existing row', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-upsert', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      for (final content in ['first cue', 'updated cue']) {
        await db.into(db.associationRecords).insert(
              AssociationRecordsCompanion.insert(
                id: 'assoc-up-$content',
                ownerId: 'owner-upsert',
                wordKey: 'apple',
                type: 'keyword',
                content: content,
                createdAtUtcMs: now.millisecondsSinceEpoch,
              ),
              mode: InsertMode.insertOrReplace,
            );
      }

      final rows = await (db.select(db.associationRecords)
            ..where((t) =>
                t.ownerId.equals('owner-upsert') & t.wordKey.equals('apple')))
          .get();
      expect(rows, hasLength(1));
      expect(rows.first.content, 'updated cue');
    });
  });
}
