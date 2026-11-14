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

import 'dart:math' as math;

import 'package:timezone/timezone.dart';

const String bundledTzdbRevision =
    'timezone-0.9.4/latest_all/sha256:'
    '88010336afd9dac1f89c685ed10b0613acf75641d52de868e74503f6b92c6756';

final class OwnerCalendarRule {
  const OwnerCalendarRule({
    required this.ruleId,
    required this.originOwnerId,
    required this.ianaId,
    required this.tzdbRevision,
    required this.effectiveUtcUs,
    this.expiresUtcUs,
  });

  final String ruleId;
  final String originOwnerId;
  final String ianaId;
  final String tzdbRevision;
  final int effectiveUtcUs;
  final int? expiresUtcUs;
}

/// Includes [startUtc] and excludes [endUtc].
final class UtcSegment {
  const UtcSegment._(this.startUtc, this.endUtc);

  final DateTime startUtc;
  final DateTime endUtc;

  bool containsUtc(DateTime utc) {
    if (!utc.isUtc) throw ArgumentError.value(utc, 'utc', 'must be UTC');
    return !utc.isBefore(startUtc) && utc.isBefore(endUtc);
  }
}

/// Civil labels are UTC date ordinals. Clock rollbacks can split a labelled
/// day or week into multiple disjoint UTC segments.
final class LearningCalendarWindow {
  const LearningCalendarWindow._({
    required this.timezoneId,
    required this.offsetSeconds,
    required this.civilDay,
    required this.weekMonday,
    required this.daySegments,
    required this.weekSegments,
  });

  final String timezoneId;
  final int offsetSeconds;
  final DateTime civilDay;
  final DateTime weekMonday;
  final List<UtcSegment> daySegments;
  final List<UtcSegment> weekSegments;
}

/// Policy namespace — not meant to be instantiated.
abstract final class TimezonePolicy {
  /// Schema version. Increment when the calculation logic changes so that
  /// cached streak values can be invalidated if necessary.
  static const int version = 1;

  /// Tests the whole civil date, including returning fragments and epoch bounds.
  static bool hasCivilDay(
    DateTime civilDay,
    String timezoneId, {
    DateTime? epochEffectiveAtUtc,
    DateTime? epochExpiresAtUtc,
  }) {
    if (!civilDay.isUtc ||
        civilDay != DateTime.utc(civilDay.year, civilDay.month, civilDay.day)) {
      throw ArgumentError.value(
        civilDay,
        'civilDay',
        'must be a UTC date ordinal',
      );
    }
    if ((epochEffectiveAtUtc != null && !epochEffectiveAtUtc.isUtc) ||
        (epochExpiresAtUtc != null && !epochExpiresAtUtc.isUtc) ||
        (epochEffectiveAtUtc != null &&
            epochExpiresAtUtc != null &&
            !epochExpiresAtUtc.isAfter(epochEffectiveAtUtc))) {
      throw ArgumentError('Calendar epoch must be a nonempty UTC interval');
    }
    if (!timeZoneDatabase.isInitialized) {
      throw StateError('timezone database is not initialized');
    }
    final location = timeZoneDatabase.locations[timezoneId];
    if (location == null) {
      throw ArgumentError.value(timezoneId, 'timezoneId', 'unknown IANA zone');
    }
    return _civilSegments(
      location,
      civilDay.millisecondsSinceEpoch,
      1,
      epochEffectiveAtUtc: epochEffectiveAtUtc,
      epochExpiresAtUtc: epochExpiresAtUtc,
    ).isNotEmpty;
  }

  /// Captures the UTC segments of the occurrence's day and Monday-based week
  /// from [epochEffectiveAtUtc] until (but excluding) [epochExpiresAtUtc].
  static LearningCalendarWindow captureWindow(
    DateTime occurredAtUtc,
    String timezoneId, {
    DateTime? epochEffectiveAtUtc,
    DateTime? epochExpiresAtUtc,
  }) {
    if (!occurredAtUtc.isUtc) {
      throw ArgumentError.value(occurredAtUtc, 'occurredAtUtc', 'must be UTC');
    }
    if (epochEffectiveAtUtc != null &&
        (!epochEffectiveAtUtc.isUtc ||
            epochEffectiveAtUtc.isAfter(occurredAtUtc))) {
      throw ArgumentError.value(
        epochEffectiveAtUtc,
        'epochEffectiveAtUtc',
        'must be UTC and at or before the occurrence',
      );
    }
    if (epochExpiresAtUtc != null &&
        (!epochExpiresAtUtc.isUtc ||
            !epochExpiresAtUtc.isAfter(occurredAtUtc))) {
      throw ArgumentError.value(
        epochExpiresAtUtc,
        'epochExpiresAtUtc',
        'must be UTC and after the occurrence',
      );
    }
    if (!timeZoneDatabase.isInitialized) {
      throw StateError('timezone database is not initialized');
    }
    final location = timeZoneDatabase.locations[timezoneId];
    if (location == null) {
      throw ArgumentError.value(timezoneId, 'timezoneId', 'unknown IANA zone');
    }

    // Floor to the containing tzdb millisecond, including before the Unix epoch.
    final occurrenceMs =
        (occurredAtUtc.microsecondsSinceEpoch - occurredAtUtc.microsecond) ~/
        Duration.microsecondsPerMillisecond;
    final offset = location.timeZone(occurrenceMs).offset;
    final wallMs = occurrenceMs + offset;
    RangeError.checkValueInInterval(wallMs, minTime, maxTime, 'civil time');
    final wall = DateTime.fromMillisecondsSinceEpoch(wallMs, isUtc: true);
    final day = DateTime.utc(wall.year, wall.month, wall.day);
    final dayMs = day.millisecondsSinceEpoch;
    final weekMs =
        dayMs - (day.weekday - DateTime.monday) * Duration.millisecondsPerDay;
    List<UtcSegment> segments(int start, int count) => _civilSegments(
      location,
      start,
      count,
      epochEffectiveAtUtc: epochEffectiveAtUtc,
      epochExpiresAtUtc: epochExpiresAtUtc,
    );
    final days = segments(dayMs, 1);
    final weeks = segments(weekMs, 7);
    return LearningCalendarWindow._(
      timezoneId: timezoneId,
      offsetSeconds: offset ~/ Duration.millisecondsPerSecond,
      civilDay: day,
      weekMonday: DateTime.fromMillisecondsSinceEpoch(weekMs, isUtc: true),
      daySegments: days,
      weekSegments: weeks,
    );
  }

  static List<UtcSegment> _civilSegments(
    Location location,
    int civilStart,
    int days, {
    DateTime? epochEffectiveAtUtc,
    DateTime? epochExpiresAtUtc,
  }) {
    var minOffset = location.zones.first.offset;
    var maxOffset = minOffset;
    for (final zone in location.zones) {
      minOffset = math.min(minOffset, zone.offset);
      maxOffset = math.max(maxOffset, zone.offset);
    }
    final civilEnd = civilStart + days * Duration.millisecondsPerDay;
    var cursor = civilStart - maxOffset;
    final limit = civilEnd - minOffset;
    if (civilStart < minTime ||
        civilEnd > maxTime ||
        cursor < minTime ||
        limit > maxTime) {
      throw RangeError('Calendar period exceeds the supported date range');
    }
    final result = <UtcSegment>[];
    while (cursor < limit) {
      final interval = location.lookupTimeZone(cursor);
      final next = math.min(interval.end, limit);
      final first = math.max(cursor, civilStart - interval.timeZone.offset);
      final last = math.min(next, civilEnd - interval.timeZone.offset);
      if (first < last) {
        var start = DateTime.fromMillisecondsSinceEpoch(first, isUtc: true);
        var end = DateTime.fromMillisecondsSinceEpoch(last, isUtc: true);
        if (epochEffectiveAtUtc != null &&
            start.isBefore(epochEffectiveAtUtc)) {
          start = epochEffectiveAtUtc;
        }
        if (epochExpiresAtUtc != null && end.isAfter(epochExpiresAtUtc)) {
          end = epochExpiresAtUtc;
        }
        if (start.isBefore(end)) {
          if (result.isNotEmpty && result.last.endUtc.isAtSameMomentAs(start)) {
            start = result.removeLast().startUtc;
          }
          result.add(UtcSegment._(start, end));
        }
      }
      cursor = next;
    }
    return List.unmodifiable(result);
  }

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
    final today = getLearningDay(utcNow, timezoneId);
    final tomorrow = today.add(const Duration(days: 1));
    final tz = getLocation(timezoneId);
    return TZDateTime(tz, tomorrow.year, tomorrow.month, tomorrow.day).toUtc();
  }
}
