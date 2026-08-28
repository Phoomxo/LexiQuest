enum ReminderPermissionState { unknown, denied, granted }

final class ReminderPlatformEntry {
  const ReminderPlatformEntry({
    required this.platformId,
    required this.ownerId,
    required this.reminderId,
  });

  final int platformId;
  final String ownerId;
  final String reminderId;

  @override
  bool operator ==(Object other) =>
      other is ReminderPlatformEntry &&
      platformId == other.platformId &&
      ownerId == other.ownerId &&
      reminderId == other.reminderId;

  @override
  int get hashCode => Object.hash(platformId, ownerId, reminderId);
}

final class ReminderScheduleRequest {
  const ReminderScheduleRequest({
    required this.platformId,
    required this.ownerId,
    required this.reminderId,
    required this.scheduledAtUtc,
    required this.timezoneId,
    required this.title,
    required this.body,
  });

  final int platformId;
  final String ownerId;
  final String reminderId;
  final DateTime scheduledAtUtc;
  final String timezoneId;
  final String title;
  final String body;
}

abstract interface class ReminderScheduler {
  Future<void> initialize();
  Future<bool> isSupported();
  Future<ReminderPermissionState> permissionState();
  Future<ReminderPermissionState> requestPermission();
  Future<List<ReminderPlatformEntry>> pendingEntries();
  Future<void> schedule(ReminderScheduleRequest request);
  Future<void> cancel(int platformId);
}

final class UnsupportedReminderScheduler implements ReminderScheduler {
  const UnsupportedReminderScheduler();

  @override
  Future<void> initialize() async {}

  @override
  Future<bool> isSupported() async => false;

  @override
  Future<ReminderPermissionState> permissionState() async =>
      ReminderPermissionState.unknown;

  @override
  Future<ReminderPermissionState> requestPermission() async =>
      ReminderPermissionState.unknown;

  @override
  Future<List<ReminderPlatformEntry>> pendingEntries() async => const [];

  @override
  Future<void> schedule(ReminderScheduleRequest request) async {}

  @override
  Future<void> cancel(int platformId) async {}
}

int studyReminderPlatformId(String ownerId, String reminderId) {
  const offset = 0x811c9dc5;
  const prime = 0x01000193;
  var hash = offset;
  for (final byte in '$ownerId\u001f$reminderId'.codeUnits) {
    hash ^= byte;
    hash = (hash * prime) & 0xffffffff;
  }
  final positive = hash & 0x7fffffff;
  return positive == 0 ? 1 : positive;
}
