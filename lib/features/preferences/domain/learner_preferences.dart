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

final class LearnerPreferences {
  factory LearnerPreferences({
    required String ownerId,
    required int preferenceVersion,
    required LearnerPreferenceGoal goal,
    required int availableMinutesPerDay,
    required LearnerActivityPreference activityPreference,
    required DateTime updatedAtUtc,
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
  });

  final String ownerId;
  final int preferenceVersion;
  final LearnerPreferenceGoal goal;
  final int availableMinutesPerDay;
  final LearnerActivityPreference activityPreference;
  final DateTime updatedAtUtc;

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
      other.updatedAtUtc == updatedAtUtc;

  @override
  int get hashCode => Object.hash(
    ownerId,
    preferenceVersion,
    goal,
    availableMinutesPerDay,
    activityPreference,
    updatedAtUtc,
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
