import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_context.dart';

import '../support/current_database_contract.dart';

void main() {
  test(
    'v12 attempts gain exact legacy evidence metadata without row loss',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: _createSchemaTwelveFixture),
      );
      addTearDown(database.close);

      final attempt = await database
          .customSelect(
            'SELECT id, evidence_class, evidence_context_json '
            'FROM answer_attempts',
          )
          .getSingle();
      final evidenceContextJson = attempt.read<String>('evidence_context_json');
      final context = EvidenceContext.fromJson(
        (jsonDecode(evidenceContextJson) as Map).cast<String, Object?>(),
      );
      final expectedContext = EvidenceContext.legacyCompatibility(
        evidenceClass: EvidenceClass.independentRecall,
        skillId: 'legacy-unspecified',
        hintLevel: 0,
        contentRevision: 'legacy-unknown',
        engagementAllowed: true,
      );

      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
      await expectCurrentDatabaseContract(database);
      expect(attempt.read<String>('id'), 'attempt:v12');
      expect(
        attempt.read<String>('evidence_class'),
        EvidenceClass.independentRecall.name,
      );
      expect(
        context.classificationSource,
        EvidenceClassificationSource.legacyInferred,
      );
      expect(context.policyVersion, EvidenceContext.legacyPolicyVersion);
      expect(context.engagementAllowed, isTrue);
      expect(context.toJson(), expectedContext.toJson());
      expect(evidenceContextJson, jsonEncode(expectedContext.toJson()));
      expect(await _count(database, 'answer_attempts'), 1);
      expect(await _count(database, 'srs_states'), 1);
      expect(await _count(database, 'points_ledger_entries'), 1);
      expect(await _count(database, 'achievement_unlocks'), 1);
      expect(await _count(database, 'events_v2'), 1);
      expect(await _count(database, 'outbox_operations'), 1);
      expect(
        await _read<String>(database, 'SELECT id FROM srs_states', 'id'),
        'srs:v12',
      );
      expect(
        await _read<int>(
          database,
          'SELECT repetitions FROM srs_states',
          'repetitions',
        ),
        1,
      );
      expect(
        await _read<int>(
          database,
          'SELECT amount FROM points_ledger_entries',
          'amount',
        ),
        10,
      );
      expect(
        await _read<String>(
          database,
          'SELECT source_event_id FROM achievement_unlocks',
          'source_event_id',
        ),
        'attempt:v12',
      );
      expect(
        await _read<String>(
          database,
          'SELECT event_id FROM events_v2',
          'event_id',
        ),
        'event:v12',
      );
      expect(
        await _read<String>(
          database,
          'SELECT operation_id FROM outbox_operations',
          'operation_id',
        ),
        'attempt:attempt:v12:1',
      );
    },
  );
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

void _createSchemaTwelveFixture(dynamic sqlite) {
  sqlite.execute('PRAGMA foreign_keys = ON');
  sqlite.execute('''
    CREATE TABLE local_owners (
      id TEXT NOT NULL PRIMARY KEY,
      firebase_uid TEXT UNIQUE,
      account_state TEXT NOT NULL DEFAULT 'localGuest',
      created_at_utc_ms INTEGER NOT NULL,
      upgraded_at_utc_ms INTEGER,
      is_active INTEGER NOT NULL DEFAULT 1
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
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
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
      is_global INTEGER NOT NULL DEFAULT 0,
      local_revision INTEGER NOT NULL DEFAULT 1,
      cloud_revision INTEGER NOT NULL DEFAULT 0,
      last_acknowledged_at_utc_ms INTEGER,
      server_updated_at_utc_ms INTEGER,
      is_deleted INTEGER NOT NULL DEFAULT 0,
      created_at_utc_ms INTEGER NOT NULL,
      updated_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, category_id, normalized_spelling, normalized_meaning)
    )
  ''');
  sqlite.execute('''
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
  ''');
  sqlite.execute('''
    CREATE TABLE answer_attempts (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      session_id TEXT NOT NULL REFERENCES learning_sessions(id),
      word_id TEXT NOT NULL REFERENCES vocabulary_words(id),
      prompt_mode TEXT NOT NULL,
      is_correct INTEGER NOT NULL,
      response_time_ms INTEGER,
      attempt_number INTEGER NOT NULL,
      occurred_at_utc_ms INTEGER NOT NULL,
      provider_provenance TEXT
    )
  ''');
  sqlite.execute('''
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
  ''');
  sqlite.execute('''
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
  ''');
  sqlite.execute('''
    CREATE TABLE achievement_unlocks (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      achievement_id TEXT NOT NULL,
      definition_version INTEGER NOT NULL,
      source_event_id TEXT NOT NULL,
      unlocked_at_utc_ms INTEGER NOT NULL,
      UNIQUE(owner_id, achievement_id, definition_version)
    )
  ''');
  sqlite.execute('''
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
      lease_token TEXT,
      lease_expires_at_utc_ms INTEGER,
      last_attempt_at_utc_ms INTEGER,
      created_at_utc_ms INTEGER NOT NULL,
      acknowledged_at_utc_ms INTEGER,
      failure_code TEXT
    )
  ''');

  sqlite.execute(
    "INSERT INTO local_owners(id, created_at_utc_ms) VALUES ('owner:v12', 1)",
  );
  sqlite.execute('''
    INSERT INTO vocabulary_categories(
      id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms
    ) VALUES ('category:v12', 'owner:v12', 'Legacy', 'legacy', 1, 1)
  ''');
  sqlite.execute('''
    INSERT INTO vocabulary_words(
      id, owner_id, category_id, spelling, normalized_spelling, meaning,
      normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms
    ) VALUES (
      'word:v12', 'owner:v12', 'category:v12', 'legacy', 'legacy', 'legacy',
      'legacy', 'noun', 1, 1
    )
  ''');
  sqlite.execute('''
    INSERT INTO learning_sessions(
      id, owner_id, activity_type, state, started_at_utc_ms, app_version,
      build_id
    ) VALUES ('session:v12', 'owner:v12', 'quiz', 'active', 1, '1', '1')
  ''');
  sqlite.execute('''
    INSERT INTO answer_attempts(
      id, owner_id, session_id, word_id, prompt_mode, is_correct,
      response_time_ms, attempt_number, occurred_at_utc_ms
    ) VALUES (
      'attempt:v12', 'owner:v12', 'session:v12', 'word:v12', 'meaning', 1,
      100, 1, 2
    )
  ''');
  sqlite.execute('''
    INSERT INTO srs_states(
      id, owner_id, word_id, interval_days, repetitions, due_at_utc_ms,
      algorithm_version
    ) VALUES ('srs:v12', 'owner:v12', 'word:v12', 1, 1, 3, 1)
  ''');
  sqlite.execute('''
    INSERT INTO points_ledger_entries(
      id, owner_id, idempotency_key, entry_type, amount, source_event_id,
      occurred_at_utc_ms
    ) VALUES (
      'points:v12', 'owner:v12', 'points:v12', 'award', 10, 'attempt:v12', 2
    )
  ''');
  sqlite.execute('''
    INSERT INTO achievement_unlocks(
      id, owner_id, achievement_id, definition_version, source_event_id,
      unlocked_at_utc_ms
    ) VALUES (
      'achievement:v12', 'owner:v12', 'first_answer', 1, 'attempt:v12', 2
    )
  ''');
  sqlite.execute('''
    INSERT INTO events_v2(
      event_id, event_type, event_version, occurred_at_utc, recorded_at_utc,
      actor_identity, owner_id, aggregate_type, aggregate_id, idempotency_key,
      consent_context_json, app_version, build_id, privacy_classification,
      payload_json
    ) VALUES (
      'event:v12', 'answerRecorded', 2, 2, 2, 'owner:v12', 'owner:v12',
      'answerAttempt', 'attempt:v12', 'attempt:v12', '{}', '1', '1',
      'sensitive', '{}'
    )
  ''');
  sqlite.execute('''
    INSERT INTO outbox_operations(
      operation_id, owner_id, entity_type, entity_id, operation_kind,
      created_at_utc_ms
    ) VALUES (
      'attempt:attempt:v12:1', 'owner:v12', 'attempt', 'attempt:v12', 'upsert', 2
    )
  ''');
  sqlite.execute('PRAGMA user_version = 12');
}
