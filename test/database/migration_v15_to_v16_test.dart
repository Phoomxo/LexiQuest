import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v13_to_v14_test.dart' as inventory_fixture;
import 'migration_v14_to_v15_test.dart' as fixture;

void main() {
  test('frozen v15 upgrades through the named current v18 inventory', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: fixture.createSchemaFifteenFixture),
    );
    addTearDown(database.close);

    expect(AppDatabase.currentSchemaVersion, 18);
    final v15Inventory = inventory_fixture.migrationInventoryForSchemaVersion(
      15,
    );
    expect(v15Inventory, hasLength(33));
    expect(currentDatabaseTableInventory, hasLength(40));
    expect(currentDatabaseTableInventory.difference(v15Inventory), {
      'learning_packs',
      'learning_pack_items',
      'content_manifests',
      'content_download_states',
      'saved_learning_items',
      'content_quality_reports',
      'learning_time_segments',
    });
    await expectCurrentDatabaseContract(database);

    for (final sentinel in fixture.migrationV15Sentinels.entries) {
      expect(
        await _count(database, sentinel.key),
        1,
        reason: '${sentinel.key} lost its frozen v15 sentinel row',
      );
      expect(
        await _read<String>(
          database,
          'SELECT ${sentinel.value.column} FROM ${sentinel.key}',
          sentinel.value.column,
        ),
        sentinel.value.value,
        reason: '${sentinel.key} changed its frozen v15 sentinel row',
      );
    }
    for (final table in currentDatabaseTableInventory.difference(
      v15Inventory,
    )) {
      expect(await _count(database, table), 0, reason: table);
    }
  });

  test(
    'v15 learner words gain explicit legacy-safe content identity',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(setup: fixture.createSchemaFifteenFixture),
      );
      addTearDown(database.close);

      expect(
        await _columnNames(database, 'vocabulary_words'),
        containsAll(const <String>[
          'content_revision',
          'content_checksum_sha256',
          'content_provenance',
          'content_review_state',
          'content_publication_state',
        ]),
      );
      final word = await database.customSelect('''
          SELECT content_revision, content_checksum_sha256,
                 content_provenance, content_review_state,
                 content_publication_state
          FROM vocabulary_words WHERE id = 'word:v13'
        ''').getSingle();
      expect(word.read<int>('content_revision'), 1);
      expect(word.readNullable<String>('content_checksum_sha256'), isNull);
      expect(word.read<String>('content_provenance'), 'userAuthored');
      expect(word.read<String>('content_review_state'), 'unreviewed');
      expect(word.read<String>('content_publication_state'), 'private');
    },
  );

  test('v16 content tables pin immutable identity and FK references', () async {
    final database = AppDatabase(
      NativeDatabase.memory(setup: fixture.createSchemaFifteenFixture),
    );
    addTearDown(database.close);

    expect(await _columnNames(database, 'content_manifests'), const [
      'id',
      'content_type',
      'content_id',
      'revision',
      'checksum_sha256',
      'byte_length',
      'provenance',
      'source_uri',
      'review_state',
      'publication_state',
      'created_at_utc_ms',
      'reviewed_at_utc_ms',
      'published_at_utc_ms',
    ]);
    expect(await _columnNames(database, 'learning_packs'), const [
      'id',
      'pack_id',
      'revision',
      'manifest_id',
      'title',
      'cefr_level',
      'topic',
      'skill',
      'goal',
      'created_at_utc_ms',
    ]);
    expect(await _columnNames(database, 'learning_pack_items'), const [
      'id',
      'learning_pack_id',
      'vocabulary_word_id',
      'position',
    ]);
    expect(await _columnNames(database, 'content_download_states'), const [
      'id',
      'manifest_id',
      'state',
      'local_path',
      'downloaded_bytes',
      'verified_checksum_sha256',
      'failure_code',
      'updated_at_utc_ms',
    ]);
    expect(await _foreignKeys(database, 'learning_packs'), {
      'manifest_id->content_manifests.id',
    });
    expect(await _foreignKeys(database, 'learning_pack_items'), {
      'learning_pack_id->learning_packs.id',
    });
    expect(await _foreignKeys(database, 'content_download_states'), {
      'manifest_id->content_manifests.id',
    });
    expect(await _uniqueColumnSets(database, 'content_manifests'), {
      'id',
      'content_type,content_id,revision',
    });
    expect(await _uniqueColumnSets(database, 'learning_packs'), {
      'id',
      'manifest_id',
      'pack_id,revision',
    });
    expect(await _uniqueColumnSets(database, 'learning_pack_items'), {
      'id',
      'learning_pack_id,position',
      'learning_pack_id,vocabulary_word_id',
    });
    expect(await _uniqueColumnSets(database, 'content_download_states'), {
      'id',
      'manifest_id',
    });

    await expectLater(
      database.customInsert('''
        INSERT INTO learning_packs(
          id, pack_id, revision, manifest_id, title, cefr_level, topic,
          skill, goal, created_at_utc_ms
        ) VALUES (
          'pack:missing:r1', 'pack:missing', 1, 'manifest:missing', 'Missing',
          'A1', 'travel', 'vocabulary', 'recognition', 1
        )
      '''),
      throwsA(isA<Exception>()),
    );
    await expectLater(
      database.customInsert('''
        INSERT INTO learning_pack_items(
          id, learning_pack_id, vocabulary_word_id, position
        ) VALUES ('item:missing', 'pack:missing:r1', 'word:v13', 0)
      '''),
      throwsA(isA<Exception>()),
    );
  });
}

Future<List<String>> _columnNames(AppDatabase database, String tableName) {
  return database
      .customSelect("PRAGMA table_info('$tableName')")
      .map((row) => row.read<String>('name'))
      .get();
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

Future<int> _count(AppDatabase database, String tableName) => database
    .customSelect('SELECT COUNT(*) AS count FROM $tableName')
    .map((row) => row.read<int>('count'))
    .getSingle();

Future<T> _read<T extends Object>(
  AppDatabase database,
  String statement,
  String column,
) => database
    .customSelect(statement)
    .map((row) => row.read<T>(column))
    .getSingle();
