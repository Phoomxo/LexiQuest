import '../../domain/learning_activity_recovery_limits.dart';

/// Optional actions must reserve the worst allowed
/// remaining answers, Continue untimed, and exact terminal receipts.
abstract final class PairMatchingCheckpointBudget {
  static const maximumCounter = 9223372036854775807;
  static const maximumRevisions =
      LearningActivityRecoveryLimits.maximumCheckpoints;
  static const maximumAttempts = LearningActivityRecoveryLimits.maximumAttempts;
  static const maximumBytes =
      LearningActivityRecoveryLimits.maximumCheckpointBytes;
  static const terminalReserve = 3;
  static const continueUntimedReserve = 1;
  static bool canTransition({
    required int revision,
    required int cost,
    required int attempts,
    required int remainingAttemptBound,
    required int revealReserve,
    required int timerReserve,
  }) =>
      revision >= 1 &&
      cost >= 0 &&
      attempts >= 0 &&
      remainingAttemptBound >= 0 &&
      attempts + remainingAttemptBound <= maximumAttempts &&
      revision +
              cost +
              remainingAttemptBound * 2 +
              revealReserve +
              timerReserve +
              terminalReserve <=
          maximumRevisions;
  static bool canAnswer({
    required int revision,
    required int attempts,
    required int remainingPairs,
    bool isCorrect = false,
    int? remainingAttemptBound,
    int revealReserve = 0,
    int timerReserve = continueUntimedReserve,
  }) =>
      remainingPairs > 0 &&
      canTransition(
        revision: revision,
        cost: 2,
        attempts: attempts + 1,
        remainingAttemptBound:
            remainingAttemptBound ?? remainingPairs - (isCorrect ? 1 : 0),
        revealReserve: revealReserve,
        timerReserve: timerReserve,
      );
}
