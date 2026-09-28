/// Canonical recovery ceilings shared by all learning activities. A mode may
/// reserve capacity within these centrally defined bounds.
abstract final class LearningActivityRecoveryLimits {
  static const maximumCheckpoints = 64;
  // Frozen admission + draft/pending/feedback/advance for 100 meaning questions,
  // plus the frozen close occurrence. Other activity ceilings stay unchanged.
  static const maximumOrdinaryMeaningCheckpoints = 404;
  static const maximumAttempts = 128;
  static const maximumCheckpointBytes = 65536;
}
