import '../../domain/learning_activity_recovery_limits.dart';

/// Optional actions must reserve the worst allowed
/// remaining answers, Continue untimed, and exact terminal receipts.
abstract final class PairMatchingCheckpointBudget {
  static const maximumRevisions =
      LearningActivityRecoveryLimits.maximumCheckpoints;
  static const maximumAttempts = LearningActivityRecoveryLimits.maximumAttempts;
  static const maximumBytes =
      LearningActivityRecoveryLimits.maximumCheckpointBytes;
  static const terminalReserve = 3;
  static const continueUntimedReserve = 1;
  static bool canAnswer({
    required int revision,
    required int attempts,
    required int remainingPairs,
    bool isCorrect = false,
    int? remainingAttemptBound,
    int revealReserve = 0,
  }) =>
      revision >= 1 &&
      attempts >= 0 &&
      remainingPairs > 0 &&
      attempts +
              1 +
              (remainingAttemptBound ?? remainingPairs - (isCorrect ? 1 : 0)) <=
          maximumAttempts &&
      revision +
              2 +
              (remainingAttemptBound ?? remainingPairs - (isCorrect ? 1 : 0)) *
                  2 +
              revealReserve +
              terminalReserve +
              continueUntimedReserve <=
          maximumRevisions;
}
