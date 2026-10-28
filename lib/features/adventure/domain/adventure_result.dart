enum AdventureCanonicalRewardState { accepted, pending, unavailable }

enum AdventureCanonicalReceiptState {
  committed,
  pending,
  notEligible,
  unavailable,
}

enum AdventureNextAction { reviewCenter, spacedRepetition, none }

final class AdventureLearningResult {
  const AdventureLearningResult({
    required this.correctCount,
    required this.incorrectCount,
    required this.reviewDueCount,
  }) : assert(correctCount >= 0),
       assert(incorrectCount >= 0),
       assert(reviewDueCount >= 0);

  final int correctCount;
  final int incorrectCount;
  final int reviewDueCount;

  Map<String, Object?> toJson() => <String, Object?>{
    'correctCount': correctCount,
    'incorrectCount': incorrectCount,
    'reviewDueCount': reviewDueCount,
  };
}

final class AdventureEffortResult {
  const AdventureEffortResult({
    required this.activeDuration,
    required this.completedItems,
  }) : assert(completedItems >= 0);

  final Duration activeDuration;
  final int completedItems;

  Map<String, Object?> toJson() => <String, Object?>{
    'activeDurationMs': activeDuration.inMilliseconds,
    'completedItems': completedItems,
  };
}

final class AdventureEngagementResult {
  const AdventureEngagementResult({
    required this.completedMission,
    required this.returnedAfterBreak,
  });

  final bool completedMission;
  final bool returnedAfterBreak;

  Map<String, Object?> toJson() => <String, Object?>{
    'completedMission': completedMission,
    'returnedAfterBreak': returnedAfterBreak,
  };
}

final class AdventureRewardReceiptView {
  const AdventureRewardReceiptView({
    required this.state,
    this.receiptId,
    this.canonicalAmount,
  }) : assert(
         state != AdventureCanonicalRewardState.accepted || receiptId != null,
       ),
       assert(canonicalAmount == null || canonicalAmount >= 0),
       assert(
         state == AdventureCanonicalRewardState.accepted || receiptId == null,
       );

  final AdventureCanonicalRewardState state;
  final String? receiptId;
  final int? canonicalAmount;

  Map<String, Object?> toJson() => <String, Object?>{
    'state': state.name,
    'receiptId': receiptId,
    'canonicalAmount': canonicalAmount,
  };
}

final class AdventureMotivationReceiptView {
  AdventureMotivationReceiptView({
    required this.questState,
    required this.streakState,
    required this.achievementState,
    Iterable<String> questCodes = const <String>[],
    Iterable<String> streakCodes = const <String>[],
    Iterable<String> achievementCodes = const <String>[],
  }) : questCodes = List<String>.unmodifiable(questCodes),
       streakCodes = List<String>.unmodifiable(streakCodes),
       achievementCodes = List<String>.unmodifiable(achievementCodes);

  final AdventureCanonicalReceiptState questState;
  final AdventureCanonicalReceiptState streakState;
  final AdventureCanonicalReceiptState achievementState;
  final List<String> questCodes;
  final List<String> streakCodes;
  final List<String> achievementCodes;

  Map<String, Object?> toJson() => <String, Object?>{
    'questState': questState.name,
    'streakState': streakState.name,
    'achievementState': achievementState.name,
    'questCodes': questCodes,
    'streakCodes': streakCodes,
    'achievementCodes': achievementCodes,
  };
}

final class AdventureResult {
  const AdventureResult({
    required this.ownerId,
    required this.sessionId,
    required this.learning,
    required this.effort,
    required this.engagement,
    required this.motivation,
    required this.reward,
    required this.nextAction,
    this.technicalMessage,
  });

  final String ownerId;
  final String sessionId;
  final AdventureLearningResult learning;
  final AdventureEffortResult effort;
  final AdventureEngagementResult engagement;
  final AdventureMotivationReceiptView motivation;
  final AdventureRewardReceiptView reward;
  final AdventureNextAction nextAction;
  final String? technicalMessage;

  Map<String, Object?> toJson() => <String, Object?>{
    'ownerId': ownerId,
    'sessionId': sessionId,
    'learning': learning.toJson(),
    'effort': effort.toJson(),
    'engagement': engagement.toJson(),
    'motivation': motivation.toJson(),
    'reward': reward.toJson(),
    'nextAction': nextAction.name,
    'technicalMessage': technicalMessage,
  };
}
