import 'dart:convert';

const learningProfileMaxRevision = 9007199254740991;

enum LearningOnboardingState { completed, skipped }

enum LearningProfileFailureCode { ownerChanged, conflict, unavailable, invalid }

final class LearningProfileException implements Exception {
  const LearningProfileException(this.code);
  final LearningProfileFailureCode code;

  @override
  String toString() => 'LearningProfileException(${code.name})';
}

final class LearningCivilDate implements Comparable<LearningCivilDate> {
  factory LearningCivilDate(int year, int month, int day) {
    if (year < 1970 ||
        year > 9999 ||
        month < 1 ||
        month > 12 ||
        day < 1 ||
        day > 31) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
    final date = DateTime.utc(year, month, day);
    if (year < 1970 ||
        year > 9999 ||
        date.year != year ||
        date.month != month ||
        date.day != day) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
    return LearningCivilDate._(year, month, day);
  }

  const LearningCivilDate._(this.year, this.month, this.day);

  factory LearningCivilDate.parse(String value) {
    if (!RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
    return LearningCivilDate(
      int.parse(value.substring(0, 4)),
      int.parse(value.substring(5, 7)),
      int.parse(value.substring(8, 10)),
    );
  }

  factory LearningCivilDate.fromDateTime(DateTime value) =>
      LearningCivilDate(value.year, value.month, value.day);

  final int year;
  final int month;
  final int day;

  int daysFrom(LearningCivilDate today) => DateTime.utc(
    year,
    month,
    day,
  ).difference(DateTime.utc(today.year, today.month, today.day)).inDays;

  @override
  int compareTo(LearningCivilDate other) => daysFrom(other).sign;

  @override
  String toString() =>
      '${year.toString().padLeft(4, '0')}-'
      '${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')}';

  @override
  bool operator ==(Object other) =>
      other is LearningCivilDate &&
      year == other.year &&
      month == other.month &&
      day == other.day;

  @override
  int get hashCode => Object.hash(year, month, day);
}

final class LearningProfileDraft {
  factory LearningProfileDraft({
    required LearningOnboardingState onboardingState,
    String? goalText,
    LearningCivilDate? targetDate,
    int? dailyMinutes,
    List<String> interestCodes = const [],
  }) {
    final goal = goalText?.trim();
    final interests = List<String>.of(interestCodes)..sort();
    if ((goal != null &&
            (goal.runes.length > 120 ||
                RegExp(r'[\x00-\x1f\x7f]').hasMatch(goal))) ||
        (dailyMinutes != null && (dailyMinutes < 1 || dailyMinutes > 180)) ||
        interests.length > 8 ||
        interests.toSet().length != interests.length ||
        interests.any(
          (code) => !RegExp(r'^[a-z][a-z0-9_-]{0,39}$').hasMatch(code),
        )) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
    return LearningProfileDraft._(
      onboardingState: onboardingState,
      goalText: goal == null || goal.isEmpty ? null : goal,
      targetDate: targetDate,
      dailyMinutes: dailyMinutes,
      interestCodes: List.unmodifiable(interests),
    );
  }

  const LearningProfileDraft._({
    required this.onboardingState,
    required this.goalText,
    required this.targetDate,
    required this.dailyMinutes,
    required this.interestCodes,
  });

  final LearningOnboardingState onboardingState;
  final String? goalText;
  final LearningCivilDate? targetDate;
  final int? dailyMinutes;
  final List<String> interestCodes;

  String get interestCodesJson =>
      jsonEncode({'schemaVersion': 1, 'codes': interestCodes});

  bool sameFacts(LearningProfileDraft other) =>
      onboardingState == other.onboardingState &&
      goalText == other.goalText &&
      targetDate == other.targetDate &&
      dailyMinutes == other.dailyMinutes &&
      interestCodesJson == other.interestCodesJson;
}

final class LearningProfile {
  const LearningProfile({
    required this.ownerId,
    required this.revision,
    required this.draft,
    required this.updatedAtUtc,
  });

  final String ownerId;
  final int revision;
  final LearningProfileDraft draft;
  final DateTime updatedAtUtc;
}

final class LearningProfileSnapshot {
  const LearningProfileSnapshot({required this.ownerId, this.profile});
  final String ownerId;
  final LearningProfile? profile;
  int get revision => profile?.revision ?? 0;
}

final class LearningProfileChange {
  LearningProfileChange({
    required this.expectedOwnerId,
    required this.expectedRevision,
    required this.draft,
    required this.updatedAtUtc,
    required this.stillCurrent,
  }) {
    requireLearningProfileOwner(expectedOwnerId);
    if (expectedRevision < 0 ||
        expectedRevision >= learningProfileMaxRevision ||
        !updatedAtUtc.isUtc ||
        updatedAtUtc.microsecondsSinceEpoch % 1000 != 0 ||
        updatedAtUtc.millisecondsSinceEpoch < 0 ||
        updatedAtUtc.millisecondsSinceEpoch > 8640000000000000) {
      throw const LearningProfileException(LearningProfileFailureCode.invalid);
    }
  }

  final String expectedOwnerId;
  final int expectedRevision;
  final LearningProfileDraft draft;
  final DateTime updatedAtUtc;
  final bool Function() stillCurrent;
}

void requireLearningProfileOwner(String ownerId) {
  if (ownerId.isEmpty ||
      ownerId.trim() != ownerId ||
      utf8.encode(ownerId).length > 256) {
    throw const LearningProfileException(LearningProfileFailureCode.invalid);
  }
}
