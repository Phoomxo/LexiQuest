import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart'
    show
        ApplyInterceptor,
        OpeningDetails,
        QueryExecutor,
        QueryExecutorUser,
        QueryInterceptor;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';

const _ownerA = 'local:lineage-a';
const _ownerB = 'local:lineage-b';
const _sessionA = 'lineage-session-a';
const _civilDay = '2026-01-15';

void main() {
  for (final (name, filename, originalVersion) in [
    ('direct v25', 'schema.sql', 25),
    ('v25 upgraded from v23', 'schema_upgraded_from_v23.sql', 25),
    ('v25 opened by v29 APK source', 'schema_relabelled_v10.sql', 10),
  ]) {
    test('$name preserves study and owner archives in v26 on reopen', () async {
      final file = await _fixtureFile(filename, originalVersion);

      for (var opening = 0; opening < 2; opening++) {
        final database = AppDatabase(NativeDatabase(file));
        try {
          final progress = DriftProgressQueries(database);
          final history = await progress.loadLatestSessionForCategory(
            ownerId: _ownerA,
            categoryId: 'category-a',
          );
          expect(history, isNotNull);
          expect(history!.summary.id, _sessionA);
          expect(history.summary.score, 67);
          expect(history.summary.correctCount, 2);
          expect(history.summary.wrongCount, 1);
          expect(history.categoryName, 'Travel');
          expect(history.originalAnswers, isNull);
          expect(history.mistakes.map((word) => word.id), ['word-a']);
          expect(
            await progress.loadSession(ownerId: _ownerB, sessionId: _sessionA),
            isNull,
          );
        } finally {
          await database.close();
        }

        final raw = sqlite.sqlite3.open(
          file.path,
          mode: sqlite.OpenMode.readOnly,
        );
        try {
          expect(_version(raw), 26);
          expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
          expect(
            raw
                .select('''
              SELECT owner_id, spelling, is_bookmarked FROM vocabulary_words
              ORDER BY owner_id
              ''')
                .map((row) => row.values.toList()),
            [
              [_ownerA, 'station', 1],
              [_ownerB, 'kitchen', 0],
            ],
          );
          expect(
            raw
                .select('''
              SELECT instance_id, owner_id, state, record_kind FROM quest_instances
              ORDER BY instance_id
              ''')
                .map((row) => row.values.toList()),
            [
              ['quest-a-first', _ownerA, 'completed', 'legacy'],
              ['quest-a-second', _ownerA, 'expired', 'legacy'],
            ],
          );
          expect(
            raw
                .select('''
              SELECT id, instance_id, current_count, source_event_ids_json
              FROM quest_objective_progress
              ''')
                .single
                .values
                .toList(),
            ['objective-a', 'quest-a-first', 2, '["event-a"]'],
          );
          expect(raw.select('SELECT * FROM quest_claim_receipts'), isEmpty);
          expect(
            raw
                .select('''
              SELECT owner_id, learning_day, first_session_at_utc_ms
              FROM learning_day_log ORDER BY owner_id, learning_day
              ''')
                .map((row) => row.values.toList()),
            [
              [_ownerA, _civilDay, 1768478400000],
              [_ownerB, _civilDay, 1768478400500],
            ],
          );
          _expectArchived(raw, 'quest_instances', 'quest-a-first', _ownerA, {
            'period_key': 'v25-pinned-week',
            'definition_snapshot_json': '{"synthetic":"quest-a"}',
          });
          _expectArchived(raw, 'learning_day_log', 'day-a-later', _ownerA, {
            'source_attempt_id': 'attempt-a-2',
            'timezone_id': 'Asia/Bangkok',
            'policy_version': 1,
          });
          _expectArchived(raw, 'learning_sessions', _sessionA, _ownerA, {
            'accepted_plan_id': 'previous-round-a',
            'checkpoint_json': '{"syntheticCheckpoint":"A"}',
          });
          _expectArchived(raw, 'study_reminder_preferences', _ownerA, _ownerA, {
            'minute_of_day': 540,
          });
          _expectArchived(raw, 'study_reminder_preferences', _ownerB, _ownerB, {
            'minute_of_day': 650,
          });
        } finally {
          raw.close();
        }
      }
    });
  }

  test(
    'new practice after v25 upgrade retains only earned historical rewards',
    () async {
      final file = await _fixtureFile(
        'schema_relabelled_v10.sql',
        10,
        adjust: (raw) {
          raw.execute('''
          INSERT INTO learning_sessions
            (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,
             correct_count,wrong_count,score,app_version,build_id)
          VALUES ('mixed','$_ownerA','quiz','completed',1768478405000,1768478408000,
                  2,0,83,'v25','synthetic'),
                 ('private-round','$_ownerA','quiz','completed',1768478409000,1768478411000,
                  1,0,100,'v25','synthetic');
          INSERT INTO answer_attempts
            (id,owner_id,session_id,word_id,prompt_mode,is_correct,attempt_number,
             occurred_at_utc_ms)
          VALUES ('mixed-ordinary','$_ownerA','mixed','word-a','meaningChoice',1,1,1768478406000),
                 ('mixed-assisted','$_ownerA','mixed','word-a','hintedRecall',1,2,1768478407000),
                 ('assessment-response:${'e' * 64}','$_ownerA','private-round','word-a','meaningChoice',1,1,1768478410000);
          INSERT INTO points_ledger_entries
            (id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms)
          VALUES ('points:attempt-a-2','$_ownerA','correct-answer:attempt-a-2',
                  'quizCorrect',1,'attempt-a-2',1768478401000),
                 ('points:attempt-a-3','$_ownerA','correct-answer:attempt-a-3',
                  'quizCorrect',1,'attempt-a-3',1768478402000),
                 ('private-xp','$_ownerA','synthetic-private-xp',
                  'quizCorrect',100,'private-round',1768478410000);
          INSERT INTO reward_transactions
            (id,owner_id,idempotency_key,transaction_type,amount,catalog_version,source_event_id,occurred_at_utc_ms)
          VALUES ('coin:quiz:attempt-a-2','$_ownerA','creditQuizCorrectV1:attempt-a-2',
                  'creditQuizCorrectV1',1,0,'attempt-a-2',1768478401000);
          INSERT INTO outbox_operations
            (operation_id,owner_id,entity_type,entity_id,operation_kind,payload_version,state,created_at_utc_ms,acknowledged_at_utc_ms)
          VALUES ('old-v2','$_ownerA','attempt','attempt-a-2','upsert',2,'pending',10,NULL),
                 ('old-v2-ack','$_ownerA','attempt','attempt-a-3','upsert',2,'acknowledged',11,12),
                 ('old-mixed-v1','$_ownerA','attempt','mixed-ordinary','upsert',1,'pending',13,NULL),
                 ('old-private-v1','$_ownerA','attempt','assessment-response:${'e' * 64}','upsert',1,'pending',14,NULL);
          INSERT INTO learning_pack_versions
            (id,owner_id,pack_id,pack_version,manifest_json,manifest_sha256,package_sha256,
             package_byte_count,package_bytes,retained_media_json,retained_media_sha256,
             source_descriptor_json,is_pinned,revision,last_mutation_id,last_mutation_sha256,
             created_at_utc_ms,updated_at_utc_ms)
          VALUES ('pack','$_ownerB','pack','v1','{}','${'a' * 64}','${'b' * 64}',4,X'0001FEFF',
                  '{}','${'c' * 64}','{}',1,1,'install','${'d' * 64}',2,2);
          ''');
        },
      );
      final database = AppDatabase(NativeDatabase(file));
      try {
        final learning = DriftLearningRepository(database);
        final progress = DriftProgressQueries(database);
        final old = await progress.loadSession(
          ownerId: _ownerA,
          sessionId: 'mixed',
        );
        expect(old?.summary.score, 83);
        expect(old?.mistakes, isEmpty);
        expect(
          await progress.loadSession(
            ownerId: _ownerA,
            sessionId: 'private-round',
          ),
          isNull,
        );
        final now = DateTime.utc(2026, 2, 12);
        expect((await progress.load(ownerId: _ownerA, nowUtc: now)).totalXp, 2);
        final retainedPack = await database
            .customSelect(
              "SELECT owner_id,payload_blob FROM archived_v25_records WHERE source_table='learning_pack_versions'",
            )
            .getSingle();
        expect(retainedPack.read<String>('owner_id'), _ownerB);
        expect(retainedPack.data['payload_blob'], [0, 1, 254, 255]);
        expect(
          (await learning.rewardProjections.readLedger(_ownerA)).balance,
          1,
        );

        await learning.startSession(
          LearningSessionDraft(
            id: 'new-session',
            ownerId: _ownerA,
            activityType: 'quiz',
            startedAtUtc: now,
            appVersion: 'v26',
            buildId: 'synthetic',
          ),
        );
        final command = RecordAnswerCommand(
          id: 'new-answer',
          ownerId: _ownerA,
          sessionId: 'new-session',
          wordId: 'word-a',
          promptMode: 'meaningChoice',
          isCorrect: true,
          responseTimeMs: 275,
          attemptNumber: 1,
          occurredAtUtc: now,
        );
        final result = await learning.recordAnswer(command);
        expect(result.inserted, isTrue);
        expect(result.srs.repetitions, 3);
        expect((await learning.recordAnswer(command)).inserted, isFalse);
        expect(
          (await learning.rewardProjections.readLedger(_ownerA)).balance,
          2,
        );
        expect(
          (await learning.rewardProjections.readLedger(_ownerB)).balance,
          0,
        );
        final xp = await database.select(database.pointsLedgerEntries).get();
        expect(xp.map((row) => row.sourceEventId).toSet(), {
          'attempt-a-2',
          'attempt-a-3',
          'new-answer',
          'private-round',
        });
        expect((await progress.load(ownerId: _ownerA, nowUtc: now)).totalXp, 3);
        final awards = await database.select(database.achievementUnlocks).get();
        expect(
          {for (final row in awards) row.achievementId: row.sourceEventId},
          {'first_answer': 'new-answer', 'first_correct': 'new-answer'},
        );

        final claims = await DriftSyncStore(database).claimPending(
          ownerId: _ownerA,
          firebaseUid: 'synthetic-uid',
          limit: 10,
          leaseToken: 'synthetic-lease',
          leaseDuration: const Duration(minutes: 5),
          nowUtc: now,
        );
        expect(
          claims.map((claim) => claim.mutation.entityId),
          contains('new-answer'),
        );
        expect(
          claims.map((claim) => claim.mutation.operationId),
          isNot(
            contains(
              anyOf('old-v2', 'old-v2-ack', 'old-mixed-v1', 'old-private-v1'),
            ),
          ),
        );
        final outbox = await database.select(database.outboxOperations).get();
        expect(
          {
            for (final row in outbox.where(
              (r) => r.operationId.startsWith('old-'),
            ))
              row.operationId: row.state,
          },
          {
            'old-v2': 'historicalV25',
            'old-v2-ack': 'acknowledged',
            'old-mixed-v1': 'historicalV25',
            'old-private-v1': 'historicalV25',
          },
        );
      } finally {
        await database.close();
      }
    },
  );

  test(
    'rejects a cross-owner category link with valid SQLite foreign keys',
    () async {
      final file = await _fixtureFile(
        'schema.sql',
        25,
        adjust: (raw) {
          raw.execute(
            "UPDATE vocabulary_words SET category_id='category-b' WHERE id='word-a'",
          );
        },
      );
      await _expectRejected(file, contains('owner link mismatch'));
    },
  );

  test(
    'the persisted assessment link overrides ordinary-looking metadata',
    () async {
      final file = await _fixtureFile(
        'schema.sql',
        25,
        adjust: (raw) {
          final digest = 'a' * 64;
          raw.execute('''
        INSERT INTO experiment_assignments
          (id,owner_id,experiment_id,experiment_version,cohort,protocol_version,assigned_at_utc_ms)
          VALUES ('synthetic-assignment','$_ownerA','synthetic',1,'standard','1',1);
        INSERT INTO research_participation_permits
          (id,owner_id,participant_class,age_band_code,assignment_id,assigned_treatment,
           consent_receipt_id,protocol_id,protocol_version,issued_at_utc_ms,expires_at_utc_ms,
           issuer_key_id,payload_sha256,signature)
          VALUES ('synthetic-permit','$_ownerA','adult','synthetic','synthetic-assignment',
                  'standard','synthetic-consent','synthetic','1',2,100,
                  'synthetic-key','$digest','synthetic-signature');
        INSERT INTO motivation_measurement_runs
          (id,owner_id,permit_id,permit_payload_sha256,assignment_id,assignment_revision,
           consent_version,consent_decided_at_utc_ms,protocol_id,protocol_version,
           protocol_revision,treatment,instrument_id,instrument_version,instrument_revision,
           instrument_checksum_sha256,form_id,form_version,item_catalog_version,
           scoring_rule_version,app_version,build_id,database_schema_version,content_revision,
           evidence_policy_version,catalog_version,state,started_at_utc_ms)
          VALUES ('synthetic-run','$_ownerA','synthetic-permit','$digest','synthetic-assignment',
                  1,1,1,'synthetic','1',1,'standard','synthetic','1',1,'$digest',
                  'synthetic','1','1','normalized-score-v1','v25','synthetic',25,'1','1','1',
                  'started',3);
        INSERT INTO assessment_runs
          (id,owner_id,learning_session_id,study_cycle_id,phase,state,protocol_id,
           protocol_version,experiment_id,experiment_version,assignment_id,cohort,
           consent_version,consent_decided_at_utc_ms,instrument_id,instrument_version,
           form_id,form_version,instrument_checksum_sha256,form_checksum_sha256,app_version,
           build_id,database_schema_version,content_revision,evidence_policy_version,
           feature_contract_revision,feature_contract_hash,started_at_utc_ms,
           assignment_revision,protocol_revision,instrument_revision,form_content_revision,
           participation_permit_id,participation_permit_revision,participation_permit_payload_sha256)
          VALUES ('synthetic-assessment','$_ownerA','$_sessionA','synthetic-run','pre',
                  'active','synthetic','1','synthetic',1,'synthetic-assignment','standard',
                  1,1,'synthetic','1','synthetic','1','$digest','$digest','v25','synthetic',
                  25,'1','1','1','$digest',4,1,1,1,1,'synthetic-permit',1,'$digest');
        INSERT INTO outbox_operations
          (operation_id,owner_id,entity_type,entity_id,operation_kind,created_at_utc_ms)
          VALUES ('purported-ordinary','$_ownerA','attempt','attempt-a-2','upsert',5);
        ''');
        },
      );
      await _openAndRead(file);
      final raw = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        expect(
          raw
              .select('SELECT activity_type FROM learning_sessions')
              .single['activity_type'],
          'assessment',
        );
        expect(
          raw
              .select(
                'SELECT DISTINCT legacy_evidence_disposition FROM answer_attempts',
              )
              .single['legacy_evidence_disposition'],
          'history-v25',
        );
        expect(
          raw.select('SELECT state FROM outbox_operations').single['state'],
          'historicalV25',
        );
        expect(
          raw.select(
            'SELECT COUNT(*) AS n FROM learning_day_log WHERE owner_id = ?',
            [_ownerA],
          ).single['n'],
          0,
        );
        _expectArchived(raw, 'learning_sessions', _sessionA, _ownerA, {
          'activity_type': 'quiz',
        });
      } finally {
        raw.close();
      }
    },
  );

  test('rejects a modified historical schema without changing it', () async {
    final file = await _fixtureFile(
      'schema_relabelled_v10.sql',
      10,
      adjust: (raw) {
        raw.execute(
          'CREATE INDEX unexpected_historical_idx ON quest_instances(state)',
        );
      },
    );
    await _expectRejected(
      file,
      contains('Unrecognized historical schema 25 layout'),
    );
  });

  test(
    'late v26 failure restores historical rows and repair can be retried',
    () async {
      final file = await _fixtureFile('schema.sql', 25);
      await _expectRejected(
        file,
        contains('Synthetic fault after archive'),
        injectLateFailure: true,
      );
      await _openAndRead(file);
      final raw = sqlite.sqlite3.open(
        file.path,
        mode: sqlite.OpenMode.readOnly,
      );
      try {
        expect(_version(raw), 26);
        _expectArchived(raw, 'learning_day_log', 'day-a-later', _ownerA, {
          'source_attempt_id': 'attempt-a-2',
        });
      } finally {
        raw.close();
      }
    },
  );

  test('preserves the minimum signed SQLite rowid and its history', () async {
    final file = await _fixtureFile(
      'schema.sql',
      25,
      adjust: (raw) {
        raw.execute('''
        UPDATE answer_attempts SET rowid = -9223372036854775808 WHERE id = 'attempt-a-1';
        UPDATE learning_day_log SET rowid = -9223372036854775808 WHERE id = 'day-a-first';
        ''');
      },
    );
    await _openAndRead(file);
    final raw = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
    try {
      expect(_version(raw), 26);
      _expectArchived(raw, 'answer_attempts', 'attempt-a-1', _ownerA, {
        'occurred_at_utc_ms': 1768478400000,
      });
      _expectArchived(raw, 'learning_day_log', 'day-a-first', _ownerA, {
        'source_attempt_id': 'attempt-a-1',
      });
      expect(
        raw.select('SELECT id FROM learning_day_log WHERE owner_id = ?', [
          _ownerA,
        ]).single['id'],
        'day-a-first',
      );
    } finally {
      raw.close();
    }
  });
}

Future<File> _fixtureFile(
  String filename,
  int originalVersion, {
  void Function(sqlite.Database)? adjust,
}) async {
  final directory = await Directory.systemTemp.createTemp('lexiquest-v25-');
  final allocatedPath = await directory.resolveSymbolicLinks();
  addTearDown(() async {
    final resolved = Directory(await directory.resolveSymbolicLinks());
    expect(resolved.path, allocatedPath);
    expect(
      resolved.parent.path,
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    expect(
      resolved.uri.pathSegments.where((p) => p.isNotEmpty).last,
      startsWith('lexiquest-v25-'),
    );
    await resolved.delete(recursive: true);
  });
  final file = File('${directory.path}/synthetic.sqlite');
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute('PRAGMA foreign_keys = ON');
    raw.execute(
      File('test/fixtures/database/v25/$filename').readAsStringSync(),
    );
    expect(_version(raw), originalVersion);
    expect(raw.select('PRAGMA table_info(quest_instances)'), hasLength(12));
    _seedV25(raw);
    adjust?.call(raw);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    return file;
  } finally {
    raw.close();
  }
}

Future<void> _openAndRead(File file, {bool injectLateFailure = false}) async {
  final native = NativeDatabase(file);
  final database = AppDatabase(
    injectLateFailure ? native.interceptWith(_FailBeforeV26Stamp()) : native,
  );
  try {
    await database
        .customSelect('SELECT count(*) FROM vocabulary_words')
        .getSingle();
  } finally {
    await database.close();
  }
}

Future<void> _expectRejected(
  File file,
  Matcher message, {
  bool injectLateFailure = false,
}) async {
  final before = _historicalSnapshot(file);
  await expectLater(
    _openAndRead(file, injectLateFailure: injectLateFailure),
    throwsA(
      isA<StateError>().having((error) => error.message, 'reason', message),
    ),
  );
  expect(_historicalSnapshot(file), before);
}

Object _historicalSnapshot(File file) {
  final raw = sqlite.sqlite3.open(file.path, mode: sqlite.OpenMode.readOnly);
  try {
    final schema = raw.select('''
      SELECT type, name, sql FROM sqlite_master
      WHERE name NOT GLOB 'sqlite_*' AND sql IS NOT NULL
      ORDER BY type, name
      ''');
    return {
      'version': _version(raw),
      'schema': schema.map((row) => row.values.toList()).toList(),
      'rows': {
        for (final row in schema.where((row) => row['type'] == 'table'))
          row['name']: raw
              .select('SELECT rowid,* FROM "${row['name']}" ORDER BY rowid')
              .map((row) => row.values.toList())
              .toList(),
      },
    };
  } finally {
    raw.close();
  }
}

final class _FailBeforeV26Stamp extends QueryInterceptor {
  @override
  Future<bool> ensureOpen(QueryExecutor executor, QueryExecutorUser user) =>
      executor.ensureOpen(_InterceptedMigrationUser(user, this));

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    if (statement.trim().toLowerCase() == 'pragma user_version = 26') {
      throw StateError('Synthetic fault after archive');
    }
    await super.runCustom(executor, statement, args);
  }
}

final class _InterceptedMigrationUser implements QueryExecutorUser {
  const _InterceptedMigrationUser(this.user, this.interceptor);

  final QueryExecutorUser user;
  final QueryInterceptor interceptor;

  @override
  int get schemaVersion => user.schemaVersion;

  @override
  Future<void> beforeOpen(QueryExecutor executor, OpeningDetails details) =>
      user.beforeOpen(executor.interceptWith(interceptor), details);
}

int _version(sqlite.Database database) =>
    database.select('PRAGMA user_version').single['user_version'] as int;

void _expectArchived(
  sqlite.Database database,
  String table,
  String key,
  String owner,
  Map<String, Object?> values,
) {
  final archived = database.select(
    'SELECT owner_id, origin_owner_id, payload_json FROM archived_v25_records '
    'WHERE source_table = ? AND source_row_key = ?',
    [table, key],
  ).single;
  expect(archived['owner_id'], owner);
  expect(archived['origin_owner_id'], owner);
  final payload = jsonDecode(archived['payload_json'] as String) as Map;
  for (final entry in values.entries) {
    expect(payload[entry.key], entry.value, reason: '$table/$key/${entry.key}');
  }
}

void _seedV25(sqlite.Database database) {
  database.execute('''
    INSERT INTO local_owners (id, created_at_utc_ms, is_active) VALUES
      ('$_ownerA', 1, 1), ('$_ownerB', 2, 0);
    INSERT INTO vocabulary_categories
      (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms)
    VALUES
      ('category-a', '$_ownerA', 'Travel', 'travel', 1, 1),
      ('category-b', '$_ownerB', 'Kitchen', 'kitchen', 2, 2);
    INSERT INTO vocabulary_words
      (id, owner_id, category_id, spelling, normalized_spelling, meaning,
       normalized_meaning, part_of_speech, created_at_utc_ms, updated_at_utc_ms)
    VALUES
      ('word-a', '$_ownerA', 'category-a', 'station', 'station', 'สถานี', 'สถานี', 'noun', 1, 1),
      ('word-b', '$_ownerB', 'category-b', 'kitchen', 'kitchen', 'ครัว', 'ครัว', 'noun', 2, 2);
    INSERT INTO learning_sessions
      (id, owner_id, activity_type, state, started_at_utc_ms, ended_at_utc_ms,
       correct_count, wrong_count, score, app_version, build_id, accepted_plan_id,
       accepted_plan_json, checkpoint_revision, checkpoint_json)
    VALUES
      ('$_sessionA', '$_ownerA', 'quiz', 'completed', 1768478399100, 1768478403000,
       2, 1, 67, '1.0.0', 'synthetic-v25', 'previous-round-a',
       '{"syntheticPlan":"A"}', 3, '{"syntheticCheckpoint":"A"}');
    INSERT INTO answer_attempts
      (id, owner_id, session_id, word_id, prompt_mode, is_correct,
       response_time_ms, attempt_number, occurred_at_utc_ms)
    VALUES
      ('attempt-a-1', '$_ownerA', '$_sessionA', 'word-a', 'meaningChoice', 0, 300, 1, 1768478400000),
      ('attempt-a-2', '$_ownerA', '$_sessionA', 'word-a', 'meaningChoice', 1, 250, 2, 1768478401000),
      ('attempt-a-3', '$_ownerA', '$_sessionA', 'word-a', 'meaningChoice', 1, 250, 3, 1768478402000);
    INSERT INTO learning_day_log
      (id, owner_id, learning_day, first_session_at_utc_ms,
       source_attempt_id, timezone_id, policy_version)
    VALUES
      ('day-a-first', '$_ownerA', '$_civilDay', 1768478400000, 'attempt-a-1', 'Asia/Bangkok', 1),
      ('day-a-later', '$_ownerA', '$_civilDay', 1768478401000, 'attempt-a-2', 'Asia/Bangkok', 1),
      ('day-b', '$_ownerB', '$_civilDay', 1768478400500, NULL, NULL, NULL);
    INSERT INTO quest_definitions
      (quest_id, catalog_version, title, description, type, objectives_json, reward_json)
    VALUES ('quest-v25', 1, 'Historical quest', 'Synthetic', 'weekly', '[]', '{}');
    INSERT INTO quest_instances
      (instance_id, quest_id, owner_id, catalog_version, assigned_at_utc_ms,
       state, completed_at_utc_ms, expired_at_utc_ms, period_key, period_json,
       definition_snapshot_json, definition_sha256)
    VALUES
      ('quest-a-first', 'quest-v25', '$_ownerA', 1, 1768478399100, 'completed',
       1768478403000, NULL, 'v25-pinned-week', '{"syntheticPeriod":"a"}',
       '{"synthetic":"quest-a"}', '${'a' * 64}'),
      ('quest-a-second', 'quest-v25', '$_ownerA', 1, 1768478399000, 'expired',
       NULL, 1768478400000, 'legacy:quest-a-second', NULL, NULL, NULL);
    INSERT INTO quest_objective_progress
      (id, instance_id, objective_id, current_count, target_count, source_event_ids_json)
    VALUES ('objective-a', 'quest-a-first', 'correct-2', 2, 2, '["event-a"]');
    INSERT INTO saved_words
      (owner_id, word_id, is_saved, local_revision, first_saved_at_utc_ms,
       updated_at_utc_ms, last_mutation_id)
    VALUES
      ('$_ownerA', 'word-a', 1, 2, 1, 5, 'save-a'),
      ('$_ownerB', 'word-b', 0, 3, 2, 6, 'unsave-b');
    INSERT INTO study_reminder_preferences
      (owner_id, enabled, minute_of_day, timezone_id, revision, updated_at_utc_ms)
    VALUES
      ('$_ownerA', 1, 540, 'Asia/Bangkok', 1, 4),
      ('$_ownerB', 0, 650, 'Asia/Bangkok', 2, 6);
    ''');
}
