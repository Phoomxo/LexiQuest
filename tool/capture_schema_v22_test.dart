import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../test/support/populated_owner_migration_fixture.dart';

void main() {
  test('capture genuine populated v22 before the pack migration', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(database.schemaVersion, 22);
    expect(database.allTables.length, 41);
    await database.customSelect('SELECT 1').getSingle();
    await database.customStatement('PRAGMA foreign_keys = ON');
    final previous =
        jsonDecode(
              File(
                'test/fixtures/populated_schema_v21.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
    expect(previous['schemaVersion'], 21);
    final oldRows = previous['rows'] as Map<String, dynamic>;
    await database.transaction(() async {
      await database.customStatement('PRAGMA defer_foreign_keys = ON');
      for (final entry in oldRows.entries) {
        for (final row in entry.value as List) {
          await insertOwnerMigrationRow(
            database,
            entry.key,
            Map<String, Object?>.from(row as Map),
          );
        }
      }
      final owner = ((oldRows['local_owners'] as List).first as Map)['id'];
      await insertOwnerMigrationRow(database, 'learning_profiles', {
        'owner_id': owner,
        'revision': 1,
        'onboarding_state': 'completed',
        'goal_text': 'Synthetic retained profile',
        'target_date': '2026-12-31',
        'daily_minutes': 25,
        'interest_codes_json': '{"schemaVersion":1,"codes":["study"]}',
        'updated_at_utc_ms': 20,
      });
    });
    final rows = await ownerMigrationRows(database);
    for (final old in oldRows.entries) {
      expect(rows[old.key], old.value, reason: old.key);
    }
    expect(rows.values.every((value) => value.isNotEmpty), isTrue);
    expect(
      await database.customSelect('PRAGMA foreign_key_check').get(),
      isEmpty,
    );
    expect(
      (await database.customSelect('PRAGMA integrity_check').getSingle())
          .read<String>('integrity_check'),
      'ok',
    );
    final ddl = await database
        .customSelect(
          "SELECT sql FROM sqlite_master WHERE type IN ('table','index','trigger') "
          "AND sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY type DESC,name",
        )
        .get();
    final schema =
        '${ddl.map((row) => '${row.read<String>('sql')};').join('\n')}\n';
    final generated = File(
      'lib/data/local/app_database.g.dart',
    ).readAsBytesSync();
    final payload =
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 22, 'sourceBaselineCommit': '7c2a02393bb4fd600f2968c5996ce8cdf7773c2f', 'sourceState': 'uncommitted-wave24-v22-before-pack-migration', 'databaseGeneratedSourceSha256': sha256.convert(generated).toString(), 'synthetic': true, 'rows': rows})}\n';
    _writeExact('test/fixtures/schema_v22.sql', schema);
    _writeExact('test/fixtures/populated_schema_v22.json', payload);
  });
}

void _writeExact(String path, String value) {
  final file = File(path);
  if (file.existsSync()) {
    expect(file.readAsStringSync(), value, reason: 'Never replace a capture');
  } else {
    file.writeAsStringSync(value, flush: true);
  }
  expect(file.readAsStringSync(), value);
}
