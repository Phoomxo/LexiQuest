import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../../support/answer_attempt_evidence_fixture.dart';

void main() {
  test('populated v11 gains an empty assignment table without changing facts', () async {
    final before = <String, List<Map<String, Object?>>>{};
    final schema = File('test/fixtures/schema_v11.sql').readAsStringSync();
    expect(RegExp('CREATE TABLE').allMatches(schema), hasLength(29));
    expect(schema, contains('evidence_context_json'));
    expect(schema, isNot(contains('experiment_assignments')));
    final evidence = jsonEncode(ordinaryAnswerEvidence().toJson());
    final database = AppDatabase(
      NativeDatabase.memory(
        setup: (sqlite) {
          for (final statement in schema.split(';')) {
            if (statement.trim().isNotEmpty) sqlite.execute(statement);
          }
          sqlite.execute(
            "INSERT INTO local_owners (id, firebase_uid, account_state, created_at_utc_ms, is_active) VALUES ('owner-a', 'uid-a', 'registered', 1, 1), ('owner-b', 'uid-b', 'registered', 2, 0)",
          );
          sqlite.execute(
            "INSERT INTO research_consents (id, owner_id, consent_version, consent_state, decided_at_utc_ms) VALUES ('consent-a', 'owner-a', 3, 'accepted', 2000)",
          );
          for (final suffix in ['a', 'b']) {
            sqlite.execute(
              'INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, 1, 1)',
              ['category-$suffix', 'owner-$suffix', suffix, suffix],
            );
            sqlite.execute(
              'INSERT INTO vocabulary_words (id, owner_id, category_id, spelling, normalized_spelling, meaning, normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 1)',
              [
                'word-$suffix',
                'owner-$suffix',
                'category-$suffix',
                suffix,
                suffix,
                'meaning $suffix',
                'meaning $suffix',
                'noun',
              ],
            );
            sqlite.execute(
              "INSERT INTO learning_sessions (id, owner_id, activity_type, state, started_at_utc_ms, app_version, build_id) VALUES (?, ?, 'quiz', 'active', 3000, 'test', 'v11-snapshot')",
              ['session-$suffix', 'owner-$suffix'],
            );
            sqlite.execute(
              "INSERT INTO answer_attempts (id, owner_id, session_id, word_id, prompt_mode, is_correct, response_time_ms, attempt_number, occurred_at_utc_ms, evidence_class, evidence_context_json) VALUES (?, ?, ?, ?, 'meaningChoice', 1, 320, 1, 4000, 'recognition', ?)",
              [
                'answer-$suffix',
                'owner-$suffix',
                'session-$suffix',
                'word-$suffix',
                evidence,
              ],
            );
          }
          sqlite.execute(
            "INSERT INTO outbox_operations (operation_id, owner_id, entity_type, entity_id, operation_kind, created_at_utc_ms, payload_version) VALUES ('attempt:answer-a:1', 'owner-a', 'attempt', 'answer-a', 'append', 4000, 2)",
          );
          for (final table in sqlite.select(
            "SELECT name FROM sqlite_master WHERE type = 'table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
          )) {
            final name = table['name'] as String;
            before[name] = [
              for (final row in sqlite.select(
                'SELECT * FROM "$name" ORDER BY rowid',
              ))
                Map<String, Object?>.from(row),
            ];
          }
          sqlite.execute('PRAGMA user_version = 11');
        },
      ),
    );
    addTearDown(database.close);
    expect(
      (await database.customSelect('PRAGMA user_version').getSingle())
          .read<int>('user_version'),
      20,
    );
    expect(database.allTables, hasLength(37));
    expect(
      await database.customSelect('SELECT * FROM word_reports').get(),
      isEmpty,
    );
    expect(
      await database.customSelect('SELECT * FROM assessment_runs').get(),
      isEmpty,
    );
    expect(
      await database.customSelect('SELECT * FROM saved_words').get(),
      isEmpty,
    );
    expect(
      await database.customSelect('SELECT * FROM experiment_assignments').get(),
      isEmpty,
    );
    for (final table in before.entries) {
      final after = await database
          .customSelect('SELECT * FROM "${table.key}" ORDER BY rowid')
          .get();
      expect(
        after
            .map(
              (row) => Map<String, Object?>.from(row.data)
                ..remove('accepted_plan_id')
                ..remove('accepted_plan_json')
                ..remove('checkpoint_revision')
                ..remove('checkpoint_json'),
            )
            .toList(),
        table.value,
        reason: table.key,
      );
    }
    final columns = await database
        .customSelect('PRAGMA table_info(experiment_assignments)')
        .get();
    expect(columns.map((row) => row.read<String>('name')).toSet(), {
      'id',
      'owner_id',
      'experiment_id',
      'experiment_version',
      'cohort',
      'protocol_version',
      'assigned_at_utc_ms',
    });
    final foreignKeys = await database
        .customSelect('PRAGMA foreign_key_list(experiment_assignments)')
        .get();
    expect(foreignKeys.single.read<String>('table'), 'local_owners');
    expect(foreignKeys.single.read<String>('from'), 'owner_id');
  });

  test(
    'assignments require an owner and a unique owner experiment version',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement(
        "INSERT INTO local_owners (id, created_at_utc_ms) VALUES ('owner-a', 1)",
      );
      const insert =
          'INSERT INTO experiment_assignments (id, owner_id, experiment_id, experiment_version, cohort, protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, ?, ?, ?, ?)';
      await database.customStatement(insert, [
        'assignment-a',
        'owner-a',
        'synthetic-study',
        1,
        'standard',
        'protocol-v1',
        4000,
      ]);
      await expectLater(
        database.customStatement(insert, [
          'assignment-duplicate',
          'owner-a',
          'synthetic-study',
          1,
          'standard',
          'protocol-v1',
          4000,
        ]),
        throwsException,
      );
      await expectLater(
        database.customStatement(insert, [
          'assignment-unowned',
          'absent-owner',
          'synthetic-study',
          1,
          'standard',
          'protocol-v1',
          4000,
        ]),
        throwsException,
      );
      final rows = await database
          .customSelect('SELECT id, owner_id FROM experiment_assignments')
          .get();
      expect(rows, hasLength(1));
      expect(rows.single.read<String>('id'), 'assignment-a');
      expect(rows.single.read<String>('owner_id'), 'owner-a');
    },
  );
}
