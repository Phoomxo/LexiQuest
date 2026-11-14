enum StudyPurpose { travel }

enum StudyMethod { reading, speaking }

enum OnboardingState { unset, skipped, completed }

enum GoalState { unset, active, closed }

final class StudyPreferences {
  const StudyPreferences({
    required this.ownerId,
    required this.onboardingState,
    required this.purpose,
    required this.plannedMinutes,
    required this.method,
    required this.goalState,
    required this.goalCivilDate,
    required this.updatedAtUtcMs,
  });

  final String ownerId;
  final OnboardingState onboardingState;
  final StudyPurpose? purpose;
  final int? plannedMinutes;
  final StudyMethod? method;
  final GoalState goalState;
  final DateTime? goalCivilDate;
  final int? updatedAtUtcMs;
}
