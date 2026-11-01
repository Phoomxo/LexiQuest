import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'genuine populated v24 preserves every fact and time child through v25 reopen',
    () async {
      final fixture =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v24.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(fixture['schemaVersion'], 24);
      final rows = fixture['rows'] as Map<String, dynamic>;
      expect(rows.length, 43);
      final ddl = File('test/fixtures/schema_v24.sql').readAsStringSync();
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-v24-report-migration-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      AppDatabase? database;
      addTearDown(() async {
        await database?.close();
        final root = await Directory.systemTemp.resolveSymbolicLinks();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$root${Platform.pathSeparator}lexiquest-v24-report-migration-',
          ),
        );
        for (final entity in directory.listSync()) {
          expect(entity, isA<File>());
          expect(entity.parent.absolute.path, directory.absolute.path);
          await entity.delete();
        }
        await directory.delete();
      });
      database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            sqlite.execute(ddl);
            sqlite.execute('PRAGMA foreign_keys = ON');
            sqlite.execute('BEGIN');
            sqlite.execute('PRAGMA defer_foreign_keys = ON');
            for (final table in rows.entries) {
              for (final raw in table.value as List) {
                final row = raw as Map<String, dynamic>;
                sqlite.execute(
                  'INSERT INTO "${table.key}" (${row.keys.join(',')}) '
                  'VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values
                      .map(
                        (value) => value is List
                            ? Uint8List.fromList(value.cast<int>())
                            : value,
                      )
                      .toList(),
                );
              }
            }
            sqlite.execute('COMMIT');
            sqlite.execute('PRAGMA user_version = 24');
          },
        ),
      );
      final migrated =
          jsonDecode(jsonEncode(await ownerMigrationRows(database))) as Map;
      expect(database.schemaVersion, 25);
      expect(migrated.length, 45);
      for (final table in rows.entries) {
        expect(migrated[table.key], table.value, reason: table.key);
      }
      expect(migrated['content_reports'], isEmpty);
      expect(migrated['study_reminder_preferences'], isEmpty);
      expect(rows['learning_time_segments'], isNotEmpty);
      await _healthy(database);
      final beforeReopen = await _schema(database);
      final historicalTables = RegExp(
        r'CREATE TABLE "([^"]+)"',
      ).allMatches(ddl).map((match) => match.group(1)!).toSet();
      for (final table in historicalTables) {
        final old = ddl
            .split('\n')
            .firstWhere((line) => line.startsWith('CREATE TABLE "$table"'));
        final current = beforeReopen[table]!;
        if (table == 'learning_time_scopes') {
          expect(current, contains("'matching'"));
          expect(
            current.replaceAll(",'matching'", ''),
            old.substring(0, old.length - 1),
          );
        } else {
          expect(current, old.substring(0, old.length - 1), reason: table);
        }
      }
      await database.close();
      database = AppDatabase(NativeDatabase(file));
      expect(
        jsonDecode(jsonEncode(await ownerMigrationRows(database))),
        migrated,
      );
      expect(await _schema(database), beforeReopen);
      await _healthy(database);
    },
  );
}

Future<void> _healthy(AppDatabase database) async {
  expect(
    await database.customSelect('PRAGMA foreign_key_check').get(),
    isEmpty,
  );
  expect(
    (await database.customSelect('PRAGMA integrity_check').getSingle())
        .read<String>('integrity_check'),
    'ok',
  );
}

Future<Map<String, String>> _schema(AppDatabase database) async => {
  for (final row
      in await database
          .customSelect(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get())
    row.read<String>('name'): row.read<String>('sql'),
};
