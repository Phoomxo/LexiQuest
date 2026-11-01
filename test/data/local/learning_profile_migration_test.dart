import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'populated genuine v21 migrates to current schema and reopens intact',
    () async {
      final previous =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v21.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(previous['schemaVersion'], 21);
      final rows = previous['rows'] as Map<String, dynamic>;
      expect(rows.length, 40);
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-profile-v21-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            sqlite.execute(
              File('test/fixtures/schema_v21.sql').readAsStringSync(),
            );
            sqlite.execute('PRAGMA foreign_keys = ON');
            sqlite.execute('BEGIN');
            sqlite.execute('PRAGMA defer_foreign_keys = ON');
            for (final entry in rows.entries) {
              for (final value in entry.value as List) {
                final row = Map<String, Object?>.from(value as Map);
                sqlite.execute(
                  'INSERT INTO "${entry.key}" (${row.keys.join(',')}) '
                  'VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values.toList(),
                );
              }
            }
            sqlite.execute('COMMIT');
            sqlite.execute('PRAGMA user_version = 21');
          },
        ),
      );
      AppDatabase? reopened;
      var closed = false;
      addTearDown(() async {
        await reopened?.close();
        if (!closed) await database.close();
        final resolved = await directory.resolveSymbolicLinks();
        final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-profile-v21-',
          ),
        );
        expect(File(file.path).parent.absolute.path, directory.absolute.path);
        await directory.delete(recursive: true);
      });
      expect(database.schemaVersion, 23);
      final after = await ownerMigrationRows(database);
      expect(after.length, 43);
      for (final old in rows.entries) {
        expect(after[old.key], old.value, reason: old.key);
      }
      expect(after['learning_profiles'], isEmpty);
      expect(after['learning_pack_versions'], isEmpty);
      expect(after['lexical_content_snapshots'], isEmpty);
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      await database.close();
      closed = true;
      reopened = AppDatabase(NativeDatabase(file));
      expect(await ownerMigrationRows(reopened), after);
      expect(
        (await reopened.customSelect('PRAGMA integrity_check').getSingle())
            .read<String>('integrity_check'),
        'ok',
      );
    },
  );
}
