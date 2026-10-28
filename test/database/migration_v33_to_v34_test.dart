import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vocab_learning_app/data/local/app_database.dart';
import '../support/current_database_contract.dart';

void main() {
  for (final from in [28, 33]) {
    for (final obstruct in [false, true]) {
      test('v$from to v34 preserves history, atomic obstruction=$obstruct', () async {
        final dir = await Directory.systemTemp.createTemp('audio-migration-');
        addTearDown(() => dir.delete(recursive: true));
        final file = File('${dir.path}/db.sqlite');
        var db = AppDatabase(NativeDatabase(file));
        await db.customStatement(
          "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('keep',1,1)",
        );
        await db.customStatement(
          "INSERT INTO outbox_operations(operation_id,owner_id,entity_type,entity_id,operation_kind,state,created_at_utc_ms,attempted_mutation_json) VALUES('op','keep','category','c','upsert','inFlight',1,'{\"keep\":true}')",
        );
        await db.customStatement('DROP TABLE audio_lesson_checkpoints');
        await db.customStatement('PRAGMA user_version=$from');
        await db.close();
        if (obstruct) {
          final raw = sqlite.sqlite3.open(file.path);
          raw.execute(
            'CREATE INDEX audio_lesson_checkpoints ON local_owners(id)',
          );
          raw.close();
          db = AppDatabase(NativeDatabase(file));
          await expectLater(
            db.customSelect('SELECT 1').get(),
            throwsA(anything),
          );
          await db.close();
          final check = sqlite.sqlite3.open(file.path);
          expect(
            check.select('PRAGMA user_version').single['user_version'],
            from,
          );
          expect(
            check.select(
              "SELECT name FROM sqlite_master WHERE type='table' AND name='audio_lesson_checkpoints'",
            ),
            isEmpty,
          );
          check.execute('DROP INDEX audio_lesson_checkpoints');
          check.close();
        }
        db = AppDatabase(NativeDatabase(file));
        try {
          await expectCurrentDatabaseContract(db);
          expect(db.schemaVersion, 34);
          expect(
            (await db.select(db.outboxOperations).get())
                .single
                .attemptedMutationJson,
            '{"keep":true}',
          );
          expect(await db.select(db.audioLessonCheckpoints).get(), isEmpty);
          expect(
            await db.customSelect('PRAGMA foreign_key_check').get(),
            isEmpty,
          );
        } finally {
          await db.close();
        }
      });
    }
  }
}
