/// Canonical recovery ceilings shared by all learning activities. A mode may
/// reserve capacity within these bounds but cannot redefine them.
abstract final class LearningActivityRecoveryLimits {
  static const maximumCheckpoints = 64;
  static const maximumAttempts = 128;
  static const maximumCheckpointBytes = 65536;
}
