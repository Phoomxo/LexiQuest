import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'genuine populated v23 retains every old fact through periods v24',
    () async {
      final previous =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v23.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      expect(previous['schemaVersion'], 23);
      final rows = previous['rows'] as Map<String, dynamic>;
      expect(rows.length, 43);
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-periods-v23-',
      );
      final file = File('${directory.path}/synthetic.sqlite');
      final oldObjects = <String, String>{};
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            sqlite.execute(
              File('test/fixtures/schema_v23.sql').readAsStringSync(),
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
            sqlite.execute('PRAGMA user_version = 23');
          },
        ),
      );
      AppDatabase? reopened;
      var closed = false;
      addTearDown(() async {
        await reopened?.close();
        if (!closed) await database.close();
        final resolved = await directory.resolveSymbolicLinks();
        final temp = await Directory.systemTemp.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith('$temp${Platform.pathSeparator}lexiquest-periods-v23-'),
        );
        expect(file.parent.absolute.path, directory.absolute.path);
        await directory.delete(recursive: true);
      });
      expect(database.schemaVersion, 25);
      final after =
          jsonDecode(jsonEncode(await ownerMigrationRows(database)))
              as Map<String, dynamic>;
      expect(after.length, 45);
      expect(after['content_reports'], isEmpty);
      expect(after['study_reminder_preferences'], isEmpty);
      for (final entry in rows.entries) {
        final actual = after[entry.key] as List;
        final original = entry.value as List;
        expect(actual.length, original.length, reason: entry.key);
        for (var i = 0; i < original.length; i++) {
          final old = original[i] as Map;
          final migrated = actual[i] as Map;
          expect(
            {for (final key in old.keys) key: migrated[key]},
            old,
            reason: '${entry.key} row$i',
          );
          if (entry.key == 'quest_instances') {
            expect(migrated['period_key'], 'legacy:${old['instance_id']}');
            expect(migrated['period_json'], isNull);
            expect(migrated['definition_snapshot_json'], isNull);
            expect(migrated['definition_sha256'], isNull);
          }
          if (entry.key == 'learning_day_log') {
            expect(migrated['source_attempt_id'], isNull);
            expect(migrated['timezone_id'], isNull);
            expect(migrated['policy_version'], isNull);
          }
          if (entry.key == 'learning_profiles') {
            expect(migrated['learning_timezone_id'], isNull);
          }
        }
      }
      final objects = await database
          .customSelect(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final current = {
        for (final row in objects)
          row.read<String>('name'): row.read<String>('sql'),
      };
      expect(current.keys.toSet(), {
        ...oldObjects.keys,
        'content_reports',
        'study_reminder_preferences',
        'idx_content_reports_owner_queue',
      });
      for (final object in oldObjects.entries) {
        if (!{
          'quest_instances',
          'learning_day_log',
          'learning_profiles',
          'learning_time_scopes',
        }.contains(object.key)) {
          expect(current[object.key], object.value, reason: object.key);
        }
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      expect(
        (await database.customSelect('PRAGMA integrity_check').getSingle())
            .read<String>('integrity_check'),
        'ok',
      );
      await database.close();
      closed = true;
      reopened = AppDatabase(NativeDatabase(file));
      expect(jsonDecode(jsonEncode(await ownerMigrationRows(reopened))), after);
      expect(
        await reopened.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}
