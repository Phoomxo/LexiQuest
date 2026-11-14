import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:vocab_learning_app/data/local/app_database.dart';

const _newTables = {
  'local_content_reports',
  'focus_sessions',
  'learning_preferences',
};
const _addedColumns = {
  'learning_sessions': ['question_plan_json', 'continuation_json'],
  'answer_attempts': ['answer_evidence_json'],
  'vocabulary_words': ['is_bookmarked'],
};

void main() {
  late Directory directory;
  late String allocatedPath;
  late File file;
  late Map<String, List<String>> oldColumns;
  late Map<String, List<Map<String, Object?>>> oldRows;
  late List<Map<String, Object?>> oldIndexes;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('lexiquest-v11-v12-');
    allocatedPath = await directory.resolveSymbolicLinks();
    file = File('${directory.path}/synthetic.sqlite');
    final raw = sqlite.sqlite3.open(file.path);
    try {
      raw.execute('PRAGMA foreign_keys=ON');
      raw.execute(
        File('test/fixtures/database/v11/schema.sql').readAsStringSync(),
      );
      _seedV11(raw);
      expect(_version(raw), 11);
      oldColumns = {
        for (final table in _tables(raw))
          table: [
            for (final col in raw.select('PRAGMA table_info("$table")'))
              col['name'] as String,
          ],
      };
      expect(oldColumns, hasLength(34));
      oldRows = _projectedRows(raw, oldColumns);
      oldIndexes = _indexes(raw);
      expect(oldIndexes, hasLength(10));
      expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
    } finally {
      raw.close();
    }
  });

  tearDown(() async {
    final resolved = Directory(await directory.resolveSymbolicLinks());
    expect(resolved.path, allocatedPath);
    expect(
      resolved.parent.path,
      await Directory.systemTemp.resolveSymbolicLinks(),
    );
    expect(
      resolved.uri.pathSegments.where((p) => p.isNotEmpty).last,
      startsWith('lexiquest-v11-v12-'),
    );
    await resolved.delete(recursive: true);
  });

  test('frozen v11 contains the original study histories and schema', () {
    expect(
      oldRows.entries.where((e) => e.value.isNotEmpty).map((e) => e.key),
      containsAll([
        'local_owners',
        'vocabulary_categories',
        'vocabulary_words',
        'learning_sessions',
        'answer_attempts',
        'points_ledger_entries',
        'reward_transactions',
        'outbox_operations',
        'quest_definition_revisions',
        'owner_calendar_epochs',
        'streak_baselines',
      ]),
    );
    for (final entry in _addedColumns.entries) {
      for (final name in entry.value) {
        expect(oldColumns[entry.key], isNot(contains(name)));
      }
    }
    expect(oldColumns.keys.toSet().intersection(_newTables), isEmpty);
  });

  test(
    'v12 preserves every v11 row and starts new local fields empty on upgrade and reopen',
    () async {
      for (var openings = 0; openings < 2; openings++) {
        await _openAndClose(file);
        final raw = sqlite.sqlite3.open(file.path);
        try {
          expect(_version(raw), 12);
          expect(_tables(raw), {...oldColumns.keys, ..._newTables});
          expect(_projectedRows(raw, oldColumns), oldRows);
          expect(_indexes(raw), containsAll(oldIndexes));
          for (final table in _newTables) {
            expect(
              raw.select('SELECT * FROM "$table"'),
              isEmpty,
              reason: table,
            );
          }
          for (final entry in _addedColumns.entries) {
            for (final name in entry.value) {
              final values = raw.select('SELECT "$name" FROM "${entry.key}"');
              final column = raw
                  .select('PRAGMA table_info("${entry.key}")')
                  .singleWhere((col) => col['name'] == name);
              expect(column['notnull'], name == 'is_bookmarked' ? 1 : 0);
              final defaultSql = column['dflt_value'] as String?;
              final defaultValue = raw
                  .select('SELECT ${defaultSql ?? 'NULL'} AS value')
                  .single['value'];
              expect(
                defaultValue,
                name == 'is_bookmarked' ? equals(0) : isNull,
              );
              expect(values, isNotEmpty);
              expect(
                values.map((row) => row[name]),
                everyElement(name == 'is_bookmarked' ? equals(0) : isNull),
              );
            }
          }
          expect(raw.select('PRAGMA foreign_key_check'), isEmpty);
        } finally {
          raw.close();
        }
      }
    },
  );

  test(
    'fresh and upgraded v12 have equivalent columns, foreign keys and indexes',
    () async {
      final freshFile = File('${directory.path}/fresh.sqlite');
      await _openAndClose(freshFile);
      await _openAndClose(file);
      final fresh = sqlite.sqlite3.open(freshFile.path);
      final upgraded = sqlite.sqlite3.open(file.path);
      try {
        expect(_version(fresh), 12);
        expect(_version(upgraded), 12);
        expect(_tables(fresh), hasLength(37));
        expect(_tables(fresh), {...oldColumns.keys, ..._newTables});
        expect(_schemaFacts(upgraded), _schemaFacts(fresh));
        expect(fresh.select('PRAGMA foreign_key_check'), isEmpty);
        expect(upgraded.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        upgraded.close();
        fresh.close();
      }
    },
  );

  test(
    'malformed preexisting v12 table rolls back the entire upgrade and permits a repaired retry',
    () async {
      late List<Map<String, Object?>> hybridSchema;
      final before = sqlite.sqlite3.open(file.path);
      try {
        before.execute(
          'CREATE TABLE focus_sessions(synthetic_sentinel TEXT PRIMARY KEY)',
        );
        before.execute(
          "INSERT INTO focus_sessions VALUES ('retain until fixture repair')",
        );
        hybridSchema = _schemaObjects(before);
      } finally {
        before.close();
      }
      await expectLater(
        _openAndClose(file),
        throwsA(
          predicate<Object>(
            (e) => e.toString().toLowerCase().contains('focus_sessions'),
            'migration reports the conflicting focus_sessions table',
          ),
        ),
      );
      final failed = sqlite.sqlite3.open(file.path);
      try {
        expect(_version(failed), 11);
        expect(_schemaObjects(failed), hybridSchema);
        expect(_projectedRows(failed, oldColumns), oldRows);
        expect(
          failed
              .select('SELECT * FROM focus_sessions')
              .single['synthetic_sentinel'],
          'retain until fixture repair',
        );
        expect(failed.select('PRAGMA foreign_key_check'), isEmpty);
        failed.execute('DROP TABLE focus_sessions');
      } finally {
        failed.close();
      }
      await _openAndClose(file);
      final repaired = sqlite.sqlite3.open(file.path);
      try {
        expect(_version(repaired), 12);
        expect(_tables(repaired), {...oldColumns.keys, ..._newTables});
        expect(_projectedRows(repaired, oldColumns), oldRows);
        expect(repaired.select('PRAGMA foreign_key_check'), isEmpty);
      } finally {
        repaired.close();
      }
    },
  );
}

Future<void> _openAndClose(File file) async {
  final db = AppDatabase(
    NativeDatabase(file, setup: (raw) => raw.execute('PRAGMA foreign_keys=ON')),
  );
  try {
    await db.customSelect('SELECT 1').getSingle();
  } finally {
    await db.close();
  }
}

int _version(sqlite.Database raw) =>
    raw.select('PRAGMA user_version').single['user_version'] as int;

Set<String> _tables(sqlite.Database raw) => {
  for (final row in raw.select(
    "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
  ))
    row['name'] as String,
};

List<Map<String, Object?>> _schemaObjects(sqlite.Database raw) => [
  for (final row in raw.select(
    'SELECT type,name,tbl_name,sql FROM sqlite_master ORDER BY type,name',
  ))
    Map<String, Object?>.from(row),
];

List<Map<String, Object?>> _indexes(sqlite.Database raw) => [
  for (final row in raw.select(
    "SELECT name,tbl_name,sql FROM sqlite_master WHERE type='index' AND sql IS NOT NULL ORDER BY name",
  ))
    Map<String, Object?>.from(row),
];

Map<String, List<Map<String, Object?>>> _projectedRows(
  sqlite.Database raw,
  Map<String, List<String>> columns,
) => {
  for (final entry in columns.entries)
    entry.key: [
      for (final row in raw.select(
        'SELECT ${entry.value.map((c) => '"$c"').join(',')} FROM "${entry.key}" ORDER BY rowid',
      ))
        Map<String, Object?>.from(row),
    ],
};

Map<String, Object?> _schemaFacts(sqlite.Database raw) {
  final result = <String, Object?>{};
  for (final table in _tables(raw)) {
    final columns = {
      for (final row in raw.select('PRAGMA table_info("$table")'))
        row['name']: Map<String, Object?>.from(row)..remove('cid'),
    };
    final indexes = <String, Object?>{};
    for (final row in raw.select('PRAGMA index_list("$table")')) {
      final name = row['name'] as String;
      final fields = [
        for (final part in raw.select('PRAGMA index_xinfo("$name")'))
          if (part['key'] == 1) (part['name'], part['coll'], part['desc']),
      ];
      final sql =
          raw.select(
                'SELECT sql FROM sqlite_master WHERE type=\'index\' AND name=?',
                [name],
              ).single['sql']
              as String?;
      final predicate = sql == null
          ? null
          : RegExp(
              r'\bWHERE\b(.*)',
              caseSensitive: false,
              dotAll: true,
            ).firstMatch(sql)?.group(1)?.trim();
      final key = row['origin'] == 'c'
          ? name
          : '${row['origin']}:${fields.join(',')}';
      indexes[key] = [row['unique'], row['partial'], fields, predicate];
    }
    result[table] = {
      'columns': columns,
      'keys': [
        for (final row in raw.select('PRAGMA foreign_key_list("$table")'))
          Map<String, Object?>.from(row),
      ],
      'indexes': indexes,
    };
  }
  return result;
}

void _seedV11(sqlite.Database raw) {
  raw.execute('''
    BEGIN;
    INSERT INTO local_owners (id,created_at_utc_ms) VALUES ('owner-a',1);
    INSERT INTO local_owners (id,is_active,created_at_utc_ms) VALUES ('owner-b',0,2);
    INSERT INTO vocabulary_categories (id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms)
      VALUES ('cat','owner-a','Travel','travel',3,4);
    INSERT INTO vocabulary_words (id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,local_revision,cloud_revision,created_at_utc_ms,updated_at_utc_ms)
      VALUES ('word','owner-a','cat','station','station','สถานี','สถานี','noun',5,3,5,6);
    INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,ended_at_utc_ms,correct_count,wrong_count,score,app_version,build_id)
      VALUES ('round','owner-a','quiz','completed',10,30,1,0,100,'v11','synthetic');
    INSERT INTO answer_attempts (id,owner_id,session_id,word_id,prompt_mode,is_correct,response_time_ms,attempt_number,occurred_at_utc_ms,provider_provenance,calendar_evidence,quest_intent)
      VALUES ('answer','owner-a','round','word','meaningChoice',1,487,1,20,'retained source','{ "archive": "calendar" }','{ "archive": "intent" }');
    INSERT INTO points_ledger_entries (id,owner_id,idempotency_key,entry_type,amount,source_event_id,occurred_at_utc_ms)
      VALUES ('xp','owner-a','correct-answer:answer','quizCorrect',1,'answer',20);
    INSERT INTO reward_transactions (id,owner_id,idempotency_key,transaction_type,amount,catalog_version,source_event_id,occurred_at_utc_ms)
      VALUES ('coin','owner-a','coin:answer','creditQuizCorrectV1',1,1,'answer',20);
    INSERT INTO achievement_unlocks (id,owner_id,achievement_id,definition_version,source_event_id,unlocked_at_utc_ms)
      VALUES ('opaque-badge','owner-a','first_answer',1,'answer',20);
    INSERT INTO outbox_operations (operation_id,owner_id,entity_type,entity_id,operation_kind,state,attempt_count,created_at_utc_ms,acknowledged_at_utc_ms)
      VALUES ('opaque-op','owner-a','achievementUnlock','opaque-badge','upsert','acknowledged',2,20,40);
    INSERT INTO owner_calendar_epochs (rule_id,owner_id,origin_owner_id,effective_utc_us,iana_id,tzdb_revision,is_selected)
      VALUES ('rule','owner-a','owner-a',11,'Asia/Bangkok','synthetic-v11-revision',1);
    INSERT INTO quest_definition_revisions (quest_id,catalog_version,definition_digest,canonical_definition)
      VALUES ('quest',1,'synthetic-digest','{ "archived": true }');
    INSERT INTO streak_baselines (origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,freeze_count,updated_at_utc_ms,controls_continuity)
      VALUES ('owner-a','owner-a',7,-2,-1,-3,7,1);
    COMMIT;
  ''');
}
