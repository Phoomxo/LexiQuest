import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test('capture actual fresh v11 SQLite schema', () async {
    final db = AppDatabase(NativeDatabase.memory());
    try {
      if (db.schemaVersion != 11) {
        throw StateError('Source schema is not v11');
      }
      final version = await db.customSelect('PRAGMA user_version').getSingle();
      if (version.read<int>('user_version') != 11) {
        throw StateError('Opened database is not v11');
      }
      final objects = await db
          .customSelect(
            "SELECT type, name, sql FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' AND sql IS NOT NULL ORDER BY name",
          )
          .get();
      final tables = <String, String>{};
      final indexes = <String, String>{};
      for (final row in objects) {
        final type = row.read<String>('type');
        final name = row.read<String>('name');
        final sql = row.read<String>('sql').trim();
        if (type == 'table') {
          tables[name] = sql;
        } else if (type == 'index') {
          indexes[name] = sql;
        } else {
          throw StateError('Unsupported schema object $type: $name');
        }
      }
      if (tables.length != 34) {
        throw StateError('Expected 34 v11 tables, found ${tables.length}');
      }
      final pending = Map<String, String>.of(tables);
      final ordered = <String>[];
      final emitted = <String>{};
      final dependencies = <String, Set<String>>{};
      for (final name in tables.keys) {
        final escaped = name.replaceAll('"', '""');
        final rows = await db
            .customSelect('PRAGMA foreign_key_list("$escaped")')
            .get();
        final parents = rows
            .map((row) => row.read<String>('table'))
            .where((parent) => parent != name)
            .toSet();
        if (!tables.keys.toSet().containsAll(parents)) {
          throw StateError('Missing referenced table for $name');
        }
        dependencies[name] = parents;
      }
      while (pending.isNotEmpty) {
        final ready =
            pending.keys
                .where((name) => emitted.containsAll(dependencies[name]!))
                .toList()
              ..sort();
        if (ready.isEmpty) {
          throw StateError(
            'Foreign key cycle requires manual fixture ordering',
          );
        }
        for (final name in ready) {
          ordered.add(pending.remove(name)!);
          emitted.add(name);
        }
      }
      final buffer = StringBuffer(
        '-- Fresh AppDatabase v11; schema only, no user rows.\n',
      );
      buffer.writeln('BEGIN;');
      for (final sql in [...ordered, ...indexes.values]) {
        buffer.writeln(sql.endsWith(';') ? sql : '$sql;');
      }
      buffer.writeln('PRAGMA user_version = 11;');
      buffer.writeln('COMMIT;');
      await File('build/schema_v11.sql').writeAsString(buffer.toString());
    } finally {
      await db.close();
    }
  });

  test('compare migrated v10 and captured v11 schema', () async {
    final v10Schema = File(
      'test/fixtures/database/v10/schema.sql',
    ).readAsStringSync();
    final v10Indexes = File(
      'test/fixtures/database/v10/runtime_indexes.sql',
    ).readAsStringSync();
    final captured = File('build/schema_v11.sql').readAsStringSync();
    final upgraded = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('PRAGMA foreign_keys = ON');
          raw.execute(v10Schema);
          raw.execute(v10Indexes);
          raw.execute('PRAGMA user_version = 10');
        },
      ),
    );
    final restored = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
          raw.execute('PRAGMA foreign_keys = ON');
          raw.execute(captured);
        },
      ),
    );
    try {
      final actual = await _schemaFacts(upgraded);
      final expected = await _schemaFacts(restored);
      for (final table in {...actual.keys, ...expected.keys}.toList()..sort()) {
        if (actual[table] != expected[table]) {
          // Each value is a deterministic JSON string, so a difference is inspectable.
          stdout.writeln(
            'SCHEMA DIFFERENCE $table\n  migrated: ${actual[table]}\n  captured: ${expected[table]}',
          );
        }
      }
      expect(
        actual,
        expected,
        reason: 'Fresh v11 capture must match real v10 migration semantics',
      );
    } finally {
      await upgraded.close();
      await restored.close();
    }
  });
}

Future<Map<String, String>> _schemaFacts(AppDatabase db) async {
  final version = await db.customSelect('PRAGMA user_version').getSingle();
  if (version.read<int>('user_version') != 11) {
    throw StateError('Expected v11 after opening');
  }
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  if (tables.length != 34) {
    throw StateError('Expected 34 tables; got ${tables.length}');
  }
  final result = <String, String>{};
  for (final table in tables) {
    final name = table.read<String>('name');
    final q = name.replaceAll('"', '""');
    final columns = await db.customSelect('PRAGMA table_info("$q")').get();
    final fks = await db.customSelect('PRAGMA foreign_key_list("$q")').get();
    final indexes = await db.customSelect('PRAGMA index_list("$q")').get();
    final facts = <String>[];
    for (final row in columns) {
      facts.add(
        'column:${row.read<String>('name')}:${row.read<String>('type')}:${row.read<int>('notnull')}:${row.data['dflt_value']}:${row.read<int>('pk')}',
      );
    }
    for (final row in fks) {
      facts.add(
        'fk:${row.read<String>('table')}:${row.read<String>('from')}:${row.read<String>('to')}:${row.read<String>('on_update')}:${row.read<String>('on_delete')}:${row.read<String>('match')}',
      );
    }
    for (final row in indexes) {
      final index = row.read<String>('name');
      final iq = index.replaceAll('"', '""');
      final parts = await db.customSelect('PRAGMA index_xinfo("$iq")').get();
      final sqlRows = await db
          .customSelect(
            'SELECT sql FROM sqlite_master WHERE type = ? AND name = ?',
            variables: [Variable('index'), Variable(index)],
          )
          .get();
      final sql = sqlRows.single.data['sql'];
      final signature = parts
          .where((p) => p.read<int>('key') == 1)
          .map(
            (p) =>
                '${p.read<int>('seqno')}:${p.data['name']}:${p.read<int>('desc')}:${p.data['coll']}',
          )
          .join('|');
      facts.add(
        'index:${row.read<String>('origin')}:${row.read<int>('unique')}:${row.read<int>('partial')}:$signature:${sql ?? '<implicit>'}',
      );
    }
    facts.sort();
    result[name] = facts.join('\n');
  }
  final violations = await db.customSelect('PRAGMA foreign_key_check').get();
  if (violations.isNotEmpty) throw StateError('Foreign key violations in $db');
  return result;
}
