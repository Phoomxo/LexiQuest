import 'package:timezone/timezone.dart' as timezone;

import 'quest_models.dart';

enum QuestPeriodPolicy { legacyDuration, localCalendarV1 }

/// Durable calendar identity. Assignment time remains on the instance itself.
final class QuestPeriod {
  const QuestPeriod({
    required this.policy,
    required this.key,
    required this.startAtUtc,
    this.timezoneId,
    this.endAtUtc,
    this.deadlineAtUtc,
  });

  final QuestPeriodPolicy policy;
  final String key;
  final String? timezoneId;
  final DateTime startAtUtc;
  final DateTime? endAtUtc;
  final DateTime? deadlineAtUtc;

  factory QuestPeriod.forAssignment({
    required QuestDefinition definition,
    required DateTime assignedAtUtc,
    required String timezoneId,
  }) {
    if (!assignedAtUtc.isUtc) {
      throw ArgumentError('quest assignment must be UTC');
    }
    final duration = definition.expiresIn;
    if (duration != null && duration.inMilliseconds <= 0) {
      throw ArgumentError('quest duration must be positive');
    }
    final location = timezone.getLocation(timezoneId);
    final local = timezone.TZDateTime.from(assignedAtUtc, location);
    final recurring =
        definition.type == QuestType.daily ||
        definition.type == QuestType.weekly;
    final offset = definition.type == QuestType.weekly
        ? local.weekday - DateTime.monday
        : 0;
    final start = recurring
        ? timezone.TZDateTime(
            location,
            local.year,
            local.month,
            local.day - offset,
          )
        : assignedAtUtc;
    final end = recurring
        ? timezone.TZDateTime(
            location,
            local.year,
            local.month,
            local.day - offset + (definition.type == QuestType.weekly ? 7 : 1),
          ).toUtc()
        : null;
    final explicitDeadline = duration == null
        ? null
        : safeDeadline(assignedAtUtc, duration);
    final deadline = end == null
        ? explicitDeadline
        : explicitDeadline == null || end.isBefore(explicitDeadline)
        ? end
        : explicitDeadline;
    final date =
        '${start.year.toString().padLeft(4, '0')}-${start.month.toString().padLeft(2, '0')}-${start.day.toString().padLeft(2, '0')}';
    return QuestPeriod(
      policy: QuestPeriodPolicy.localCalendarV1,
      key: recurring ? '${definition.type.name}:$date' : 'once',
      timezoneId: timezoneId,
      startAtUtc: start.toUtc(),
      endAtUtc: end,
      deadlineAtUtc: deadline,
    );
  }

  /// Clamp before addition so legacy duration overflow cannot wrap a deadline.
  static DateTime safeDeadline(DateTime assignedAtUtc, Duration duration) =>
      safeDeadlineMilliseconds(assignedAtUtc, duration.inMilliseconds);

  static DateTime safeDeadlineMilliseconds(DateTime assignedAtUtc, int delta) {
    const maximum = 8640000000000000;
    final assigned = assignedAtUtc.millisecondsSinceEpoch;
    if (delta <= 0) throw ArgumentError('quest duration must be positive');
    return DateTime.fromMillisecondsSinceEpoch(
      delta > maximum - assigned ? maximum : assigned + delta,
      isUtc: true,
    );
  }
}
