import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v16_to_v17_test.dart' as fixture;

void main() {
  test('frozen v17 adds only immutable learning-time segments', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: createSchemaSeventeenFixture),
    );
    addTearDown(database.close);

    expect(AppDatabase.currentSchemaVersion, 22);
    expect(schemaEighteenInventory, hasLength(40));
    expect(schemaEighteenInventory.difference(schemaSeventeenInventory), const {
      'learning_time_segments',
    });
    await expectCurrentDatabaseContract(database);

    expect(await _count(database, 'learning_time_segments'), 0);
    expect(
      await database
          .customSelect(
            "SELECT spelling FROM vocabulary_words WHERE id = 'word:v13'",
          )
          .map((row) => row.read<String>('spelling'))
          .getSingle(),
      'lexicon',
    );
  });

  test(
    'learning-time schema separates wall context from active duration',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaSeventeenFixture),
      );
      addTearDown(database.close);

      expect(await _columnNames(database, 'learning_time_segments'), const [
        'id',
        'owner_id',
        'session_id',
        'active_start_offset_ms',
        'active_duration_ms',
        'started_at_utc_ms',
        'ended_at_utc_ms',
        'timezone_id',
        'timezone_offset_minutes',
        'capture_source',
      ]);
      expect(await _foreignKeys(database, 'learning_time_segments'), {
        'owner_id->local_owners.id',
        'session_id->learning_sessions.id',
      });
      expect(await _uniqueColumnSets(database, 'learning_time_segments'), {
        'id',
        'session_id,active_start_offset_ms',
      });
    },
  );
}

final schemaSeventeenInventory = currentDatabaseTableInventory
    .difference(const {
      'learning_time_segments',
      'learning_goals',
      'study_reminders',
      'session_configurations',
      'learner_preferences',
    });

final schemaEighteenInventory = currentDatabaseTableInventory.difference(const {
  'learning_goals',
  'study_reminders',
  'session_configurations',
  'learner_preferences',
});

void createSchemaSeventeenFixture(dynamic sqlite) {
  fixture.createSchemaSixteenFixture(sqlite);
  sqlite.execute('''
    CREATE TABLE saved_learning_items (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      content_type TEXT NOT NULL,
      content_id TEXT NOT NULL,
      content_revision INTEGER NOT NULL,
      saved_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      UNIQUE(owner_id, content_type, content_id, content_revision)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE content_quality_reports (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      content_type TEXT NOT NULL,
      content_id TEXT NOT NULL,
      content_revision INTEGER NOT NULL,
      reason_code TEXT NOT NULL,
      comment TEXT,
      submitted_at_utc_ms INTEGER NOT NULL
    )
  ''');
  sqlite.execute('PRAGMA user_version = 17');
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
