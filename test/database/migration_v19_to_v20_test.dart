import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v18_to_v19_test.dart' as fixture;

void main() {
  test(
    'released v19 upgrades session configuration authority without data loss',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaNineteenFixture),
      );
      addTearDown(database.close);

      await expectCurrentDatabaseContract(database);
      final session = await database
          .customSelect(
            "SELECT owner_id, activity_type, session_configuration_identity, "
            "session_configuration_json, configuration_active_effort_us "
            "FROM learning_sessions WHERE id = 'session:v19'",
          )
          .getSingle();
      expect(session.read<String>('owner_id'), 'owner:v19');
      expect(session.read<String>('activity_type'), 'quiz');
      expect(session.data['session_configuration_identity'], isNull);
      expect(session.data['session_configuration_json'], isNull);
      expect(session.read<int>('configuration_active_effort_us'), 0);
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
              "SELECT source_kind FROM study_reminders WHERE id = 'reminder:v19'",
            )
            .map((row) => row.read<String>('source_kind'))
            .getSingle(),
        'goalDeadline',
      );
    },
  );
}

void createSchemaNineteenFixture(dynamic sqlite) {
  fixture.createSchemaEighteenFixture(sqlite);
  sqlite.execute('''
    CREATE TABLE learning_goals (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      kind TEXT NOT NULL,
      title TEXT NOT NULL,
      deadline_at_utc_ms INTEGER NOT NULL,
      timezone_id TEXT NOT NULL,
      timezone_offset_minutes INTEGER NOT NULL,
      status TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');
  sqlite.execute('''
    CREATE TABLE study_reminders (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      goal_id TEXT REFERENCES learning_goals(id) ON DELETE CASCADE,
      source_kind TEXT NOT NULL,
      scheduled_at_utc_ms INTEGER NOT NULL,
      timezone_id TEXT NOT NULL,
      timezone_offset_minutes INTEGER NOT NULL,
      quiet_hours_start_minutes INTEGER,
      quiet_hours_end_minutes INTEGER,
      is_enabled INTEGER NOT NULL DEFAULT 0,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0
    )
  ''');
  sqlite.execute(
    "INSERT INTO local_owners "
    "(id, account_state, is_active, created_at_utc_ms) "
    "VALUES ('owner:v19', 'localGuest', 1, 1787702400000)",
  );
  sqlite.execute(
    "INSERT INTO learning_sessions "
    "(id, owner_id, activity_type, state, started_at_utc_ms, "
    "correct_count, wrong_count, app_version, build_id) VALUES "
    "('session:v19', 'owner:v19', 'quiz', 'active', 1787702400000, "
    "0, 0, '19.0.0', 'released-v19')",
  );
  sqlite.execute(
    "INSERT INTO learning_goals "
    "(id, owner_id, kind, title, deadline_at_utc_ms, timezone_id, "
    "timezone_offset_minutes, status, created_at_utc_ms, updated_at_utc_ms) "
    "VALUES ('goal:v19', 'owner:v19', 'exam', 'Keep this goal', "
    "1787788800000, 'Etc/UTC', 0, 'active', 1787702400000, 1787702400000)",
  );
  sqlite.execute(
    "INSERT INTO study_reminders "
    "(id, owner_id, goal_id, source_kind, scheduled_at_utc_ms, timezone_id, "
    "timezone_offset_minutes, created_at_utc_ms, updated_at_utc_ms) VALUES "
    "('reminder:v19', 'owner:v19', 'goal:v19', 'goalDeadline', "
    "1787785200000, 'Etc/UTC', 0, 1787702400000, 1787702400000)",
  );
  sqlite.execute('PRAGMA user_version = 19');
}
