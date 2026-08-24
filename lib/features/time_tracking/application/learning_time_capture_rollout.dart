enum LearningTimeCaptureStage { implementedOff, internal }

final class LearningTimeCaptureRollout {
  const LearningTimeCaptureRollout.implementedOff()
    : stage = LearningTimeCaptureStage.implementedOff,
      emergencyOff = false;

  const LearningTimeCaptureRollout.internal({this.emergencyOff = false})
    : stage = LearningTimeCaptureStage.internal;

  final LearningTimeCaptureStage stage;
  final bool emergencyOff;

  bool get allowsCapture =>
      stage == LearningTimeCaptureStage.internal && !emergencyOff;
}
