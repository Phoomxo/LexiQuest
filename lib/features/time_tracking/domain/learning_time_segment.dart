import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

enum LearningTimeCaptureSource { automaticLesson, focusTimer }

final class LearningTimeZoneContext {
  const LearningTimeZoneContext({
    required this.timezoneId,
    required this.utcOffsetMinutes,
  });

  final String timezoneId;
  final int utcOffsetMinutes;
}

final class LearningTimeSegment {
  static const Duration maximumActiveDuration = Duration(minutes: 5);

  factory LearningTimeSegment({
    required String sessionId,
    required Duration activeStartOffset,
    required Duration activeDuration,
    required DateTime startedAtUtc,
    required DateTime endedAtUtc,
    required LearningTimeZoneContext timezone,
    required LearningTimeCaptureSource captureSource,
  }) {
    final canonicalSessionId = _canonicalText(
      sessionId,
      'sessionId',
      maximumLength: 256,
    );
    final activeStartOffsetMs = activeStartOffset.inMilliseconds;
    final activeDurationMs = activeDuration.inMilliseconds;
    if (activeStartOffset.isNegative || activeStartOffsetMs < 0) {
      throw ArgumentError.value(
        activeStartOffset,
        'activeStartOffset',
        'must be nonnegative',
      );
    }
    if (activeDuration <= Duration.zero || activeDurationMs <= 0) {
      throw ArgumentError.value(
        activeDuration,
        'activeDuration',
        'must be at least one millisecond',
      );
    }
    if (activeDuration > maximumActiveDuration) {
      throw ArgumentError.value(
        activeDuration,
        'activeDuration',
        'must not exceed five minutes',
      );
    }
    final canonicalStartedAt = _canonicalUtc(startedAtUtc, 'startedAtUtc');
    final canonicalEndedAt = _canonicalUtc(endedAtUtc, 'endedAtUtc');
    final canonicalTimezoneId = _canonicalText(
      timezone.timezoneId,
      'timezone.timezoneId',
      maximumLength: 128,
    );
    requireCanonicalTimezoneContext(
      timezoneId: canonicalTimezoneId,
      utcOffsetMinutes: timezone.utcOffsetMinutes,
      occurredAtUtcMs: canonicalStartedAt.millisecondsSinceEpoch,
    );
    return LearningTimeSegment._(
      id: canonicalId(
        sessionId: canonicalSessionId,
        activeStartOffsetMs: activeStartOffsetMs,
        captureSource: captureSource,
      ),
      sessionId: canonicalSessionId,
      activeStartOffset: Duration(milliseconds: activeStartOffsetMs),
      activeDuration: Duration(milliseconds: activeDurationMs),
      startedAtUtc: canonicalStartedAt,
      endedAtUtc: canonicalEndedAt,
      timezone: LearningTimeZoneContext(
        timezoneId: canonicalTimezoneId,
        utcOffsetMinutes: timezone.utcOffsetMinutes,
      ),
      captureSource: captureSource,
    );
  }

  const LearningTimeSegment._({
    required this.id,
    required this.sessionId,
    required this.activeStartOffset,
    required this.activeDuration,
    required this.startedAtUtc,
    required this.endedAtUtc,
    required this.timezone,
    required this.captureSource,
  });

  final String id;
  final String sessionId;
  final Duration activeStartOffset;
  final Duration activeDuration;
  final DateTime startedAtUtc;
  final DateTime endedAtUtc;
  final LearningTimeZoneContext timezone;
  final LearningTimeCaptureSource captureSource;

  static String canonicalId({
    required String sessionId,
    required int activeStartOffsetMs,
    required LearningTimeCaptureSource captureSource,
  }) {
    final identity = 'v1|$sessionId|$activeStartOffsetMs|${captureSource.name}';
    return 'learning-time-segment:${sha256.convert(utf8.encode(identity))}';
  }

  static String canonicalOperationId(String segmentId) =>
      'learning-time-operation:'
      '${sha256.convert(utf8.encode('v1|$segmentId'))}';

  static void requireCanonicalTimezoneContext({
    required String timezoneId,
    required int utcOffsetMinutes,
    required int occurredAtUtcMs,
  }) {
    if (!_timezoneId.hasMatch(timezoneId)) {
      throw ArgumentError.value(
        timezoneId,
        'timezoneId',
        'must be a canonical IANA timezone identifier',
      );
    }
    if (utcOffsetMinutes < -840 || utcOffsetMinutes > 840) {
      throw ArgumentError.value(
        utcOffsetMinutes,
        'utcOffsetMinutes',
        'must be between -840 and 840',
      );
    }
    if (occurredAtUtcMs < 0) {
      throw ArgumentError.value(
        occurredAtUtcMs,
        'occurredAtUtcMs',
        'must be nonnegative UTC',
      );
    }
    _initializeTimezonesOnce();
    late final tz.Location location;
    try {
      location = tz.getLocation(timezoneId);
    } on Object {
      throw ArgumentError.value(
        timezoneId,
        'timezoneId',
        'must identify a bundled IANA timezone',
      );
    }
    final historicalOffset = tz.TZDateTime.fromMillisecondsSinceEpoch(
      location,
      occurredAtUtcMs,
    ).timeZoneOffset.inMinutes;
    if (historicalOffset != utcOffsetMinutes) {
      throw ArgumentError.value(
        utcOffsetMinutes,
        'utcOffsetMinutes',
        'must match the timezone offset at occurredAtUtcMs',
      );
    }
  }

  @override
  bool operator ==(Object other) =>
      other is LearningTimeSegment &&
      other.id == id &&
      other.sessionId == sessionId &&
      other.activeStartOffset == activeStartOffset &&
      other.activeDuration == activeDuration &&
      other.startedAtUtc == startedAtUtc &&
      other.endedAtUtc == endedAtUtc &&
      other.timezone.timezoneId == timezone.timezoneId &&
      other.timezone.utcOffsetMinutes == timezone.utcOffsetMinutes &&
      other.captureSource == captureSource;

  @override
  int get hashCode => Object.hash(
    id,
    sessionId,
    activeStartOffset,
    activeDuration,
    startedAtUtc,
    endedAtUtc,
    timezone.timezoneId,
    timezone.utcOffsetMinutes,
    captureSource,
  );
}

final RegExp _timezoneId = RegExp(
  r'^(UTC|[A-Za-z][A-Za-z0-9._+\-]{0,63}/'
  r'[A-Za-z][A-Za-z0-9._+\-]{0,63}'
  r'(/[A-Za-z][A-Za-z0-9._+\-]{0,63})?)$',
);
bool _timezonesInitialized = false;

void _initializeTimezonesOnce() {
  if (_timezonesInitialized) return;
  timezone_data.initializeTimeZones();
  _timezonesInitialized = true;
}

String _canonicalText(
  String value,
  String field, {
  required int maximumLength,
}) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > maximumLength) {
    throw ArgumentError.value(value, field, 'must be canonical text');
  }
  return value;
}

DateTime _canonicalUtc(DateTime value, String field) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, field, 'must be nonnegative UTC');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  );
}
