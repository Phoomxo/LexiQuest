import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as tz;

void ensureStudyTimeZones() {
  if (tz.timeZoneDatabase.locations.isEmpty) {
    timezone_data.initializeTimeZones();
  }
}

/// Resolves wall-clock fields; a gap returns none and a fold returns both.
/// The caller must explicitly choose a fold candidate before saving.
List<DateTime> resolveLocalStudyDateTime(DateTime wall, String timezoneId) {
  ensureStudyTimeZones();
  final location = tz.getLocation(timezoneId);
  final clock = DateTime.utc(
    wall.year,
    wall.month,
    wall.day,
    wall.hour,
    wall.minute,
  );
  final candidates = <DateTime>{};
  // All offsets in this location include historical/non-hour transitions.
  for (final offset in location.zones.map((zone) => zone.offset).toSet()) {
    final utc = clock.subtract(offset);
    final local = tz.TZDateTime.from(utc, location);
    if (local.year == wall.year &&
        local.month == wall.month &&
        local.day == wall.day &&
        local.hour == wall.hour &&
        local.minute == wall.minute &&
        local.second == 0) {
      candidates.add(utc);
    }
  }
  return candidates.toList()..sort();
}

tz.TZDateTime studyLocalDateTime(DateTime instantUtc, String timezoneId) {
  ensureStudyTimeZones();
  if (!instantUtc.isUtc) {
    throw ArgumentError.value(instantUtc, 'instantUtc', 'must be UTC');
  }
  return tz.TZDateTime.from(instantUtc, tz.getLocation(timezoneId));
}

String studyTimezoneLabel(String timezoneId) => switch (timezoneId) {
  'Asia/Bangkok' => 'ประเทศไทย',
  'Asia/Singapore' => 'สิงคโปร์',
  'Asia/Tokyo' => 'ญี่ปุ่น',
  'America/New_York' => 'นิวยอร์ก',
  'Europe/London' => 'ลอนดอน',
  'UTC' => 'เวลาสากล',
  _ => timezoneId.replaceAll('_', ' '),
};

String formatStudyUtcOffset(Duration offset) {
  final minutes = offset.inMinutes;
  return 'UTC${minutes < 0 ? '-' : '+'}${formatStudyClockMinutes(minutes.abs())}';
}

String formatStudyClockMinutes(int minutes) =>
    '${(minutes ~/ 60).toString().padLeft(2, '0')}:${(minutes % 60).toString().padLeft(2, '0')}';

String formatStudyCalendarDate(DateTime day) {
  const months = [
    'ม.ค.',
    'ก.พ.',
    'มี.ค.',
    'เม.ย.',
    'พ.ค.',
    'มิ.ย.',
    'ก.ค.',
    'ส.ค.',
    'ก.ย.',
    'ต.ค.',
    'พ.ย.',
    'ธ.ค.',
  ];
  return '${day.day} ${months[day.month - 1]} ${day.year + 543}';
}

String formatLocalStudyDateTime(DateTime instantUtc, String timezoneId) {
  final local = studyLocalDateTime(instantUtc, timezoneId);
  return '${formatStudyCalendarDate(local)} เวลา ${formatStudyClockMinutes(local.hour * 60 + local.minute)}'
      ' · ${studyTimezoneLabel(timezoneId)} (${formatStudyUtcOffset(local.timeZoneOffset)})';
}
