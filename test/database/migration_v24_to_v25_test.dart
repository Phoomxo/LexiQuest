import 'dart:convert';

import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

import '../support/current_database_contract.dart';
import 'migration_v23_to_v24_test.dart' as fixture;

void main() {
  test(
    'malformed stored duration preserves history with unknown metadata',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            createSchemaTwentyFourFixture(sqlite);
            seedQuestHistory(sqlite);
            sqlite.execute(
              "UPDATE quest_definitions SET expires_in_ms = 'invalid-duration' WHERE quest_id = 'q:matched'",
            );
          },
        ),
      );
      addTearDown(database.close);

      final row = await database
          .customSelect(
            "SELECT * FROM quest_instances WHERE instance_id = 'legacy:matched'",
          )
          .getSingle();

      expect(row.readNullable<String>('definition_snapshot_json'), isNull);
      expect(row.readNullable<int>('deadline_at_utc_ms'), isNull);
      expect(row.read<String>('state'), 'completed');
      final child = await database
          .customSelect(
            "SELECT * FROM quest_objective_progress WHERE id = 'original-child:matched'",
          )
          .getSingle();
      expect(child.read<String>('source_event_ids_json'), '["source:matched"]');
      expect(
        await database
            .customSelect(
              "SELECT * FROM points_ledger_entries WHERE id = 'original-xp'",
            )
            .get(),
        hasLength(1),
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'unknown old version never inherits a newer catalog expiry deadline',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            createSchemaTwentyFourFixture(sqlite);
            seedQuestHistory(sqlite);
          },
        ),
      );
      addTearDown(database.close);

      final row = await database
          .customSelect(
            "SELECT * FROM quest_instances WHERE instance_id = 'legacy:unknown'",
          )
          .getSingle();

      expect(row.read<int>('catalog_version'), 1);
      expect(row.readNullable<String>('definition_snapshot_json'), isNull);
      expect(row.readNullable<int>('deadline_at_utc_ms'), isNull);
      expect(row.readNullable<int>('period_end_at_utc_ms'), isNull);
    },
  );

  for (final foreignKeys in [false, true]) {
    test(
      'raw v24 upgrades with FK $foreignKeys preserving exact quest children and awards',
      () async {
        late Map<String, List<Map<String, Object?>>> before;
        final database = AppDatabase(
          NativeDatabase.memory(
            setup: (sqlite) {
              createSchemaTwentyFourFixture(sqlite);
              seedQuestHistory(sqlite);
              before = {
                for (final table in preservedTables)
                  table: [
                    for (final row in sqlite.select(
                      'SELECT * FROM $table ORDER BY 1',
                    ))
                      Map<String, Object?>.from(row),
                  ],
              };
              sqlite.execute('PRAGMA foreign_keys = ${foreignKeys ? 1 : 0}');
              sqlite.execute('PRAGMA legacy_alter_table = 1');
            },
          ),
        );
        addTearDown(database.close);

        await expectCurrentDatabaseContract(database);
        for (final table in preservedTables) {
          final rows = await database
              .customSelect('SELECT * FROM $table ORDER BY 1')
              .get();
          expect(
            rows.map((row) => row.data).toList(),
            before[table],
            reason: table,
          );
        }
        expect(AppDatabase.currentSchemaVersion, 34);
        expect(await currentDatabaseTableNames(database), hasLength(58));
        final rows = await database
            .customSelect(
              "SELECT * FROM quest_instances WHERE owner_id = 'owner:quest' ORDER BY instance_id",
            )
            .get();
        expect(rows, hasLength(5));
        for (final row in rows) {
          final id = row.read<String>('instance_id');
          expect(row.read<String>('period_policy'), 'legacyDuration');
          expect(row.read<String>('period_key'), 'legacy:$id');
          expect(row.readNullable<String>('period_timezone_id'), isNull);
          expect(row.read<int>('assigned_at_utc_ms'), 1785837600000);
          expect(row.read<int>('period_start_at_utc_ms'), 1785837600000);
          expect(row.read<int>('is_canonical'), 1);
        }
        final matched = rows.singleWhere(
          (row) => row.read<String>('instance_id') == 'legacy:matched',
        );
        expect(matched.read<int>('deadline_at_utc_ms'), 1785841200000);
        final snapshot =
            jsonDecode(matched.read<String>('definition_snapshot_json')) as Map;
        expect(snapshot['origin'], 'migrationCatalog');
        expect(snapshot['version'], 1);
        for (final id in ['unknown', 'malformed', 'oversized', 'objectives']) {
          expect(
            rows
                .singleWhere(
                  (row) => row.read<String>('instance_id') == 'legacy:$id',
                )
                .readNullable<String>('definition_snapshot_json'),
            isNull,
            reason: id,
          );
        }
        expect(
          await database.customSelect('PRAGMA foreign_key_check').get(),
          isEmpty,
        );
        expect(
          (await database.customSelect('PRAGMA foreign_keys').getSingle())
              .read<int>('foreign_keys'),
          1,
        );
        expect(
          (await database.customSelect('PRAGMA legacy_alter_table').getSingle())
              .read<int>('legacy_alter_table'),
          1,
        );
      },
    );
  }

  test(
    'fresh schema installs period uniqueness and immutable snapshot guard',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await database.customStatement(
        "INSERT INTO local_owners(id, created_at_utc_ms) VALUES ('owner:quest', 1)",
      );
      await database.customStatement(
        "INSERT INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json) VALUES ('q',1,'Q','Q','daily','[]','{}')",
      );
      Future<void> insert(
        String id,
        String key,
        String state,
        int canonical,
      ) => database.customStatement(
        'INSERT INTO quest_instances(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,period_policy,period_key,is_canonical,definition_snapshot_json) VALUES (?,\'q\',\'owner:quest\',1,1,?,\'localCalendarV1\',?,?,?)',
        [id, state, key, canonical, '{"synthetic":"immutable"}'],
      );
      await insert('d1', 'daily:2026-08-04', 'completed', 1);
      await insert('d2', 'daily:2026-08-05', 'active', 1);
      await expectLater(
        insert('duplicate-period', 'daily:2026-08-04', 'expired', 1),
        throwsA(anything),
      );
      await expectLater(
        insert('duplicate-active', 'daily:2026-08-06', 'active', 1),
        throwsA(anything),
      );
      await insert('preserved-loser', 'daily:2026-08-04', 'completed', 0);
      await expectLater(
        database.customStatement(
          "UPDATE quest_instances SET definition_snapshot_json = NULL WHERE instance_id = 'd1'",
        ),
        throwsA(anything),
      );
      await database.customStatement(
        "UPDATE quest_instances SET is_canonical = 0 WHERE instance_id = 'd1'",
      );
      expect(
        await database.customSelect('SELECT * FROM quest_instances').get(),
        hasLength(3),
      );
    },
  );

  test(
    'migration rerun on latest layout preserves period snapshot and child identity',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            createSchemaTwentyFourFixture(sqlite);
            seedQuestHistory(sqlite);
          },
        ),
      );
      addTearDown(database.close);
      await database.customSelect('SELECT 1').get();
      final before = await database
          .customSelect('SELECT * FROM quest_instances ORDER BY instance_id')
          .get();
      expect(before.first.data, contains('definition_snapshot_json'));
      final children = await database
          .customSelect('SELECT * FROM quest_objective_progress ORDER BY id')
          .get();

      await database.migration.onUpgrade(Migrator(database), 24, 25);

      final after = await database
          .customSelect('SELECT * FROM quest_instances ORDER BY instance_id')
          .get();
      expect(after.map((row) => row.data), before.map((row) => row.data));
      expect(
        (await database
                .customSelect(
                  'SELECT * FROM quest_objective_progress ORDER BY id',
                )
                .get())
            .map((row) => row.data),
        children.map((row) => row.data),
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );

  test(
    'older fixture with missing quest tables creates latest guarded layout',
    () async {
      final database = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            fixture.createSchemaTwentyThreeFixture(sqlite);
            sqlite.execute('DROP TABLE quest_objective_progress');
            sqlite.execute('DROP TABLE quest_instances');
            sqlite.execute('DROP TABLE quest_definitions');
          },
        ),
      );
      addTearDown(database.close);
      await expectCurrentDatabaseContract(database);
      final columns = await database
          .customSelect('PRAGMA table_info(quest_instances)')
          .get();
      expect(
        columns.map((row) => row.read<String>('name')),
        containsAll([
          'period_policy',
          'period_key',
          'period_timezone_id',
          'period_start_at_utc_ms',
          'period_end_at_utc_ms',
          'deadline_at_utc_ms',
          'is_canonical',
          'definition_snapshot_json',
        ]),
      );
      expect(
        await database.customSelect('PRAGMA foreign_key_check').get(),
        isEmpty,
      );
    },
  );
}

const preservedTables = [
  'quest_objective_progress',
  'points_ledger_entries',
  'reward_transactions',
];

void seedQuestHistory(dynamic sqlite) {
  sqlite.execute(
    "INSERT INTO local_owners(id,account_state,created_at_utc_ms) VALUES ('owner:quest','localGuest',1)",
  );
  for (final kind in [
    'matched',
    'unknown',
    'malformed',
    'oversized',
    'objectives',
  ]) {
    final objectives = kind == 'malformed'
        ? '{'
        : jsonEncode([
            {
              'objectiveId': 'answer',
              'description': 'Answer',
              'targetCount': 1,
              'eventType': 'QuizCompleted',
              'filters': {'correct': true},
            },
          ]);
    sqlite.execute(
      'INSERT INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json,expires_in_ms,tags_json) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        'q:$kind',
        kind == 'unknown' ? 2 : 1,
        kind == 'oversized' ? 'ก' * 23000 : 'Original $kind',
        'Synthetic history',
        'daily',
        objectives,
        '{"xpAmount":25,"rewardItemId":null}',
        3600000,
        '["synthetic"]',
      ],
    );
    sqlite.execute(
      'INSERT INTO quest_instances(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,completed_at_utc_ms) VALUES (?,?,?,?,?,?,?)',
      [
        'legacy:$kind',
        'q:$kind',
        'owner:quest',
        1,
        1785837600000,
        'completed',
        1785837600100,
      ],
    );
    sqlite.execute(
      'INSERT INTO quest_objective_progress(id,instance_id,objective_id,current_count,target_count,source_event_ids_json) VALUES (?,?,?,?,?,?)',
      [
        'original-child:$kind',
        'legacy:$kind',
        'answer',
        1,
        kind == 'objectives' ? 2 : 1,
        '["source:$kind"]',
      ],
    );
  }
  sqlite.execute(
    "INSERT INTO points_ledger_entries(id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) VALUES ('original-xp','owner:quest','quest_complete_legacy:matched_q:matched','quest',25,'quest_complete_legacy:matched_q:matched',1785837600100)",
  );
  sqlite.execute(
    "INSERT INTO reward_transactions(id,owner_id,idempotency_key,transaction_type,amount,catalog_version,source_event_id,occurred_at_utc_ms) VALUES ('original-coins','owner:quest','original-reward-key','quest',25,1,'quest_complete_legacy:matched_q:matched',1785837600100)",
  );
}

/// Frozen raw v24 DDL, extended from the maintained raw v23 fixture chain.
/// Deliberately independent of current AppDatabase/createAll/generated tables.
void createSchemaTwentyFourFixture(dynamic sqlite) {
  fixture.createSchemaTwentyThreeFixture(sqlite);
  for (final statement in researchV24Ddl) {
    sqlite.execute(statement);
  }
  sqlite.execute('PRAGMA user_version = 24');
}

const ownedV24Columns = '''
  id TEXT NOT NULL PRIMARY KEY,
  owner_id TEXT NOT NULL REFERENCES local_owners(id) ON DELETE CASCADE,
  local_revision INTEGER NOT NULL DEFAULT 1 CHECK(local_revision > 0),
  cloud_revision INTEGER NOT NULL DEFAULT 0 CHECK(cloud_revision >= 0),
  last_acknowledged_at_utc_ms INTEGER CHECK(last_acknowledged_at_utc_ms IS NULL OR last_acknowledged_at_utc_ms >= 0),
  server_updated_at_utc_ms INTEGER CHECK(server_updated_at_utc_ms IS NULL OR server_updated_at_utc_ms >= 0),
  is_deleted INTEGER NOT NULL DEFAULT 0 CHECK(is_deleted IN (0,1))
''';

const researchV24Ddl = <String>[
  '''CREATE TABLE motivation_measurement_runs ($ownedV24Columns,
    assignment_id TEXT NOT NULL REFERENCES experiment_assignments(id),
    consent_version INTEGER NOT NULL, consent_decided_at_utc_ms INTEGER NOT NULL,
    protocol_id TEXT NOT NULL, protocol_version TEXT NOT NULL, treatment TEXT NOT NULL,
    instrument_id TEXT NOT NULL, instrument_version TEXT NOT NULL, form_id TEXT NOT NULL,
    form_version TEXT NOT NULL, app_version TEXT NOT NULL, build_id TEXT NOT NULL,
    database_schema_version INTEGER NOT NULL, content_revision TEXT NOT NULL,
    evidence_policy_version TEXT NOT NULL, state TEXT NOT NULL,
    started_at_utc_ms INTEGER NOT NULL, closed_at_utc_ms INTEGER,
    CHECK(consent_version > 0 AND consent_decided_at_utc_ms >= 0 AND database_schema_version > 0),
    CHECK(treatment IN ('standard','adventure')),
    CHECK(state IN ('started','completed','skipped','abandoned','withdrawn')),
    CHECK(started_at_utc_ms >= consent_decided_at_utc_ms),
    CHECK((state = 'started' AND closed_at_utc_ms IS NULL) OR (state <> 'started' AND closed_at_utc_ms >= started_at_utc_ms AND closed_at_utc_ms IS NOT NULL)))''',
  '''CREATE TABLE motivation_responses ($ownedV24Columns,
    run_id TEXT NOT NULL REFERENCES motivation_measurement_runs(id) ON DELETE CASCADE,
    item_id TEXT NOT NULL, item_catalog_version TEXT NOT NULL, response_code TEXT NOT NULL,
    ordinal_value INTEGER, answered_at_utc_ms INTEGER NOT NULL,
    UNIQUE(owner_id,run_id,item_id), CHECK(answered_at_utc_ms >= 0),
    CHECK(ordinal_value IS NULL OR ordinal_value BETWEEN 0 AND 100))''',
  '''CREATE TABLE research_participation_permits ($ownedV24Columns,
    participant_class TEXT NOT NULL, age_band_code TEXT NOT NULL,
    assignment_id TEXT NOT NULL REFERENCES experiment_assignments(id), assigned_treatment TEXT NOT NULL,
    consent_receipt_id TEXT NOT NULL, guardian_permission_receipt_ref TEXT,
    learner_assent_receipt_ref TEXT, protocol_id TEXT NOT NULL, protocol_version TEXT NOT NULL,
    issued_at_utc_ms INTEGER NOT NULL, expires_at_utc_ms INTEGER NOT NULL, revoked_at_utc_ms INTEGER,
    issuer_key_id TEXT NOT NULL, payload_sha256 TEXT NOT NULL, signature TEXT NOT NULL,
    CHECK(participant_class IN ('adult','minor')), CHECK(assigned_treatment IN ('standard','adventure')),
    CHECK(participant_class = 'adult' OR (guardian_permission_receipt_ref IS NOT NULL AND learner_assent_receipt_ref IS NOT NULL)),
    CHECK(issued_at_utc_ms >= 0 AND expires_at_utc_ms > issued_at_utc_ms),
    CHECK(revoked_at_utc_ms IS NULL OR revoked_at_utc_ms >= issued_at_utc_ms),
    CHECK(length(payload_sha256) = 64 AND payload_sha256 NOT GLOB '*[^0-9a-f]*'))''',
  '''CREATE TABLE measurement_opportunities ($ownedV24Columns,
    measurement_run_id TEXT NOT NULL REFERENCES motivation_measurement_runs(id) ON DELETE CASCADE,
    permit_id TEXT NOT NULL REFERENCES research_participation_permits(id), entry_attempt_id TEXT NOT NULL,
    assigned_treatment TEXT NOT NULL, effective_presentation TEXT NOT NULL, presented_event_id TEXT,
    learning_session_id TEXT REFERENCES learning_sessions(id), started_event_id TEXT, completed_event_id TEXT,
    last_switch_ordinal INTEGER NOT NULL DEFAULT 0, suppressed_switch_count INTEGER NOT NULL DEFAULT 0,
    opened_at_utc_ms INTEGER NOT NULL, closed_at_utc_ms INTEGER,
    UNIQUE(owner_id,measurement_run_id,permit_id,entry_attempt_id),
    CHECK(assigned_treatment IN ('standard','adventure')), CHECK(effective_presentation IN ('standard','adventure')),
    CHECK(last_switch_ordinal BETWEEN 0 AND 10 AND suppressed_switch_count >= 0),
    CHECK(opened_at_utc_ms >= 0 AND (closed_at_utc_ms IS NULL OR closed_at_utc_ms >= opened_at_utc_ms)),
    CHECK(started_event_id IS NULL OR learning_session_id IS NOT NULL),
    CHECK(completed_event_id IS NULL OR (started_event_id IS NOT NULL AND closed_at_utc_ms IS NOT NULL)))''',
];
