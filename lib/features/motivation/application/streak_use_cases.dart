import '../../identity/domain/local_owner_repository.dart';
import '../data/drift_streak_repository.dart';
import '../domain/streak_policy.dart';

typedef StreakUtcNow = DateTime Function();

/// Application façade for streak tracking.
///
/// **Responsibilities:**
/// - On each learning session: evaluate the streak impact via [StreakPolicy]
///   and persist both the [StreakState] and a [LearningDayLog] entry.
/// - On demand: return the current [StreakState].
/// - On request: consume a freeze token to protect an at-risk streak.
///
/// All methods are idempotent when called multiple times for the same
/// learning day.
final class StreakUseCases {
  StreakUseCases({
    required this.repository,
    required this.owners,
    required this.nowUtc,
    required this.timezoneId,
  });

  final DriftStreakRepository repository;
  final LocalOwnerRepository owners;
  final StreakUtcNow nowUtc;

  /// IANA timezone identifier, e.g. `'Asia/Bangkok'`.
  final String timezoneId;

  // ISO date formatter: 'YYYY-MM-DD'
  static String _formatDay(DateTime utcMidnight) {
    final y = utcMidnight.year.toString().padLeft(4, '0');
    final m = utcMidnight.month.toString().padLeft(2, '0');
    final d = utcMidnight.day.toString().padLeft(2, '0');
    return '$y-$m-$d';
  }

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Record that the current owner completed a learning session and return
  /// the resulting [StreakUpdate].
  ///
  /// Safe to call multiple times for the same day — [StreakOutcome.sameDay]
  /// is returned for subsequent calls with no DB writes beyond the first.
  Future<StreakUpdate> recordLearningDay({DateTime? occurredAtUtc}) async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now(occurredAtUtc);
    final nowMs = now.millisecondsSinceEpoch;

    final current = await repository.getOrCreate(owner.id, nowMs);
    final update = StreakPolicy.evaluate(
      current: current,
      nowUtc: now,
      timezoneId: timezoneId,
    );

    if (update.changed) {
      final updated = update.after.copyWith(updatedAtUtcMs: nowMs);
      await repository.save(updated);
    }

    // Always record learning day (insertOrIgnore — idempotent).
    final dayLabel = _formatDay(update.learningDay);
    await repository.recordLearningDay(
      ownerId: owner.id,
      learningDay: dayLabel,
      firstSessionAtUtcMs: nowMs,
    );

    return update;
  }

  /// Return the current [StreakState] for the active owner.
  Future<StreakState> getCurrentStreak() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    return repository.getOrCreate(owner.id, now.millisecondsSinceEpoch);
  }

  /// Consume one freeze token to protect the current streak.
  ///
  /// Returns `true` if a token was consumed, `false` if none were available.
  Future<bool> useFreezeToken() async {
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    final current = await repository.getOrCreate(
      owner.id,
      now.millisecondsSinceEpoch,
    );
    if (current.freezeCount <= 0) return false;
    final updated = current.copyWith(
      freezeCount: current.freezeCount - 1,
      updatedAtUtcMs: now.millisecondsSinceEpoch,
    );
    await repository.save(updated);
    return true;
  }

  /// Grant [count] freeze tokens to the active owner (called by reward
  /// pipeline when a daily/weekly quest is completed).
  Future<StreakState> grantFreezeTokens(int count) async {
    assert(count > 0, 'count must be positive');
    final owner = await owners.getOrCreateActiveOwner();
    final now = _now();
    final current = await repository.getOrCreate(
      owner.id,
      now.millisecondsSinceEpoch,
    );
    final updated = current.copyWith(
      freezeCount: current.freezeCount + count,
      updatedAtUtcMs: now.millisecondsSinceEpoch,
    );
    await repository.save(updated);
    return updated;
  }

  // ── Private ────────────────────────────────────────────────────────────────

  DateTime _now([DateTime? value]) {
    final resolved = value ?? nowUtc();
    if (!resolved.isUtc) {
      throw ArgumentError.value(resolved, 'nowUtc', 'must be UTC');
    }
    return resolved;
  }
}
