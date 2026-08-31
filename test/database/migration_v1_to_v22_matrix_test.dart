import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';

typedef _RawFixtureSetup = void Function(dynamic sqlite);
typedef _MigratedDataAssertion = Future<void> Function(AppDatabase database);

void main() {
  final fixtures =
      <
        ({
          int sourceVersion,
          _RawFixtureSetup setup,
          _MigratedDataAssertion verifyData,
        })
      >[
        (
          sourceVersion: 1,
          setup: _createSchemaOneFixture,
          verifyData: (database) async {
            final category = await database
                .customSelect(
                  'SELECT name, cloud_revision FROM vocabulary_categories '
                  "WHERE id = 'category:travel'",
                )
                .getSingle();
            final outbox = await database
                .customSelect(
                  'SELECT state, lease_token FROM outbox_operations '
                  "WHERE operation_id = 'category:travel:1:upsert'",
                )
                .getSingle();
            final conflict = await database
                .customSelect(
                  'SELECT outcome, local_snapshot_json, cloud_snapshot_json '
                  "FROM sync_conflicts WHERE id = 'conflict:1'",
                )
                .getSingle();

            expect(category.read<String>('name'), 'Travel');
            expect(category.read<int>('cloud_revision'), 0);
            expect(outbox.read<String>('state'), 'pending');
            expect(outbox.readNullable<String>('lease_token'), isNull);
            expect(conflict.read<String>('outcome'), 'cloudWins');
            expect(
              conflict.readNullable<String>('local_snapshot_json'),
              isNull,
            );
            expect(
              conflict.readNullable<String>('cloud_snapshot_json'),
              isNull,
            );
          },
        ),
        (
          sourceVersion: 2,
          setup: _createSchemaTwoFixture,
          verifyData: (database) async {
            final category = await database
                .customSelect(
                  'SELECT name, cloud_revision, last_acknowledged_at_utc_ms, '
                  'server_updated_at_utc_ms FROM vocabulary_categories '
                  "WHERE id = 'category:v2'",
                )
                .getSingle();

            expect(category.read<String>('name'), 'Schema Two');
            expect(category.read<int>('cloud_revision'), 7);
            expect(category.read<int>('last_acknowledged_at_utc_ms'), 12);
            expect(category.read<int>('server_updated_at_utc_ms'), 13);
          },
        ),
        (
          sourceVersion: 3,
          setup: _createSchemaThreeFixture,
          verifyData: (database) async {
            final event = await database
                .customSelect(
                  'SELECT document_revision FROM reading_events '
                  "WHERE id = 'reading:v3'",
                )
                .getSingle();
            expect(event.read<int>('document_revision'), 1);
          },
        ),
        (
          sourceVersion: 4,
          setup: _createSchemaFourFixture,
          verifyData: (database) async {
            final download = await database
                .customSelect(
                  'SELECT state, failure_code FROM model_downloads '
                  "WHERE id = 'vision@v4'",
                )
                .getSingle();
            expect(download.read<String>('state'), 'downloading');
            expect(download.readNullable<String>('failure_code'), isNull);
          },
        ),
        (
          sourceVersion: 5,
          setup: _createSchemaFiveFixture,
          verifyData: (database) async {
            final download = await database
                .customSelect(
                  'SELECT state, failure_code FROM model_downloads '
                  "WHERE id = 'vision@v5'",
                )
                .getSingle();
            expect(download.read<String>('state'), 'failed');
            expect(download.read<String>('failure_code'), 'networkUnavailable');
          },
        ),
        (
          sourceVersion: 10,
          setup: _createSchemaTenFixture,
          verifyData: (database) async {
            final association = await database
                .customSelect(
                  'SELECT content FROM association_records '
                  "WHERE id = 'association:v10'",
                )
                .getSingle();
            final memory = await database
                .customSelect(
                  'SELECT stability, difficulty, cue_dependency, lapse_count '
                  'FROM associative_memory_states '
                  "WHERE id = 'memory:v10'",
                )
                .getSingle();
            final aiUsageTables = await database
                .customSelect(
                  "SELECT COUNT(*) AS count FROM sqlite_master "
                  "WHERE type = 'table' AND name = 'ai_usage_events'",
                )
                .getSingle();

            expect(association.read<String>('content'), 'yellow platform sign');
            expect(memory.read<double>('stability'), 2.5);
            expect(memory.read<double>('difficulty'), 4.0);
            expect(memory.read<double>('cue_dependency'), 0.25);
            expect(memory.read<int>('lapse_count'), 1);
            expect(aiUsageTables.read<int>('count'), 1);
          },
        ),
      ];

  for (final fixture in fixtures) {
    test('final test plan migration matrix: frozen v${fixture.sourceVersion} '
        'fixture reaches current with data intact', () async {
      final database = AppDatabase(NativeDatabase.memory(setup: fixture.setup));
      addTearDown(database.close);

      final version = await database
          .customSelect('PRAGMA user_version')
          .map((row) => row.read<int>('user_version'))
          .getSingle();

      expect(version, AppDatabase.currentSchemaVersion);
      await expectCurrentDatabaseContract(database);
      await fixture.verifyData(database);
    });
  }
}

void _createSchemaOneFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  _createLegacyOwnerTable(sqlite);
  sqlite.execute('''
    CREATE TABLE vocabulary_categories (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      local_revision INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, normalized_name)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE vocabulary_words (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      category_id TEXT NOT NULL REFERENCES vocabulary_categories(id),
      spelling TEXT NOT NULL,
      normalized_spelling TEXT NOT NULL,
      meaning TEXT NOT NULL,
      normalized_meaning TEXT NOT NULL,
      part_of_speech TEXT NOT NULL,
      cefr_level TEXT,
      source TEXT NOT NULL DEFAULT 'manual',
      is_global INTEGER NOT NULL DEFAULT 0 CHECK (is_global IN (0, 1)),
      local_revision INTEGER NOT NULL DEFAULT 1,
      is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, category_id, normalized_spelling, normalized_meaning)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE outbox_operations (
      operation_id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      operation_kind TEXT NOT NULL,
      payload_version INTEGER NOT NULL DEFAULT 1,
      base_revision INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT 'pending',
      attempt_count INTEGER NOT NULL DEFAULT 0,
      next_attempt_at_utc_ms INTEGER,
      created_at_utc_ms INTEGER NOT NULL,
      acknowledged_at_utc_ms INTEGER,
      failure_code TEXT
    )
  ''');
  sqlite.execute('''
    CREATE TABLE sync_conflicts (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      local_revision INTEGER NOT NULL,
      cloud_revision INTEGER NOT NULL,
      resolution_policy TEXT NOT NULL,
      outcome TEXT NOT NULL,
      resolved_at_utc_ms INTEGER NOT NULL
    )
  ''');
  _insertLegacyOwner(sqlite, 'owner:v1');
  sqlite.execute('''
    INSERT INTO vocabulary_categories (
      id, owner_id, name, normalized_name, local_revision,
      is_deleted, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'category:travel', 'owner:v1', 'Travel', 'travel', 1, 0, 1, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO vocabulary_words (
      id, owner_id, category_id, spelling, normalized_spelling,
      meaning, normalized_meaning, part_of_speech, source, local_revision,
      is_deleted, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'word:station', 'owner:v1', 'category:travel', 'station', 'station',
      'สถานี', 'สถานี', 'noun', 'manual', 1, 0, 1, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO outbox_operations (
      operation_id, owner_id, entity_type, entity_id, operation_kind,
      payload_version, base_revision, state, attempt_count, created_at_utc_ms
    ) VALUES (
      'category:travel:1:upsert', 'owner:v1', 'category',
      'category:travel', 'upsert', 1, 0, 'pending', 0, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO sync_conflicts (
      id, owner_id, entity_type, entity_id, local_revision, cloud_revision,
      resolution_policy, outcome, resolved_at_utc_ms
    ) VALUES (
      'conflict:1', 'owner:v1', 'word', 'word:station', 1, 2,
      'highestAcknowledgedRevision', 'cloudWins', 2
    )
  ''');
  sqlite.execute('PRAGMA user_version = 1');
}

void _createSchemaTwoFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  _createLegacyOwnerTable(sqlite);
  sqlite.execute('''
    CREATE TABLE vocabulary_categories (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      is_deleted INTEGER NOT NULL DEFAULT 0 CHECK (is_deleted IN (0, 1)),
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      UNIQUE(owner_id, normalized_name)
    )
  ''');
  _insertLegacyOwner(sqlite, 'owner:v2');
  sqlite.execute('''
    INSERT INTO vocabulary_categories (
      id, owner_id, name, normalized_name, local_revision, cloud_revision,
      is_deleted, created_at_utc_ms, updated_at_utc_ms,
      last_acknowledged_at_utc_ms, server_updated_at_utc_ms
    ) VALUES (
      'category:v2', 'owner:v2', 'Schema Two', 'schema two', 3, 7,
      0, 10, 11, 12, 13
    )
  ''');
  sqlite.execute('PRAGMA user_version = 2');
}

void _createSchemaThreeFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  _createLegacyOwnerTable(sqlite);
  sqlite.execute('''
    CREATE TABLE reading_events (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      document_id TEXT NOT NULL,
      event_type TEXT NOT NULL,
      position INTEGER,
      occurred_at_utc_ms INTEGER NOT NULL
    )
  ''');
  _insertLegacyOwner(sqlite, 'owner:v3');
  sqlite.execute('''
    INSERT INTO reading_events (
      id, owner_id, document_id, event_type, position, occurred_at_utc_ms
    ) VALUES ('reading:v3', 'owner:v3', 'doc:v3', 'checkpoint', 7, 10)
  ''');
  sqlite.execute('PRAGMA user_version = 3');
}

void _createSchemaFourFixture(dynamic sqlite) {
  _createSchemaFourOrFiveModelDownloads(sqlite);
  sqlite.execute('''
    INSERT INTO model_downloads (
      id, model_version, source_url, expected_checksum, expected_bytes,
      downloaded_bytes, retry_count, state, local_path, updated_at_utc_ms
    ) VALUES (
      'vision@v4', '4', 'https://models.example/v4.tflite',
      'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
      20, 5, 0, 'downloading', 'models/v4.tflite.partial', 10
    )
  ''');
  sqlite.execute('PRAGMA user_version = 4');
}

void _createSchemaFiveFixture(dynamic sqlite) {
  _createSchemaFourOrFiveModelDownloads(sqlite, includeFailureCode: true);
  sqlite.execute('''
    INSERT INTO model_downloads (
      id, model_version, source_url, expected_checksum, expected_bytes,
      downloaded_bytes, retry_count, state, local_path, updated_at_utc_ms,
      failure_code
    ) VALUES (
      'vision@v5', '5', 'https://models.example/v5.tflite',
      'bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb',
      30, 6, 1, 'failed', 'models/v5.tflite.partial', 20,
      'networkUnavailable'
    )
  ''');
  sqlite.execute('PRAGMA user_version = 5');
}

void _createSchemaTenFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  _createLegacyOwnerTable(sqlite);
  sqlite.execute('''
    CREATE TABLE association_records (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      word_key TEXT NOT NULL,
      type TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, word_key, type)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE associative_memory_states (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      word_key TEXT NOT NULL,
      stability REAL NOT NULL DEFAULT 1.0,
      difficulty REAL NOT NULL DEFAULT 5.0,
      cue_dependency REAL NOT NULL DEFAULT 0.0,
      lapse_count INTEGER NOT NULL DEFAULT 0,
      last_reviewed_at_utc_ms INTEGER,
      next_due_at_utc_ms INTEGER NOT NULL,
      algorithm_version TEXT NOT NULL,
      UNIQUE(owner_id, word_key)
    )
  ''');
  _insertLegacyOwner(sqlite, 'owner:v10');
  sqlite.execute('''
    INSERT INTO association_records (
      id, owner_id, word_key, type, content, created_at_utc_ms
    ) VALUES (
      'association:v10', 'owner:v10', 'station', 'keyword',
      'yellow platform sign', 100
    )
  ''');
  sqlite.execute('''
    INSERT INTO associative_memory_states (
      id, owner_id, word_key, stability, difficulty, cue_dependency,
      lapse_count, last_reviewed_at_utc_ms, next_due_at_utc_ms,
      algorithm_version
    ) VALUES (
      'memory:v10', 'owner:v10', 'station', 2.5, 4.0, 0.25,
      1, 100, 200, 'v1.0.0'
    )
  ''');
  sqlite.execute('PRAGMA user_version = 10');
}

void _createLegacyOwnerTable(dynamic sqlite) {
  sqlite.execute('''
    CREATE TABLE local_owners (
      id TEXT NOT NULL PRIMARY KEY,
      firebase_uid TEXT UNIQUE,
      account_state TEXT NOT NULL DEFAULT 'localGuest',
      created_at_utc_ms INTEGER NOT NULL CHECK (created_at_utc_ms >= 0),
      upgraded_at_utc_ms INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1 CHECK (is_active IN (0, 1))
    )
  ''');
}

void _insertLegacyOwner(dynamic sqlite, String ownerId) {
  sqlite.execute(
    "INSERT INTO local_owners "
    "(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('$ownerId', 'localGuest', 1, 1)",
  );
}

void _createSchemaFourOrFiveModelDownloads(
  dynamic sqlite, {
  bool includeFailureCode = false,
}) {
  sqlite.execute('''
    CREATE TABLE model_downloads (
      id TEXT NOT NULL PRIMARY KEY,
      model_version TEXT NOT NULL UNIQUE,
      source_url TEXT NOT NULL,
      expected_checksum TEXT NOT NULL,
      expected_bytes INTEGER NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      retry_count INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT 'notStarted',
      local_path TEXT,
      updated_at_utc_ms INTEGER NOT NULL
      ${includeFailureCode ? ', failure_code TEXT' : ''}
    )
  ''');
}
