import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v17_to_v18_test.dart' as fixture;

void main() {
  test('frozen v18 adds only goals and reserved reminders', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: createSchemaEighteenFixture),
    );
    addTearDown(database.close);

    expect(AppDatabase.currentSchemaVersion, 19);
    expect(currentDatabaseTableInventory, hasLength(42));
    expect(
      currentDatabaseTableInventory.difference(schemaEighteenInventory),
      const {'learning_goals', 'study_reminders'},
    );
    await expectCurrentDatabaseContract(database);
    expect(await _count(database, 'learning_goals'), 0);
    expect(await _count(database, 'study_reminders'), 0);
  });

  test('goal schema pins typed deadline and sync lifecycle fields', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: createSchemaEighteenFixture),
    );
    addTearDown(database.close);

    expect(await _columnNames(database, 'learning_goals'), const [
      'id',
      'owner_id',
      'kind',
      'title',
      'deadline_at_utc_ms',
      'timezone_id',
      'timezone_offset_minutes',
      'status',
      'created_at_utc_ms',
      'updated_at_utc_ms',
      'local_revision',
      'cloud_revision',
      'last_acknowledged_at_utc_ms',
      'server_updated_at_utc_ms',
      'is_deleted',
    ]);
    expect(await _foreignKeys(database, 'learning_goals'), {
      'owner_id->local_owners.id',
    });
    expect(await _uniqueColumnSets(database, 'learning_goals'), {'id'});
  });

  test('reserved reminder schema is owner-scoped and goal-linked', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: createSchemaEighteenFixture),
    );
    addTearDown(database.close);

    expect(
      await _columnNames(database, 'study_reminders'),
      containsAll([
        'id',
        'owner_id',
        'goal_id',
        'scheduled_at_utc_ms',
        'timezone_id',
        'timezone_offset_minutes',
        'is_enabled',
        'is_deleted',
      ]),
    );
    expect(await _foreignKeys(database, 'study_reminders'), {
      'goal_id->learning_goals.id',
      'owner_id->local_owners.id',
    });
  });
}

final schemaEighteenInventory = currentDatabaseTableInventory.difference(const {
  'learning_goals',
  'study_reminders',
});

void createSchemaEighteenFixture(dynamic sqlite) {
  fixture.createSchemaSeventeenFixture(sqlite);
  sqlite.execute('''
    CREATE TABLE learning_time_segments (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      session_id TEXT NOT NULL REFERENCES learning_sessions(id) ON DELETE CASCADE,
      active_start_offset_ms INTEGER NOT NULL,
      active_duration_ms INTEGER NOT NULL,
      started_at_utc_ms INTEGER NOT NULL,
      ended_at_utc_ms INTEGER NOT NULL,
      timezone_id TEXT NOT NULL,
      timezone_offset_minutes INTEGER NOT NULL,
      capture_source TEXT NOT NULL,
      UNIQUE(session_id, active_start_offset_ms)
    )
  ''');
  sqlite.execute('PRAGMA user_version = 18');
}

Future<List<String>> _columnNames(AppDatabase database, String tableName) =>
    database
        .customSelect("PRAGMA table_info('$tableName')")
        .map((row) => row.read<String>('name'))
        .get();

Future<Set<String>> _foreignKeys(
  AppDatabase database,
  String tableName,
) async =>
    (await database.customSelect("PRAGMA foreign_key_list('$tableName')").get())
        .map(
          (row) =>
              '${row.read<String>('from')}->'
              '${row.read<String>('table')}.${row.read<String>('to')}',
        )
        .toSet();

Future<Set<String>> _uniqueColumnSets(
  AppDatabase database,
  String tableName,
) async {
  final indexes = await database
      .customSelect("PRAGMA index_list('$tableName')")
      .get();
  final result = <String>{};
  for (final index in indexes.where((row) => row.read<int>('unique') == 1)) {
    final name = index.read<String>('name').replaceAll("'", "''");
    final columns = await database
        .customSelect("PRAGMA index_info('$name')")
        .get();
    columns.sort(
      (left, right) =>
          left.read<int>('seqno').compareTo(right.read<int>('seqno')),
    );
    result.add(columns.map((row) => row.read<String>('name')).join(','));
  }
  return result;
}

Future<int> _count(AppDatabase database, String tableName) => database
    .customSelect('SELECT COUNT(*) AS count FROM $tableName')
    .map((row) => row.read<int>('count'))
    .getSingle();
