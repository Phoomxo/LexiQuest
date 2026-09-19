import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test(
    'raw27 outbox migration preserves unresolved send without inventing a snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp('outbox-v27-');
      final file = File('${directory.path}/migration.sqlite');
      final before = AppDatabase(NativeDatabase(file));
      try {
        await before.customSelect('SELECT 1').get();
        await before.customStatement(
          "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('owner', 1)",
        );
        await before.customStatement(
          "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, state, attempt_count, last_attempt_at_utc_ms, created_at_utc_ms) VALUES ('category:c:1', 'owner', 'category', 'c', 'upsert', 'inFlight', 1, 2, 1)",
        );
      } finally {
        await before.close();
      }
      // v28 adds only this nullable column. Remove it outside Drift to restore
      // the actual v27 table shape, retaining the complete surrounding schema.
      final sqlite = raw.sqlite3.open(file.path);
      try {
        sqlite.execute(
          'ALTER TABLE outbox_operations DROP COLUMN attempted_mutation_json',
        );
        sqlite.execute('PRAGMA user_version = 27');
        expect(
          sqlite
              .select('PRAGMA table_info(outbox_operations)')
              .map((row) => row['name']),
          isNot(contains('attempted_mutation_json')),
        );
        expect(sqlite.select('PRAGMA user_version').single.values.single, 27);
      } finally {
        sqlite.close();
      }
      final database = AppDatabase(NativeDatabase(file));
      try {
        final row = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(row.operationId, 'category:c:1');
        expect(row.state, 'inFlight');
        expect(row.attemptCount, 1);
        expect(row.lastAttemptAtUtcMs, 2);
        expect(row.attemptedMutationJson, isNull);
        expect(
          (await database.customSelect('PRAGMA user_version').getSingle())
              .read<int>('user_version'),
          28,
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
