enum FocusTimerStatus { notStarted, running, paused, finished }

enum FocusTimerPauseReason { explicit, processBackground, featureDisabled }

final class FocusTimerSnapshot {
  const FocusTimerSnapshot({
    required this.status,
    required this.sessionId,
    required this.startedAtUtc,
    required this.lastTransitionAtUtc,
    required this.activeDuration,
    required this.pauseReason,
  });

  const FocusTimerSnapshot.notStarted()
    : status = FocusTimerStatus.notStarted,
      sessionId = null,
      startedAtUtc = null,
      lastTransitionAtUtc = null,
      activeDuration = Duration.zero,
      pauseReason = null;

  final FocusTimerStatus status;
  final String? sessionId;
  final DateTime? startedAtUtc;
  final DateTime? lastTransitionAtUtc;
  final Duration activeDuration;
  final FocusTimerPauseReason? pauseReason;
}
