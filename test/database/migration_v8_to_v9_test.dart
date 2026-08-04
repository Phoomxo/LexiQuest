import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';

void main() {
  group('Schema v8→v9 migration — D7.2 Streak persistence', () {
    late AppDatabase db;

    setUp(() {
      db = AppDatabase(NativeDatabase.memory());
    });

    tearDown(() async => db.close());

    test('streak_states table exists after fresh onCreate', () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='streak_states'",
          )
          .get();
      expect(tables, hasLength(1));
    });

    test('learning_day_log table exists after fresh onCreate', () async {
      await db.customSelect('SELECT 1').get();
      final tables = await db
          .customSelect(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name='learning_day_log'",
          )
          .get();
      expect(tables, hasLength(1));
    });

    test('fresh database reports schema version 10', () async {
      await db.customSelect('SELECT 1').get();
      final version = await db
          .customSelect('PRAGMA user_version')
          .map((r) => r.read<int>('user_version'))
          .getSingle();
      expect(version, 10); // schema v10 is current
    });

    test('can insert and retrieve streak_states row', () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-streak', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db.into(db.streakStates).insert(
            StreakStatesCompanion.insert(
              ownerId: 'owner-streak',
              updatedAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );

      final rows = await db.select(db.streakStates).get();
      expect(rows, hasLength(1));
      expect(rows.first.currentStreakDays, 0);
      expect(rows.first.freezeCount, 0);
    });

    test('learning_day_log unique(owner_id, learning_day) prevents duplicates',
        () async {
      final now = DateTime.now().toUtc();
      await db.customInsert(
        "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
        "VALUES ('owner-day', 'localGuest', ${now.millisecondsSinceEpoch})",
      );

      await db.into(db.learningDayLog).insert(
            LearningDayLogCompanion.insert(
              id: 'day:owner-day:2026-08-04',
              ownerId: 'owner-day',
              learningDay: '2026-08-04',
              firstSessionAtUtcMs: now.millisecondsSinceEpoch,
            ),
          );

      // Second insert with same (owner, day) must be ignored.
      await db.into(db.learningDayLog).insert(
            LearningDayLogCompanion.insert(
              id: 'day:owner-day:2026-08-04',
              ownerId: 'owner-day',
              learningDay: '2026-08-04',
              firstSessionAtUtcMs: now.millisecondsSinceEpoch + 3600000,
            ),
            mode: InsertMode.insertOrIgnore,
          );

      final rows = await db.select(db.learningDayLog).get();
      expect(rows, hasLength(1),
          reason: 'learning_day_log must be idempotent per (owner, day)');
    });
  });
}
