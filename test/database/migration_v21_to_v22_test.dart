import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v20_to_v21_test.dart' as fixture;

void main() {
  test(
    'f39 frozen v21 adds display columns only and preserves all rows',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaTwentyOneFixture),
      );
      addTearDown(database.close);

      expect(AppDatabase.currentSchemaVersion, 22);
      expect(currentDatabaseTableInventory, hasLength(44));
      await expectCurrentDatabaseContract(database);
      expect(await _tableNames(database), currentDatabaseTableInventory);
      expect((await _columnNames(database, 'learner_preferences')).toSet(), {
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
      });

      final row = await database
          .customSelect(
            'SELECT owner_id, goal, available_minutes_per_day, '
            'activity_preference, updated_at_utc_ms, theme_mode, motion_mode, '
            'display_updated_at_utc_ms FROM learner_preferences',
          )
          .getSingle();
      expect(row.data, {
        'owner_id': 'owner:v19',
        'goal': 'examPreparation',
        'available_minutes_per_day': 45,
        'activity_preference': 'quiz',
        'updated_at_utc_ms': 1788048000000,
        'theme_mode': 'system',
        'motion_mode': 'system',
        'display_updated_at_utc_ms': 0,
      });
    },
  );
}

void createSchemaTwentyOneFixture(dynamic sqlite) {
  fixture.createSchemaTwentyFixture(sqlite);
  sqlite.execute('''
    CREATE TABLE learner_preferences (
      owner_id TEXT NOT NULL REFERENCES local_owners(id) ON DELETE CASCADE,
      preference_version INTEGER NOT NULL,
      goal TEXT NOT NULL,
      available_minutes_per_day INTEGER NOT NULL
        CHECK (available_minutes_per_day >= 1
          AND available_minutes_per_day <= 240),
      activity_preference TEXT NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      PRIMARY KEY(owner_id)
    )
  ''');
  sqlite.execute(
    'INSERT INTO learner_preferences '
    '(owner_id, preference_version, goal, available_minutes_per_day, '
    'activity_preference, updated_at_utc_ms) VALUES '
    "('owner:v19', 1, 'examPreparation', 45, 'quiz', 1788048000000)",
  );
  sqlite.execute('PRAGMA user_version = 21');
}

Future<List<String>> _columnNames(AppDatabase database, String tableName) =>
    database
        .customSelect('PRAGMA table_info($tableName)')
        .map((row) => row.read<String>('name'))
        .get();

Future<Set<String>> _tableNames(AppDatabase database) => database
    .customSelect(
      "SELECT name FROM sqlite_master "
      "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
    )
    .map((row) => row.read<String>('name'))
    .get()
    .then((rows) => rows.toSet());
