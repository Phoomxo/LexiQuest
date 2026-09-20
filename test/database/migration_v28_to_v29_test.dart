import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vocab_learning_app/data/local/app_database.dart';
import '../support/current_database_contract.dart';

const extensions = <String>[
  'personal_set_members',
  'personal_set_revisions',
  'audio_lesson_checkpoints',
  'speaking_practice_results',
  'written_practice_results',
  'guided_repair_operations',
  'study_plan_revisions',
  'active_plan_pointers',
];

void main() {
  for (final obstruct in [false, true]) {
    test(
      'schema28 adds all extensions atomically and preserves sync; obstruction=$obstruct',
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
        for (final table in extensions) {
          sqlite.execute('DROP TABLE $table');
        }
        sqlite.execute('PRAGMA user_version = 28');
        expect(
          sqlite.select(
            "SELECT name FROM sqlite_master WHERE name LIKE 'personal_set_%'",
          ),
          isEmpty,
        );
        if (obstruct) {
          sqlite.execute(
            'CREATE INDEX active_plan_pointers ON local_owners(id)',
          );
        }
        sqlite.close();
        if (obstruct) {
          final failed = AppDatabase(NativeDatabase(file));
          await expectLater(
            failed.customSelect('SELECT 1').get(),
            throwsA(anything),
          );
          await failed.close();
          final inspect = raw.sqlite3.open(file.path);
          try {
            expect(
              inspect.select('PRAGMA user_version').single['user_version'],
              28,
            );
            for (final table in extensions) {
              expect(
                inspect.select(
                  "SELECT name FROM sqlite_master WHERE type='table' AND name=?",
                  [table],
                ),
                isEmpty,
                reason: 'Failed extension migration must roll back $table',
              );
            }
            expect(
              inspect
                  .select(
                    'SELECT attempted_mutation_json FROM outbox_operations',
                  )
                  .single['attempted_mutation_json'],
              '{"pinned":true}',
            );
          } finally {
            inspect.execute('DROP INDEX active_plan_pointers');
            inspect.close();
          }
        }
        final database = AppDatabase(NativeDatabase(file));
        try {
          await expectCurrentDatabaseContract(database);
          expect(AppDatabase.currentSchemaVersion, 34);
          for (final table in extensions) {
            expect(
              await database.customSelect('SELECT * FROM $table').get(),
              isEmpty,
            );
          }
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
}
