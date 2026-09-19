import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v21_to_v22_test.dart' as fixture;

void main() {
  test(
    'v23 adds home experience only and preserves the complete v22 row',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaTwentyTwoFixture),
      );
      addTearDown(database.close);

      expect(AppDatabase.currentSchemaVersion, 29);
      expect(currentDatabaseTableInventory, hasLength(52));
      await expectCurrentDatabaseContract(database);
      final columns = await _columnNames(database, 'learner_preferences');
      expect(columns, contains('home_experience'));
      expect(columns, hasLength(15));

      final rows = await database
          .customSelect('SELECT * FROM learner_preferences ORDER BY owner_id')
          .get();
      expect(rows, hasLength(2));
      expect(rows.first.data, <String, Object?>{
        'owner_id': 'owner:tombstone',
        'preference_version': 2,
        'goal': 'vocabularyGrowth',
        'available_minutes_per_day': 25,
        'activity_preference': 'vocabulary',
        'updated_at_utc_ms': 1788048000800,
        'theme_mode': 'light',
        'motion_mode': 'system',
        'display_updated_at_utc_ms': 1788048000810,
        'home_experience': 'standard',
        'local_revision': 9,
        'cloud_revision': 8,
        'last_acknowledged_at_utc_ms': 1788048000820,
        'server_updated_at_utc_ms': 1788048000830,
        'is_deleted': 1,
      });
      expect(rows.last.data, <String, Object?>{
        'owner_id': 'owner:v19',
        'preference_version': 2,
        'goal': 'examPreparation',
        'available_minutes_per_day': 45,
        'activity_preference': 'quiz',
        'updated_at_utc_ms': 1788048000000,
        'theme_mode': 'dark',
        'motion_mode': 'reduced',
        'display_updated_at_utc_ms': 1788048000500,
        'home_experience': 'standard',
        'local_revision': 7,
        'cloud_revision': 5,
        'last_acknowledged_at_utc_ms': 1788048000600,
        'server_updated_at_utc_ms': 1788048000700,
        'is_deleted': 0,
      });
    },
  );

  test('v23 database rejects unknown durable home experience values', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await database.customStatement(
      'INSERT INTO local_owners '
      '(id, account_state, is_active, created_at_utc_ms) '
      "VALUES ('owner:one', 'guest', 1, 1)",
    );

    await expectLater(
      database.customStatement(
        'INSERT INTO learner_preferences '
        '(owner_id, preference_version, goal, available_minutes_per_day, '
        'activity_preference, updated_at_utc_ms, home_experience) '
        "VALUES ('owner:one', 2, 'balancedGrowth', 20, 'mixedPractice', 1, "
        "'unknown')",
      ),
      throwsA(anything),
    );
  });
}

void createSchemaTwentyTwoFixture(dynamic sqlite) {
  fixture.createSchemaTwentyOneFixture(sqlite);
  sqlite.execute(
    "ALTER TABLE learner_preferences ADD COLUMN theme_mode TEXT NOT NULL DEFAULT 'system'",
  );
  sqlite.execute(
    "ALTER TABLE learner_preferences ADD COLUMN motion_mode TEXT NOT NULL DEFAULT 'system'",
  );
  sqlite.execute(
    'ALTER TABLE learner_preferences ADD COLUMN '
    'display_updated_at_utc_ms INTEGER NOT NULL DEFAULT 0',
  );
  sqlite.execute(
    "UPDATE learner_preferences SET theme_mode = 'dark', "
    "motion_mode = 'reduced', display_updated_at_utc_ms = 1788048000500, "
    'local_revision = 7, cloud_revision = 5, '
    'last_acknowledged_at_utc_ms = 1788048000600, '
    'server_updated_at_utc_ms = 1788048000700',
  );
  sqlite.execute(
    'INSERT INTO local_owners '
    '(id, account_state, created_at_utc_ms, is_active) '
    "VALUES ('owner:tombstone', 'localGuest', 1788048000000, 0)",
  );
  sqlite.execute(
    'INSERT INTO learner_preferences '
    '(owner_id, preference_version, goal, available_minutes_per_day, '
    'activity_preference, updated_at_utc_ms, theme_mode, motion_mode, '
    'display_updated_at_utc_ms, local_revision, cloud_revision, '
    'last_acknowledged_at_utc_ms, server_updated_at_utc_ms, is_deleted) '
    "VALUES ('owner:tombstone', 1, 'vocabularyGrowth', 25, 'vocabulary', "
    "1788048000800, 'light', 'system', 1788048000810, 9, 8, "
    '1788048000820, 1788048000830, 1)',
  );
  sqlite.execute('PRAGMA user_version = 22');
}

Future<List<String>> _columnNames(AppDatabase database, String tableName) =>
    database
        .customSelect('PRAGMA table_info($tableName)')
        .map((row) => row.read<String>('name'))
        .get();
