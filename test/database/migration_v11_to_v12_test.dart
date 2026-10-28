import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  test('v11 drops unattributable AI usage and preserves owner data', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: _createSchemaElevenFixture),
    );
    addTearDown(database.close);

    final version = await database
        .customSelect('PRAGMA user_version')
        .map((row) => row.read<int>('user_version'))
        .getSingle();
    final columns = await database
        .customSelect('PRAGMA table_info(ai_usage_events)')
        .map((row) => row.read<String>('name'))
        .get();
    final ownerCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM local_owners')
        .map((row) => row.read<int>('count'))
        .getSingle();
    final usageCount = await database
        .customSelect('SELECT COUNT(*) AS count FROM ai_usage_events')
        .map((row) => row.read<int>('count'))
        .getSingle();

    expect(version, AppDatabase.currentSchemaVersion);
    expect(columns, contains('owner_id'));
    expect(ownerCount, 1);
    expect(usageCount, 0);
  });

  test('fresh current schema preserves the v12 AI usage contract', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);

    final foreignKeys = await database
        .customSelect('PRAGMA foreign_key_list(ai_usage_events)')
        .get();
    final indexes = await database
        .customSelect(
          "SELECT name FROM sqlite_master WHERE type = 'index' "
          "AND tbl_name = 'ai_usage_events'",
        )
        .map((row) => row.read<String>('name'))
        .get();

    expect(database.schemaVersion, AppDatabase.currentSchemaVersion);
    expect(
      foreignKeys.any(
        (row) =>
            row.read<String>('table') == 'local_owners' &&
            row.read<String>('from') == 'owner_id',
      ),
      isTrue,
    );
    expect(indexes, contains('idx_ai_usage_owner_occurred'));
  });
}

void _createSchemaElevenFixture(dynamic raw) {
  raw.execute('PRAGMA foreign_keys = ON');
  raw.execute('''
    CREATE TABLE local_owners (
      id TEXT NOT NULL PRIMARY KEY,
      firebase_uid TEXT UNIQUE,
      account_state TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL,
      upgraded_at_utc_ms INTEGER,
      CHECK (account_state IN ('localGuest', 'anonymousCloud', 'registered')),
      CHECK (created_at_utc_ms >= 0),
      CHECK (upgraded_at_utc_ms IS NULL OR upgraded_at_utc_ms >= created_at_utc_ms)
    )
  ''');
  raw.execute(
    "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
    "VALUES ('owner-a', 'localGuest', 1)",
  );
  raw.execute('''
    CREATE TABLE ai_usage_events (
      event_id TEXT NOT NULL PRIMARY KEY,
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
      schema_version INTEGER NOT NULL DEFAULT 1
    )
  ''');
  raw.execute('''
    INSERT INTO ai_usage_events(
      event_id, occurred_at_utc_ms, provider_id, model, request_type,
      outcome, latency_ms
    ) VALUES ('legacy-event', 1, 'gemini', 'legacy-model', 'tutorReply',
      'success', 1)
  ''');
  raw.execute('PRAGMA user_version = 11');
}
