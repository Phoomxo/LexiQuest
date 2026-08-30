enum LearnerPreferenceGoal {
  balancedGrowth,
  examPreparation,
  conversationConfidence,
  vocabularyGrowth,
}

abstract final class LearnerPreferenceGoalCodec {
  static LearnerPreferenceGoal parse(String value) => switch (value) {
    'balancedGrowth' => LearnerPreferenceGoal.balancedGrowth,
    'examPreparation' => LearnerPreferenceGoal.examPreparation,
    'conversationConfidence' => LearnerPreferenceGoal.conversationConfidence,
    'vocabularyGrowth' => LearnerPreferenceGoal.vocabularyGrowth,
    _ => throw LearnerPreferencesValidationFailure(
      'unsupported learner preference goal: $value',
    ),
  };
}

enum LearnerActivityPreference {
  mixedPractice,
  quiz,
  speaking,
  reading,
  vocabulary,
}

enum LearnerThemePreference { system, light, dark }

abstract final class LearnerThemePreferenceCodec {
  static LearnerThemePreference parse(String value) => switch (value) {
    'system' => LearnerThemePreference.system,
    'light' => LearnerThemePreference.light,
    'dark' => LearnerThemePreference.dark,
    _ => throw LearnerPreferencesValidationFailure(
      'unsupported learner theme preference: $value',
    ),
  };
}

enum LearnerMotionPreference { system, reduced }

abstract final class LearnerMotionPreferenceCodec {
  static LearnerMotionPreference parse(String value) => switch (value) {
    'system' => LearnerMotionPreference.system,
    'reduced' => LearnerMotionPreference.reduced,
    _ => throw LearnerPreferencesValidationFailure(
      'unsupported learner motion preference: $value',
    ),
  };
}

abstract final class LearnerActivityPreferenceCodec {
  static LearnerActivityPreference parse(String value) => switch (value) {
    'mixedPractice' => LearnerActivityPreference.mixedPractice,
    'quiz' => LearnerActivityPreference.quiz,
    'speaking' => LearnerActivityPreference.speaking,
    'reading' => LearnerActivityPreference.reading,
    'vocabulary' => LearnerActivityPreference.vocabulary,
    _ => throw LearnerPreferencesValidationFailure(
      'unsupported learner activity preference: $value',
    ),
  };
}

final class LearnerPreferencesValidationFailure implements Exception {
  const LearnerPreferencesValidationFailure(this.message);

  final String message;

  @override
  String toString() => 'LearnerPreferencesValidationFailure($message)';
}

final class LearnerDisplayPreferences {
  factory LearnerDisplayPreferences({
    required LearnerThemePreference themeMode,
    required LearnerMotionPreference motionMode,
    required DateTime updatedAtUtc,
  }) {
    if (!updatedAtUtc.isUtc || updatedAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        updatedAtUtc,
        'updatedAtUtc',
        'must be nonnegative UTC',
      );
    }
    return LearnerDisplayPreferences._(
      themeMode: themeMode,
      motionMode: motionMode,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        updatedAtUtc.millisecondsSinceEpoch,
        isUtc: true,
      ),
    );
  }

  factory LearnerDisplayPreferences.defaults({DateTime? updatedAtUtc}) =>
      LearnerDisplayPreferences(
        themeMode: LearnerThemePreference.system,
        motionMode: LearnerMotionPreference.system,
        updatedAtUtc:
            updatedAtUtc ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );

  const LearnerDisplayPreferences._({
    required this.themeMode,
    required this.motionMode,
    required this.updatedAtUtc,
  });

  final LearnerThemePreference themeMode;
  final LearnerMotionPreference motionMode;
  final DateTime updatedAtUtc;

  @override
  bool operator ==(Object other) =>
      other is LearnerDisplayPreferences &&
      other.themeMode == themeMode &&
      other.motionMode == motionMode &&
      other.updatedAtUtc == updatedAtUtc;

  @override
  int get hashCode => Object.hash(themeMode, motionMode, updatedAtUtc);
}

final class LearnerPreferences {
  factory LearnerPreferences({
    required String ownerId,
    required int preferenceVersion,
    required LearnerPreferenceGoal goal,
    required int availableMinutesPerDay,
    required LearnerActivityPreference activityPreference,
    required DateTime updatedAtUtc,
    LearnerDisplayPreferences? display,
  }) {
    if (ownerId.isEmpty || ownerId != ownerId.trim()) {
      throw ArgumentError.value(ownerId, 'ownerId', 'must be canonical');
    }
    if (preferenceVersion != 1) {
      throw ArgumentError.value(
        preferenceVersion,
        'preferenceVersion',
        'only version 1 is supported',
      );
    }
    if (availableMinutesPerDay < 1 || availableMinutesPerDay > 240) {
      throw ArgumentError.value(
        availableMinutesPerDay,
        'availableMinutesPerDay',
        'must be between 1 and 240',
      );
    }
    if (!updatedAtUtc.isUtc || updatedAtUtc.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(
        updatedAtUtc,
        'updatedAtUtc',
        'must be nonnegative UTC',
      );
    }
    return LearnerPreferences._(
      ownerId: ownerId,
      preferenceVersion: preferenceVersion,
      goal: goal,
      availableMinutesPerDay: availableMinutesPerDay,
      activityPreference: activityPreference,
      updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
        updatedAtUtc.millisecondsSinceEpoch,
        isUtc: true,
      ),
      display: display ?? LearnerDisplayPreferences.defaults(),
    );
  }

  factory LearnerPreferences.defaults({
    required String ownerId,
    required DateTime updatedAtUtc,
  }) => LearnerPreferences(
    ownerId: ownerId,
    preferenceVersion: 1,
    goal: LearnerPreferenceGoal.balancedGrowth,
    availableMinutesPerDay: 20,
    activityPreference: LearnerActivityPreference.mixedPractice,
    updatedAtUtc: updatedAtUtc,
  );

  const LearnerPreferences._({
    required this.ownerId,
    required this.preferenceVersion,
    required this.goal,
    required this.availableMinutesPerDay,
    required this.activityPreference,
    required this.updatedAtUtc,
    required this.display,
  });

  final String ownerId;
  final int preferenceVersion;
  final LearnerPreferenceGoal goal;
  final int availableMinutesPerDay;
  final LearnerActivityPreference activityPreference;
  final DateTime updatedAtUtc;
  final LearnerDisplayPreferences display;

  Map<String, Object?> toJson() => <String, Object?>{
    'preferenceVersion': preferenceVersion,
    'goal': goal.name,
    'availableMinutesPerDay': availableMinutesPerDay,
    'activityPreference': activityPreference.name,
    'updatedAtUtcMs': updatedAtUtc.millisecondsSinceEpoch,
  };

  @override
  bool operator ==(Object other) =>
      other is LearnerPreferences &&
      other.ownerId == ownerId &&
      other.preferenceVersion == preferenceVersion &&
      other.goal == goal &&
      other.availableMinutesPerDay == availableMinutesPerDay &&
      other.activityPreference == activityPreference &&
      other.updatedAtUtc == updatedAtUtc &&
      other.display == display;

  @override
  int get hashCode => Object.hash(
    ownerId,
    preferenceVersion,
    goal,
    availableMinutesPerDay,
    activityPreference,
    updatedAtUtc,
    display,
  );
}

final class LearnerPreferenceProtocolClamp {
  const LearnerPreferenceProtocolClamp({
    required this.maximumAvailableMinutesPerDay,
    required this.activityPreference,
  });

  final int maximumAvailableMinutesPerDay;
  final LearnerActivityPreference activityPreference;
}

final class EffectiveLearnerPreferences {
  const EffectiveLearnerPreferences({
    required this.saved,
    required this.availableMinutesPerDay,
    required this.activityPreference,
    required this.wasClamped,
  });

  final LearnerPreferences saved;
  final int availableMinutesPerDay;
  final LearnerActivityPreference activityPreference;
  final bool wasClamped;
}
