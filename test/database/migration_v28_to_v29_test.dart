import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vocab_learning_app/data/local/app_database.dart';
import '../support/current_database_contract.dart';

void main() {
  test(
    'raw28 adds empty personal sets and preserves pending sync snapshot',
    () async {
      final directory = await Directory.systemTemp.createTemp('sets-v28-');
      final file = File('${directory.path}/data.sqlite');
      final initial = AppDatabase(NativeDatabase(file));
      await initial.customStatement(
        "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('owner', 1)",
      );
      await initial.customStatement(
        "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, state, attempt_count, created_at_utc_ms, attempted_mutation_json) VALUES ('op', 'owner', 'category', 'c', 'upsert', 'inFlight', 1, 1, '{\"pinned\":true}')",
      );
      await initial.close();
      final sqlite = raw.sqlite3.open(file.path);
      sqlite.execute('DROP TABLE personal_set_members');
      sqlite.execute('DROP TABLE personal_set_revisions');
      sqlite.execute('PRAGMA user_version = 28');
      expect(
        sqlite.select(
          "SELECT name FROM sqlite_master WHERE name LIKE 'personal_set_%'",
        ),
        isEmpty,
      );
      sqlite.close();
      final database = AppDatabase(NativeDatabase(file));
      try {
        await expectCurrentDatabaseContract(database);
        expect(AppDatabase.currentSchemaVersion, 34);
        final row = await database
            .select(database.outboxOperations)
            .getSingle();
        expect(row.attemptedMutationJson, '{"pinned":true}');
        expect(row.state, 'inFlight');
        expect(row.attemptCount, 1);
        expect(
          await database.select(database.personalSetRevisions).get(),
          isEmpty,
        );
        expect(
          await database.select(database.personalSetMembers).get(),
          isEmpty,
        );
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
      } finally {
        await database.close();
        await directory.delete(recursive: true);
      }
    },
  );
}
