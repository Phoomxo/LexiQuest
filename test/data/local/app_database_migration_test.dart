import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test('new databases use schema version three with learning indexes', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    expect(database.schemaVersion, 3);

    final categoryColumns = await _columnNames(
      database,
      'vocabulary_categories',
    );
    final wordColumns = await _columnNames(database, 'vocabulary_words');
    final outboxColumns = await _columnNames(database, 'outbox_operations');
    final conflictColumns = await _columnNames(database, 'sync_conflicts');
    final tables = await database
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .map((row) => row.read<String>('name'))
        .get();

    expect(
      categoryColumns,
      containsAll(<String>[
        'cloud_revision',
        'last_acknowledged_at_utc_ms',
        'server_updated_at_utc_ms',
      ]),
    );
    expect(
      wordColumns,
      containsAll(<String>[
        'cloud_revision',
        'last_acknowledged_at_utc_ms',
        'server_updated_at_utc_ms',
      ]),
    );
    expect(
      outboxColumns,
      containsAll(<String>[
        'lease_token',
        'lease_expires_at_utc_ms',
        'last_attempt_at_utc_ms',
      ]),
    );
    expect(
      conflictColumns,
      containsAll(<String>['local_snapshot_json', 'cloud_snapshot_json']),
    );
    expect(tables, contains('runtime_flags'));
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' AND name LIKE 'idx_learning_%'",
        )
        .map((row) => row.read<String>('name'))
        .get();
    expect(
      indexes,
      containsAll(<String>[
        'idx_learning_sessions_owner_started',
        'idx_learning_attempts_owner_word_time',
        'idx_learning_srs_owner_due',
        'idx_learning_reading_owner_document',
      ]),
    );
  });

  test('schema one data migrates to schema two without row loss', () async {
    final executor = NativeDatabase.memory(setup: _createSchemaOneFixture);
    final database = AppDatabase(executor);
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    final category = await database
        .customSelect(
          'SELECT id, name, cloud_revision '
          'FROM vocabulary_categories WHERE id = ?',
          variables: const [Variable<String>('category:travel')],
        )
        .getSingle();
    final word = await database
        .customSelect(
          'SELECT id, spelling, cloud_revision '
          'FROM vocabulary_words WHERE id = ?',
          variables: const [Variable<String>('word:station')],
        )
        .getSingle();
    final outbox = await database
        .customSelect(
          'SELECT operation_id, state, lease_token '
          'FROM outbox_operations WHERE operation_id = ?',
          variables: const [Variable<String>('category:travel:1:upsert')],
        )
        .getSingle();
    final conflict = await database
        .customSelect(
          'SELECT id, outcome, local_snapshot_json, cloud_snapshot_json '
          'FROM sync_conflicts WHERE id = ?',
          variables: const [Variable<String>('conflict:1')],
        )
        .getSingle();

    expect(version, 3);
    expect(category.read<String>('name'), 'Travel');
    expect(category.read<int>('cloud_revision'), 0);
    expect(word.read<String>('spelling'), 'station');
    expect(word.read<int>('cloud_revision'), 0);
    expect(outbox.read<String>('state'), 'pending');
    expect(outbox.readNullable<String>('lease_token'), isNull);
    expect(conflict.read<String>('outcome'), 'cloudWins');
    expect(conflict.readNullable<String>('local_snapshot_json'), isNull);
    expect(conflict.readNullable<String>('cloud_snapshot_json'), isNull);
  });
}

Future<Set<String>> _columnNames(AppDatabase database, String tableName) async {
  final rows = await database
      .customSelect('PRAGMA table_info($tableName)')
      .get();
  return rows.map((row) => row.read<String>('name')).toSet();
}

void _createSchemaOneFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
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
  sqlite.execute(
    "INSERT INTO local_owners "
    "(id, account_state, created_at_utc_ms, is_active) "
    "VALUES ('local:guest', 'localGuest', 1, 1)",
  );
  sqlite.execute('''
    INSERT INTO vocabulary_categories (
      id, owner_id, name, normalized_name, local_revision,
      is_deleted, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'category:travel', 'local:guest', 'Travel', 'travel', 1, 0, 1, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO vocabulary_words (
      id, owner_id, category_id, spelling, normalized_spelling,
      meaning, normalized_meaning, part_of_speech, source, local_revision,
      is_deleted, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'word:station', 'local:guest', 'category:travel', 'station', 'station',
      'สถานี', 'สถานี', 'noun', 'manual', 1, 0, 1, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO outbox_operations (
      operation_id, owner_id, entity_type, entity_id, operation_kind,
      payload_version, base_revision, state, attempt_count, created_at_utc_ms
    ) VALUES (
      'category:travel:1:upsert', 'local:guest', 'category',
      'category:travel', 'upsert', 1, 0, 'pending', 0, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO sync_conflicts (
      id, owner_id, entity_type, entity_id, local_revision, cloud_revision,
      resolution_policy, outcome, resolved_at_utc_ms
    ) VALUES (
      'conflict:1', 'local:guest', 'word', 'word:station', 1, 2,
      'highestAcknowledgedRevision', 'cloudWins', 2
    )
  ''');
  sqlite.execute('PRAGMA user_version = 1');
}
