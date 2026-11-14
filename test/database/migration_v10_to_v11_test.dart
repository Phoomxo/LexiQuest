import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';

const _at = 1800000000000;
const _newTables = {
  'owner_calendar_epochs',
  'quest_definition_revisions',
  'quest_claim_receipts',
  'streak_baselines',
  'streak_token_adjustments',
  'local_content_reports',
  'focus_sessions',
  'learning_preferences',
  'archived_v25_records',
};
const _objectives =
    '[ { "objectiveId": "synthetic-correct", "targetCount": 5 } ]';
const _reward = '{ "xpAmount": 50, "rewardItemId": null }';
const _sources = '[ "answer-a", "answer-a", "synthetic-old-event" ]';

void main() {
  late Directory directory;
  late File file;
  late _V10Snapshot original;
  AppDatabase? opened;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lexiquest-v10-v11-');
    file = File('${directory.path}/synthetic.sqlite');
    original = _createV10File(file);
  });

  tearDown(() async {
    await opened?.close();
    opened = null;
    final tempRoot = Directory.systemTemp.absolute.path;
    expect(
      directory.absolute.path.startsWith('$tempRoot${Platform.pathSeparator}'),
      isTrue,
    );
    await directory.delete(recursive: true);
  });

  test('frozen v10 enforces lifetime Quest uniqueness and child cascade', () {
    final raw = sqlite.sqlite3.open(file.path);
    try {
      raw.execute('PRAGMA foreign_keys = ON');
      expect(raw.select('PRAGMA user_version').single['user_version'], 10);
      expect(original.columns, hasLength(29));
      expect(original.columns['events_v2'], hasLength(22));
      expect(
        original.columns['answer_attempts'],
        isNot(contains('quest_intent')),
      );
      expect(original.columns['quest_instances'], hasLength(8));
      raw.execute('BEGIN IMMEDIATE');
      try {
        expect(
          () => raw.execute(
            'INSERT INTO quest_instances '
            '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state) '
            "VALUES ('duplicate-old','synthetic-daily','owner-a',1,?, 'active')",
            [_at],
          ),
          throwsA(isA<sqlite.SqliteException>()),
        );
        raw.execute(
          "DELETE FROM quest_instances WHERE instance_id = 'instance-a'",
        );
        expect(raw.select('SELECT * FROM quest_objective_progress'), isEmpty);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        raw.execute('ROLLBACK');
      }
      expect(_readRawRows(raw, original.columns), original.rows);
    } finally {
      raw.close();
    }
  });

  test(
    'real v10 file conserves raw history and assets through two reopens',
    () async {
      final earliestCutoff = DateTime.now().toUtc().millisecondsSinceEpoch;
      var db = _openFile(file);
      opened = db;
      expect((await db.customSelect('PRAGMA user_version').getSingle()).data, {
        'user_version': 26,
      });
      final latestCutoff = DateTime.now().toUtc().millisecondsSinceEpoch;
      expect(await _tableNames(db), {...original.columns.keys, ..._newTables});
      await _expectOriginalRows(db, original);
      final baselines = await _rows(
        db,
        'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
      );
      expect(baselines, hasLength(2));
      final cutoffs = baselines.map((row) => row['cutoff_utc_ms']).toSet();
      expect(cutoffs, hasLength(1));
      expect(cutoffs.single, inInclusiveRange(earliestCutoff, latestCutoff));
      for (final baseline in baselines) {
        final state = original.rows['streak_states']!.singleWhere(
          (row) => row['owner_id'] == baseline['origin_owner_id'],
        );
        expect(baseline['owner_id'], state['owner_id']);
        expect(baseline['controls_continuity'], 1);
        for (final field in [
          'current_streak_days',
          'longest_streak_days',
          'freeze_count',
          'last_learned_at_utc_ms',
          'updated_at_utc_ms',
        ]) {
          expect(baseline[field], state[field], reason: field);
        }
      }

      for (var reopen = 0; reopen <= 2; reopen++) {
        await _expectOriginalRows(db, original);
        expect(
          await _rows(
            db,
            'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
          ),
          baselines,
        );
        expect(
          await _rows(
            db,
            'SELECT calendar_evidence,quest_intent FROM answer_attempts',
          ),
          [
            {'calendar_evidence': null, 'quest_intent': null},
          ],
        );
        expect(
          await _rows(
            db,
            'SELECT record_kind,origin_owner_id,period_key,calendar_rule_id,'
            'civil_label,segments_json,definition_digest,canonical_instance_id '
            'FROM quest_instances',
          ),
          [
            {
              'record_kind': 'legacy',
              'origin_owner_id': null,
              'period_key': null,
              'calendar_rule_id': null,
              'civil_label': null,
              'segments_json': null,
              'definition_digest': null,
              'canonical_instance_id': null,
            },
          ],
        );
        for (final table in _newTables.difference({'streak_baselines'})) {
          expect(
            await _rows(db, 'SELECT * FROM "$table"'),
            isEmpty,
            reason: table,
          );
        }
        expect(await _rows(db, 'SELECT * FROM research_consents'), isEmpty);
        expect(await _rows(db, 'SELECT * FROM events_v2'), isEmpty);
        expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
        expect(
          (await db.customSelect('PRAGMA foreign_keys').getSingle()).data,
          {'foreign_keys': 1},
        );
        expect(
          (await db.customSelect('PRAGMA user_version').getSingle()).data,
          {'user_version': 26},
        );
        final rewards = DriftRewardRepository(db);
        expect((await rewards.load('owner-a')).balance, 1);
        final b = await rewards.load('owner-b');
        expect(b.balance, 120);
        expect(b.ownedItemIds, contains('theme_ocean'));
        expect(b.equippedBySlot, {'theme': 'theme_ocean'});
        expect(
          (await DriftProgressQueries(db).load(
            ownerId: 'owner-b',
            nowUtc: DateTime.fromMillisecondsSinceEpoch(_at, isUtc: true),
          )).totalXp,
          200,
        );
        await _expectOriginalRows(db, original);
        if (reopen < 2) {
          await db.close();
          opened = null;
          db = _openFile(file);
          opened = db;
        }
      }

      final fresh = AppDatabase(NativeDatabase.memory());
      try {
        expect(await _schemaShape(db), await _schemaShape(fresh));
        expect(await _rows(fresh, 'SELECT * FROM streak_baselines'), isEmpty);
      } finally {
        await fresh.close();
      }
    },
  );

  test(
    'canonical Quest periods recur but one period cannot gain a second identity',
    () async {
      final db = _openFile(file);
      opened = db;
      await db.customStatement(
        'INSERT INTO owner_calendar_epochs '
        '(rule_id,owner_id,origin_owner_id,effective_utc_us,expires_utc_us,'
        'iana_id,tzdb_revision,is_selected) VALUES (?,?,?,?,?,?,?,?)',
        [
          'synthetic-rule-a',
          'owner-a',
          'owner-a',
          _at * 1000,
          null,
          'UTC',
          'synthetic',
          1,
        ],
      );
      // Persistence pins only: these rows do not represent an issued claim.
      final digest = List.filled(64, 'a').join();
      for (final version in [3, 4]) {
        await db.customStatement(
          'INSERT INTO quest_definition_revisions '
          '(quest_id,catalog_version,definition_digest,canonical_definition) '
          'VALUES (?,?,?,?)',
          [
            'synthetic-daily',
            version,
            digest,
            '{"synthetic":true,"xpAmount":50}',
          ],
        );
      }
      Future<void> insertPeriod(
        String id,
        String period,
        String label,
        int start, {
        int catalogVersion = 3,
      }) => db.customStatement(
        'INSERT INTO quest_instances '
        '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state,'
        'origin_owner_id,period_key,calendar_rule_id,civil_label,segments_json,'
        'definition_digest,record_kind) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?)',
        [
          id,
          'synthetic-daily',
          'owner-a',
          catalogVersion,
          start,
          'active',
          'owner-a',
          period,
          'synthetic-rule-a',
          label,
          '[[${start * 1000},${(start + 86400000) * 1000}]]',
          digest,
          'canonical',
        ],
      );
      await insertPeriod('period-one', 'daily:one', '2027-01-15', _at);
      await insertPeriod(
        'period-two',
        'daily:two',
        '2027-01-16',
        _at + 86400000,
      );
      await expectLater(
        insertPeriod(
          'same-period-other-id',
          'daily:one',
          '2027-01-15',
          _at,
          catalogVersion: 4,
        ),
        throwsA(isA<sqlite.SqliteException>()),
      );
      expect(
        await _rows(
          db,
          'SELECT instance_id,period_key FROM quest_instances '
          "WHERE record_kind = 'canonical' ORDER BY instance_id",
        ),
        [
          {'instance_id': 'period-one', 'period_key': 'daily:one'},
          {'instance_id': 'period-two', 'period_key': 'daily:two'},
        ],
      );
      expect(await _rows(db, 'SELECT * FROM quest_claim_receipts'), isEmpty);
      expect(await _rows(db, 'PRAGMA foreign_key_check'), isEmpty);
      await _expectOriginalRows(db, original, ignoreNewQuestInstances: true);
    },
  );

  test(
    'mixed-case extension FK cannot lose its rows to a cascading drop',
    () async {
      final before = _withRaw(file, (raw) {
        raw.execute(
          'CREATE TABLE synthetic_extension (parent TEXT NOT NULL '
          'REFERENCES "QUEST_INSTANCES"(instance_id) ON DELETE CASCADE)',
        );
        raw.execute("INSERT INTO synthetic_extension VALUES ('instance-a')");
        return _rawSchema(raw);
      });

      await _expectOpenFailure(_openFile(file), isA<StateError>());
      _withRaw(file, (raw) {
        _expectV10Unchanged(raw, original, before);
        expect(
          raw.select('SELECT parent FROM synthetic_extension').single['parent'],
          'instance-a',
        );
      });
    },
  );

  test('unsupported partial Quest period schema stays intact at v10', () async {
    final before = _withRaw(file, (raw) {
      final parentDdl =
          raw
                  .select(
                    "SELECT sql FROM sqlite_master WHERE name='quest_instances'",
                  )
                  .single['sql']
              as String;
      final childDdl =
          raw
                  .select(
                    "SELECT sql FROM sqlite_master WHERE name='quest_objective_progress'",
                  )
                  .single['sql']
              as String;
      const lifetimeUnique = ', UNIQUE ("owner_id", "quest_id")';
      expect(parentDdl, contains(lifetimeUnique));
      final fields = original.columns['quest_instances']!.join(',');
      raw.execute('BEGIN IMMEDIATE');
      raw.execute(
        'CREATE TEMP TABLE saved_parents AS SELECT * FROM quest_instances',
      );
      raw.execute(
        'CREATE TEMP TABLE saved_children AS SELECT * FROM quest_objective_progress',
      );
      raw.execute('DROP TABLE quest_objective_progress');
      raw.execute('DROP TABLE quest_instances');
      raw.execute(parentDdl.replaceFirst(lifetimeUnique, ''));
      raw.execute(
        "ALTER TABLE quest_instances ADD COLUMN record_kind TEXT DEFAULT 'legacy'",
      );
      raw.execute('ALTER TABLE quest_instances ADD COLUMN period_key TEXT');
      raw.execute(
        'INSERT INTO quest_instances ($fields) SELECT $fields FROM saved_parents',
      );
      raw.execute(
        "UPDATE quest_instances SET period_key = 'existing-hybrid-value'",
      );
      raw.execute(childDdl);
      raw.execute(
        'INSERT INTO quest_objective_progress SELECT * FROM saved_children',
      );
      raw.execute('COMMIT');
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
      return _rawSchema(raw);
    });

    await _expectOpenFailure(
      AppDatabase(NativeDatabase(file)),
      isA<StateError>(),
    );
    _withRaw(file, (raw) {
      _expectV10Unchanged(raw, original, before);
      final parent = raw
          .select('SELECT record_kind,period_key FROM quest_instances')
          .single;
      expect(
        [parent['record_kind'], parent['period_key']],
        ['legacy', 'existing-hybrid-value'],
      );
    });
  });

  test(
    'unexpected calendar table without constraints stays intact at v10',
    () async {
      final before = _withRaw(file, (raw) {
        raw.execute(
          'CREATE TABLE owner_calendar_epochs (rule_id TEXT, owner_id TEXT, '
          'origin_owner_id TEXT, effective_utc_us INTEGER, expires_utc_us INTEGER, '
          'iana_id TEXT, tzdb_revision TEXT, is_selected INTEGER)',
        );
        raw.execute(
          "INSERT INTO owner_calendar_epochs VALUES "
          "('sentinel','owner-a','owner-a',1,0,'UTC','synthetic',1)",
        );
        return _rawSchema(raw);
      });

      await _expectOpenFailure(_openFile(file), isA<Object>());
      _withRaw(file, (raw) {
        _expectV10Unchanged(raw, original, before);
        final rows = raw.select('SELECT * FROM owner_calendar_epochs');
        expect(rows, hasLength(1));
        expect(rows.single['rule_id'], 'sentinel');
        expect(rows.single['expires_utc_us'], 0);
      });
    },
  );

  test('preexisting populated revision archive stays intact at v10', () async {
    final before = _withRaw(file, (raw) {
      raw.execute(
        'CREATE TABLE quest_definition_revisions ('
        'quest_id TEXT NOT NULL, catalog_version INTEGER NOT NULL, '
        'definition_digest TEXT NOT NULL, canonical_definition TEXT NOT NULL, '
        'PRIMARY KEY (quest_id, catalog_version), '
        'UNIQUE (quest_id, catalog_version, definition_digest))',
      );
      raw.execute(
        "INSERT INTO quest_definition_revisions VALUES "
        "('synthetic-daily', 1, 'untrusted-digest', '{\"synthetic\":true}')",
      );
      return _rawSchema(raw);
    });

    await _expectOpenFailure(_openFile(file), isA<Object>());
    _withRaw(file, (raw) {
      _expectV10Unchanged(raw, original, before);
      final rows = raw.select('SELECT * FROM quest_definition_revisions');
      expect(rows, hasLength(1));
      expect(rows.single['definition_digest'], 'untrusted-digest');
      expect(rows.single['canonical_definition'], '{"synthetic":true}');
    });
  });

  test('wrong-table nonunique index collision stays intact at v10', () async {
    const name = 'idx_quest_canonical_owner_period';
    final before = _withRaw(file, (raw) {
      raw.execute('CREATE INDEX $name ON streak_states(owner_id)');
      return _rawSchema(raw);
    });

    await _expectOpenFailure(_openFile(file), isA<Object>());
    _withRaw(file, (raw) {
      _expectV10Unchanged(raw, original, before);
      expect(
        raw
            .select("SELECT tbl_name FROM sqlite_master WHERE name='$name'")
            .single['tbl_name'],
        'streak_states',
      );
    });
  });

  test('wrong partial attempt index collision stays intact at v10', () async {
    const name = 'idx_learning_attempts_owner_time_id';
    final before = _withRaw(file, (raw) {
      raw.execute(
        'CREATE INDEX $name ON answer_attempts(owner_id,occurred_at_utc_ms,id) '
        'WHERE is_correct = 0',
      );
      return _rawSchema(raw);
    });

    await _expectOpenFailure(_openFile(file), isA<Object>());
    _withRaw(file, (raw) {
      _expectV10Unchanged(raw, original, before);
      expect(
        raw
            .select("SELECT sql FROM sqlite_master WHERE name='$name'")
            .single['sql'],
        contains('WHERE is_correct = 0'),
      );
    });
  });

  test(
    'failure after restoring Quest rolls back the file and permits retry',
    () async {
      const collision = 'idx_learning_attempts_owner_time_id';
      final before = _withRaw(file, (raw) {
        raw.execute('CREATE TABLE $collision (sentinel TEXT NOT NULL)');
        raw.execute("INSERT INTO $collision VALUES ('keep')");
        return _rawSchema(raw);
      });

      await _expectOpenFailure(
        _openFile(file),
        isA<StateError>().having(
          (e) => e.message,
          'message',
          contains(collision),
        ),
      );
      _withRaw(file, (raw) {
        _expectV10Unchanged(raw, original, before);
        expect(
          raw.select('SELECT sentinel FROM $collision').single['sentinel'],
          'keep',
        );
        raw.execute('DROP TABLE $collision');
      });
      final retry = _openFile(file);
      opened = retry;
      expect(
        (await retry.customSelect('PRAGMA user_version').getSingle()).data,
        {'user_version': 26},
      );
      await _expectOriginalRows(retry, original);
      expect(await _rows(retry, 'PRAGMA foreign_key_check'), isEmpty);
    },
  );

  for (final badDefinition in [
    'CREATE INDEX idx_quest_canonical_owner_period ON streak_states(owner_id)',
    "CREATE UNIQUE INDEX idx_quest_canonical_owner_period ON quest_instances(owner_id,period_key) WHERE record_kind='CANONICAL'",
    "CREATE UNIQUE INDEX idx_quest_canonical_owner_period ON quest_instances(owner_id,period_key) WHERE record_kind='c a n o n i c a l'",
    "CREATE UNIQUE INDEX idx_quest_canonical_owner_period ON quest_instances(owner_id,period_key) WHERE record_kind='canon IF NOT EXISTSical'",
  ]) {
    test('v26 rejects and repairs index: $badDefinition', () async {
      const index = 'idx_quest_canonical_owner_period';
      final initial = _openFile(file);
      await initial.customSelect('SELECT 1').get();
      final baselines = await _rows(
        initial,
        'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
      );
      await initial.close();

      final before = _withRaw(file, (raw) {
        raw.execute('DROP INDEX $index');
        raw.execute(badDefinition);
        return _rawSchema(raw);
      });
      await _expectOpenFailure(
        _openFile(file),
        isA<StateError>().having((e) => e.message, 'message', contains(index)),
      );
      _withRaw(file, (raw) {
        expect(raw.select('PRAGMA user_version').single['user_version'], 26);
        expect(_rawSchema(raw), before);
        expect(_readRawRows(raw, original.columns), original.rows);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        expect([
          for (final row in raw.select(
            'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
          ))
            Map<String, Object?>.from(row),
        ], baselines);
        raw.execute('DROP INDEX $index');
      });

      final repaired = _openFile(file);
      opened = repaired;
      await _expectOriginalRows(repaired, original);
      expect(await _rows(repaired, 'PRAGMA foreign_key_check'), isEmpty);
      expect(
        await _rows(
          repaired,
          'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
        ),
        baselines,
      );
      final definition = await _rows(
        repaired,
        "SELECT tbl_name,sql FROM sqlite_master WHERE name='$index'",
      );
      expect(definition.single['tbl_name'], 'quest_instances');
      expect(definition.single['sql'], contains('UNIQUE INDEX'));
    });
  }

  test(
    'failure after migration commit retains v26 and its sealed baselines',
    () async {
      const collision = 'idx_events_v2_owner_occurred';
      _withRaw(file, (raw) {
        raw.execute('DROP INDEX $collision');
        raw.execute('CREATE TABLE $collision (sentinel TEXT NOT NULL)');
        raw.execute("INSERT INTO $collision VALUES ('keep')");
      });

      await _expectOpenFailure(_openFile(file), _indexCollision(collision));
      final beforeRetry = _withRaw(file, (raw) {
        expect(raw.select('PRAGMA user_version').single['user_version'], 26);
        expect(_readRawRows(raw, original.columns), original.rows);
        expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        final tables = raw
            .select("SELECT name FROM sqlite_master WHERE type='table'")
            .map((row) => row['name'])
            .toSet();
        expect(tables, {...original.columns.keys, ..._newTables, collision});
        expect(
          raw
              .select('SELECT record_kind FROM quest_instances')
              .single['record_kind'],
          'legacy',
        );
        final baselines = [
          for (final row in raw.select(
            'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
          ))
            Map<String, Object?>.from(row),
        ];
        expect(baselines, hasLength(2));
        expect(
          baselines.map((row) => row['cutoff_utc_ms']).toSet(),
          hasLength(1),
        );
        expect(
          raw.select('SELECT sentinel FROM $collision').single['sentinel'],
          'keep',
        );
        raw.execute('DROP TABLE $collision');
        return baselines;
      });

      final retry = _openFile(file);
      opened = retry;
      await _expectOriginalRows(retry, original);
      expect(
        await _rows(
          retry,
          'SELECT * FROM streak_baselines ORDER BY origin_owner_id',
        ),
        beforeRetry,
      );
      expect(await _rows(retry, 'PRAGMA foreign_key_check'), isEmpty);
      expect(
        (await retry.customSelect('PRAGMA user_version').getSingle()).data,
        {'user_version': 26},
      );
    },
  );
}

T _withRaw<T>(File file, T Function(sqlite.Database raw) read) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute('PRAGMA foreign_keys = ON');
    return read(raw);
  } finally {
    raw.close();
  }
}

List<Map<String, Object?>> _rawSchema(sqlite.Database raw) => [
  for (final row in raw.select(
    'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
  ))
    Map<String, Object?>.from(row),
];

void _expectV10Unchanged(
  sqlite.Database raw,
  _V10Snapshot original,
  List<Map<String, Object?>> before,
) {
  expect(raw.select('PRAGMA user_version').single['user_version'], 10);
  expect(_rawSchema(raw), before);
  expect(_readRawRows(raw, original.columns), original.rows);
  expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
}

Matcher _indexCollision(String name) => isA<sqlite.SqliteException>().having(
  (e) => e.message,
  'SQLite collision message',
  contains(name),
);

Future<void> _expectOpenFailure(AppDatabase db, Matcher error) async {
  try {
    await expectLater(db.customSelect('SELECT 1').get(), throwsA(error));
  } finally {
    await db.close();
  }
}

AppDatabase _openFile(File file) => AppDatabase(
  NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA foreign_keys = ON')),
);

final class _V10Snapshot {
  const _V10Snapshot(this.columns, this.rows, this.indexes);
  final Map<String, List<String>> columns;
  final Map<String, List<Map<String, Object?>>> rows;
  final List<Map<String, Object?>> indexes;
}

_V10Snapshot _createV10File(File file) {
  final raw = sqlite.sqlite3.open(file.path);
  try {
    raw.execute('PRAGMA foreign_keys = ON');
    raw.execute(
      File('test/fixtures/database/v10/schema.sql').readAsStringSync(),
    );
    raw.execute(
      File('test/fixtures/database/v10/runtime_indexes.sql').readAsStringSync(),
    );
    raw.execute('PRAGMA user_version = 10');
    for (final owner in ['a', 'b']) {
      raw.execute(
        'INSERT INTO local_owners(id,is_active,created_at_utc_ms) VALUES (?,?,?)',
        ['owner-$owner', owner == 'a' ? 1 : 0, _at],
      );
      raw.execute(
        'INSERT INTO vocabulary_categories '
        '(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) '
        'VALUES (?,?,?,?,?,?)',
        [
          'category-$owner',
          'owner-$owner',
          'Synthetic $owner',
          'synthetic-$owner',
          _at,
          _at,
        ],
      );
      raw.execute(
        'INSERT INTO vocabulary_words '
        '(id,owner_id,category_id,spelling,normalized_spelling,meaning,'
        'normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) '
        'VALUES (?,?,?,?,?,?,?,?,?,?)',
        [
          'word-$owner',
          'owner-$owner',
          'category-$owner',
          'synthetic-$owner',
          'synthetic-$owner',
          'test',
          'test',
          'noun',
          _at,
          _at,
        ],
      );
    }
    raw.execute(
      'INSERT INTO learning_sessions '
      '(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
      "VALUES ('session-a','owner-a','quiz','active',?,'synthetic','synthetic')",
      [_at],
    );
    raw.execute(
      'INSERT INTO answer_attempts '
      '(id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,'
      'attempt_number,occurred_at_utc_ms,provider_provenance) '
      "VALUES ('answer-a','owner-a','session-a','word-a','meaningChoice',1,120,1,?,?)",
      [_at, 'synthetic-provider'],
    );
    raw.execute(
      'INSERT INTO quest_definitions '
      '(quest_id,catalog_version,title,description,type,objectives_json,reward_json,'
      'expires_in_ms,tags_json) VALUES (?,?,?,?,?,?,?,?,?)',
      [
        'synthetic-daily',
        2,
        'Synthetic daily',
        'Historical only',
        'daily',
        _objectives,
        _reward,
        86400000,
        '[ "synthetic", "history" ]',
      ],
    );
    raw.execute(
      'INSERT INTO quest_instances '
      '(instance_id,quest_id,owner_id,catalog_version,assigned_at_utc_ms,state) '
      "VALUES ('instance-a','synthetic-daily','owner-a',1,?,'active')",
      [_at],
    );
    raw.execute(
      'INSERT INTO quest_objective_progress '
      '(id,instance_id,objective_id,current_count,target_count,source_event_ids_json) '
      "VALUES ('objective-a','instance-a','synthetic-correct',5,5,?)",
      [_sources],
    );
    raw.execute(
      'INSERT INTO streak_states '
      '(owner_id,current_streak_days,longest_streak_days,freeze_count,'
      'last_learned_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,?,?,?)',
      ['owner-a', 3, 9, 2, _at, _at + 5],
    );
    // v10 permits surprising raw assets; migration must preserve, not repair them.
    raw.execute(
      'INSERT INTO streak_states '
      '(owner_id,current_streak_days,longest_streak_days,freeze_count,'
      'last_learned_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,?,?,?)',
      ['owner-b', -2, -1, -3, null, _at + 4],
    );
    raw.execute(
      'INSERT INTO learning_day_log(id,owner_id,learning_day,first_session_at_utc_ms) '
      "VALUES ('day-a','owner-a','2027-01-15',?)",
      [_at],
    );
    raw.execute(
      'INSERT INTO points_ledger_entries '
      '(id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms) '
      "VALUES ('points:answer-a','owner-a','correct-answer:answer-a','quizCorrect',1,'answer-a',?),"
      "('legacy-b','owner-b','legacy-b','learning',200,NULL,?)",
      [_at, _at],
    );
    raw.execute(
      'INSERT INTO reward_transactions '
      '(id,owner_id,idempotency_key,transaction_type,amount,item_id,catalog_version,'
      'source_event_id,occurred_at_utc_ms) VALUES '
      "('coin:quiz:answer-a','owner-a','creditQuizCorrectV1:answer-a','creditQuizCorrectV1',1,NULL,0,'answer-a',?),"
      "('coin:legacy:legacy-b','owner-b','creditLegacyCarryV1:legacy-b','creditLegacyCarryV1',200,NULL,0,'legacy-b',?),"
      "('purchase-b','owner-b','purchase-b','purchase',-80,'theme_ocean',1,NULL,?),"
      "('equip-b','owner-b','equip-b','equip',0,'theme_ocean',1,NULL,?)",
      [_at, _at, _at + 1, _at + 2],
    );
    raw.execute(
      'INSERT INTO owned_reward_items '
      '(id,owner_id,item_id,catalog_version,acquired_by_transaction_id,acquired_at_utc_ms) '
      "VALUES ('owned-b','owner-b','theme_ocean',1,'purchase-b',?)",
      [_at + 1],
    );
    raw.execute(
      'INSERT INTO equipped_reward_items(id,owner_id,slot,item_id,equipped_at_utc_ms) '
      "VALUES ('equipped-b','owner-b','theme','theme_ocean',?)",
      [_at + 2],
    );
    raw.execute(
      'INSERT INTO outbox_operations '
      '(operation_id,owner_id,entity_type,entity_id,operation_kind,created_at_utc_ms) '
      "VALUES ('ordinary-pending-b','owner-b','word','word-b','upsert',?)",
      [_at + 3],
    );
    expect(raw.select('PRAGMA foreign_keys').single['foreign_keys'], 1);
    expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    final tables = raw.select(
      "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
    );
    final columns = <String, List<String>>{
      for (final table in tables)
        table['name'] as String: raw
            .select('PRAGMA table_info("${table['name']}")')
            .map((row) => row['name'] as String)
            .toList(),
    };
    final indexes = raw.select(
      "SELECT name,sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name",
    );
    return _V10Snapshot(columns, _readRawRows(raw, columns), [
      for (final row in indexes) Map<String, Object?>.from(row),
    ]);
  } finally {
    raw.close();
  }
}

Map<String, List<Map<String, Object?>>> _readRawRows(
  sqlite.Database raw,
  Map<String, List<String>> columns,
) => {
  for (final entry in columns.entries)
    entry.key: [
      for (final row in raw.select(_oldRowQuery(entry.key, entry.value)))
        Map<String, Object?>.from(row),
    ],
};

String _oldRowQuery(String table, List<String> columns) {
  final fields = columns.map((name) => '"$name"').join(',');
  return 'SELECT $fields FROM "$table" ORDER BY $fields';
}

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String sql) async =>
    (await db.customSelect(sql).get()).map((row) => row.data).toList();

Future<Set<String>> _tableNames(AppDatabase db) async => {
  for (final row in await _rows(
    db,
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'",
  ))
    row['name']! as String,
};

Future<void> _expectOriginalRows(
  AppDatabase db,
  _V10Snapshot original, {
  bool ignoreNewQuestInstances = false,
}) async {
  for (final entry in original.columns.entries) {
    final fields = await _rows(db, 'PRAGMA table_info("${entry.key}")');
    expect(fields.map((row) => row['name']), containsAll(entry.value));
    var sql = _oldRowQuery(entry.key, entry.value);
    if (ignoreNewQuestInstances && entry.key == 'quest_instances') {
      sql = sql.replaceFirst(
        ' ORDER BY',
        " WHERE record_kind='legacy' ORDER BY",
      );
    }
    expect(await _rows(db, sql), original.rows[entry.key], reason: entry.key);
  }
  for (final index in original.indexes) {
    final actual = await _rows(
      db,
      "SELECT name,sql FROM sqlite_master WHERE type='index' AND name='${index['name']}'",
    );
    expect(actual, [index], reason: 'v10 runtime index changed');
  }
}

Future<Map<String, Object?>> _schemaShape(AppDatabase db) async {
  final shape = <String, Object?>{};
  final tables = (await _tableNames(db)).toList()..sort();
  for (final table in tables) {
    final indexes = <String, Object?>{};
    for (final index in await _rows(db, 'PRAGMA index_list("$table")')) {
      final fields = await _rows(db, 'PRAGMA index_info("${index['name']}")');
      final key =
          '${index['unique']}:${index['origin']}:${index['partial']}:'
          '${fields.map((row) => row['name']).join(',')}';
      indexes[key] = fields.map((row) => row['name']).toList();
    }
    shape[table] = {
      'columns': await _rows(db, 'PRAGMA table_info("$table")'),
      'foreignKeys': await _rows(db, 'PRAGMA foreign_key_list("$table")'),
      'indexes': indexes,
    };
  }
  return shape;
}
