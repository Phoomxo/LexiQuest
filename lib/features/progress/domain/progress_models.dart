import '../../learning/domain/learning_models.dart';

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
    required this.totalXp,
    required this.completedSessions,
    required this.streakDays,
    required this.dueReviewCount,
    required this.masteredWordCount,
    required this.achievementCount,
    required this.gameLevel,
    required this.skills,
    required this.weaknesses,
    required this.recommendations,
    this.vocabularyWordCount = 0,
    this.nextDueSpelling,
    this.nextDueCategoryName,
    this.recentSessions = const [],
    this.achievements = const [],
    this.algorithmVersion = 1,
    this.averageResponseTimeMs,
    this.latestEvidenceAtUtc,
  });

  final int sampleSize;
  final int correctCount;
  final int wrongCount;
  final double? accuracy;
  final int totalXp;
  final int completedSessions;
  final int streakDays;
  final int dueReviewCount;
  final int vocabularyWordCount;
  final String? nextDueSpelling;
  final String? nextDueCategoryName;
  final List<SessionHistoryEntry> recentSessions;
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

final class SessionHistoryEntry {
  const SessionHistoryEntry({
    required this.ownerId,
    required this.summary,
    required this.activityType,
    required this.startedAtUtc,
    required this.completedAtUtc,
    this.mistakes = const [],
    this.categoryId,
    this.categoryName,
  });

  final String ownerId;
  final LearningSessionSummary summary;
  final String activityType;
  final DateTime startedAtUtc;
  final DateTime completedAtUtc;
  final List<QuizWord> mistakes;
  final String? categoryId;
  final String? categoryName;
}
