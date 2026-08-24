import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v13_to_v14_test.dart' as fixture;

void main() {
  test(
    'frozen v14 fixture upgrades through the named current inventory',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: fixture.createSchemaFourteenFixture),
      );
      addTearDown(database.close);

      expect(
        AppDatabase.currentSchemaVersion,
        16,
        reason: 'f04 owns the single v15-to-v16 schema advance.',
      );
      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);

      final v14Inventory = fixture.migrationInventoryForSchemaVersion(14);
      final v15Inventory = fixture.migrationInventoryForSchemaVersion(15);
      const currentInventory = currentDatabaseTableInventory;
      expect(v14Inventory, hasLength(32));
      expect(v15Inventory, hasLength(33));
      expect(v15Inventory.difference(v14Inventory), {'assessment_runs'});
      expect(currentInventory, hasLength(37));
      expect(currentInventory.difference(v15Inventory), {
        'learning_packs',
        'learning_pack_items',
        'content_manifests',
        'content_download_states',
      });
      expect(await _tableNames(database), currentInventory);
      expect(
        currentInventory.intersection(const <String>{
          'assessment_attempts',
          'assessment_responses',
          'assessment_scores',
          'assessment_score_ledger',
        }),
        isEmpty,
        reason: 'Canonical assessment responses remain AnswerAttempts.',
      );

      for (final sentinel in fixture.migrationV14Sentinels.entries) {
        expect(
          await _count(database, sentinel.key),
          1,
          reason: '${sentinel.key} lost its frozen v14 sentinel row',
        );
        expect(
          await _read<String>(
            database,
            'SELECT ${sentinel.value.column} FROM ${sentinel.key}',
            sentinel.value.column,
          ),
          sentinel.value.value,
          reason: '${sentinel.key} changed its frozen v14 sentinel row',
        );
      }

      expect(await _count(database, 'assessment_runs'), 0);
    },
  );

  test(
    'assessment_runs has the exact v15 columns nullability and keys',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: fixture.createSchemaFourteenFixture),
      );
      addTearDown(database.close);

      expect(AppDatabase.currentSchemaVersion, 16);
      expect(await _columnContract(database, 'assessment_runs'), const [
        (name: 'id', type: 'TEXT', notNull: true, primaryKey: true),
        (name: 'owner_id', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'learning_session_id',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'study_cycle_id',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'phase', type: 'TEXT', notNull: true, primaryKey: false),
        (name: 'state', type: 'TEXT', notNull: true, primaryKey: false),
        (name: 'protocol_id', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'protocol_version',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'experiment_id', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'experiment_version',
          type: 'INTEGER',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'assignment_id', type: 'TEXT', notNull: true, primaryKey: false),
        (name: 'cohort', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'consent_version',
          type: 'INTEGER',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'consent_decided_at_utc_ms',
          type: 'INTEGER',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'instrument_id', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'instrument_version',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'form_id', type: 'TEXT', notNull: true, primaryKey: false),
        (name: 'form_version', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'instrument_checksum_sha256',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'form_checksum_sha256',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (name: 'app_version', type: 'TEXT', notNull: true, primaryKey: false),
        (name: 'build_id', type: 'TEXT', notNull: true, primaryKey: false),
        (
          name: 'database_schema_version',
          type: 'INTEGER',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'content_revision',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'evidence_policy_version',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'feature_contract_revision',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'feature_contract_hash',
          type: 'TEXT',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'started_at_utc_ms',
          type: 'INTEGER',
          notNull: true,
          primaryKey: false,
        ),
        (
          name: 'completed_at_utc_ms',
          type: 'INTEGER',
          notNull: false,
          primaryKey: false,
        ),
        (
          name: 'abandoned_at_utc_ms',
          type: 'INTEGER',
          notNull: false,
          primaryKey: false,
        ),
      ]);
      expect(await _foreignKeys(database, 'assessment_runs'), const <String>{
        'assignment_id->experiment_assignments.id',
        'learning_session_id->learning_sessions.id',
        'owner_id->local_owners.id',
      });
      expect(await _uniqueColumnSets(database, 'assessment_runs'), {
        'id',
        'learning_session_id',
        'owner_id,study_cycle_id,phase',
      });
    },
  );
}

/// Frozen v15 fixture: every v14 table and sentinel plus assessment_runs.
void createSchemaFifteenFixture(dynamic sqlite) {
  fixture.createSchemaFourteenFixture(sqlite);
  sqlite.execute('''
    CREATE TABLE assessment_runs (
      id TEXT NOT NULL PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES local_owners(id),
      learning_session_id TEXT NOT NULL REFERENCES learning_sessions(id),
      study_cycle_id TEXT NOT NULL,
      phase TEXT NOT NULL,
      state TEXT NOT NULL,
      protocol_id TEXT NOT NULL,
      protocol_version TEXT NOT NULL,
      experiment_id TEXT NOT NULL,
      experiment_version INTEGER NOT NULL,
      assignment_id TEXT NOT NULL REFERENCES experiment_assignments(id),
      cohort TEXT NOT NULL,
      consent_version INTEGER NOT NULL,
      consent_decided_at_utc_ms INTEGER NOT NULL,
      instrument_id TEXT NOT NULL,
      instrument_version TEXT NOT NULL,
      form_id TEXT NOT NULL,
      form_version TEXT NOT NULL,
      instrument_checksum_sha256 TEXT NOT NULL,
      form_checksum_sha256 TEXT NOT NULL,
      app_version TEXT NOT NULL,
      build_id TEXT NOT NULL,
      database_schema_version INTEGER NOT NULL,
      content_revision TEXT NOT NULL,
      evidence_policy_version TEXT NOT NULL,
      feature_contract_revision TEXT NOT NULL,
      feature_contract_hash TEXT NOT NULL,
      started_at_utc_ms INTEGER NOT NULL,
      completed_at_utc_ms INTEGER,
      abandoned_at_utc_ms INTEGER,
      UNIQUE(learning_session_id),
      UNIQUE(owner_id, study_cycle_id, phase)
    )
  ''');
  sqlite.execute('''
    INSERT INTO assessment_runs(
      id, owner_id, learning_session_id, study_cycle_id, phase, state,
      protocol_id, protocol_version, experiment_id, experiment_version,
      assignment_id, cohort, consent_version, consent_decided_at_utc_ms,
      instrument_id, instrument_version, form_id, form_version,
      instrument_checksum_sha256, form_checksum_sha256, app_version, build_id,
      database_schema_version, content_revision, evidence_policy_version,
      feature_contract_revision, feature_contract_hash, started_at_utc_ms,
      completed_at_utc_ms
    ) VALUES (
      'assessment-run:v15', 'owner:v13', 'session:v13', 'cycle:v15', 'pre',
      'completed', 'protocol:v15', '1.0.0', 'experiment:v14', 1,
      'assignment:v14', 'control', 1, 20, 'instrument:v15', '1.0.0',
      'form:v15', '1.0.0',
      '1111111111111111111111111111111111111111111111111111111111111111',
      '2222222222222222222222222222222222222222222222222222222222222222',
      '1.0.0', 'fixture-v15', 15, 'content:v15', 'legacy-v1',
      'alltcas-8-44-v1',
      '3333333333333333333333333333333333333333333333333333333333333333',
      30, 31
    )
  ''');
  sqlite.execute('PRAGMA user_version = 15');
}

const migrationV15Sentinels = <String, ({String column, String value})>{
  ...fixture.migrationV14Sentinels,
  'assessment_runs': (column: 'id', value: 'assessment-run:v15'),
};

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

Future<List<({String name, String type, bool notNull, bool primaryKey})>>
_columnContract(AppDatabase database, String tableName) async {
  final rows = await database
      .customSelect("PRAGMA table_info('$tableName')")
      .get();
  return rows
      .map(
        (row) => (
          name: row.read<String>('name'),
          type: row.read<String>('type'),
          notNull: row.read<int>('notnull') == 1,
          primaryKey: row.read<int>('pk') == 1,
        ),
      )
      .toList(growable: false);
}

Future<Set<String>> _foreignKeys(AppDatabase database, String tableName) async {
  final rows = await database
      .customSelect("PRAGMA foreign_key_list('$tableName')")
      .get();
  return rows
      .map(
        (row) =>
            '${row.read<String>('from')}->'
            '${row.read<String>('table')}.${row.read<String>('to')}',
      )
      .toSet();
}

Future<Set<String>> _uniqueColumnSets(
  AppDatabase database,
  String tableName,
) async {
  final indexes = await database
      .customSelect("PRAGMA index_list('$tableName')")
      .get();
  final result = <String>{};
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
    result.add(columns.map((row) => row.read<String>('name')).join(','));
  }
  return result;
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
