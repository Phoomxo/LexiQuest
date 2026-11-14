import 'package:drift/drift.dart';
import 'identity_tables.dart';

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

/// A learner-selected calendar rule and its interval of authority.
class OwnerCalendarEpochs extends Table {
  TextColumn get ruleId => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get originOwnerId => text()();
  IntColumn get effectiveUtcUs => integer()();
  IntColumn get expiresUtcUs => integer().nullable()();
  TextColumn get ianaId => text()();
  TextColumn get tzdbRevision => text()();
  BoolColumn get isSelected => boolean()();

  @override
  Set<Column> get primaryKey => {ruleId};

  @override
  List<Set<Column>> get uniqueKeys => [
    {originOwnerId, effectiveUtcUs},
  ];

  @override
  List<String> get customConstraints => [
    'CHECK (expires_utc_us IS NULL OR expires_utc_us > effective_utc_us)',
  ];
}

/// Raw v10 streak state sealed at migration, including any legacy anomalies.
class StreakBaselines extends Table {
  TextColumn get originOwnerId => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  IntColumn get cutoffUtcMs => integer()();
  IntColumn get currentStreakDays => integer()();
  IntColumn get longestStreakDays => integer()();
  IntColumn get freezeCount => integer()();
  IntColumn get lastLearnedAtUtcMs => integer().nullable()();
  IntColumn get updatedAtUtcMs => integer()();
  BoolColumn get controlsContinuity => boolean()();

  @override
  Set<Column> get primaryKey => {originOwnerId};
}

class StreakTokenAdjustments extends Table {
  TextColumn get id => text()();
  TextColumn get ownerId => text().references(LocalOwners, #id)();
  TextColumn get originOwnerId => text()();
  TextColumn get commandId => text()();
  IntColumn get occurredAtUtcMs => integer()();
  TextColumn get kind => text()();
  IntColumn get delta => integer()();
  TextColumn get protectedDay => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {originOwnerId, commandId},
  ];

  @override
  List<String> get customConstraints => [
    "CHECK ((kind = 'grant' AND delta > 0 AND protected_day IS NULL) "
        "OR (kind = 'manualDebit' AND delta = -1 AND protected_day IS NULL) "
        "OR (kind = 'autoProtect' AND delta = -1 AND COALESCE(protected_day, '') <> ''))",
  ];
}
