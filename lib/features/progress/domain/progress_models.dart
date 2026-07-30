final class SkillEvidence {
  const SkillEvidence({
    required this.key,
    required this.label,
    required this.sampleSize,
    required this.accuracy,
  });

  final String key;
  final String label;
  final int sampleSize;
  final double? accuracy;
}

final class WeaknessEvidence {
  const WeaknessEvidence({
    required this.wordId,
    required this.spelling,
    required this.meaning,
    required this.sampleSize,
    required this.incorrectCount,
    required this.errorRate,
    required this.dueAtUtc,
  });

  final String wordId;
  final String spelling;
  final String meaning;
  final int sampleSize;
  final int incorrectCount;
  final double errorRate;
  final DateTime? dueAtUtc;
}

final class LearningRecommendation {
  const LearningRecommendation({
    required this.wordId,
    required this.title,
    required this.reason,
    required this.sampleSize,
  });

  final String wordId;
  final String title;
  final String reason;
  final int sampleSize;
}

final class AchievementEvidence {
  const AchievementEvidence({
    required this.id,
    required this.definitionVersion,
    required this.sourceEventId,
    required this.unlockedAtUtc,
  });

  final String id;
  final int definitionVersion;
  final String sourceEventId;
  final DateTime unlockedAtUtc;
}

final class ProgressSnapshot {
  const ProgressSnapshot({
    required this.sampleSize,
    required this.correctCount,
    required this.wrongCount,
    required this.accuracy,
    required this.points,
    required this.completedSessions,
    required this.streakDays,
    required this.dueReviewCount,
    required this.masteredWordCount,
    required this.achievementCount,
    required this.gameLevel,
    required this.skills,
    required this.weaknesses,
    required this.recommendations,
    this.achievements = const [],
    this.algorithmVersion = 1,
    this.averageResponseTimeMs,
    this.latestEvidenceAtUtc,
  });

  final int sampleSize;
  final int correctCount;
  final int wrongCount;
  final double? accuracy;
  final int points;
  final int completedSessions;
  final int streakDays;
  final int dueReviewCount;
  final int masteredWordCount;
  final int achievementCount;
  final int gameLevel;
  final List<SkillEvidence> skills;
  final List<WeaknessEvidence> weaknesses;
  final List<LearningRecommendation> recommendations;
  final List<AchievementEvidence> achievements;
  final int algorithmVersion;
  final double? averageResponseTimeMs;
  final DateTime? latestEvidenceAtUtc;
}
