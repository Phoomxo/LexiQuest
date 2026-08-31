import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v14_to_v15_test.dart' as fixture;

void main() {
  test(
    'frozen v16 upgrades through saved/report and active-time tables',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaSixteenFixture),
      );
      addTearDown(database.close);

      expect(AppDatabase.currentSchemaVersion, 22);
      expect(currentDatabaseTableInventory, hasLength(44));
      expect(
        currentDatabaseTableInventory.difference(schemaSixteenInventory),
        const {
          'saved_learning_items',
          'content_quality_reports',
          'learning_time_segments',
          'learning_goals',
          'study_reminders',
          'session_configurations',
          'learner_preferences',
        },
      );
      await expectCurrentDatabaseContract(database);

      expect(
        await database
            .customSelect(
              "SELECT spelling FROM vocabulary_words WHERE id = 'word:v13'",
            )
            .map((row) => row.read<String>('spelling'))
            .getSingle(),
        'lexicon',
      );
      expect(await _count(database, 'saved_learning_items'), 0);
      expect(await _count(database, 'content_quality_reports'), 0);
      expect(await _count(database, 'learning_time_segments'), 0);
    },
  );

  test(
    'saved items pin owner content and revision with one natural key',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaSixteenFixture),
      );
      addTearDown(database.close);

      expect(await _columnNames(database, 'saved_learning_items'), const [
        'id',
        'owner_id',
        'content_type',
        'content_id',
        'content_revision',
        'saved_at_utc_ms',
        'updated_at_utc_ms',
        'local_revision',
        'cloud_revision',
        'last_acknowledged_at_utc_ms',
        'server_updated_at_utc_ms',
        'is_deleted',
      ]);
      expect(await _uniqueColumnSets(database, 'saved_learning_items'), {
        'id',
        'owner_id,content_type,content_id,content_revision',
      });
      expect(await _foreignKeys(database, 'saved_learning_items'), {
        'owner_id->local_owners.id',
      });
    },
  );

  test(
    'report table is lifecycle-ready without introducing a writer state',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: createSchemaSixteenFixture),
      );
      addTearDown(database.close);

      expect(await _columnNames(database, 'content_quality_reports'), const [
        'id',
        'owner_id',
        'content_type',
        'content_id',
        'content_revision',
        'reason_code',
        'comment',
        'submitted_at_utc_ms',
      ]);
      expect(await _foreignKeys(database, 'content_quality_reports'), {
        'owner_id->local_owners.id',
      });
    },
  );
}

final schemaSixteenInventory = currentDatabaseTableInventory.difference(const {
  'saved_learning_items',
  'content_quality_reports',
  'learning_time_segments',
  'learning_goals',
  'study_reminders',
  'session_configurations',
  'learner_preferences',
});

/// Frozen v16 fixture: v15 plus the four immutable-content tables and columns.
void createSchemaSixteenFixture(dynamic sqlite) {
  fixture.createSchemaFifteenFixture(sqlite);
  sqlite.execute(
    "ALTER TABLE vocabulary_words ADD COLUMN content_revision INTEGER "
    'NOT NULL DEFAULT 1',
  );
  sqlite.execute(
    'ALTER TABLE vocabulary_words ADD COLUMN content_checksum_sha256 TEXT',
  );
  sqlite.execute(
    "ALTER TABLE vocabulary_words ADD COLUMN content_provenance TEXT "
    "NOT NULL DEFAULT 'userAuthored'",
  );
  sqlite.execute(
    "ALTER TABLE vocabulary_words ADD COLUMN content_review_state TEXT "
    "NOT NULL DEFAULT 'unreviewed'",
  );
  sqlite.execute(
    "ALTER TABLE vocabulary_words ADD COLUMN content_publication_state TEXT "
    "NOT NULL DEFAULT 'private'",
  );
  sqlite.execute('''
    CREATE TABLE content_manifests (
      id TEXT NOT NULL PRIMARY KEY, content_type TEXT NOT NULL,
      content_id TEXT NOT NULL, revision INTEGER NOT NULL,
      checksum_sha256 TEXT NOT NULL, byte_length INTEGER NOT NULL,
      provenance TEXT NOT NULL, source_uri TEXT NOT NULL,
      review_state TEXT NOT NULL, publication_state TEXT NOT NULL,
      created_at_utc_ms INTEGER NOT NULL, reviewed_at_utc_ms INTEGER,
      published_at_utc_ms INTEGER,
      UNIQUE(content_type, content_id, revision)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE learning_packs (
      id TEXT NOT NULL PRIMARY KEY, pack_id TEXT NOT NULL,
      revision INTEGER NOT NULL,
      manifest_id TEXT NOT NULL REFERENCES content_manifests(id),
      title TEXT NOT NULL, cefr_level TEXT NOT NULL, topic TEXT NOT NULL,
      skill TEXT NOT NULL, goal TEXT NOT NULL, created_at_utc_ms INTEGER NOT NULL,
      UNIQUE(pack_id, revision), UNIQUE(manifest_id)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE learning_pack_items (
      id TEXT NOT NULL PRIMARY KEY,
      learning_pack_id TEXT NOT NULL REFERENCES learning_packs(id)
        ON DELETE CASCADE,
      vocabulary_word_id TEXT NOT NULL, position INTEGER NOT NULL,
      UNIQUE(learning_pack_id, position),
      UNIQUE(learning_pack_id, vocabulary_word_id)
    )
  ''');
  sqlite.execute('''
    CREATE TABLE content_download_states (
      id TEXT NOT NULL PRIMARY KEY,
      manifest_id TEXT NOT NULL REFERENCES content_manifests(id),
      state TEXT NOT NULL DEFAULT 'notDownloaded', local_path TEXT,
      downloaded_bytes INTEGER NOT NULL DEFAULT 0,
      verified_checksum_sha256 TEXT, failure_code TEXT,
      updated_at_utc_ms INTEGER NOT NULL, UNIQUE(manifest_id)
    )
  ''');
  sqlite.execute('PRAGMA user_version = 16');
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
