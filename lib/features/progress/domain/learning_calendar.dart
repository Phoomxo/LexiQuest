/// Immutable, separately-labelled read-model axes for a learner-local week.
///
/// This model deliberately has no score or profile aggregate. Effort, answer
/// accuracy, skill distribution, and the accuracy trend retain their distinct
/// evidence rules so callers cannot mistake one axis for another.
library;

final class LearningCalendarSnapshot {
  LearningCalendarSnapshot({
    required this.timezoneId,
    required DateTime weekStart,
    required List<LearningCalendarDay> days,
    required this.weekly,
  }) : weekStart = _calendarDay(weekStart),
       days = List<LearningCalendarDay>.unmodifiable(days);

  final String timezoneId;
  final DateTime weekStart;
  final List<LearningCalendarDay> days;
  final WeeklyLearningAnalytics weekly;
}

final class LearningCalendarDay {
  LearningCalendarDay({
    required DateTime day,
    required this.effort,
    required this.accuracy,
    required List<LearningSkillDistribution> skillDistribution,
  }) : day = _calendarDay(day),
       skillDistribution = List<LearningSkillDistribution>.unmodifiable(
         skillDistribution,
       );

  final DateTime day;
  final LearningEffortAxis effort;
  final LearningAccuracyAxis accuracy;
  final List<LearningSkillDistribution> skillDistribution;
}

final class WeeklyLearningAnalytics {
  WeeklyLearningAnalytics({
    required this.effort,
    required this.accuracy,
    required List<LearningSkillDistribution> skillDistribution,
    required List<LearningAccuracyTrendPoint> accuracyTrend,
  }) : skillDistribution = List<LearningSkillDistribution>.unmodifiable(
         skillDistribution,
       ),
       accuracyTrend = List<LearningAccuracyTrendPoint>.unmodifiable(
         accuracyTrend,
       );

  final LearningEffortAxis effort;
  final LearningAccuracyAxis accuracy;
  final List<LearningSkillDistribution> skillDistribution;
  final List<LearningAccuracyTrendPoint> accuracyTrend;
}

final class LearningEffortAxis {
  const LearningEffortAxis({required this.activeDuration});

  /// f24's immutable active duration. It is never inferred from wall-clock
  /// start and end timestamps.
  final Duration activeDuration;
}

final class LearningAccuracyAxis {
  const LearningAccuracyAxis({
    required this.sampleSize,
    required this.correctCount,
  }) : assert(sampleSize >= 0),
       assert(correctCount >= 0),
       assert(correctCount <= sampleSize);

  final int sampleSize;
  final int correctCount;

  int get wrongCount => sampleSize - correctCount;

  double? get accuracy => sampleSize == 0 ? null : correctCount / sampleSize;
}

final class LearningSkillDistribution {
  const LearningSkillDistribution({
    required this.skillId,
    required this.sampleSize,
    required this.correctCount,
  }) : assert(skillId != ''),
       assert(sampleSize >= 0),
       assert(correctCount >= 0),
       assert(correctCount <= sampleSize);

  final String skillId;
  final int sampleSize;
  final int correctCount;

  double? get accuracy => sampleSize == 0 ? null : correctCount / sampleSize;
}

final class LearningAccuracyTrendPoint {
  LearningAccuracyTrendPoint({required DateTime day, required this.accuracy})
    : day = _calendarDay(day);

  final DateTime day;
  final LearningAccuracyAxis accuracy;
}

DateTime _calendarDay(DateTime value) =>
    DateTime(value.year, value.month, value.day);
