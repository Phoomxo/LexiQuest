import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Migrator;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/owner_lifecycle_manifest.dart';

import '../support/schema_v25_fixture.dart';
import 'migration_v23_to_v24_test.dart' as older;

void main() {
  test(
    'frozen raw25 control has real quest25 layout and legacy research guards',
    () async {
      var checked = false;
      final db = AppDatabase(
        NativeDatabase.memory(
          setup: (sqlite) {
            createSchemaTwentyFiveFixture(sqlite);
            expect(
              sqlite.select('PRAGMA user_version').single.values.single,
              25,
            );
            expect(
              sqlite.select(
                "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
              ),
              hasLength(48),
            );
            final columns = sqlite
                .select('PRAGMA table_info(quest_instances)')
                .map((row) => row['name']);
            expect(
              columns,
              containsAll([
                'period_key',
                'deadline_at_utc_ms',
                'definition_snapshot_json',
              ]),
            );
            expect(
              sqlite
                  .select('PRAGMA foreign_key_list(measurement_opportunities)')
                  .map((row) => row['table']),
              contains('learning_sessions'),
            );
            for (final entry in schemaTwentyFiveGuards.entries) {
              expect(
                sqlite.select('SELECT sql FROM sqlite_master WHERE name=?', [
                  entry.key,
                ]).single['sql'],
                entry.value,
              );
            }
            _seedRaw(sqlite, canonical: true, opportunity: true);
            expect(
              () => sqlite.execute(
                _insertSql(
                  'measurement_opportunities',
                  _opportunity(id: 'invalid', session: 'absent'),
                ),
                _opportunity(id: 'invalid', session: 'absent').values.toList(),
              ),
              throwsA(_constraint),
            );
            expect(sqlite.select('PRAGMA foreign_key_check'), isEmpty);
            checked = true;
          },
        ),
      );
      addTearDown(db.close);
      await db.customSelect('SELECT 1').get();
      expect(checked, isTrue);
    },
  );

  test(
    'fresh26 has exactly49 tables and the reserved guards and indexes',
    () async {
      final db = _database();
      await _expectLayout(db);
      final indexes = await _rows(
        db,
        'PRAGMA index_list(research_session_proofs)',
      );
      expect(
        indexes.where((row) => row['unique'] == 1 && row['origin'] != 'pk'),
        hasLength(1),
      );
      expect(
        (await _rows(
          db,
          'PRAGMA index_info(research_session_proofs_owner_phase_v26)',
        )).map((row) => row['name']),
        [
          'owner_id',
          'measurement_run_id',
          'permit_id',
          'learning_session_id',
          'proof_revision',
        ],
      );
      final fks = await _rows(
        db,
        'PRAGMA foreign_key_list(research_session_proofs)',
      );
      for (final parent in [
        'motivation_measurement_runs',
        'research_participation_permits',
      ]) {
        expect(
          fks.singleWhere((row) => row['table'] == parent)['on_delete'],
          'NO ACTION',
        );
      }
      expect(
        fks.map((row) => row['table']),
        isNot(contains('learning_sessions')),
      );
    },
  );

  for (final foreignKeys in [0, 1]) {
    for (final legacyAlter in [0, 1]) {
      test(
        'raw25 FK$foreignKeys legacy$legacyAlter upgrade preserves every retained value',
        () async {
          late Map<String, List<Map<String, Object?>>> before;
          final db = _database(
            setup: (sqlite) {
              createSchemaTwentyFiveFixture(sqlite);
              _seedRaw(sqlite, canonical: true, opportunity: true);
              before = _rawSnapshot(sqlite, _retained);
              sqlite.execute('PRAGMA foreign_keys=$foreignKeys');
              sqlite.execute('PRAGMA legacy_alter_table=$legacyAlter');
            },
          );
          await _expectLayout(db);
          expect(await _snapshot(db, _retained), before);
          expect(
            (await _rows(db, 'PRAGMA legacy_alter_table')).single.values.single,
            legacyAlter,
          );
          // beforeOpen intentionally enables FK after migration restores its input.
          expect(
            (await _rows(db, 'PRAGMA foreign_keys')).single.values.single,
            1,
          );
          final fresh = _database();
          await _expectLayout(fresh);
          expect(await _schema(db), await _schema(fresh));
          await _insert(db, 'research_session_proofs', _proof());
          expect(await _snapshot(db, _retained), before);
        },
      );
    }
  }

  test(
    'actual raw23 path and latest layout migration reruns retain proofs and children',
    () async {
      final db = _database(setup: older.createSchemaTwentyThreeFixture);
      await _expectLayout(db);
      await _seed(db, canonical: true, opportunity: true);
      await _insert(db, 'research_session_proofs', _proof());
      final before = await _snapshot(db, [
        ..._retained,
        'research_session_proofs',
      ]);
      final schema = await _schema(db);
      for (final fk in [0, 1]) {
        await db.customStatement('PRAGMA foreign_keys=$fk');
        await db.customStatement('PRAGMA legacy_alter_table=1');
        await db.customStatement('PRAGMA user_version=25');
        await db.migration.onUpgrade(Migrator(db), 25, 26);
        expect(
          (await _rows(db, 'PRAGMA foreign_keys')).single.values.single,
          fk,
        );
        expect(
          (await _rows(db, 'PRAGMA legacy_alter_table')).single.values.single,
          1,
        );
        expect(
          await _snapshot(db, [..._retained, 'research_session_proofs']),
          before,
        );
        expect(await _schema(db), schema);
        expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
      }
    },
  );

  test(
    'real file latest26 layout with old user_version reopens twice without losing proofs',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-schema26-',
      );
      AppDatabase? opened;
      addTearDown(() async {
        await opened?.close();
        await directory.delete(recursive: true);
      });
      final file = File('${directory.path}/fixture.sqlite');
      final first = AppDatabase(NativeDatabase(file));
      opened = first;
      await _seed(first, canonical: true, opportunity: true);
      await _insert(first, 'research_session_proofs', _proof());
      final before = await _snapshot(first, [
        ..._retained,
        'research_session_proofs',
      ]);
      await first.customStatement('PRAGMA user_version=25');
      await first.close();
      opened = null;
      for (var pass = 0; pass < 2; pass++) {
        final db = AppDatabase(NativeDatabase(file));
        opened = db;
        await _expectLayout(db);
        expect(
          await _snapshot(db, [..._retained, 'research_session_proofs']),
          before,
        );
        await db.close();
        opened = null;
      }
    },
  );

  for (final legacyAlter in [0, 1]) {
    for (final foreignOwner in [false, true]) {
      for (final foreignKeys in [0, 1]) {
        test(
          'invalid retained raw25 authority aborts atomically and restores pragmas FK$foreignKeys legacy$legacyAlter foreignOwner$foreignOwner',
          () async {
            late dynamic raw;
            late Map<String, List<Map<String, Object?>>> before;
            final db = _database(
              setup: (sqlite) {
                raw = sqlite;
                createSchemaTwentyFiveFixture(sqlite);
                _seedRaw(sqlite, canonical: true, opportunity: true);
                sqlite.execute('PRAGMA foreign_keys=OFF');
                sqlite.execute(
                  "DELETE FROM learning_sessions WHERE id='session:a'",
                );
                if (foreignOwner) {
                  final session = {..._session(), 'owner_id': 'owner:b'};
                  sqlite.execute(
                    _insertSql('learning_sessions', session),
                    session.values.toList(),
                  );
                  // FK checks alone cannot detect an existing session with wrong owner.
                  expect(sqlite.select('PRAGMA foreign_key_check'), isEmpty);
                }
                sqlite.execute('PRAGMA legacy_alter_table=$legacyAlter');
                sqlite.execute('PRAGMA foreign_keys=$foreignKeys');
                before = _rawSnapshot(sqlite, _retained);
              },
            );
            await expectLater(
              db.customSelect('SELECT 1').get(),
              throwsA(anyOf(isA<StateError>(), isA<SqliteException>())),
            );
            expect(raw.select('PRAGMA user_version').single.values.single, 25);
            expect(
              raw.select('PRAGMA foreign_keys').single.values.single,
              foreignKeys,
            );
            expect(
              raw.select('PRAGMA legacy_alter_table').single.values.single,
              legacyAlter,
            );
            expect(
              raw.select(
                "SELECT name FROM sqlite_master WHERE name='research_session_proofs'",
              ),
              isEmpty,
            );
            expect(
              raw
                  .select('PRAGMA foreign_key_list(measurement_opportunities)')
                  .map((row) => row['table']),
              contains('learning_sessions'),
            );
            expect(_rawSnapshot(raw, _retained), before);
            expect(
              raw.select(
                "SELECT name FROM sqlite_master WHERE name='measurement_opportunities_owner_insert'",
              ),
              hasLength(1),
            );
          },
        );
      }
    }
  }

  test(
    'proof-only completed-first admits exact opportunity without creating learning effects',
    () async {
      final db = _database();
      await _seed(db);
      final untouched = await _snapshot(db, _learningEffects);
      await _insert(db, 'research_session_proofs', _proof(phase: 2));
      await _insert(db, 'measurement_opportunities', _opportunity());
      await _insert(db, 'research_session_proofs', _proof());
      await _insert(
        db,
        'measurement_opportunities',
        _opportunity(id: 'presented', session: null),
      );
      expect(
        await _rows(db, 'SELECT * FROM research_session_proofs'),
        hasLength(2),
      );
      expect(await _snapshot(db, _learningEffects), untouched);
      expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
    },
  );

  for (final changes in <Map<String, Object?>>[
    {'owner_id': 'owner:b'},
    {'measurement_run_id': 'run:b'},
    {'permit_id': 'permit:b'},
    {'measurement_run_id': 'missing'},
    {'permit_id': 'missing'},
  ]) {
    test('proof rejects mismatched authority $changes', () async {
      final db = _database();
      await _seed(db);
      await _rejectInsert(db, 'research_session_proofs', {
        ..._proof(),
        ...changes,
      });
    });
  }

  for (final pin in ['assignment', 'protocol', 'treatment']) {
    test(
      'proof rejects same-owner run and permit with mismatched $pin',
      () async {
        final db = _database();
        await _seed(db);
        await _insert(db, 'experiment_assignments', {
          'id': 'assignment:other',
          'owner_id': 'owner:a',
          'experiment_id': 'other-study',
          'experiment_version': 1,
          'cohort': pin == 'treatment' ? 'standard' : 'adventure',
          'protocol_version': '1',
          'assigned_at_utc_ms': 1,
        });
        final run = {..._run('a'), 'id': 'run:other'};
        if (pin == 'assignment' || pin == 'treatment')
          run['assignment_id'] = 'assignment:other';
        if (pin == 'protocol') run['protocol_id'] = 'other-protocol';
        if (pin == 'treatment') run['treatment'] = 'standard';
        await _insert(db, 'motivation_measurement_runs', run);
        await _rejectInsert(db, 'research_session_proofs', {
          ..._proof(),
          'measurement_run_id': 'run:other',
        });
      },
    );
  }

  test(
    'proof authority cannot be borrowed by another valid same-owner run or permit',
    () async {
      final db = _database();
      await _seed(db);
      await _insert(db, 'research_session_proofs', _proof());
      await _insert(db, 'motivation_measurement_runs', {
        ..._run('a'),
        'id': 'run:other',
      });
      final permit = (await _rows(
        db,
        "SELECT * FROM research_participation_permits WHERE id='permit:a'",
      )).single;
      await _insert(db, 'research_participation_permits', {
        ...permit,
        'id': 'permit:other',
      });
      for (final pins in <Map<String, Object?>>[
        {'measurement_run_id': 'run:other'},
        {'permit_id': 'permit:other'},
      ]) {
        await _rejectInsert(db, 'measurement_opportunities', {
          ..._opportunity(),
          ...pins,
        });
      }
      await _insert(db, 'measurement_opportunities', _opportunity());
    },
  );

  for (final changes in <Map<String, Object?>>[
    {'owner_id': 'owner:b'},
    {'measurement_run_id': 'run:b'},
    {'permit_id': 'permit:b'},
    {'assigned_treatment': 'standard'},
    {'learning_session_id': 'missing'},
  ]) {
    test('opportunity requires exact live proof tuple $changes', () async {
      final db = _database();
      await _seed(db);
      await _insert(db, 'research_session_proofs', _proof());
      await _rejectInsert(db, 'measurement_opportunities', {
        ..._opportunity(),
        ...changes,
      });
      await _insert(db, 'measurement_opportunities', _opportunity());
      await _rejectStatement(
        db,
        "UPDATE measurement_opportunities SET learning_session_id='missing'",
      );
    });
  }

  final invalidScalars = <String, Map<String, Object?>>{
    'phase0': {'proof_revision': 0},
    'phase3': {'proof_revision': 3},
    'phase fraction': {'proof_revision': 1.5},
    'active end': {'ended_at_utc_ms': 20},
    'wrong phase state': {'session_state': 'completed'},
    'negative start': {'started_at_utc_ms': -1},
    'partial config identity': {'session_configuration_identity': 'config'},
    'partial config json': {'session_configuration_json': '{}'},
    'quiz Pair fields': {
      'pair_start_operation': '{}',
      'pair_checkpoint_event_version': 1,
      'pair_owner_lineage_json': '[]',
    },
    'matching missing Pair fields': {'activity_type': 'matching'},
    'uppercase digest': {'permit_payload_sha256': 'A' * 64},
    'short digest': {'permit_payload_sha256': 'a' * 63},
    'NUL digest': {'permit_payload_sha256': '${'a' * 64}\u0000tail'},
    'blob digest': {
      'permit_payload_sha256': Uint8List.fromList(List.filled(64, 97)),
    },
    'zero permit revision': {'permit_revision': 0},
    'negative permit revision': {'permit_revision': -1},
    'fraction permit revision': {'permit_revision': 1.5},
    'text permit revision': {'permit_revision': 'invalid'},
  };
  for (final entry in invalidScalars.entries) {
    test('proof SQL scalar rejects ${entry.key}', () async {
      final db = _database();
      await _seed(db);
      await _rejectInsert(db, 'research_session_proofs', {
        ..._proof(),
        ...entry.value,
      });
    });
  }

  test(
    'completed phase needs ordered nonnull end; matching and configured scalar shapes accepted',
    () async {
      final db = _database();
      await _seed(db);
      await _rejectInsert(db, 'research_session_proofs', {
        ..._proof(phase: 2),
        'ended_at_utc_ms': null,
      });
      await _rejectInsert(db, 'research_session_proofs', {
        ..._proof(phase: 2),
        'ended_at_utc_ms': 9,
      });
      await _insert(db, 'research_session_proofs', {
        ..._proof(phase: 2),
        'activity_type': 'matching',
        'pair_start_operation': 'synthetic-sql-shape',
        'pair_checkpoint_event_version': 2,
        'pair_owner_lineage_json': '[]',
        'session_configuration_identity': 'synthetic',
        'session_configuration_json': '{}',
      });
      // SQL shape validation is separate from the strict transport codec's authenticity checks.
      expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'phase tuple unique and every proof core field immutable; delivery metadata writable',
    () async {
      final db = _database();
      await _seed(db);
      await _insert(db, 'research_session_proofs', _proof());
      await _rejectInsert(db, 'research_session_proofs', {
        ..._proof(),
        'id': 'duplicate-id',
      });
      final changes = <String, Object?>{
        'id': 'different',
        'owner_id': 'owner:b',
        'measurement_run_id': 'run:b',
        'permit_id': 'permit:b',
        'learning_session_id': 'different-session',
        'proof_revision': 2,
        'activity_type': 'reading',
        'session_state': 'completed',
        'started_at_utc_ms': 11,
        'ended_at_utc_ms': 20,
        'app_version': '2',
        'build_id': 'different',
        'session_configuration_identity': 'different',
        'session_configuration_json': '{}',
        'pair_start_operation': 'different',
        'pair_checkpoint_event_version': 1,
        'pair_owner_lineage_json': '[]',
        'permit_payload_sha256': 'b' * 64,
        'permit_revision': 2,
      };
      for (final entry in changes.entries) {
        await _rejectStatement(
          db,
          'UPDATE research_session_proofs SET ${entry.key}=?',
          [entry.value],
        );
      }
      await db.customStatement(
        'UPDATE research_session_proofs SET local_revision=2,cloud_revision=3,last_acknowledged_at_utc_ms=30,server_updated_at_utc_ms=31,is_deleted=1',
      );
      final row = (await _rows(
        db,
        'SELECT * FROM research_session_proofs',
      )).single;
      expect(row['local_revision'], 2);
      expect(row['cloud_revision'], 3);
      expect(row['is_deleted'], 1);
      expect(row['permit_payload_sha256'], 'a' * 64);
      expect(row['permit_revision'], 1);
    },
  );

  for (final tombstoned in [false, true]) {
    test(
      'sibling core includes original permit pins even tombstoned=$tombstoned',
      () async {
        final db = _database();
        await _seed(db);
        await _insert(db, 'research_session_proofs', {
          ..._proof(phase: 2),
          'is_deleted': tombstoned ? 1 : 0,
        });
        for (final change in <Map<String, Object?>>[
          {'started_at_utc_ms': 11},
          {'app_version': '2'},
          {'build_id': '2'},
          {'permit_payload_sha256': 'b' * 64},
          {'permit_revision': 2},
          {'activity_type': 'reading'},
          {
            'session_configuration_identity': 'config',
            'session_configuration_json': '{}',
          },
        ]) {
          await _rejectInsert(db, 'research_session_proofs', {
            ..._proof(),
            ...change,
          });
        }
        await _insert(db, 'research_session_proofs', _proof());
      },
    );
  }

  test(
    'permit renewal leaves historical proof byte values stable and parent pins guarded without opportunity',
    () async {
      final db = _database();
      await _seed(db);
      await db.customStatement('DELETE FROM motivation_responses');
      await _insert(db, 'research_session_proofs', _proof());
      final before = await _rows(db, 'SELECT * FROM research_session_proofs');
      await db.customStatement(
        "UPDATE research_participation_permits SET payload_sha256=?,local_revision=2,cloud_revision=2,signature='renewed-synthetic',expires_at_utc_ms=200000 WHERE id='permit:a'",
        ['b' * 64],
      );
      expect(await _rows(db, 'SELECT * FROM research_session_proofs'), before);
      for (final sql in [
        "UPDATE motivation_measurement_runs SET protocol_version='2' WHERE id='run:a'",
        "UPDATE motivation_measurement_runs SET instrument_version='2' WHERE id='run:a'",
        "UPDATE motivation_measurement_runs SET owner_id='owner:b' WHERE id='run:a'",
        "UPDATE research_participation_permits SET protocol_version='2' WHERE id='permit:a'",
        "UPDATE research_participation_permits SET age_band_code='different' WHERE id='permit:a'",
        "UPDATE research_participation_permits SET assigned_treatment='standard' WHERE id='permit:a'",
        "DELETE FROM motivation_measurement_runs WHERE id='run:a'",
        "DELETE FROM research_participation_permits WHERE id='permit:a'",
      ]) {
        await _rejectStatement(db, sql);
      }
      await _insert(db, 'research_session_proofs', _proof(phase: 2));
    },
  );

  for (final opportunityDeleted in [0, 1]) {
    test(
      'last proof delete and tombstone guarded including opportunity tombstone$opportunityDeleted',
      () async {
        final db = _database();
        await _seed(db);
        await _insert(db, 'research_session_proofs', _proof());
        await _insert(db, 'measurement_opportunities', {
          ..._opportunity(),
          'is_deleted': opportunityDeleted,
        });
        await _rejectStatement(
          db,
          "DELETE FROM research_session_proofs WHERE id='proof:a:1'",
        );
        await _rejectStatement(
          db,
          "UPDATE research_session_proofs SET is_deleted=1 WHERE id='proof:a:1'",
        );
        await _insert(db, 'research_session_proofs', {
          ..._proof(phase: 2),
          'is_deleted': 1,
        });
        await _rejectStatement(
          db,
          "DELETE FROM research_session_proofs WHERE id='proof:a:1'",
        );
        await db.customStatement(
          "UPDATE research_session_proofs SET is_deleted=0 WHERE id='proof:a:2'",
        );
        await db.customStatement(
          "DELETE FROM research_session_proofs WHERE id='proof:a:1'",
        );
        await _rejectStatement(
          db,
          "DELETE FROM research_session_proofs WHERE id='proof:a:2'",
        );
        await _insert(db, 'learning_sessions', _session());
        await db.customStatement(
          "DELETE FROM research_session_proofs WHERE id='proof:a:2'",
        );
        await _rejectStatement(
          db,
          "DELETE FROM learning_sessions WHERE id='session:a'",
        );
      },
    );
  }

  test(
    'canonical deletion needs exact live proof for every opportunity; session pins remain protected',
    () async {
      final db = _database();
      await _seed(db, canonical: true, opportunity: true);
      await _rejectStatement(
        db,
        "DELETE FROM learning_sessions WHERE id='session:a'",
      );
      await _insert(db, 'research_session_proofs', _proof());
      await _rejectStatement(
        db,
        "UPDATE learning_sessions SET id='changed' WHERE id='session:a'",
      );
      await _rejectStatement(
        db,
        "UPDATE learning_sessions SET owner_id='owner:b' WHERE id='session:a'",
      );
      await _insert(db, 'motivation_measurement_runs', {
        ..._run('a'),
        'id': 'run:a:second',
      });
      await _insert(db, 'measurement_opportunities', {
        ..._opportunity(id: 'second'),
        'measurement_run_id': 'run:a:second',
        'is_deleted': 1,
      });
      await _rejectStatement(
        db,
        "DELETE FROM learning_sessions WHERE id='session:a'",
      );
      await _insert(db, 'research_session_proofs', {
        ..._proof(),
        'id': 'proof:second',
        'measurement_run_id': 'run:a:second',
      });
      await db.customStatement(
        "DELETE FROM learning_sessions WHERE id='session:a'",
      );
      expect(
        await _rows(db, 'SELECT * FROM measurement_opportunities'),
        hasLength(2),
      );
      expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
    },
  );

  test(
    'tombstoned proof cannot admit an opportunity or its session update',
    () async {
      final db = _database();
      await _seed(db);
      await _insert(db, 'research_session_proofs', {
        ..._proof(),
        'is_deleted': 1,
      });
      await _rejectInsert(db, 'measurement_opportunities', _opportunity());
      await _insert(
        db,
        'measurement_opportunities',
        _opportunity(session: null),
      );
      await _rejectStatement(
        db,
        "UPDATE measurement_opportunities SET learning_session_id='session:a'",
      );
    },
  );

  test(
    'manifest registers proof owner export and physical deletion before restrictive parents',
    () async {
      expect(
        ownerLifecycleExportTableNames,
        contains('research_session_proofs'),
      );
      expect(
        ownerLifecycleDirectOwnerTableNames,
        contains('research_session_proofs'),
      );
      final order = ownerLifecyclePhysicalDeletionOrder;
      expect(
        order.indexOf('research_session_proofs'),
        order.indexOf('measurement_opportunities') + 1,
      );
      expect(
        order.indexOf('research_session_proofs'),
        lessThan(order.indexOf('motivation_measurement_runs')),
      );
      final db = _database();
      await _seed(db);
      for (final suffix in ['a', 'b']) {
        await _insert(db, 'research_session_proofs', _proof(suffix: suffix));
        await _insert(
          db,
          'measurement_opportunities',
          _opportunity(suffix: suffix),
        );
      }
      final foreign = await _snapshot(db, _research, owner: 'owner:b');
      await db.transaction(() async {
        for (final table in order.where((table) => _research.contains(table))) {
          await db.customStatement('DELETE FROM $table WHERE owner_id=?', [
            'owner:a',
          ]);
        }
        await db.customStatement(
          "DELETE FROM experiment_assignments WHERE owner_id='owner:a'",
        );
        await db.customStatement("DELETE FROM local_owners WHERE id='owner:a'");
      });
      expect(await _snapshot(db, _research, owner: 'owner:b'), foreign);
      for (final rows in (await _snapshot(
        db,
        _research,
        owner: 'owner:a',
      )).values) {
        expect(rows, isEmpty);
      }
      expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
    },
  );
}

const _retained = [
  'research_participation_permits',
  'motivation_measurement_runs',
  'motivation_responses',
  'measurement_opportunities',
  'learning_sessions',
  'quest_instances',
  'quest_objective_progress',
  'points_ledger_entries',
  'events_v2',
];
const _research = [
  'measurement_opportunities',
  'research_session_proofs',
  'motivation_responses',
  'motivation_measurement_runs',
  'research_participation_permits',
];
const _learningEffects = [
  'learning_sessions',
  'session_configurations',
  'runtime_flags',
  'answer_attempts',
  'srs_states',
  'points_ledger_entries',
  'reward_transactions',
  'events_v2',
];
const _retired = [
  'measurement_opportunities_owner_insert',
  'measurement_opportunities_owner_update',
  'motivation_measurement_runs_referenced_pins_v24_update',
  'research_participation_permits_referenced_pins_v24_update',
];
const _added = [
  'measurement_opportunities_owner_v26_insert',
  'measurement_opportunities_owner_v26_update',
  'motivation_measurement_runs_referenced_pins_v26_update',
  'research_participation_permits_referenced_pins_v26_update',
  'research_session_proofs_owner_v26_insert',
  'research_session_proofs_owner_v26_update',
  'research_session_proofs_immutable_v26_update',
  'research_session_proofs_sibling_core_v26_insert',
  'research_session_proofs_last_authority_v26_delete',
  'research_session_proofs_last_authority_v26_update',
  'learning_sessions_last_authority_v26_delete',
  'research_session_proofs_owner_phase_v26',
  'measurement_opportunities_session_authority_v26',
];
final _constraint = isA<SqliteException>().having(
  (error) => error.resultCode,
  'constraint result code',
  19,
);

AppDatabase _database({void Function(dynamic)? setup}) {
  final db = AppDatabase(NativeDatabase.memory(setup: setup));
  addTearDown(db.close);
  return db;
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String sql) async => [
  for (final row in await db.customSelect(sql).get())
    Map<String, Object?>.from(row.data),
];
Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
  List<String> tables, {
  String? owner,
}) async => {
  for (final table in tables)
    table: await _rows(
      db,
      "SELECT * FROM $table ${owner == null ? '' : "WHERE owner_id='$owner'"} ORDER BY 1",
    ),
};
Map<String, List<Map<String, Object?>>> _rawSnapshot(
  dynamic sqlite,
  List<String> tables,
) => {
  for (final table in tables)
    table: [
      for (final row in sqlite.select('SELECT * FROM $table ORDER BY 1'))
        Map<String, Object?>.from(row),
    ],
};
String _insertSql(String table, Map<String, Object?> row) =>
    'INSERT INTO $table (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})';
Future<void> _insert(AppDatabase db, String table, Map<String, Object?> row) =>
    db.customStatement(_insertSql(table, row), row.values.toList());
Future<void> _rejectInsert(
  AppDatabase db,
  String table,
  Map<String, Object?> row,
) async {
  final before = await _rows(db, 'SELECT * FROM $table ORDER BY 1');
  await expectLater(_insert(db, table, row), throwsA(_constraint));
  expect(await _rows(db, 'SELECT * FROM $table ORDER BY 1'), before);
}

Future<void> _rejectStatement(
  AppDatabase db,
  String sql, [
  List<Object?> args = const [],
]) async {
  await expectLater(db.customStatement(sql, args), throwsA(_constraint));
  expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
}

Future<List<Map<String, Object?>>> _schema(AppDatabase db) => _rows(
  db,
  "SELECT type,name,tbl_name,sql FROM sqlite_master WHERE name IN (${[..._added, 'measurement_opportunities', 'research_session_proofs', 'learning_sessions_referenced_pins_v24_update'].map((s) => "'$s'").join(',')}) ORDER BY name",
);
Future<void> _expectLayout(AppDatabase db) async {
  expect((await _rows(db, 'PRAGMA user_version')).single.values.single, AppDatabase.currentSchemaVersion);
  expect(
    await _rows(
      db,
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
    ),
    hasLength(50),
  );
  final names = (await _rows(
    db,
    'SELECT name FROM sqlite_master',
  )).map((row) => row['name']).toSet();
  expect(names, containsAll(_added));
  expect(names.intersection(_retired.toSet()), isEmpty);
  for (final entry in schemaTwentyFiveGuards.entries.where(
    (entry) => !_retired.contains(entry.key),
  )) {
    expect(
      (await _rows(
        db,
        "SELECT sql FROM sqlite_master WHERE name='${entry.key}'",
      )).single['sql'],
      entry.value,
    );
  }
  final fks = await _rows(
    db,
    'PRAGMA foreign_key_list(measurement_opportunities)',
  );
  expect(
    fks.map((row) => row['table']),
    unorderedEquals([
      'local_owners',
      'motivation_measurement_runs',
      'research_participation_permits',
    ]),
  );
  expect(
    fks.singleWhere(
      (row) => row['table'] == 'motivation_measurement_runs',
    )['on_delete'],
    'CASCADE',
  );
  expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
  expect(
    (await _schema(db)).map((row) => row['sql']).join('\n'),
    isNot(contains('tmp_for_copy')),
  );
}

Map<String, Object?> _run(String s) => {
  'id': 'run:$s',
  'owner_id': 'owner:$s',
  'assignment_id': 'assignment:$s',
  'consent_version': 1,
  'consent_decided_at_utc_ms': 1,
  'protocol_id': 'motivation',
  'protocol_version': '1',
  'treatment': 'adventure',
  'instrument_id': 'synthetic',
  'instrument_version': '1',
  'form_id': 'paired',
  'form_version': '1',
  'app_version': '1',
  'build_id': 'synthetic',
  'database_schema_version': 25,
  'content_revision': '1',
  'evidence_policy_version': '1',
  'state': 'started',
  'started_at_utc_ms': 10,
};
Map<String, Object?> _session() => {
  'id': 'session:a',
  'owner_id': 'owner:a',
  'activity_type': 'quiz',
  'state': 'completed',
  'started_at_utc_ms': 10,
  'ended_at_utc_ms': 20,
  'app_version': '1',
  'build_id': 'synthetic',
};
Map<String, Object?> _proof({int phase = 1, String suffix = 'a'}) => {
  'id': 'proof:$suffix:$phase',
  'owner_id': 'owner:$suffix',
  'measurement_run_id': 'run:$suffix',
  'permit_id': 'permit:$suffix',
  'learning_session_id': 'session:$suffix',
  'proof_revision': phase,
  'activity_type': 'quiz',
  'session_state': phase == 1 ? 'active' : 'completed',
  'started_at_utc_ms': 10,
  'ended_at_utc_ms': phase == 1 ? null : 20,
  'app_version': '1',
  'build_id': 'synthetic',
  'session_configuration_identity': null,
  'session_configuration_json': null,
  'pair_start_operation': null,
  'pair_checkpoint_event_version': null,
  'pair_owner_lineage_json': null,
  'permit_payload_sha256': 'a' * 64,
  'permit_revision': 1,
};
Map<String, Object?> _opportunity({
  String id = 'opportunity',
  String? session = 'session:a',
  String suffix = 'a',
}) => {
  'id': '$id:$suffix',
  'owner_id': 'owner:$suffix',
  'measurement_run_id': 'run:$suffix',
  'permit_id': 'permit:$suffix',
  'entry_attempt_id': '$id:entry:$suffix',
  'assigned_treatment': 'adventure',
  'effective_presentation': 'adventure',
  'learning_session_id': suffix == 'a' ? session : 'session:$suffix',
  'opened_at_utc_ms': 5,
};
Iterable<(String, Map<String, Object?>)> _graph({
  bool canonical = false,
  bool opportunity = false,
}) sync* {
  for (final s in ['a', 'b']) {
    yield (
      'local_owners',
      {'id': 'owner:$s', 'account_state': 'localGuest', 'created_at_utc_ms': 1},
    );
    yield (
      'experiment_assignments',
      {
        'id': 'assignment:$s',
        'owner_id': 'owner:$s',
        'experiment_id': 'synthetic-study',
        'experiment_version': 1,
        'cohort': 'adventure',
        'protocol_version': '1',
        'assigned_at_utc_ms': 1,
      },
    );
    yield (
      'research_participation_permits',
      {
        'id': 'permit:$s',
        'owner_id': 'owner:$s',
        'participant_class': 'adult',
        'age_band_code': 'adult',
        'assignment_id': 'assignment:$s',
        'assigned_treatment': 'adventure',
        'consent_receipt_id': 'receipt:$s',
        'protocol_id': 'motivation',
        'protocol_version': '1',
        'issued_at_utc_ms': 1,
        'expires_at_utc_ms': 100000,
        'issuer_key_id': 'synthetic-key',
        'payload_sha256': 'a' * 64,
        'signature': 'synthetic-signature',
        'cloud_revision': 1,
      },
    );
    yield ('motivation_measurement_runs', _run(s));
    yield (
      'motivation_responses',
      {
        'id': 'response:$s',
        'owner_id': 'owner:$s',
        'run_id': 'run:$s',
        'item_id': 'item',
        'item_catalog_version': '1',
        'response_code': 'agree',
        'ordinal_value': 3,
        'answered_at_utc_ms': 15,
      },
    );
  }
  if (canonical) yield ('learning_sessions', _session());
  if (opportunity)
    yield (
      'measurement_opportunities',
      {
        ..._opportunity(),
        'presented_event_id': 'event:presented',
        'started_event_id': 'event:started',
        'completed_event_id': 'event:completed',
        'closed_at_utc_ms': 20,
        'local_revision': 3,
        'cloud_revision': 2,
        'last_acknowledged_at_utc_ms': 25,
        'server_updated_at_utc_ms': 24,
      },
    );
}

void _seedRaw(
  dynamic sqlite, {
  bool canonical = false,
  bool opportunity = false,
}) {
  for (final (table, row) in _graph(
    canonical: canonical,
    opportunity: opportunity,
  )) {
    sqlite.execute(_insertSql(table, row), row.values.toList());
  }
  sqlite.execute(
    "INSERT INTO quest_definitions(quest_id,catalog_version,title,description,type,objectives_json,reward_json) VALUES('quest:history',1,'Original','Synthetic','daily','[]','{}')",
  );
  sqlite.execute(
    "INSERT INTO quest_instances(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,completed_at_utc_ms,period_policy,period_key,period_start_at_utc_ms,period_end_at_utc_ms,deadline_at_utc_ms) VALUES('quest-instance:history','quest:history','owner:a',1,10,'completed',20,'localCalendarV1','daily:synthetic',0,86400000,1000)",
  );
  sqlite.execute(
    "INSERT INTO quest_objective_progress(id,instance_id,objective_id,current_count,target_count,source_event_ids_json) VALUES('quest-child:history','quest-instance:history','answer',1,1,'[\"original-source\"]')",
  );
  sqlite.execute(
    "INSERT INTO points_ledger_entries(id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) VALUES('points:history','owner:a','original-reward-key','quest',50,'original-source',20)",
  );
}

Future<void> _seed(
  AppDatabase db, {
  bool canonical = false,
  bool opportunity = false,
}) async {
  for (final (table, row) in _graph(
    canonical: canonical,
    opportunity: opportunity,
  )) {
    await _insert(db, table, row);
  }
}
