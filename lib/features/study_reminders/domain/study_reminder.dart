import '../../learning_profile/domain/learning_timezone.dart';

enum StudyReminderFailureCode {
  invalidChoice,
  ownerChanged,
  unavailable,
  staleRevision,
  permissionDenied,
  platformUnavailable,
  requestUnconfirmed,
}

final class StudyReminderException implements Exception {
  const StudyReminderException(this.code);
  final StudyReminderFailureCode code;
}

final class StudyReminderChoice {
  const StudyReminderChoice({
    required this.enabled,
    required this.minuteOfDay,
    required this.timezoneId,
  });
  final bool enabled;
  final int minuteOfDay;
  final String timezoneId;

  void validate() {
    if (minuteOfDay < 0 || minuteOfDay > 1439) {
      throw const StudyReminderException(
        StudyReminderFailureCode.invalidChoice,
      );
    }
    try {
      requireLearningTimezone(timezoneId);
    } on FormatException {
      throw const StudyReminderException(
        StudyReminderFailureCode.invalidChoice,
      );
    }
  }
}

final class StudyReminderSetting {
  const StudyReminderSetting({
    required this.ownerId,
    required this.enabled,
    required this.minuteOfDay,
    required this.timezoneId,
    required this.revision,
    required this.updatedAtUtc,
  });
  const StudyReminderSetting.absent(this.ownerId)
    : enabled = false,
      minuteOfDay = null,
      timezoneId = null,
      revision = 0,
      updatedAtUtc = null;
  final String ownerId;
  final bool enabled;
  final int? minuteOfDay;
  final String? timezoneId;
  final int revision;
  final DateTime? updatedAtUtc;
}

final class StudyReminderPlatformStatus {
  const StudyReminderPlatformStatus({
    required this.supported,
    required this.notificationsAllowed,
  });
  const StudyReminderPlatformStatus.unsupported()
    : supported = false,
      notificationsAllowed = false;
  final bool supported, notificationsAllowed;
}

final class StudyReminderRequestAck {
  const StudyReminderRequestAck({required this.revision, this.nextAtUtc});
  final int revision;
  final DateTime? nextAtUtc;
}

abstract interface class StudyReminderPlatform {
  Future<StudyReminderPlatformStatus> inspect();
  Future<StudyReminderPlatformStatus> requestPermission();
  Future<String> bindScope({
    required String databasePath,
    required String ownerId,
  });
  Future<StudyReminderRequestAck> schedule({
    required String scopeToken,
    required int revision,
  });
  Future<StudyReminderRequestAck> cancel({
    required String scopeToken,
    required int revision,
  });
  Future<void> retire({String? scopeToken});
}
