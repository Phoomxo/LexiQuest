import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v19_to_v20_test.dart' as fixture;

void main() {
  test(
    'f35 frozen v20 adds only learner preferences and preserves all data',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaTwentyFixture),
      );
      addTearDown(database.close);

      expect(AppDatabase.currentSchemaVersion, 22);
      expect(currentDatabaseTableInventory, hasLength(44));
      expect(currentDatabaseTableInventory.difference(schemaTwentyInventory), {
        'learner_preferences',
      });
      await expectCurrentDatabaseContract(database);
      expect(await _count(database, 'learner_preferences'), 0);
      expect(
        await database
            .customSelect(
              "SELECT title FROM learning_goals WHERE id = 'goal:v19'",
            )
            .map((row) => row.read<String>('title'))
            .getSingle(),
        'Keep this goal',
      );
      expect(
        await database
            .customSelect(
              'SELECT stable_serialization FROM session_configurations '
              "WHERE owner_id = 'owner:v19' AND mode = 'quiz'",
            )
            .map((row) => row.read<String>('stable_serialization'))
            .getSingle(),
        '{"mode":"quiz","version":1}',
      );
    },
  );

  test(
    'f35 learner preferences has the exact owner and sync contract',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaTwentyFixture),
      );
      addTearDown(database.close);

      expect(await _columnNames(database, 'learner_preferences'), const [
        'owner_id',
        'preference_version',
        'goal',
        'available_minutes_per_day',
        'activity_preference',
        'updated_at_utc_ms',
        'theme_mode',
        'motion_mode',
        'display_updated_at_utc_ms',
        'local_revision',
        'cloud_revision',
        'last_acknowledged_at_utc_ms',
        'server_updated_at_utc_ms',
        'is_deleted',
      ]);
      expect(await _foreignKeys(database, 'learner_preferences'), {
        'owner_id->local_owners.id',
      });
      expect(await _primaryKey(database, 'learner_preferences'), ['owner_id']);
      expect(
        await _tableNames(database),
        currentDatabaseTableInventory,
        reason:
            'v22 extends the one preference table without a second authority',
      );
      expect(
        await _tableNames(database),
        isNot(containsAll({'learning_styles', 'personality_profiles'})),
      );
    },
  );
}

final schemaTwentyInventory = currentDatabaseTableInventory.difference(const {
  'learner_preferences',
});

void createSchemaTwentyFixture(dynamic sqlite) {
  fixture.createSchemaNineteenFixture(sqlite);
  sqlite.execute(
    'ALTER TABLE learning_sessions '
    'ADD COLUMN session_configuration_identity TEXT',
  );
  sqlite.execute(
    'ALTER TABLE learning_sessions '
    'ADD COLUMN session_configuration_json TEXT',
  );
  sqlite.execute(
    'ALTER TABLE learning_sessions ADD COLUMN '
    'configuration_active_effort_us INTEGER NOT NULL DEFAULT 0',
  );
  sqlite.execute('''
    CREATE TABLE session_configurations (
      owner_id TEXT NOT NULL REFERENCES local_owners(id) ON DELETE CASCADE,
      mode TEXT NOT NULL,
      content_identity TEXT NOT NULL,
      stable_serialization TEXT NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      PRIMARY KEY(owner_id, mode)
    )
  ''');
  sqlite.execute(
    "INSERT INTO session_configurations "
    "(owner_id, mode, content_identity, stable_serialization, "
    "updated_at_utc_ms) VALUES "
    "('owner:v19', 'quiz', 'pack:v19@1', "
    "'{\"mode\":\"quiz\",\"version\":1}', 1787702400000)",
  );
  sqlite.execute('PRAGMA user_version = 20');
}

Future<Set<String>> _tableNames(AppDatabase database) => database
    .customSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )
    .map((row) => row.read<String>('name'))
    .get()
    .then((rows) => rows.toSet());

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

Future<List<String>> _primaryKey(AppDatabase database, String tableName) async {
  final rows = await database
      .customSelect("PRAGMA table_info('$tableName')")
      .get();
  final primary = rows.where((row) => row.read<int>('pk') > 0).toList()
    ..sort(
      (left, right) => left.read<int>('pk').compareTo(right.read<int>('pk')),
    );
  return primary.map((row) => row.read<String>('name')).toList();
}

Future<int> _count(AppDatabase database, String tableName) => database
    .customSelect('SELECT COUNT(*) AS count FROM $tableName')
    .map((row) => row.read<int>('count'))
    .getSingle();
