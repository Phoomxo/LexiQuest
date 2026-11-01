import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../test/support/populated_owner_migration_fixture.dart';

void main() {
  test('capture genuine populated v21 before the profile migration', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(database.schemaVersion, 21);
    expect(database.allTables.length, 40);
    await database.customSelect('SELECT 1').getSingle();
    await database.customStatement('PRAGMA foreign_keys = ON');
    final previous =
        jsonDecode(
              File(
                'test/fixtures/populated_schema_v20.json',
              ).readAsStringSync(),
            )
            as Map<String, dynamic>;
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
      await insertOwnerMigrationRow(database, 'learning_time_preferences', {
        'owner_id': owner,
        'enabled': 1,
        'revision': 1,
        'updated_at_utc_ms': 20,
      });
      await insertOwnerMigrationRow(database, 'learning_time_scopes', {
        'id': 'time-scope:synthetic-v21-capture',
        'owner_id': owner,
        'source_kind': 'reading',
        'source_binding_json':
            '{"version":1,"documentId":"synthetic","revision":1}',
        'created_at_utc_ms': 20,
        'linked_session_id': null,
        'session_link_binding_json': null,
      });
      await insertOwnerMigrationRow(database, 'learning_time_segments', {
        'id': 'time-segment:synthetic-v21-capture',
        'scope_id': 'time-scope:synthetic-v21-capture',
        'ordinal': 0,
        'eligibility_context_json': '{"version":1,"stage":"reading"}',
        'started_at_utc_ms': 20,
        'ended_at_utc_ms': 10,
        'active_duration_us': 1234567,
        'capture_policy_revision': 'confirmed-interaction-v1',
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
    final payload =
        '${const JsonEncoder.withIndent('  ').convert({'schemaVersion': 21, 'sourceCommit': '7c2a02393bb4fd600f2968c5996ce8cdf7773c2f', 'synthetic': true, 'rows': rows})}\n';
    _writeExact('test/fixtures/schema_v21.sql', schema);
    _writeExact('test/fixtures/populated_schema_v21.json', payload);
    expect(File('test/fixtures/schema_v21.sql').readAsStringSync(), schema);
    expect(
      File('test/fixtures/populated_schema_v21.json').readAsStringSync(),
      payload,
    );
    printOnFailure(
      'Captured ${rows.length} genuine v21 tables and '
      '${rows.values.fold<int>(0, (sum, value) => sum + value.length)} synthetic rows.',
    );
  });
}

void _writeExact(String path, String value) {
  final file = File(path);
  if (file.existsSync()) {
    expect(
      file.readAsStringSync(),
      value,
      reason: 'Never overwrite a different capture',
    );
  } else {
    file.writeAsStringSync(value, flush: true);
  }
}
