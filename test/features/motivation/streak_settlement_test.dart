import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_upgrade_repository.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';

final _day = DateTime.utc(2026, 1, 1, 12);
DateTime _at(int day) => _day.add(Duration(days: day));

void main() {
  setUpAll(tz.initializeTimeZones);
  late Directory directory;
  late File file;
  late AppDatabase database;
  late DriftStreakRepository streak;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp(
      'synthetic-streak-settle-',
    );
    file = File('${directory.path}/local.sqlite');
    database = _open(file);
    streak = DriftStreakRepository(database);
    await _seedOwner(database, 'a', active: true);
    await _seedOwner(database, 'b', active: false);
  });
  tearDown(() async {
    await database.close();
    final root = Directory.systemTemp.absolute.path;
    expect(
      directory.absolute.path.startsWith('$root${Platform.pathSeparator}'),
      isTrue,
    );
    await directory.delete(recursive: true);
  });

  test(
    'read is pending and side-effect free; settlement recovers after reopen',
    () async {
      await _answer(database, 'a', 'a-1', _at(0));
      final before = await _snapshot(database);
      final pending = await streak.loadLearningDays(
        ownerId: 'a',
        asOfUtc: _at(0),
      );
      expect(pending.status, StreakFoldStatus.pending);
      expect(await _snapshot(database), before);
      await database.close();
      database = _open(file);
      streak = DriftStreakRepository(database);
      final settled = await streak.settle(
        expectedOwnerId: 'a',
        asOfUtc: _at(0),
      );
      expect(settled.status, StreakFoldStatus.ready);
      expect(settled.state.currentStreakDays, 1);
      final after = await _snapshot(database);
      await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0));
      expect(await _snapshot(database), after);
      expect(await _rows(database, 'research_consents'), isEmpty);
      expect(await _rows(database, 'events_v2'), isEmpty);
    },
  );

  test(
    'one gap consumes one freeze atomically; a late filled day never refunds',
    () async {
      await _baseline(database, 'a', freeze: 1);
      await _answer(database, 'a', 'first', _at(0));
      await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0));
      await _answer(database, 'a', 'third', _at(2));
      final result = await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(2));
      expect(result.state.currentStreakDays, 1);
      expect(result.state.freezeCount, 0);
      expect(
        (await _rows(
          database,
          'streak_token_adjustments',
        )).where((r) => r['kind'] == 'autoProtect'),
        hasLength(1),
      );
      expect(await _rows(database, 'learning_day_log'), hasLength(2));
      await _answer(database, 'a', 'late-second', _at(1));
      await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(2));
      expect(
        (await streak.loadLearningDays(
          ownerId: 'a',
          asOfUtc: _at(2),
        )).state.freezeCount,
        0,
      );
      expect(
        (await _rows(
          database,
          'streak_token_adjustments',
        )).where((r) => r['kind'] == 'autoProtect'),
        hasLength(1),
      );
    },
  );

  test('late evidence never moves the forward anchor backwards', () async {
    await _answer(database, 'a', 'first', _at(0));
    await _answer(database, 'a', 'fourth', _at(3));
    await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(3));
    await _answer(database, 'a', 'late-second', _at(1));
    await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(3));
    final before = await streak.loadLearningDays(ownerId: 'a', asOfUtc: _at(3));
    expect(before.state.lastLearnedAtUtcMs, _at(3).millisecondsSinceEpoch);
    await _answer(database, 'a', 'fifth', _at(4));
    final after = await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(4));
    expect(after.state.lastLearnedAtUtcMs, _at(4).millisecondsSinceEpoch);
    expect(after.state.currentStreakDays, 2);
  });

  test(
    'manual debit replays exact command, rejects conflicts and cannot underflow',
    () async {
      await _baseline(database, 'a', freeze: 1);
      Future<bool> debit(String id, DateTime at) => streak.debitFreezeToken(
        expectedOwnerId: 'a',
        commandId: id,
        occurredAtUtc: at,
      );
      expect(await debit('manual-1', _at(0)), isTrue);
      expect(await debit('manual-1', _at(0)), isTrue);
      final afterFirst = await _snapshot(database);
      expect(await debit('manual-1', _at(1)), isTrue);
      expect(await _snapshot(database), afterFirst);
      expect(await debit('manual-2', _at(1)), isFalse);
      await database.customStatement(
        'INSERT INTO streak_token_adjustments(id,owner_id,origin_owner_id,command_id,occurred_at_utc_ms,kind,delta) VALUES (?,?,?,?,?,?,?)',
        [
          'synthetic-grant',
          'a',
          'a',
          'grant-command',
          _at(1).millisecondsSinceEpoch,
          'grant',
          1,
        ],
      );
      await expectLater(debit('grant-command', _at(1)), throwsStateError);
      final rows = await _rows(database, 'streak_token_adjustments');
      final manual = rows.where((r) => r['kind'] == 'manualDebit');
      expect(manual, hasLength(1));
      expect(
        (
          manual.single['kind'],
          manual.single['delta'],
          manual.single['protected_day'],
        ),
        ('manualDebit', -1, null),
      );
    },
  );

  test(
    'an insert failure rolls back settlement while answer stays pending',
    () async {
      await _answer(database, 'a', 'durable', _at(0));
      await database.customStatement(
        "CREATE TRIGGER synthetic_streak_failure BEFORE INSERT ON learning_day_log BEGIN SELECT RAISE(ABORT, 'synthetic failure'); END",
      );
      final before = await _snapshot(database);
      await expectLater(
        streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0)),
        throwsA(
          predicate<Object>(
            (error) => error.toString().contains('synthetic failure'),
          ),
        ),
      );
      expect(await _snapshot(database), before);
      expect(
        (await database.select(database.answerAttempts).getSingle()).id,
        'durable',
      );
      expect(
        (await streak.loadLearningDays(ownerId: 'a', asOfUtc: _at(0))).status,
        StreakFoldStatus.pending,
      );
      await database.customStatement('DROP TRIGGER synthetic_streak_failure');
      expect(
        (await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0))).status,
        StreakFoldStatus.ready,
      );
    },
  );

  test('stale owner cannot settle or spend another owner assets', () async {
    await _baseline(database, 'a', freeze: 1);
    await _answer(database, 'a', 'a-answer', _at(0));
    final original = await _snapshot(database);
    await expectLater(
      streak.settle(
        expectedOwnerId: 'a',
        asOfUtc: _at(0),
        answer: (
          attemptId: 'a-answer',
          occurredAtUtcMs: _at(0).millisecondsSinceEpoch + 1,
        ),
      ),
      throwsStateError,
    );
    await expectLater(
      streak.settle(
        expectedOwnerId: 'a',
        asOfUtc: _at(0),
        answer: (
          attemptId: 'missing',
          occurredAtUtcMs: _at(0).millisecondsSinceEpoch,
        ),
      ),
      throwsStateError,
    );
    expect(await _snapshot(database), original);
    await database.customStatement(
      "UPDATE local_owners SET is_active=CASE WHEN id='b' THEN 1 ELSE 0 END",
    );
    final before = await _snapshot(database);
    await expectLater(
      streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0)),
      throwsStateError,
    );
    await expectLater(
      streak.debitFreezeToken(
        expectedOwnerId: 'a',
        commandId: 'stale',
        occurredAtUtc: _at(0),
      ),
      throwsStateError,
    );
    expect(await _snapshot(database), before);
  });

  test('two file connections converge on one auto protection', () async {
    await _baseline(database, 'a', freeze: 1);
    await _answer(database, 'a', 'first', _at(0));
    await streak.settle(expectedOwnerId: 'a', asOfUtc: _at(0));
    await _answer(database, 'a', 'third', _at(2));
    final other = _open(file);
    try {
      final otherStreak = DriftStreakRepository(other);
      await Future.wait([
        streak.settle(expectedOwnerId: 'a', asOfUtc: _at(2)),
        otherStreak.settle(expectedOwnerId: 'a', asOfUtc: _at(2)),
      ]);
      final debits = (await _rows(
        database,
        'streak_token_adjustments',
      )).where((r) => r['kind'] == 'autoProtect');
      expect(debits, hasLength(1));
      expect(
        (await streak.loadLearningDays(
          ownerId: 'a',
          asOfUtc: _at(2),
        )).state.freezeCount,
        0,
      );
    } finally {
      await other.close();
    }
  });

  test('actual owner merge preserves origin assets and target continuity', () async {
    await _baseline(database, 'a', freeze: 2);
    await _baseline(database, 'b', freeze: 3);
    await _answer(database, 'a', 'synthetic-guest-history', _at(-1));
    await database.customStatement(
      'UPDATE streak_baselines SET cutoff_utc_ms=?,current_streak_days=3,'
      'longest_streak_days=7,last_learned_at_utc_ms=?,updated_at_utc_ms=? '
      "WHERE origin_owner_id='a'",
      [
        _at(0).millisecondsSinceEpoch,
        _at(-1).millisecondsSinceEpoch,
        _at(0).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      'INSERT INTO streak_states(owner_id,current_streak_days,longest_streak_days,'
      'freeze_count,last_learned_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,?,?,?)',
      [
        'a',
        3,
        7,
        2,
        _at(-1).millisecondsSinceEpoch,
        _at(0).millisecondsSinceEpoch,
      ],
    );
    await database.customStatement(
      "UPDATE local_owners SET firebase_uid='synthetic-b',account_state='firebaseBound' WHERE id='b'",
    );
    var sequence = 0;
    await DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => _at(1),
      generateConflictId: () => 'synthetic-conflict-${sequence++}',
      generateOwnerId: () => 'unused',
    ).upgrade(activeOwnerId: 'a', firebaseUid: 'synthetic-b');
    final baselines = await _rows(database, 'streak_baselines');
    expect(baselines, hasLength(2));
    expect(baselines.every((r) => r['owner_id'] == 'b'), isTrue);
    expect(
      baselines.singleWhere(
        (r) => r['origin_owner_id'] == 'b',
      )['controls_continuity'],
      1,
    );
    expect(
      baselines.singleWhere(
        (r) => r['origin_owner_id'] == 'a',
      )['controls_continuity'],
      0,
    );
    final result = await streak.loadLearningDays(ownerId: 'b', asOfUtc: _at(1));
    expect(result.state.freezeCount, 5);
    expect(result.currentStreakDays, 0);
    expect(result.state.longestStreakDays, 7);
    await _answer(database, 'b', 'synthetic-target-new-answer', _at(1));
    final settled = await streak.settle(expectedOwnerId: 'b', asOfUtc: _at(1));
    expect(settled.currentStreakDays, 1);
    expect(settled.state.longestStreakDays, 7);
    expect(settled.state.freezeCount, 5);
    expect(
      (await _rows(
        database,
        'streak_token_adjustments',
      )).where((r) => r['kind'] == 'autoProtect'),
      isEmpty,
    );
    expect(await _rows(database, 'events_v2'), isEmpty);
  });
}

AppDatabase _open(File file) => AppDatabase(
  NativeDatabase(
    file,
    setup: (raw) {
      raw.execute('PRAGMA foreign_keys = ON');
      raw.execute('PRAGMA busy_timeout = 5000');
    },
  ),
);

Future<void> _seedOwner(
  AppDatabase db,
  String owner, {
  required bool active,
}) async {
  await db.customStatement(
    'INSERT INTO local_owners(id,created_at_utc_ms,is_active) VALUES (?,?,?)',
    [owner, 1, active ? 1 : 0],
  );
  await db.customStatement(
    'INSERT INTO vocabulary_categories(id,owner_id,name,normalized_name,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,?,1,1)',
    ['cat-$owner', owner, 'Synthetic', 'synthetic'],
  );
  await db.customStatement(
    'INSERT INTO vocabulary_words(id,owner_id,category_id,spelling,normalized_spelling,meaning,normalized_meaning,part_of_speech,created_at_utc_ms,updated_at_utc_ms) VALUES (?,?,?,?,?,?,?,?,1,1)',
    [
      'word-$owner',
      owner,
      'cat-$owner',
      'test',
      'test',
      'test',
      'test',
      'noun',
    ],
  );
  await db.customStatement(
    'INSERT INTO learning_sessions(id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) VALUES (?,?,?,?,?,?,?)',
    ['session-$owner', owner, 'quiz', 'active', 1, 'synthetic', 'synthetic'],
  );
}

Future<void> _answer(
  AppDatabase db,
  String owner,
  String id,
  DateTime time,
) async {
  await DriftLearningRepository(db).recordAnswer(
    RecordAnswerCommand(
      id: id,
      ownerId: owner,
      sessionId: 'session-$owner',
      wordId: 'word-$owner',
      promptMode: 'meaningChoice',
      isCorrect: true,
      responseTimeMs: 100,
      attemptNumber: 1,
      occurredAtUtc: time,
    ),
  );
}

Future<void> _baseline(
  AppDatabase db,
  String owner, {
  required int freeze,
}) => db.customStatement(
  'INSERT INTO streak_baselines(origin_owner_id,owner_id,cutoff_utc_ms,current_streak_days,longest_streak_days,freeze_count,last_learned_at_utc_ms,updated_at_utc_ms,controls_continuity) VALUES (?,?,?,?,?,?,?,?,?)',
  [owner, owner, 1, 0, 0, freeze, null, 1, 1],
);

Future<List<Map<String, Object?>>> _rows(AppDatabase db, String table) async =>
    [
      for (final row
          in await db.customSelect('SELECT * FROM $table ORDER BY rowid').get())
        row.data,
    ];

Future<Map<String, List<Map<String, Object?>>>> _snapshot(
  AppDatabase db,
) async {
  final tables = await db
      .customSelect(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name",
      )
      .get();
  return {
    for (final table in tables.map((row) => row.read<String>('name')))
      table: await _rows(db, table),
  };
}
