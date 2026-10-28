import 'package:timezone/timezone.dart' as tz;

import '../../time_tracking/domain/learning_time_segment.dart';

enum StudyReminderSourceKind { dueReview, goalDeadline }

final class StudyReminderSource {
  const StudyReminderSource.dueReview()
    : kind = StudyReminderSourceKind.dueReview,
      goalId = null;

  factory StudyReminderSource.goalDeadline(String goalId) =>
      StudyReminderSource._(
        StudyReminderSourceKind.goalDeadline,
        _canonicalText(goalId, 'goalId', maximumLength: 256),
      );

  const StudyReminderSource._(this.kind, this.goalId);

  final StudyReminderSourceKind kind;
  final String? goalId;

  String get stableIdentity => switch (kind) {
    StudyReminderSourceKind.dueReview => 'dueReview',
    StudyReminderSourceKind.goalDeadline => 'goal:$goalId',
  };

  @override
  bool operator ==(Object other) =>
      other is StudyReminderSource &&
      kind == other.kind &&
      goalId == other.goalId;

  @override
  int get hashCode => Object.hash(kind, goalId);
}

final class StudyReminderTimezoneContext {
  const StudyReminderTimezoneContext({
    required this.timezoneId,
    required this.utcOffsetMinutes,
  });

  final String timezoneId;
  final int utcOffsetMinutes;
}

final class ReminderQuietHours {
  const ReminderQuietHours({
    required this.startMinutes,
    required this.endMinutes,
  }) : assert(startMinutes >= 0 && startMinutes < 24 * 60),
       assert(endMinutes >= 0 && endMinutes < 24 * 60);

  final int startMinutes;
  final int endMinutes;

  bool contains(int minuteOfDay) {
    if (startMinutes == endMinutes) return false;
    if (startMinutes < endMinutes) {
      return minuteOfDay >= startMinutes && minuteOfDay < endMinutes;
    }
    return minuteOfDay >= startMinutes || minuteOfDay < endMinutes;
  }

  DateTime shiftOutside(DateTime scheduledAtUtc, String timezoneId) {
    final location = tz.getLocation(timezoneId);
    final local = tz.TZDateTime.from(scheduledAtUtc, location);
    final minute = local.hour * 60 + local.minute;
    if (!contains(minute)) return scheduledAtUtc;

    final crossesMidnight = startMinutes > endMinutes;
    final addDay = crossesMidnight && minute >= startMinutes ? 1 : 0;
    final target = tz.TZDateTime(
      location,
      local.year,
      local.month,
      local.day + addDay,
      endMinutes ~/ 60,
      endMinutes % 60,
    );
    return target.toUtc();
  }
}

final class StudyReminder {
  factory StudyReminder({
    required String id,
    required String ownerId,
    required StudyReminderSource source,
    required DateTime scheduledAtUtc,
    required StudyReminderTimezoneContext timezone,
    ReminderQuietHours? quietHours,
    required bool isEnabled,
    required DateTime createdAtUtc,
    required DateTime updatedAtUtc,
    bool isDeleted = false,
  }) {
    final canonicalId = _canonicalText(id, 'id', maximumLength: 256);
    final canonicalOwner = _canonicalText(
      ownerId,
      'ownerId',
      maximumLength: 256,
    );
    final scheduled = _utc(scheduledAtUtc, 'scheduledAtUtc');
    final created = _utc(createdAtUtc, 'createdAtUtc');
    final updated = _utc(updatedAtUtc, 'updatedAtUtc');
    if (updated.isBefore(created)) {
      throw ArgumentError.value(
        updatedAtUtc,
        'updatedAtUtc',
        'must not precede createdAtUtc',
      );
    }
    if (source.kind == StudyReminderSourceKind.goalDeadline &&
        source.goalId == null) {
      throw ArgumentError.value(source, 'source', 'goal identity is required');
    }
    LearningTimeSegment.requireCanonicalTimezoneContext(
      timezoneId: timezone.timezoneId,
      utcOffsetMinutes: timezone.utcOffsetMinutes,
      occurredAtUtcMs: scheduled.millisecondsSinceEpoch,
    );
    return StudyReminder._(
      id: canonicalId,
      ownerId: canonicalOwner,
      source: source,
      scheduledAtUtc: scheduled,
      timezone: StudyReminderTimezoneContext(
        timezoneId: timezone.timezoneId,
        utcOffsetMinutes: timezone.utcOffsetMinutes,
      ),
      quietHours: quietHours,
      isEnabled: isEnabled && !isDeleted,
      createdAtUtc: created,
      updatedAtUtc: updated,
      isDeleted: isDeleted,
    );
  }

  const StudyReminder._({
    required this.id,
    required this.ownerId,
    required this.source,
    required this.scheduledAtUtc,
    required this.timezone,
    required this.quietHours,
    required this.isEnabled,
    required this.createdAtUtc,
    required this.updatedAtUtc,
    required this.isDeleted,
  });

  final String id;
  final String ownerId;
  final StudyReminderSource source;
  final DateTime scheduledAtUtc;
  final StudyReminderTimezoneContext timezone;
  final ReminderQuietHours? quietHours;
  final bool isEnabled;
  final DateTime createdAtUtc;
  final DateTime updatedAtUtc;
  final bool isDeleted;

  DateTime get effectiveScheduledAtUtc =>
      quietHours?.shiftOutside(scheduledAtUtc, timezone.timezoneId) ??
      scheduledAtUtc;

  StudyReminder rebaseTimezone(
    String timezoneId, {
    required DateTime updatedAtUtc,
  }) {
    final localWall = scheduledAtUtc.add(
      Duration(minutes: timezone.utcOffsetMinutes),
    );
    final location = tz.getLocation(timezoneId);
    final rebased = tz.TZDateTime(
      location,
      localWall.year,
      localWall.month,
      localWall.day,
      localWall.hour,
      localWall.minute,
      localWall.second,
      localWall.millisecond,
      localWall.microsecond,
    );
    return copyWith(
      scheduledAtUtc: rebased.toUtc(),
      timezone: StudyReminderTimezoneContext(
        timezoneId: timezoneId,
        utcOffsetMinutes: rebased.timeZoneOffset.inMinutes,
      ),
      updatedAtUtc: updatedAtUtc,
    );
  }

  StudyReminder copyWith({
    DateTime? scheduledAtUtc,
    StudyReminderTimezoneContext? timezone,
    ReminderQuietHours? quietHours,
    bool? isEnabled,
    DateTime? updatedAtUtc,
    bool? isDeleted,
  }) => StudyReminder(
    id: id,
    ownerId: ownerId,
    source: source,
    scheduledAtUtc: scheduledAtUtc ?? this.scheduledAtUtc,
    timezone: timezone ?? this.timezone,
    quietHours: quietHours ?? this.quietHours,
    isEnabled: isEnabled ?? this.isEnabled,
    createdAtUtc: createdAtUtc,
    updatedAtUtc: updatedAtUtc ?? this.updatedAtUtc,
    isDeleted: isDeleted ?? this.isDeleted,
  );
}

String _canonicalText(
  String value,
  String field, {
  required int maximumLength,
}) {
  if (value.isEmpty ||
      value != value.trim() ||
      value.runes.length > maximumLength ||
      value.contains(RegExp(r'[\u0000-\u001f\u007f-\u009f]'))) {
    throw ArgumentError.value(value, field, 'must be canonical text');
  }
  return value;
}

DateTime _utc(DateTime value, String field) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, field, 'must be nonnegative UTC');
  }
  return DateTime.fromMillisecondsSinceEpoch(
    value.millisecondsSinceEpoch,
    isUtc: true,
  );
}
