import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test('populated genuine v22 migrates to packs v23 and reopens intact', () async {
    final previous =
        jsonDecode(
              File(
                'test/fixtures/populated_schema_v22.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(previous['schemaVersion'], 22);
    final rows = previous['rows'] as Map<String, dynamic>;
    expect(rows.length, 41);
    final directory = await Directory.systemTemp.createTemp(
      'lexiquest-packs-v22-',
    );
    final file = File('${directory.path}/synthetic.sqlite');
    final oldObjects = <String, String>{};
    final database = AppDatabase(
      NativeDatabase(
        file,
        setup: (sqlite) {
          sqlite.execute(
            File('test/fixtures/schema_v22.sql').readAsStringSync(),
          );
          for (final object in sqlite.select(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )) {
            oldObjects[object['name']! as String] = object['sql']! as String;
          }
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
          sqlite.execute('PRAGMA user_version = 22');
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
        startsWith('$tempRoot${Platform.pathSeparator}lexiquest-packs-v22-'),
      );
      expect(File(file.path).parent.absolute.path, directory.absolute.path);
      await directory.delete(recursive: true);
    });
    expect(database.schemaVersion, 25);
    final after = await ownerMigrationRows(database);
    expect(after.length, 45);
    expectHistoricalOwnerMigrationRows(after, {
      for (final table in rows.entries)
        table.key: [
          for (final row in table.value as List)
            Map<String, Object?>.from(row as Map),
        ],
    });
    expect(after['learning_pack_versions'], isEmpty);
    expect(after['lexical_content_snapshots'], isEmpty);
    expect(after['content_reports'], isEmpty);
    expect(after['study_reminder_preferences'], isEmpty);
    final objects = await database
        .customSelect(
          "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
        )
        .get();
    final byName = {
      for (final row in objects)
        row.read<String>('name'): row.read<String>('sql'),
    };
    expect(byName.keys.toSet(), {
      ...oldObjects.keys,
      'learning_pack_versions',
      'lexical_content_snapshots',
      'idx_lexical_content_owner_word',
      'content_reports',
      'study_reminder_preferences',
      'idx_content_reports_owner_queue',
    });
    expectHistoricalMigrationObjects(oldObjects, byName);
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
  });
}
