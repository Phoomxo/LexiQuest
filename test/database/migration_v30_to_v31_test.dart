import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  for (final obstruct in [false, true]) {
    test('schema30 upgrade retains data; obstruction=$obstruct', () async {
      final dir = await Directory.systemTemp.createTemp(
        'guided-repair-migration-',
      );
      addTearDown(() => dir.delete(recursive: true));
      final file = File('${dir.path}/db.sqlite');
      var db = AppDatabase(NativeDatabase(file));
      await db.customStatement(
        "INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES('keep',1,1)",
      );
      await db.customStatement('DROP TABLE guided_repair_operations');
      await db.customStatement('PRAGMA user_version=30');
      await db.close();
      if (obstruct) {
        final raw = sqlite.sqlite3.open(file.path);
        raw.execute(
          'CREATE INDEX guided_repair_operations ON local_owners(id)',
        );
        raw.close();
        db = AppDatabase(NativeDatabase(file));
        await expectLater(db.customSelect('SELECT 1').get(), throwsA(anything));
        await db.close();
        final inspect = sqlite.sqlite3.open(file.path);
        expect(
          inspect.select('PRAGMA user_version').single['user_version'],
          30,
        );
        expect(
          inspect.select(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='guided_repair_operations'",
          ),
          isEmpty,
        );
        expect(
          inspect.select('SELECT id FROM local_owners').single['id'],
          'keep',
        );
        inspect.execute('DROP INDEX guided_repair_operations');
        inspect.close();
      }
      db = AppDatabase(NativeDatabase(file));
      try {
        expect(await db.select(db.guidedRepairOperations).get(), isEmpty);
        expect((await db.select(db.localOwners).get()).single.id, 'keep');
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).read<int>(
            'user_version',
          ),
          AppDatabase.currentSchemaVersion,
        );
      } finally {
        await db.close();
      }
    });
  }
}
