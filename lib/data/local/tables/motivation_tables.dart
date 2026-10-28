import 'package:drift/drift.dart';
import 'identity_tables.dart';

/// Drift tables for the Motivation domain (streaks, learning-day log).
///
/// Schema v9 — added in Phase 1 D7.2.
///
/// Two tables:
///   - [StreakStates]    — one row per owner, mutable streak counters
///   - [LearningDayLog] — immutable append-only log; one row per
///                         (owner, local learning-day string)

// ─── StreakStates ────────────────────────────────────────────────────────────

/// Current streak state for a learner.
///
/// One row per owner.  Updated by [StreakUseCases.recordLearningDay] after
/// each session.  The [TimezonePolicy] determines the learning-day boundary.
class StreakStates extends Table {
  TextColumn get ownerId => text().references(LocalOwners, #id)();

  /// Number of consecutive learning days including today (or the last
  /// active day).  Reset to 0 if the learner missed a full day without
  /// using a freeze token.
  IntColumn get currentStreakDays => integer().withDefault(const Constant(0))();

  /// All-time maximum streak — never decremented.
  IntColumn get longestStreakDays => integer().withDefault(const Constant(0))();

  /// Remaining freeze tokens.  Incremented by daily/milestone rewards;
  /// decremented by [StreakUseCases.useFreezeToken].
  IntColumn get freezeCount => integer().withDefault(const Constant(0))();

  /// UTC timestamp of the most recent session that counted toward the
  /// streak.  Null before the first session.
  IntColumn get lastLearnedAtUtcMs => integer().nullable()();

  IntColumn get updatedAtUtcMs => integer()();

  /// PK is the owner — one streak row per learner.
  @override
  Set<Column> get primaryKey => {ownerId};
}

// ─── LearningDayLog ──────────────────────────────────────────────────────────

/// Immutable record of every learning day the owner was active.
///
/// Row ID is deterministic: `'day:{ownerId}:{learningDay}'`.
/// Inserting twice for the same day is a no-op (insertOrIgnore).
class LearningDayLog extends Table {
  /// Deterministic ID: `day:{ownerId}:{learningDay}`.
  TextColumn get id => text()();

  TextColumn get ownerId => text().references(LocalOwners, #id)();

  /// ISO-8601 date in the learner's local timezone: `'YYYY-MM-DD'`.
  /// Computed by [TimezonePolicy.getLearningDay].
  TextColumn get learningDay => text()();

  /// UTC timestamp of the first session on this day.
  IntColumn get firstSessionAtUtcMs => integer()();

  @override
  Set<Column> get primaryKey => {id};

  /// Prevents two rows for the same owner+day from being inserted.
  @override
  List<Set<Column>> get uniqueKeys => [
    {ownerId, learningDay},
  ];
}
