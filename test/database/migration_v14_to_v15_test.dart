import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import 'migration_v13_to_v14_test.dart' as fixture;

void main() {
  test(
    'frozen v14 fixture upgrades to the named 33-table v15 inventory',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: fixture.createSchemaFourteenFixture),
      );
      addTearDown(database.close);

      expect(
        AppDatabase.currentSchemaVersion,
        15,
        reason: 'Task 12 owns the single v14-to-v15 schema advance.',
      );
      expect(database.schemaVersion, AppDatabase.currentSchemaVersion);

      final v14Inventory = fixture.migrationInventoryForSchemaVersion(14);
      final currentInventory = fixture.migrationInventoryForSchemaVersion(
        AppDatabase.currentSchemaVersion,
      );
      expect(v14Inventory, hasLength(32));
      expect(currentInventory, hasLength(33));
      expect(currentInventory.difference(v14Inventory), {'assessment_runs'});
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

      expect(AppDatabase.currentSchemaVersion, 15);
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
