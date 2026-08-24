enum FocusTimerStage { implementedOff, internal }

final class FocusTimerRollout {
  const FocusTimerRollout.implementedOff()
    : stage = FocusTimerStage.implementedOff,
      emergencyOff = false;

  const FocusTimerRollout.internal({this.emergencyOff = false})
    : stage = FocusTimerStage.internal;

  final FocusTimerStage stage;
  final bool emergencyOff;

  bool get allowsFocusTimer =>
      stage == FocusTimerStage.internal && !emergencyOff;
}
