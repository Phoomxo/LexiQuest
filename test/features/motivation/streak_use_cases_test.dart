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
  late DateTime clock;

  const timezoneId = 'Asia/Bangkok';

  setUp(() async {
    clock = DateTime.utc(
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
      nowUtc: () => clock,
      timezoneId: timezoneId,
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
      clock = DateTime.utc(2026, 8, 5, 10, 0); // Day 2
      final update = await useCases.recordLearningDay();
      expect(update.outcome, StreakOutcome.extended);
      expect(update.after.currentStreakDays, 2);
    });

    test('three consecutive days reaches streak of 3', () async {
      await useCases.recordLearningDay(); // Day 1
      clock = DateTime.utc(2026, 8, 5, 10, 0);
      await useCases.recordLearningDay(); // Day 2
      clock = DateTime.utc(2026, 8, 6, 10, 0);
      final update = await useCases.recordLearningDay(); // Day 3
      expect(update.after.currentStreakDays, 3);
      expect(update.after.longestStreakDays, 3);
    });

    // ── Same day idempotency ──────────────────────────────────────────────────

    test('calling twice on the same day is a no-op', () async {
      await useCases.recordLearningDay();
      clock = DateTime.utc(2026, 8, 4, 14, 0); // same day, later
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

    test(
      'a longer gap begins a gentle recovery and retains the best',
      () async {
        await useCases.recordLearningDay(); // Day 1
        clock = DateTime.utc(2026, 8, 7, 10, 0); // Day 4 — missed 2+3
        final update = await useCases.recordLearningDay();
        expect(update.outcome, StreakOutcome.recovered);
        expect(update.after.currentStreakDays, 1);
        expect(update.after.longestStreakDays, 1);
        expect(update.reaction.title, 'Welcome back');
        expect(update.reaction.message, isNot(contains('lost')));
        expect(update.reaction.message, isNot(contains('broken')));
      },
    );

    // ── Freeze tokens ─────────────────────────────────────────────────────────

    test('freeze token protects streak on one missed day', () async {
      await useCases.recordLearningDay(); // Day 1
      await useCases.grantFreezeTokens(1);

      clock = DateTime.utc(2026, 8, 6, 10, 0); // Day 3 — skipped day 2
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

    test('freeze inventory is bounded and rejects invalid grants', () async {
      await useCases.grantFreezeTokens(StreakPolicy.maxFreezeInventory);

      await expectLater(useCases.grantFreezeTokens(1), throwsRangeError);
      await expectLater(useCases.grantFreezeTokens(0), throwsRangeError);

      final state = await useCases.getCurrentStreak();
      expect(state.freezeCount, StreakPolicy.maxFreezeInventory);
    });

    test('grandfathered freeze surplus stays visible and consumable', () async {
      await DriftStreakRepository(database).save(
        StreakState(
          ownerId: owner.id,
          currentStreakDays: 2,
          longestStreakDays: 4,
          freezeCount: 5,
          lastLearnedAtUtcMs: clock.millisecondsSinceEpoch,
          updatedAtUtcMs: clock.millisecondsSinceEpoch,
        ),
      );

      expect((await useCases.getGentleStreak()).freezeCount, 5);
      await expectLater(useCases.grantFreezeTokens(1), throwsRangeError);
      expect((await useCases.getCurrentStreak()).freezeCount, 5);

      expect(await useCases.useFreezeToken(), isTrue);
      expect((await useCases.getGentleStreak()).freezeCount, 4);
    });

    test('policy receipt pins exact owner day and version', () async {
      final update = await useCases.recordLearningDay();

      expect(update.receipt.ownerId, owner.id);
      expect(update.receipt.learningDay, '2026-08-04');
      expect(update.receipt.policyVersion, StreakPolicy.version);
      expect(
        update.receipt.receiptId,
        'gentle-streak:${owner.id}:2026-08-04:v${StreakPolicy.version}',
      );
    });

    test('future event fails closed without a learning day write', () async {
      await expectLater(
        useCases.recordLearningDay(
          occurredAtUtc: clock.add(const Duration(seconds: 1)),
        ),
        throwsArgumentError,
      );

      expect(
        await DriftStreakRepository(database).getLearningDays(owner.id),
        isEmpty,
      );
      expect((await useCases.getCurrentStreak()).currentStreakDays, 0);
    });

    test('clock rollback fails closed and retains durable state', () async {
      await useCases.recordLearningDay();
      clock = clock.add(const Duration(hours: 4));

      await expectLater(
        useCases.recordLearningDay(
          occurredAtUtc: DateTime.utc(2026, 8, 4, 9, 59, 59),
        ),
        throwsStateError,
      );

      final state = await useCases.getCurrentStreak();
      expect(state.currentStreakDays, 1);
      expect(
        state.lastLearnedAtUtcMs,
        DateTime.utc(2026, 8, 4, 10).millisecondsSinceEpoch,
      );
      expect(await DriftStreakRepository(database).getLearningDays(owner.id), [
        '2026-08-04',
      ]);
    });

    test('same instant under a timezone change remains the same day', () async {
      await useCases.recordLearningDay();
      final shifted = StreakUseCases(
        repository: DriftStreakRepository(database),
        owners: _FakeOwners(owner),
        nowUtc: () => clock,
        timezoneId: 'Pacific/Pago_Pago',
      );

      final update = await shifted.recordLearningDay(occurredAtUtc: clock);

      expect(update.outcome, StreakOutcome.sameDay);
      expect(update.after.currentStreakDays, 1);
      expect(
        update.receipt.learningDay,
        '2026-08-04',
        reason: 'an exact replay keeps the durable day pinned across zones',
      );
      expect(await DriftStreakRepository(database).getLearningDays(owner.id), [
        '2026-08-04',
      ]);
    });

    test(
      'DST transition counts consecutive local dates exactly once',
      () async {
        final newYork = StreakUseCases(
          repository: DriftStreakRepository(database),
          owners: _FakeOwners(owner),
          nowUtc: () => clock,
          timezoneId: 'America/New_York',
        );
        clock = DateTime.utc(2026, 3, 7, 12);
        await newYork.recordLearningDay();
        clock = DateTime.utc(2026, 3, 8, 11);

        final update = await newYork.recordLearningDay();

        expect(update.outcome, StreakOutcome.extended);
        expect(update.after.currentStreakDays, 2);
      },
    );

    test(
      'gentle status exposes grace and recovery without mutating state',
      () async {
        await useCases.recordLearningDay();
        clock = DateTime.utc(2026, 8, 5, 10);
        final grace = await useCases.getGentleStreak();
        clock = DateTime.utc(2026, 8, 7, 10);
        final recovery = await useCases.getGentleStreak();

        expect(grace.phase, GentleStreakPhase.grace);
        expect(grace.recoveryPromptVisible, isFalse);
        expect(recovery.phase, GentleStreakPhase.recovery);
        expect(recovery.recoveryPromptVisible, isTrue);
        expect((await useCases.getCurrentStreak()).currentStreakDays, 1);
      },
    );

    test('concurrent duplicate learning day advances exactly once', () async {
      await useCases.recordLearningDay();
      clock = DateTime.utc(2026, 8, 5, 10);

      await Future.wait<StreakUpdate>(
        List<Future<StreakUpdate>>.generate(
          12,
          (_) => useCases.recordLearningDay(occurredAtUtc: clock),
        ),
      );

      final state = await useCases.getCurrentStreak();
      expect(state.currentStreakDays, 2);
      expect(
        await DriftStreakRepository(database).getLearningDays(owner.id),
        hasLength(2),
      );
    });

    // ── Longest streak ────────────────────────────────────────────────────────

    test('longestStreakDays tracks all-time high', () async {
      // Build streak of 3.
      await useCases.recordLearningDay();
      clock = DateTime.utc(2026, 8, 5, 10, 0);
      await useCases.recordLearningDay();
      clock = DateTime.utc(2026, 8, 6, 10, 0);
      await useCases.recordLearningDay();

      // Break streak.
      clock = DateTime.utc(2026, 8, 9, 10, 0);
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
