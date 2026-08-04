import 'package:timezone/timezone.dart' show getLocation, TZDateTime;

/// Policy for evaluating whether a new session extends, breaks, or
/// maintains a learner's streak.
///
/// All decisions are pure functions of the current [StreakState] and the
/// current UTC clock.  No I/O.
abstract final class StreakPolicy {
  static const int version = 1;

  // ── Core evaluation ───────────────────────────────────────────────────────

  /// Evaluate the streak impact of a new learning event at [nowUtc] in
  /// [timezoneId] and return the updated [StreakState].
  ///
  /// Rules (in priority order):
  /// 1. First ever session → streak starts at 1.
  /// 2. Same learning day as last session → no change (idempotent).
  /// 3. Consecutive day → extend streak by 1.
  /// 4. One day missed + freeze available → use one freeze, keep streak.
  /// 5. Gap of 2+ days (or 1 day missed + no freeze) → streak resets to 1.
  static StreakUpdate evaluate({
    required StreakState current,
    required DateTime nowUtc,
    required String timezoneId,
  }) {
    assert(nowUtc.isUtc, 'nowUtc must be UTC');

    final today = _learningDay(nowUtc, timezoneId);

    // First session ever.
    if (current.lastLearnedAtUtcMs == null) {
      final next = current.copyWith(
        currentStreakDays: 1,
        longestStreakDays: 1,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
      );
      return StreakUpdate(
        before: current,
        after: next,
        outcome: StreakOutcome.started,
        learningDay: today,
      );
    }

    final lastDay = _learningDay(
      DateTime.fromMillisecondsSinceEpoch(
        current.lastLearnedAtUtcMs!,
        isUtc: true,
      ),
      timezoneId,
    );
    final dayDiff = today.difference(lastDay).inDays;

    if (dayDiff == 0) {
      // Same day — idempotent.
      return StreakUpdate(
        before: current,
        after: current,
        outcome: StreakOutcome.sameDay,
        learningDay: today,
      );
    }

    if (dayDiff == 1) {
      // Consecutive day — extend streak.
      final newStreak = current.currentStreakDays + 1;
      final next = current.copyWith(
        currentStreakDays: newStreak,
        longestStreakDays: newStreak > current.longestStreakDays
            ? newStreak
            : current.longestStreakDays,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
      );
      return StreakUpdate(
        before: current,
        after: next,
        outcome: StreakOutcome.extended,
        learningDay: today,
      );
    }

    // dayDiff >= 2 — either freeze or reset.
    if (dayDiff == 2 && current.freezeCount > 0) {
      final next = current.copyWith(
        freezeCount: current.freezeCount - 1,
        lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
        // Streak length unchanged.
      );
      return StreakUpdate(
        before: current,
        after: next,
        outcome: StreakOutcome.froze,
        learningDay: today,
      );
    }

    // Streak broken.
    final next = current.copyWith(
      currentStreakDays: 1,
      lastLearnedAtUtcMs: nowUtc.millisecondsSinceEpoch,
    );
    return StreakUpdate(
      before: current,
      after: next,
      outcome: StreakOutcome.reset,
      learningDay: today,
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// Returns midnight of the local learning day in [timezoneId] as a UTC
  /// [DateTime].
  static DateTime learningDayBoundary(DateTime utcNow, String timezoneId) {
    final tz = getLocation(timezoneId);
    final local = TZDateTime.from(utcNow, tz);
    return DateTime.utc(local.year, local.month, local.day);
  }

  static DateTime _learningDay(DateTime utcNow, String timezoneId) =>
      learningDayBoundary(utcNow, timezoneId);
}

// ─── Value objects ────────────────────────────────────────────────────────────

/// Current persisted streak counters for one owner.
final class StreakState {
  const StreakState({
    required this.ownerId,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.freezeCount,
    required this.lastLearnedAtUtcMs,
    required this.updatedAtUtcMs,
  });

  const StreakState.initial({required String ownerId, required int nowMs})
    : this(
        ownerId: ownerId,
        currentStreakDays: 0,
        longestStreakDays: 0,
        freezeCount: 0,
        lastLearnedAtUtcMs: null,
        updatedAtUtcMs: nowMs,
      );

  final String ownerId;
  final int currentStreakDays;
  final int longestStreakDays;
  final int freezeCount;

  /// `null` before the learner's first session.
  final int? lastLearnedAtUtcMs;
  final int updatedAtUtcMs;

  StreakState copyWith({
    int? currentStreakDays,
    int? longestStreakDays,
    int? freezeCount,
    int? lastLearnedAtUtcMs,
    int? updatedAtUtcMs,
  }) => StreakState(
    ownerId: ownerId,
    currentStreakDays: currentStreakDays ?? this.currentStreakDays,
    longestStreakDays: longestStreakDays ?? this.longestStreakDays,
    freezeCount: freezeCount ?? this.freezeCount,
    lastLearnedAtUtcMs: lastLearnedAtUtcMs ?? this.lastLearnedAtUtcMs,
    updatedAtUtcMs: updatedAtUtcMs ?? this.updatedAtUtcMs,
  );
}

/// The result of a [StreakPolicy.evaluate] call.
final class StreakUpdate {
  const StreakUpdate({
    required this.before,
    required this.after,
    required this.outcome,
    required this.learningDay,
  });

  final StreakState before;
  final StreakState after;
  final StreakOutcome outcome;

  /// UTC midnight of the local learning day that triggered this update.
  final DateTime learningDay;

  bool get changed => outcome != StreakOutcome.sameDay;
}

/// The streak outcome for a single [StreakPolicy.evaluate] call.
enum StreakOutcome {
  /// First ever session — streak started at 1.
  started,

  /// Session on the same learning day as the previous — no change.
  sameDay,

  /// Consecutive day — streak extended by 1.
  extended,

  /// One day missed; freeze token used to protect the streak.
  froze,

  /// Two or more days missed (or missed + no freeze) — streak reset to 1.
  reset,
}
