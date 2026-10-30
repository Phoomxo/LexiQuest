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
  test('fresh v20 has one empty ten-column historical report queue', () async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    expect(database.schemaVersion, 20);
    expect(database.allTables, hasLength(37));
    final columns = await database
        .customSelect('PRAGMA table_info(word_reports)')
        .get();
    expect(columns.map((row) => row.read<String>('name')), [
      'id',
      'owner_id',
      'word_id',
      'category_id',
      'word_revision',
      'snapshot_json',
      'snapshot_sha256',
      'reason',
      'comment',
      'queued_at_utc_ms',
    ]);
    expect(columns.map((row) => row.read<int>('notnull')), [
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      1,
      0,
      1,
    ]);
    expect(columns.map((row) => row.read<int>('pk')), [
      1,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
      0,
    ]);
    final keys = await database
        .customSelect('PRAGMA foreign_key_list(word_reports)')
        .get();
    expect(keys, hasLength(1));
    expect(keys.single.read<String>('from'), 'owner_id');
    expect(keys.single.read<String>('table'), 'local_owners');
    expect(keys.single.read<String>('on_delete'), 'RESTRICT');
    expect(
      await database.customSelect('SELECT * FROM word_reports').get(),
      isEmpty,
    );
  });

  test(
    'report queue enforces scalar constraints without requiring a live target',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final captured = _captured();
      await insertOwnerMigrationRow(
        database,
        'local_owners',
        captured['local_owners']!.first,
      );
      final owner = captured['local_owners']!.first['id'];
      final snapshot = jsonEncode({
        'version': 'owned-word-report-v1',
        'wordId': 'historical-word',
        'categoryId': 'historical-category',
        'wordRevision': 1,
        'spelling': 'fixture',
        'meaning': 'synthetic fixture',
        'partOfSpeech': 'noun',
        'source': 'manual',
        'cefrLevel': null,
      });
      final row = <String, Object?>{
        'id': 'word-report:synthetic-storage',
        'owner_id': owner,
        'word_id': 'historical-word',
        'category_id': 'historical-category',
        'word_revision': 1,
        'snapshot_json': snapshot,
        'snapshot_sha256': sha256.convert(utf8.encode(snapshot)).toString(),
        'reason': 'spelling',
        'comment': null,
        'queued_at_utc_ms': 0,
      };
      for (final change in <(String, Object?)>[
        ('id', 'wrong-prefix'),
        ('id', 'word-report:   '),
        ('id', 'word-report:${'a' * 245}'),
        ('owner_id', 'missing-owner'),
        ('word_id', ''),
        ('word_id', 'ก' * 257),
        ('category_id', ' '),
        ('category_id', 'a' * 257),
        ('word_revision', 0),
        ('word_revision', 1.5),
        ('snapshot_json', 'a' * 8193),
        ('snapshot_sha256', 'A' * 64),
        ('snapshot_sha256', 'a' * 63),
        ('snapshot_sha256', 'g' * 64),
        ('reason', 'unknown'),
        ('reason', 'other'),
        ('comment', ''),
        ('comment', ' padded '),
        ('comment', 'a' * 501),
        ('comment', '😀' * 501),
        ('queued_at_utc_ms', -1),
        ('queued_at_utc_ms', 1.5),
        ('queued_at_utc_ms', 8640000000000001),
      ]) {
        await expectLater(
          insertOwnerMigrationRow(database, 'word_reports', {
            ...row,
            change.$1: change.$2,
          }),
          throwsException,
          reason: '${change.$1} scalar constraint',
        );
      }
      await insertOwnerMigrationRow(database, 'word_reports', row);
      expect(
        (await database.customSelect('SELECT * FROM word_reports').get())
            .single
            .data,
        row,
      );
      await insertOwnerMigrationRow(database, 'word_reports', {
        ...row,
        'id': 'word-report:synthetic-unicode-boundary',
        'reason': 'other',
        'comment': '😀' * 500,
        'queued_at_utc_ms': 8640000000000000,
      });
      expect(
        (await database.customSelect('SELECT * FROM word_reports').get()),
        hasLength(2),
      );
      expect(
        await database.customSelect('SELECT * FROM vocabulary_words').get(),
        isEmpty,
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
      await expectLater(
        database.customStatement('DELETE FROM local_owners WHERE id = ?', [
          owner,
        ]),
        throwsException,
      );
    },
  );

  test(
    'actual populated v19 migrates and reopens with every old row and DDL intact',
    () async {
      final schema = _fixture(
        'schema_v19.sql',
        'ea30538113a7837ecf3c896513c71cfe96fd1e62ab2340d051414e6cf87dbd92',
      );
      final rows = _captured();
      expect(
        RegExp(r'^CREATE TABLE', multiLine: true).allMatches(schema),
        hasLength(36),
      );
      expect(schema, isNot(contains('word_reports')));
      final oldObjects = <String, String>{};
      final before = <String, List<Map<String, Object?>>>{};
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-word-reports-v19-');
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
            sqlite.execute('PRAGMA user_version = 19');
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
            '$tempRoot${Platform.pathSeparator}lexiquest-word-reports-v19-',
          ),
        );
        expect(resolved, directory.absolute.path);
        await Directory(resolved).delete(recursive: true);
      });
      expect(
        (await database.customSelect('PRAGMA user_version').getSingle())
            .read<int>('user_version'),
        20,
      );
      expect(database.allTables, hasLength(37));
      expect(before, rows);
      final after = await ownerMigrationRows(database);
      expect(after['word_reports'], isEmpty);
      expect(
        Map<String, List<Map<String, Object?>>>.of(after)
          ..remove('word_reports'),
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
      expect(byName.keys.toSet(), {...oldObjects.keys, 'word_reports'});
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
              'populated_schema_v19.json',
              'c6e03a6f30ed047c31ace45d9aff368da46d1a3a7f104d006c84178a30cdf605',
            ),
          )
          as Map<String, dynamic>;
  expect(value['schemaVersion'], 19);
  expect(value['tableCount'], 36);
  expect(value['syntheticOnly'], isTrue);
  expect(value['sourceCheckpoint'], 'b06be6e8aa0855764e126a73a17f9cb47dd35202');
  final rows = <String, List<Map<String, Object?>>>{
    for (final entry in (value['rows'] as Map<String, dynamic>).entries)
      entry.key: [
        for (final row in entry.value as List<dynamic>)
          Map<String, Object?>.from(row as Map),
      ],
  };
  expect(rows, hasLength(36));
  for (final table in rows.entries) {
    expect(
      table.value,
      isNotEmpty,
      reason: 'Historical populated ${table.key}',
    );
  }
  return rows;
}
