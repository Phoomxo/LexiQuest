import 'package:drift/native.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/motivation/application/streak_use_cases.dart';
import 'package:vocab_learning_app/features/motivation/data/drift_streak_repository.dart';
import 'package:vocab_learning_app/features/motivation/domain/streak_policy.dart';

// ── Fake owner ────────────────────────────────────────────────────────────────

class _FakeOwners implements LocalOwnerRepository {
  final LocalOwner _owner;
  _FakeOwners(this._owner);
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => _owner;
  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String uid) async =>
      _owner;
}

// ── Tests ─────────────────────────────────────────────────────────────────────

void main() {
  setUpAll(tz.initializeTimeZones);

  late db.AppDatabase database;
  late StreakUseCases useCases;
  late LocalOwner owner;
  late DateTime _clock;

  const _tz = 'Asia/Bangkok';

  setUp(() async {
    _clock = DateTime.utc(
      2026,
      8,
      4,
      10,
      0,
    ); // Mon 04 Aug 2026 10:00 UTC = 17:00 BKK
    database = db.AppDatabase(NativeDatabase.memory());
    owner = LocalOwner(
      id: 'owner-streak',
      createdAtUtc: DateTime.utc(2026, 8, 4),
    );

    await database.customInsert(
      "INSERT INTO local_owners(id, account_state, created_at_utc_ms) "
      "VALUES ('owner-streak', 'localGuest', 1722758400000)",
    );

    useCases = StreakUseCases(
      repository: DriftStreakRepository(database),
      owners: _FakeOwners(owner),
      nowUtc: () => _clock,
      timezoneId: _tz,
    );
  });

  tearDown(() async => database.close());

  group('StreakUseCases — D7.2', () {
    // ── First session ────────────────────────────────────────────────────────

    test('first session starts streak at 1', () async {
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.started);
      expect(update.after.currentStreakDays, 1);
    });

    test('getCurrentStreak before any session returns 0', () async {
      final state = await useCases.getCurrentStreak();
      expect(state.currentStreakDays, 0);
    });

    // ── Consecutive days ─────────────────────────────────────────────────────

    test('consecutive day extends streak', () async {
      await useCases.recordLearningDay(); // Day 1
      _clock = DateTime.utc(2026, 8, 5, 10, 0); // Day 2
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.extended);
      expect(update.after.currentStreakDays, 2);
    });

    test('three consecutive days reaches streak of 3', () async {
      await useCases.recordLearningDay(); // Day 1
      _clock = DateTime.utc(2026, 8, 5, 10, 0);
      await useCases.recordLearningDay(); // Day 2
      _clock = DateTime.utc(2026, 8, 6, 10, 0);
      final update = await useCases.recordLearningDay(); // Day 3
      expect(update.after.currentStreakDays, 3);
      expect(update.after.longestStreakDays, 3);
    });

    // ── Same day idempotency ──────────────────────────────────────────────────

    test('calling twice on the same day is a no-op', () async {
      await useCases.recordLearningDay();
      _clock = DateTime.utc(2026, 8, 4, 14, 0); // same day, later
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.sameDay);
      expect(update.after.currentStreakDays, 1);

      // LearningDayLog should have exactly one entry.
      final days = await DriftStreakRepository(
        database,
      ).getLearningDays('owner-streak');
      expect(days, hasLength(1));
    });

    // ── Streak reset ─────────────────────────────────────────────────────────

    test('missing two days resets streak', () async {
      await useCases.recordLearningDay(); // Day 1
      _clock = DateTime.utc(2026, 8, 7, 10, 0); // Day 4 — missed 2+3
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.reset);
      expect(update.after.currentStreakDays, 1);
    });

    // ── Freeze tokens ─────────────────────────────────────────────────────────

    test('freeze token protects streak on one missed day', () async {
      await useCases.recordLearningDay(); // Day 1
      await useCases.grantFreezeTokens(1);

      _clock = DateTime.utc(2026, 8, 6, 10, 0); // Day 3 — skipped day 2
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.froze);
      expect(update.after.currentStreakDays, 1); // streak preserved
      expect(update.after.freezeCount, 0); // token consumed
    });

    test('useFreezeToken returns false when no tokens', () async {
      final used = await useCases.useFreezeToken();
      expect(used, isFalse);
    });

    test('useFreezeToken returns true and decrements count', () async {
      await useCases.grantFreezeTokens(2);
      final used = await useCases.useFreezeToken();
      expect(used, isTrue);
      final state = await useCases.getCurrentStreak();
      expect(state.freezeCount, 1);
    });

    // ── Longest streak ────────────────────────────────────────────────────────

    test('longestStreakDays tracks all-time high', () async {
      // Build streak of 3.
      await useCases.recordLearningDay();
      _clock = DateTime.utc(2026, 8, 5, 10, 0);
      await useCases.recordLearningDay();
      _clock = DateTime.utc(2026, 8, 6, 10, 0);
      await useCases.recordLearningDay();

      // Break streak.
      _clock = DateTime.utc(2026, 8, 9, 10, 0);
      await useCases.recordLearningDay();

      final state = await useCases.getCurrentStreak();
      expect(state.currentStreakDays, 1);
      expect(
        state.longestStreakDays,
        3,
        reason: 'all-time best never decreases',
      );
    });
  });
}
