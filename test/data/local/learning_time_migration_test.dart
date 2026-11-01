import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';

import '../../support/populated_owner_migration_fixture.dart';

void main() {
  test(
    'fresh current schema has three empty local time relations and no backfill',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      expect(database.schemaVersion, 23);
      expect(database.allTables, hasLength(43));
      for (final table in const [
        'learning_time_preferences',
        'learning_time_scopes',
        'learning_time_segments',
      ]) {
        expect(
          await database.customSelect('SELECT * FROM $table').get(),
          isEmpty,
        );
      }
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'time relations enforce bounded durations, exact policy and real parents',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final captured =
          jsonDecode(
                File(
                  'test/fixtures/populated_schema_v20.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>;
      final rows = captured['rows'] as Map<String, dynamic>;
      final owner = Map<String, Object?>.from(
        (rows['local_owners'] as List).first as Map,
      );
      await insertOwnerMigrationRow(database, 'local_owners', owner);
      final ownerId = owner['id'];
      final preference = <String, Object?>{
        'owner_id': ownerId,
        'enabled': 1,
        'revision': 1,
        'updated_at_utc_ms': 0,
      };
      for (final change in <(String, Object?)>[
        ('owner_id', 'missing-owner'),
        ('enabled', 2),
        ('revision', 0),
        ('revision', 1.5),
        ('revision', 9007199254740992),
        ('updated_at_utc_ms', -1),
        ('updated_at_utc_ms', 1.5),
      ]) {
        await expectLater(
          insertOwnerMigrationRow(database, 'learning_time_preferences', {
            ...preference,
            change.$1: change.$2,
          }),
          throwsA(isA<Exception>()),
          reason: change.toString(),
        );
      }
      await insertOwnerMigrationRow(
        database,
        'learning_time_preferences',
        preference,
      );
      final scope = <String, Object?>{
        'id': 'time-scope:synthetic-migration',
        'owner_id': ownerId,
        'source_kind': 'reading',
        'source_binding_json':
            '{"version":1,"documentId":"synthetic","revision":1}',
        'created_at_utc_ms': 20,
        'linked_session_id': null,
        'session_link_binding_json': null,
      };
      for (final change in <(String, Object?)>[
        ('id', 'wrong-prefix'),
        ('id', 'time-scope:  '),
        ('owner_id', 'missing-owner'),
        ('source_kind', 'recreational'),
        ('source_binding_json', ''),
        ('created_at_utc_ms', -1),
        ('linked_session_id', 'missing-session'),
        ('session_link_binding_json', '{}'),
      ]) {
        await expectLater(
          insertOwnerMigrationRow(database, 'learning_time_scopes', {
            ...scope,
            change.$1: change.$2,
          }),
          throwsA(isA<Exception>()),
          reason: change.toString(),
        );
      }
      await insertOwnerMigrationRow(database, 'learning_time_scopes', scope);
      final segment = <String, Object?>{
        'id': 'time-segment:synthetic-migration',
        'scope_id': scope['id'],
        'ordinal': 0,
        'eligibility_context_json': '{"version":1,"stage":"reading"}',
        'started_at_utc_ms': 20,
        'ended_at_utc_ms': 10,
        'active_duration_us': 1,
        'capture_policy_revision': 'confirmed-interaction-v1',
      };
      for (final change in <(String, Object?)>[
        ('id', 'wrong-prefix'),
        ('scope_id', 'missing-scope'),
        ('ordinal', -1),
        ('ordinal', 1.5),
        ('eligibility_context_json', ''),
        ('started_at_utc_ms', -1),
        ('ended_at_utc_ms', -1),
        ('active_duration_us', 0),
        ('active_duration_us', 120000001),
        ('active_duration_us', 1.5),
        ('capture_policy_revision', 'unknown'),
      ]) {
        await expectLater(
          insertOwnerMigrationRow(database, 'learning_time_segments', {
            ...segment,
            change.$1: change.$2,
          }),
          throwsA(isA<Exception>()),
          reason: change.toString(),
        );
      }
      await insertOwnerMigrationRow(
        database,
        'learning_time_segments',
        segment,
      );
      await expectLater(
        insertOwnerMigrationRow(database, 'learning_time_segments', {
          ...segment,
          'id': 'time-segment:duplicate-ordinal',
        }),
        throwsA(isA<Exception>()),
      );
      // UTC observations can move backwards; they never calculate duration.
      expect(
        (await database
                .customSelect(
                  'SELECT active_duration_us FROM learning_time_segments',
                )
                .getSingle())
            .read<int>('active_duration_us'),
        1,
      );
      await database.customStatement(
        'DELETE FROM learning_time_scopes WHERE id = ?',
        [scope['id']],
      );
      expect(
        await database
            .customSelect('SELECT * FROM learning_time_segments')
            .get(),
        isEmpty,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
  test(
    'actual populated v20 migrates and reopens with every old row and DDL intact',
    () async {
      final schema = _fixture(
        'schema_v20.sql',
        '44b96f263f86fe9e32df8533a793fd14a3449a079bb889c3b0946e2c736581e7',
      );
      final rows = _captured();
      expect(
        RegExp(r'^CREATE TABLE', multiLine: true).allMatches(schema),
        hasLength(37),
      );
      expect(schema, isNot(contains('learning_time_')));
      final oldObjects = <String, String>{};
      final before = <String, List<Map<String, Object?>>>{};
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-learning-time-v20-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}historical.sqlite',
      );
      final database = AppDatabase(
        NativeDatabase(
          file,
          setup: (sqlite) {
            for (final statement in schema.split(';')) {
              if (statement.trim().isNotEmpty) sqlite.execute(statement);
            }
            for (final table in rows.entries) {
              for (final row in table.value) {
                sqlite.execute(
                  'INSERT INTO "${table.key}" (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
                  row.values.toList(),
                );
              }
            }
            for (final object in sqlite.select(
              "SELECT type,name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%' ORDER BY name",
            )) {
              final name = object['name']! as String;
              oldObjects[name] = object['sql']! as String;
              if (object['type'] == 'table') {
                before[name] = [
                  for (final row in sqlite.select(
                    'SELECT * FROM "$name" ORDER BY rowid',
                  ))
                    Map<String, Object?>.from(row),
                ];
              }
            }
            sqlite.execute('PRAGMA user_version = 20');
          },
        ),
      );
      var closed = false;
      AppDatabase? reopened;
      addTearDown(() async {
        await reopened?.close();
        if (!closed) await database.close();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-learning-time-v20-',
          ),
        );
        expect(resolved, directory.absolute.path);
        await Directory(resolved).delete(recursive: true);
      });
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        23,
      );
      expect(database.allTables, hasLength(43));
      expect(before, rows);
      final after = await ownerMigrationRows(database);
      for (final table in _newTimeTables) {
        expect(after[table], isEmpty);
      }
      expect(after['learning_profiles'], isEmpty);
      expect(after['learning_pack_versions'], isEmpty);
      expect(after['lexical_content_snapshots'], isEmpty);
      expect(
        Map<String, List<Map<String, Object?>>>.of(after)
          ..removeWhere((key, value) => _newTimeTables.contains(key))
          ..remove('learning_profiles')
          ..remove('learning_pack_versions')
          ..remove('lexical_content_snapshots'),
        before,
      );
      final objects = await database
          .customSelect(
            "SELECT name,sql FROM sqlite_master WHERE sql IS NOT NULL AND name NOT LIKE 'sqlite_%'",
          )
          .get();
      final byName = {
        for (final row in objects)
          row.read<String>('name'): row.read<String>('sql'),
      };
      expect(byName.keys.toSet(), {
        ...oldObjects.keys,
        ..._newTimeTables,
        'learning_profiles',
        'learning_pack_versions',
        'lexical_content_snapshots',
        'idx_lexical_content_owner_word',
        'idx_learning_time_scopes_owner_session',
      });
      for (final object in oldObjects.entries) {
        expect(
          byName[object.key],
          object.value,
          reason: 'Retain exact old DDL ${object.key}',
        );
      }
      expect(after['assessment_runs']!.single['database_schema_version'], 19);
      expect(after['saved_words']!.map((row) => row['is_saved']).toSet(), {
        0,
        1,
      });
      expect(
        after['learning_sessions']!.singleWhere(
          (row) => row['id'] == 'synthetic-retained-pending-quiz',
        )['checkpoint_json'],
        contains('synthetic-retained-unsubmitted-answer'),
      );
      final pending = after['measurement_opportunities']!.singleWhere(
        (row) => row['owner_id'] == 'owner-a',
      );
      expect(pending['last_switch_ordinal'], 10);
      expect(pending['suppressed_switch_count'], 2);
      expect(
        PendingPresentationChange.fromJson(
          pending['pending_presentation_change_json']! as String,
        ).position,
        13,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      final coordinator = DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.utc(2026, 10, 30),
      );
      expect(
        (await coordinator.inspect())!.phase,
        DeletionIntentPhase.pendingCloud,
      );
      await expectLater(
        coordinator.requireOwnerUnfenced('owner-a'),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(await ownerMigrationRows(database), after);
      await database.close();
      closed = true;
      reopened = AppDatabase(NativeDatabase(file));
      expect(await ownerMigrationRows(reopened), after);
      expect(
        await reopened.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

const _newTimeTables = {
  'learning_time_preferences',
  'learning_time_scopes',
  'learning_time_segments',
};

String _fixture(String name, String expectedSha) {
  final value = File(
    'test/fixtures/$name',
  ).readAsStringSync().replaceAll('\r\n', '\n');
  expect(sha256.convert(utf8.encode(value)).toString(), expectedSha);
  return value;
}

Map<String, List<Map<String, Object?>>> _captured() {
  final value =
      jsonDecode(
            _fixture(
              'populated_schema_v20.json',
              'fcb804bb185f2b3c2d43c41fce185ed99597ce18ae06c9a108507afa2cfdbcb4',
            ),
          )
          as Map<String, dynamic>;
  expect(value['schemaVersion'], 20);
  expect(value['tableCount'], 37);
  expect(value['syntheticOnly'], isTrue);
  expect(value['sourceCheckpoint'], '1b56fa039488d86c64342a2e11f1d90fa18100d2');
  final rows = <String, List<Map<String, Object?>>>{
    for (final entry in (value['rows'] as Map<String, dynamic>).entries)
      entry.key: [
        for (final row in entry.value as List<dynamic>)
          Map<String, Object?>.from(row as Map),
      ],
  };
  expect(rows, hasLength(37));
  for (final table in rows.entries) {
    expect(
      table.value,
      isNotEmpty,
      reason: 'Historical populated ${table.key}',
    );
  }
  return rows;
}
