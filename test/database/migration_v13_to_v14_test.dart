import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test(
    'v13 fixture upgrades through current schema with immutable experiment assignments',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: _createSchemaThirteenFixture),
      );
      addTearDown(database.close);

      final expectedCurrentInventory = _inventoryForSchemaVersion(
        AppDatabase.currentSchemaVersion,
      );
      final actualInventory = await _tableNames(database);

      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
      expect(
        AppDatabase.currentSchemaVersion,
        greaterThanOrEqualTo(14),
        reason: 'Task 11 must advance the production schema to v14.',
      );
      expect(actualInventory, expectedCurrentInventory);
      expect(
        _inventoryForSchemaVersion(14).difference(_v13TableInventory),
        {'experiment_assignments'},
        reason: 'The v14 migration has exactly one additive table.',
      );

      for (final sentinel in _v13Sentinels.entries) {
        expect(
          await _count(database, sentinel.key),
          1,
          reason: '${sentinel.key} lost its v13 sentinel row',
        );
        expect(
          await _read<String>(
            database,
            'SELECT ${sentinel.value.column} FROM ${sentinel.key}',
            sentinel.value.column,
          ),
          sentinel.value.value,
          reason: '${sentinel.key} changed its v13 sentinel row',
        );
      }

      expect(await _columnNames(database, 'experiment_assignments'), const [
        'id',
        'owner_id',
        'experiment_id',
        'experiment_version',
        'cohort',
        'protocol_version',
        'assigned_at_utc_ms',
      ]);
      expect(
        await _uniqueColumnSets(database, 'experiment_assignments'),
        contains('owner_id,experiment_id,experiment_version'),
      );
      expect(await _count(database, 'experiment_assignments'), 0);
    },
  );
}

Set<String> _inventoryForSchemaVersion(int version) {
  return switch (version) {
    13 => _v13TableInventory,
    14 => {..._v13TableInventory, 'experiment_assignments'},
    15 => {..._v13TableInventory, 'experiment_assignments', 'assessment_runs'},
    _ => throw TestFailure(
      'Add the named table inventory for schema v$version before changing '
      'AppDatabase.currentSchemaVersion.',
    ),
  };
}

Future<Set<String>> _tableNames(AppDatabase database) {
  return database
      .customSelect(
        "SELECT name FROM sqlite_master "
        "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'",
      )
      .map((row) => row.read<String>('name'))
      .get()
      .then((rows) => rows.toSet());
}

Future<List<String>> _columnNames(AppDatabase database, String tableName) {
  return database
      .customSelect("PRAGMA table_info('$tableName')")
      .map((row) => row.read<String>('name'))
      .get();
}

Future<Set<String>> _uniqueColumnSets(
  AppDatabase database,
  String tableName,
) async {
  final indexes = await database
      .customSelect("PRAGMA index_list('$tableName')")
      .get();
  final uniqueColumnSets = <String>{};
  for (final index in indexes) {
    if (index.read<int>('unique') != 1) continue;
    final name = index.read<String>('name').replaceAll("'", "''");
    final columns = await database
        .customSelect("PRAGMA index_info('$name')")
        .get();
    columns.sort(
      (left, right) =>
          left.read<int>('seqno').compareTo(right.read<int>('seqno')),
    );
    uniqueColumnSets.add(
      columns.map((row) => row.read<String>('name')).join(','),
    );
  }
  return uniqueColumnSets;
}

Future<int> _count(AppDatabase database, String tableName) {
  return database
      .customSelect('SELECT COUNT(*) AS count FROM $tableName')
      .map((row) => row.read<int>('count'))
      .getSingle();
}

Future<T> _read<T extends Object>(
  AppDatabase database,
  String statement,
  String column,
) {
  return database
      .customSelect(statement)
      .map((row) => row.read<T>(column))
      .getSingle();
}

void _createSchemaThirteenFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  for (final statement in _v13SchemaStatements) {
    sqlite.execute(statement);
  }
  for (final statement in _v13SeedStatements) {
    sqlite.execute(statement);
  }
  sqlite.execute('PRAGMA user_version = 13');
}

const _v13TableInventory = <String>{
  'local_owners',
  'research_consents',
  'vocabulary_categories',
  'vocabulary_words',
  'vocabulary_imports',
  'vocabulary_import_rows',
  'learning_sessions',
  'answer_attempts',
  'srs_states',
  'reading_progress_entries',
  'reading_events',
  'points_ledger_entries',
  'achievement_unlocks',
  'reward_transactions',
  'owned_reward_items',
  'equipped_reward_items',
  'outbox_operations',
  'sync_checkpoints',
  'sync_conflicts',
  'runtime_flags',
  'model_downloads',
  'events_v2',
  'quest_definitions',
  'quest_instances',
  'quest_objective_progress',
  'streak_states',
  'learning_day_log',
  'association_records',
  'associative_memory_states',
  'ai_usage_events',
  'speech_evidence',
};

const _v13Sentinels = <String, ({String column, String value})>{
  'local_owners': (column: 'id', value: 'owner:v13'),
  'research_consents': (column: 'id', value: 'consent:v13'),
  'vocabulary_categories': (column: 'id', value: 'category:v13'),
  'vocabulary_words': (column: 'id', value: 'word:v13'),
  'vocabulary_imports': (column: 'id', value: 'import:v13'),
  'vocabulary_import_rows': (column: 'id', value: 'import-row:v13'),
  'learning_sessions': (column: 'id', value: 'session:v13'),
  'answer_attempts': (column: 'id', value: 'attempt:v13'),
  'srs_states': (column: 'id', value: 'srs:v13'),
  'reading_progress_entries': (column: 'id', value: 'reading-progress:v13'),
  'reading_events': (column: 'id', value: 'reading-event:v13'),
  'points_ledger_entries': (column: 'id', value: 'points:v13'),
  'achievement_unlocks': (column: 'id', value: 'achievement:v13'),
  'reward_transactions': (column: 'id', value: 'reward:v13'),
  'owned_reward_items': (column: 'id', value: 'owned:v13'),
  'equipped_reward_items': (column: 'id', value: 'equipped:v13'),
  'outbox_operations': (column: 'operation_id', value: 'outbox:v13'),
  'sync_checkpoints': (column: 'id', value: 'checkpoint:v13'),
  'sync_conflicts': (column: 'id', value: 'conflict:v13'),
  'runtime_flags': (column: 'key', value: 'flag:v13'),
  'model_downloads': (column: 'id', value: 'model:v13'),
  'events_v2': (column: 'event_id', value: 'event:v13'),
  'quest_definitions': (column: 'quest_id', value: 'quest:v13'),
  'quest_instances': (column: 'instance_id', value: 'quest-instance:v13'),
  'quest_objective_progress': (column: 'id', value: 'quest-progress:v13'),
  'streak_states': (column: 'owner_id', value: 'owner:v13'),
  'learning_day_log': (column: 'id', value: 'day:v13'),
  'association_records': (column: 'id', value: 'association:v13'),
  'associative_memory_states': (column: 'id', value: 'memory:v13'),
  'ai_usage_events': (column: 'event_id', value: 'ai:v13'),
  'speech_evidence': (column: 'id', value: 'speech:v13'),
};

const _v13SchemaStatements = <String>[
  '''
    CREATE TABLE local_owners (
      id TEXT NOT NULL PRIMARY KEY,
      firebase_uid TEXT UNIQUE,
      account_state TEXT NOT NULL DEFAULT 'localGuest',
      created_at_utc_ms INTEGER NOT NULL,
      upgraded_at_utc_ms INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1
    )
  ''',
  '''
    CREATE TABLE research_consents (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      consent_version INTEGER NOT NULL,
      consent_state TEXT NOT NULL,
      decided_at_utc_ms INTEGER NOT NULL,
      withdrawn_at_utc_ms INTEGER,
      UNIQUE(owner_id, consent_version)
    )
  ''',
  '''
    CREATE TABLE vocabulary_categories (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      name TEXT NOT NULL,
      normalized_name TEXT NOT NULL,
      sort_order INTEGER NOT NULL DEFAULT 0,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, normalized_name)
    )
  ''',
  '''
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
      is_global INTEGER NOT NULL DEFAULT 0,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(
        owner_id,
        category_id,
        normalized_spelling,
        normalized_meaning
      )
    )
  ''',
  '''
    CREATE TABLE vocabulary_imports (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      category_id TEXT NOT NULL REFERENCES vocabulary_categories(id),
      source_type TEXT NOT NULL,
      source_name TEXT NOT NULL,
      source_hash TEXT NOT NULL,
      status TEXT NOT NULL,
      accepted_count INTEGER NOT NULL DEFAULT 0,
      duplicate_count INTEGER NOT NULL DEFAULT 0,
      rejected_count INTEGER NOT NULL DEFAULT 0,
      created_at_utc_ms INTEGER NOT NULL,
      completed_at_utc_ms INTEGER,
      UNIQUE(owner_id, category_id, source_hash)
    )
  ''',
  '''
    CREATE TABLE vocabulary_import_rows (
      id TEXT NOT NULL PRIMARY KEY,
      import_id TEXT NOT NULL REFERENCES vocabulary_imports(id) ON DELETE CASCADE,
      row_number INTEGER NOT NULL,
      payload_hash TEXT NOT NULL,
      status TEXT NOT NULL,
      failure_code TEXT,
      word_id TEXT,
      UNIQUE(import_id, row_number)
    )
  ''',
  '''
    CREATE TABLE learning_sessions (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      activity_type TEXT NOT NULL,
      state TEXT NOT NULL,
      started_at_utc_ms INTEGER NOT NULL,
      ended_at_utc_ms INTEGER,
      correct_count INTEGER NOT NULL DEFAULT 0,
      wrong_count INTEGER NOT NULL DEFAULT 0,
      score INTEGER,
      app_version TEXT NOT NULL,
      build_id TEXT NOT NULL
    )
  ''',
  '''
    CREATE TABLE answer_attempts (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      session_id TEXT NOT NULL REFERENCES learning_sessions(id) ON DELETE CASCADE,
      word_id TEXT NOT NULL REFERENCES vocabulary_words(id),
      prompt_mode TEXT NOT NULL,
      is_correct INTEGER NOT NULL,
      response_time_ms INTEGER,
      attempt_number INTEGER NOT NULL,
      occurred_at_utc_ms INTEGER NOT NULL,
      provider_provenance TEXT,
      evidence_class TEXT NOT NULL DEFAULT 'independentRecall',
      evidence_context_json TEXT NOT NULL DEFAULT '{"schemaVersion":1,"evidenceClass":"independentRecall","skillId":"legacy-unspecified","hintLevel":0,"policyVersion":"legacy-v1","contentRevision":"legacy-unknown","featureContractRevision":"legacy-unversioned","featureContractHash":"0000000000000000000000000000000000000000000000000000000000000000","classificationSource":"legacyInferred","rolloutMode":"legacy","protocolId":null,"protocolVersion":null,"experimentId":null,"experimentVersion":null,"assignmentId":null,"cohort":null,"researchConsentVersion":null,"instrumentId":null,"instrumentVersion":null,"formId":null,"formVersion":null,"assessmentItemId":null,"assessmentResponseCode":null,"scoringRuleVersion":null,"engagementAllowed":true}'
    )
  ''',
  '''
    CREATE TABLE srs_states (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      word_id TEXT NOT NULL REFERENCES vocabulary_words(id),
      stability REAL NOT NULL DEFAULT 0,
      difficulty REAL NOT NULL DEFAULT 0,
      interval_days INTEGER NOT NULL DEFAULT 0,
      repetitions INTEGER NOT NULL DEFAULT 0,
      lapses INTEGER NOT NULL DEFAULT 0,
      last_review_at_utc_ms INTEGER,
      due_at_utc_ms INTEGER NOT NULL,
      algorithm_version INTEGER NOT NULL,
      UNIQUE(owner_id, word_id)
    )
  ''',
  '''
    CREATE TABLE reading_progress_entries (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      document_id TEXT NOT NULL,
      document_revision INTEGER NOT NULL DEFAULT 1,
      last_position INTEGER NOT NULL DEFAULT 0,
      is_completed INTEGER NOT NULL DEFAULT 0,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, document_id, document_revision)
    )
  ''',
  '''
    CREATE TABLE reading_events (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      document_id TEXT NOT NULL,
      document_revision INTEGER NOT NULL DEFAULT 1,
      event_type TEXT NOT NULL,
      position INTEGER,
      occurred_at_utc_ms INTEGER NOT NULL
    )
  ''',
  '''
    CREATE TABLE points_ledger_entries (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      idempotency_key TEXT NOT NULL,
      entry_type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      source_event_id TEXT,
      occurred_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, idempotency_key)
    )
  ''',
  '''
    CREATE TABLE achievement_unlocks (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      achievement_id TEXT NOT NULL,
      definition_version INTEGER NOT NULL,
      source_event_id TEXT NOT NULL,
      unlocked_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, achievement_id, definition_version)
    )
  ''',
  '''
    CREATE TABLE reward_transactions (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      idempotency_key TEXT NOT NULL,
      transaction_type TEXT NOT NULL,
      amount INTEGER NOT NULL,
      item_id TEXT,
      catalog_version INTEGER NOT NULL,
      source_event_id TEXT,
      occurred_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, idempotency_key)
    )
  ''',
  '''
    CREATE TABLE owned_reward_items (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      item_id TEXT NOT NULL,
      catalog_version INTEGER NOT NULL,
      acquired_by_transaction_id TEXT NOT NULL REFERENCES reward_transactions(id),
      acquired_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, item_id)
    )
  ''',
  '''
    CREATE TABLE equipped_reward_items (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      slot TEXT NOT NULL,
      item_id TEXT NOT NULL,
      equipped_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, slot)
    )
  ''',
  '''
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
      lease_token TEXT,
      lease_expires_at_utc_ms INTEGER,
      last_attempt_at_utc_ms INTEGER,
      created_at_utc_ms INTEGER NOT NULL,
      acknowledged_at_utc_ms INTEGER,
      failure_code TEXT
    )
  ''',
  '''
    CREATE TABLE sync_checkpoints (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      collection_name TEXT NOT NULL,
      server_cursor TEXT,
      last_success_at_utc_ms INTEGER,
      UNIQUE(owner_id, collection_name)
    )
  ''',
  '''
    CREATE TABLE sync_conflicts (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      entity_type TEXT NOT NULL,
      entity_id TEXT NOT NULL,
      local_revision INTEGER NOT NULL,
      cloud_revision INTEGER NOT NULL,
      resolution_policy TEXT NOT NULL,
      outcome TEXT NOT NULL,
      local_snapshot_json TEXT,
      cloud_snapshot_json TEXT,
      resolved_at_utc_ms INTEGER NOT NULL
    )
  ''',
  '''
    CREATE TABLE runtime_flags (
      key TEXT NOT NULL PRIMARY KEY,
      bool_value INTEGER NOT NULL,
      source TEXT NOT NULL DEFAULT 'local',
      updated_at_utc_ms INTEGER NOT NULL,
      expires_at_utc_ms INTEGER
    )
  ''',
  '''
    CREATE TABLE model_downloads (
      id TEXT NOT NULL PRIMARY KEY,
      model_version TEXT NOT NULL,
      source_url TEXT NOT NULL,
      expected_checksum TEXT NOT NULL,
      expected_bytes INTEGER NOT NULL,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      retry_count INTEGER NOT NULL DEFAULT 0,
      state TEXT NOT NULL DEFAULT 'notStarted',
      local_path TEXT,
      failure_code TEXT,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(model_version, expected_checksum)
    )
  ''',
  '''
    CREATE TABLE events_v2 (
      event_id TEXT NOT NULL PRIMARY KEY,
      event_type TEXT NOT NULL,
      event_version INTEGER NOT NULL,
      occurred_at_utc INTEGER NOT NULL,
      recorded_at_utc INTEGER NOT NULL,
      actor_identity TEXT NOT NULL,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      tenant_context_json TEXT,
      aggregate_type TEXT NOT NULL,
      aggregate_id TEXT NOT NULL,
      correlation_id TEXT,
      causation_id TEXT,
      idempotency_key TEXT NOT NULL,
      consent_context_json TEXT NOT NULL,
      experiment_context_json TEXT,
      content_revision TEXT,
      policy_version TEXT,
      app_version TEXT NOT NULL,
      build_id TEXT NOT NULL,
      provider_provenance_json TEXT,
      privacy_classification TEXT NOT NULL,
      payload_json TEXT NOT NULL,
      UNIQUE(owner_id, idempotency_key)
    )
  ''',
  '''
    CREATE TABLE quest_definitions (
      quest_id TEXT NOT NULL PRIMARY KEY,
      catalog_version INTEGER NOT NULL,
      title TEXT NOT NULL,
      description TEXT NOT NULL,
      type TEXT NOT NULL,
      objectives_json TEXT NOT NULL,
      reward_json TEXT NOT NULL,
      expires_in_ms INTEGER,
      tags_json TEXT NOT NULL DEFAULT '[]'
    )
  ''',
  '''
    CREATE TABLE quest_instances (
      instance_id TEXT NOT NULL PRIMARY KEY,
      quest_id TEXT NOT NULL REFERENCES quest_definitions(quest_id),
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      catalog_version INTEGER NOT NULL,
      assigned_at_utc_ms INTEGER NOT NULL,
      state TEXT NOT NULL,
      completed_at_utc_ms INTEGER,
      expired_at_utc_ms INTEGER,
      UNIQUE(owner_id, quest_id)
    )
  ''',
  '''
    CREATE TABLE quest_objective_progress (
      id TEXT NOT NULL PRIMARY KEY,
      instance_id TEXT NOT NULL REFERENCES quest_instances(instance_id) ON DELETE CASCADE,
      objective_id TEXT NOT NULL,
      current_count INTEGER NOT NULL DEFAULT 0,
      target_count INTEGER NOT NULL,
      source_event_ids_json TEXT NOT NULL DEFAULT '[]',
      UNIQUE(instance_id, objective_id)
    )
  ''',
  '''
    CREATE TABLE streak_states (
      owner_id TEXT NOT NULL PRIMARY KEY REFERENCES local_owners(id),
      current_streak_days INTEGER NOT NULL DEFAULT 0,
      longest_streak_days INTEGER NOT NULL DEFAULT 0,
      freeze_count INTEGER NOT NULL DEFAULT 0,
      last_learned_at_utc_ms INTEGER,
      updated_at_utc_ms INTEGER NOT NULL
    )
  ''',
  '''
    CREATE TABLE learning_day_log (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      learning_day TEXT NOT NULL,
      first_session_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, learning_day)
    )
  ''',
  '''
    CREATE TABLE association_records (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      word_key TEXT NOT NULL,
      type TEXT NOT NULL,
      content TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, word_key, type)
    )
  ''',
  '''
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
  ''',
  '''
    CREATE TABLE ai_usage_events (
      event_id TEXT NOT NULL,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      occurred_at_utc_ms INTEGER NOT NULL,
      provider_id TEXT NOT NULL,
      model TEXT NOT NULL,
      request_type TEXT NOT NULL,
      outcome TEXT NOT NULL,
      error_category TEXT,
      latency_ms INTEGER NOT NULL,
      input_tokens INTEGER,
      output_tokens INTEGER,
      total_tokens INTEGER,
      cached_tokens INTEGER,
      provider_reported_cost_micros_usd INTEGER,
      schema_version INTEGER NOT NULL DEFAULT 1,
      PRIMARY KEY(owner_id, event_id)
    )
  ''',
  '''
    CREATE TABLE speech_evidence (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      session_id TEXT NOT NULL REFERENCES learning_sessions(id) ON DELETE CASCADE,
      word_id TEXT NOT NULL REFERENCES vocabulary_words(id),
      prompt_mode TEXT NOT NULL,
      target_content TEXT NOT NULL,
      recognized_transcript TEXT NOT NULL,
      locale TEXT NOT NULL,
      stt_engine TEXT NOT NULL,
      similarity_algorithm TEXT NOT NULL,
      similarity_score INTEGER,
      is_exact_match INTEGER NOT NULL,
      recognition_confidence REAL,
      sample_size INTEGER NOT NULL DEFAULT 1,
      unavailable_reason TEXT,
      occurred_at_utc_ms INTEGER NOT NULL,
      duration_ms INTEGER
    )
  ''',
];

const _v13SeedStatements = <String>[
  "INSERT INTO local_owners(id, created_at_utc_ms) "
      "VALUES ('owner:v13', 1)",
  '''
    INSERT INTO research_consents(
      id, owner_id, consent_version, consent_state, decided_at_utc_ms
    ) VALUES ('consent:v13', 'owner:v13', 1, 'granted', 2)
  ''',
  '''
    INSERT INTO vocabulary_categories(
      id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms
    ) VALUES ('category:v13', 'owner:v13', 'V13', 'v13', 3, 3)
  ''',
  '''
    INSERT INTO vocabulary_words(
      id, owner_id, category_id, spelling, normalized_spelling, meaning,
      normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'word:v13', 'owner:v13', 'category:v13', 'lexicon', 'lexicon',
      'word list', 'word list', 'noun', 4, 4
    )
  ''',
  '''
    INSERT INTO vocabulary_imports(
      id, owner_id, category_id, source_type, source_name, source_hash,
      status, created_at_utc_ms
    ) VALUES (
      'import:v13', 'owner:v13', 'category:v13', 'csv', 'v13.csv',
      'hash:v13', 'completed', 5
    )
  ''',
  '''
    INSERT INTO vocabulary_import_rows(
      id, import_id, row_number, payload_hash, status, word_id
    ) VALUES ('import-row:v13', 'import:v13', 1, 'row-hash:v13', 'accepted', 'word:v13')
  ''',
  '''
    INSERT INTO learning_sessions(
      id, owner_id, activity_type, state, started_at_utc_ms, app_version,
      build_id
    ) VALUES ('session:v13', 'owner:v13', 'quiz', 'completed', 6, '13', '13')
  ''',
  '''
    INSERT INTO answer_attempts(
      id, owner_id, session_id, word_id, prompt_mode, is_correct,
      attempt_number, occurred_at_utc_ms, evidence_class,
      evidence_context_json
    ) VALUES (
      'attempt:v13', 'owner:v13', 'session:v13', 'word:v13', 'meaning', 1,
      1, 7, 'independentRecall', '{"schemaVersion":1}'
    )
  ''',
  '''
    INSERT INTO srs_states(
      id, owner_id, word_id, repetitions, due_at_utc_ms, algorithm_version
    ) VALUES ('srs:v13', 'owner:v13', 'word:v13', 1, 8, 1)
  ''',
  '''
    INSERT INTO reading_progress_entries(
      id, owner_id, document_id, last_position, updated_at_utc_ms
    ) VALUES ('reading-progress:v13', 'owner:v13', 'document:v13', 3, 9)
  ''',
  '''
    INSERT INTO reading_events(
      id, owner_id, document_id, event_type, position, occurred_at_utc_ms
    ) VALUES ('reading-event:v13', 'owner:v13', 'document:v13', 'progress', 3, 9)
  ''',
  '''
    INSERT INTO points_ledger_entries(
      id, owner_id, idempotency_key, entry_type, amount, source_event_id,
      occurred_at_utc_ms
    ) VALUES ('points:v13', 'owner:v13', 'points:v13', 'quizCorrect', 1, 'attempt:v13', 7)
  ''',
  '''
    INSERT INTO achievement_unlocks(
      id, owner_id, achievement_id, definition_version, source_event_id,
      unlocked_at_utc_ms
    ) VALUES ('achievement:v13', 'owner:v13', 'first', 1, 'attempt:v13', 7)
  ''',
  '''
    INSERT INTO reward_transactions(
      id, owner_id, idempotency_key, transaction_type, amount, item_id,
      catalog_version, source_event_id, occurred_at_utc_ms
    ) VALUES (
      'reward:v13', 'owner:v13', 'reward:v13', 'coinGrant', 1, NULL,
      1, 'attempt:v13', 7
    )
  ''',
  '''
    INSERT INTO owned_reward_items(
      id, owner_id, item_id, catalog_version, acquired_by_transaction_id,
      acquired_at_utc_ms
    ) VALUES ('owned:v13', 'owner:v13', 'item:v13', 1, 'reward:v13', 10)
  ''',
  '''
    INSERT INTO equipped_reward_items(
      id, owner_id, slot, item_id, equipped_at_utc_ms
    ) VALUES ('equipped:v13', 'owner:v13', 'avatar', 'item:v13', 10)
  ''',
  '''
    INSERT INTO outbox_operations(
      operation_id, owner_id, entity_type, entity_id, operation_kind,
      created_at_utc_ms
    ) VALUES ('outbox:v13', 'owner:v13', 'answerAttempt', 'attempt:v13', 'upsert', 11)
  ''',
  '''
    INSERT INTO sync_checkpoints(id, owner_id, collection_name, server_cursor)
    VALUES ('checkpoint:v13', 'owner:v13', 'answerAttempts', 'cursor:v13')
  ''',
  '''
    INSERT INTO sync_conflicts(
      id, owner_id, entity_type, entity_id, local_revision, cloud_revision,
      resolution_policy, outcome, resolved_at_utc_ms
    ) VALUES (
      'conflict:v13', 'owner:v13', 'word', 'word:v13', 1, 2,
      'cloudWins', 'resolved', 12
    )
  ''',
  "INSERT INTO runtime_flags(key, bool_value, updated_at_utc_ms) "
      "VALUES ('flag:v13', 1, 13)",
  '''
    INSERT INTO model_downloads(
      id, model_version, source_url, expected_checksum, expected_bytes,
      updated_at_utc_ms
    ) VALUES ('model:v13', 'v13', 'https://example.invalid/v13', 'sum:v13', 13, 13)
  ''',
  '''
    INSERT INTO events_v2(
      event_id, event_type, event_version, occurred_at_utc, recorded_at_utc,
      actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key,
      consent_context_json, app_version, build_id, privacy_classification,
      payload_json
    ) VALUES (
      'event:v13', 'answerRecorded', 2, 7, 7, 'owner:v13', 'owner:v13',
      'answerAttempt', 'attempt:v13', 'event:v13', '{}', '13', '13',
      'sensitive', '{}'
    )
  ''',
  '''
    INSERT INTO quest_definitions(
      quest_id, catalog_version, title, description, type, objectives_json,
      reward_json
    ) VALUES ('quest:v13', 1, 'V13', 'V13', 'daily', '[]', '{}')
  ''',
  '''
    INSERT INTO quest_instances(
      instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms,
      state
    ) VALUES ('quest-instance:v13', 'quest:v13', 'owner:v13', 1, 14, 'active')
  ''',
  '''
    INSERT INTO quest_objective_progress(
      id, instance_id, objective_id, current_count, target_count
    ) VALUES ('quest-progress:v13', 'quest-instance:v13', 'objective:v13', 1, 2)
  ''',
  '''
    INSERT INTO streak_states(
      owner_id, current_streak_days, longest_streak_days, updated_at_utc_ms
    ) VALUES ('owner:v13', 3, 3, 15)
  ''',
  '''
    INSERT INTO learning_day_log(
      id, owner_id, learning_day, first_session_at_utc_ms
    ) VALUES ('day:v13', 'owner:v13', '2026-08-14', 15)
  ''',
  '''
    INSERT INTO association_records(
      id, owner_id, word_key, type, content, created_at_utc_ms
    ) VALUES ('association:v13', 'owner:v13', 'word:v13', 'keyword', 'lex', 16)
  ''',
  '''
    INSERT INTO associative_memory_states(
      id, owner_id, word_key, next_due_at_utc_ms, algorithm_version
    ) VALUES ('memory:v13', 'owner:v13', 'word:v13', 17, 'v1')
  ''',
  '''
    INSERT INTO ai_usage_events(
      event_id, owner_id, occurred_at_utc_ms, provider_id, model,
      request_type, outcome, latency_ms
    ) VALUES ('ai:v13', 'owner:v13', 18, 'local', 'v13', 'hint', 'success', 1)
  ''',
  '''
    INSERT INTO speech_evidence(
      id, owner_id, session_id, word_id, prompt_mode, target_content,
      recognized_transcript, locale, stt_engine, similarity_algorithm,
      is_exact_match, occurred_at_utc_ms
    ) VALUES (
      'speech:v13', 'owner:v13', 'session:v13', 'word:v13', 'pronunciation',
      'lexicon', 'lexicon', 'en-US', 'local', 'exact', 1, 19
    )
  ''',
];
