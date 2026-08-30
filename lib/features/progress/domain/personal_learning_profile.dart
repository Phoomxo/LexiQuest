import 'learning_calendar.dart';
import 'progress_models.dart';

/// Availability is explicit so an absence of evidence is never rendered as
/// zero proficiency.
enum ProfileAxisAvailability { noEvidence, available }

/// Canonical authorities contributing read-only values to f36.
enum PersonalLearningProfileSource {
  driftProgress,
  learningCalendar,
  srsProjection,
  questProjection,
  streakProjection,
  rewardProjection,
}

final class PersonalLearningProfile {
  PersonalLearningProfile({
    required this.ownerId,
    required this.mastery,
    required this.srs,
    required this.effort,
    required this.accuracy,
    required this.weakness,
    required this.engagement,
    required this.calendar,
  }) {
    _requireIdentifier(ownerId, 'ownerId');
  }

  final String ownerId;
  final PersonalLearningMastery mastery;
  final PersonalLearningSrs srs;
  final PersonalLearningEffort effort;
  final PersonalLearningAccuracy accuracy;
  final PersonalLearningWeakness weakness;
  final PersonalLearningEngagement engagement;

  /// Exact f25 read model handed to the calendar route without recomputation.
  final LearningCalendarSnapshot calendar;

  bool get isEmpty =>
      mastery.availability == ProfileAxisAvailability.noEvidence &&
      srs.availability == ProfileAxisAvailability.noEvidence &&
      effort.availability == ProfileAxisAvailability.noEvidence &&
      accuracy.availability == ProfileAxisAvailability.noEvidence &&
      weakness.availability == ProfileAxisAvailability.noEvidence &&
      engagement.availability == ProfileAxisAvailability.noEvidence;
}

final class PersonalLearningMastery {
  PersonalLearningMastery({
    required this.availability,
    required this.masteredWordCount,
    required this.observedPracticeCount,
    required List<SkillEvidence> skills,
  }) : skills = List<SkillEvidence>.unmodifiable(skills) {
    _requireNonNegative(masteredWordCount, 'masteredWordCount');
    _requireNonNegative(observedPracticeCount, 'observedPracticeCount');
    if (availability == ProfileAxisAvailability.noEvidence &&
        (masteredWordCount != 0 ||
            observedPracticeCount != 0 ||
            skills.isNotEmpty)) {
      throw ArgumentError('mastery noEvidence cannot contain evidence');
    }
  }

  final ProfileAxisAvailability availability;
  final int masteredWordCount;
  final int observedPracticeCount;
  final List<SkillEvidence> skills;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.driftProgress,
    PersonalLearningProfileSource.srsProjection,
  };
}

final class PersonalLearningSrs {
  const PersonalLearningSrs({
    required this.availability,
    required this.trackedWordCount,
    required this.dueReviewCount,
  }) : assert(trackedWordCount >= 0),
       assert(dueReviewCount >= 0),
       assert(dueReviewCount <= trackedWordCount);

  final ProfileAxisAvailability availability;
  final int trackedWordCount;
  final int dueReviewCount;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.srsProjection,
  };
}

final class PersonalLearningEffort {
  PersonalLearningEffort({
    required this.availability,
    required this.activeDuration,
  }) : assert(!activeDuration.isNegative);

  final ProfileAxisAvailability availability;
  final Duration activeDuration;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.learningCalendar,
  };
}

final class PersonalLearningAccuracy {
  const PersonalLearningAccuracy({
    required this.availability,
    required this.sampleSize,
    required this.correctCount,
  }) : assert(sampleSize >= 0),
       assert(correctCount >= 0),
       assert(correctCount <= sampleSize);

  final ProfileAxisAvailability availability;
  final int sampleSize;
  final int correctCount;

  int get wrongCount => sampleSize - correctCount;
  double? get value => sampleSize == 0 ? null : correctCount / sampleSize;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.learningCalendar,
  };
}

final class PersonalLearningWeakness {
  PersonalLearningWeakness({
    required this.availability,
    required List<WeaknessEvidence> items,
  }) : items = List<WeaknessEvidence>.unmodifiable(items) {
    if (availability == ProfileAxisAvailability.noEvidence &&
        items.isNotEmpty) {
      throw ArgumentError('weakness noEvidence cannot contain evidence');
    }
  }

  final ProfileAxisAvailability availability;
  final List<WeaknessEvidence> items;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.driftProgress,
  };
}

final class PersonalLearningEngagement {
  const PersonalLearningEngagement({
    required this.availability,
    required this.totalXp,
    required this.avatarLevel,
    required this.completedSessionCount,
    required this.currentStreakDays,
    required this.longestStreakDays,
    required this.activeQuestCount,
    required this.completedQuestCount,
    required this.achievementCount,
    required this.ownedRewardItemCount,
  }) : assert(totalXp >= 0),
       assert(avatarLevel >= 1),
       assert(completedSessionCount >= 0),
       assert(currentStreakDays >= 0),
       assert(longestStreakDays >= currentStreakDays),
       assert(activeQuestCount >= 0),
       assert(completedQuestCount >= 0),
       assert(achievementCount >= 0),
       assert(ownedRewardItemCount >= 0);

  final ProfileAxisAvailability availability;
  final int totalXp;
  final int avatarLevel;
  final int completedSessionCount;
  final int currentStreakDays;
  final int longestStreakDays;
  final int activeQuestCount;
  final int completedQuestCount;
  final int achievementCount;
  final int ownedRewardItemCount;

  Set<PersonalLearningProfileSource> get sources => const {
    PersonalLearningProfileSource.driftProgress,
    PersonalLearningProfileSource.questProjection,
    PersonalLearningProfileSource.streakProjection,
    PersonalLearningProfileSource.rewardProjection,
  };
}

void _requireIdentifier(String value, String name) {
  if (value.isEmpty || value.trim() != value || value.length > 256) {
    throw ArgumentError.value(value, name, 'must be canonical bounded text');
  }
}

void _requireNonNegative(int value, String name) {
  if (value < 0) throw ArgumentError.value(value, name, 'must be non-negative');
}
