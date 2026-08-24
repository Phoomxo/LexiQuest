/// Timezone-aware policy for streak, quest, and learning-day calculations.
///
/// All public methods accept UTC [DateTime]s and a IANA timezone identifier
/// (e.g. `'Asia/Bangkok'`, `'America/New_York'`).  They never read the device
/// clock or the device timezone — callers supply both, making every calculation
/// deterministic and unit-testable.
///
/// Call [initializeTimeZones] from `timezone/data/latest_all.dart` once at
/// app start-up before invoking any method here.
library;

import 'package:timezone/timezone.dart';

/// Policy namespace — not meant to be instantiated.
abstract final class TimezonePolicy {
  /// Schema version. Increment when the calculation logic changes so that
  /// cached streak values can be invalidated if necessary.
  static const int version = 1;

  /// Returns the learner's *learning day* as a local [DateTime] with no
  /// time component (year/month/day only) for the given [utcNow] in the
  /// supplied IANA [timezoneId].
  ///
  /// Example — Bangkok is UTC+7:
  /// ```
  /// getLearningDay(DateTime.utc(2026, 8, 4, 16, 59), 'Asia/Bangkok')
  ///   → DateTime(2026, 8, 4)   // 23:59 Bangkok, still Mon Aug 4
  /// getLearningDay(DateTime.utc(2026, 8, 4, 17, 1), 'Asia/Bangkok')
  ///   → DateTime(2026, 8, 5)   // 00:01 Bangkok, already Tue Aug 5
  /// ```
  static DateTime getLearningDay(DateTime utcNow, String timezoneId) {
    final tz = getLocation(timezoneId);
    final local = TZDateTime.from(utcNow, tz);
    return DateTime(local.year, local.month, local.day);
  }

  /// Returns `true` when [utc1] and [utc2] map to the same calendar date
  /// in [timezoneId].
  ///
  /// Use this instead of comparing raw UTC dates when evaluating whether a
  /// streak should be extended — a learner who studies at 23:59 and then
  /// again at 00:01 the next UTC day has studied on *two* days in their
  /// local timezone.
  static bool isSameLearningDay(
    DateTime utc1,
    DateTime utc2,
    String timezoneId,
  ) {
    final day1 = getLearningDay(utc1, timezoneId);
    final day2 = getLearningDay(utc2, timezoneId);
    return day1.isAtSameMomentAs(day2);
  }

  /// Returns the UTC instant at which the learner's *next* learning day
  /// begins (i.e. midnight at the start of tomorrow in [timezoneId]).
  ///
  /// Useful for scheduling streak-expiry timers.
  static DateTime getNextDayBoundary(DateTime utcNow, String timezoneId) {
    final tz = getLocation(timezoneId);
    final local = TZDateTime.from(utcNow, tz);
    var nextLocalMidnight = TZDateTime(
      tz,
      local.year,
      local.month,
      local.day + 1,
    );
    var boundary = nextLocalMidnight.toUtc();
    while (!boundary.isAfter(utcNow)) {
      nextLocalMidnight = TZDateTime(
        tz,
        nextLocalMidnight.year,
        nextLocalMidnight.month,
        nextLocalMidnight.day + 1,
      );
      boundary = nextLocalMidnight.toUtc();
    }
    return boundary;
  }
}
