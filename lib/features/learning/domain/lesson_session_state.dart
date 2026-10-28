import 'lesson_mode.dart';
import 'session_configuration.dart';

enum LessonSessionStatus { planned, active, paused, completed, abandoned }

final class LessonStartCommand {
  const LessonStartCommand({
    required this.mode,
    required this.sessionId,
    required this.startedAtUtc,
    required this.itemCount,
    this.ownerId,
    this.configuration,
  });

  final LessonMode mode;
  final String sessionId;
  final DateTime startedAtUtc;
  final int itemCount;
  final String? ownerId;
  final SessionConfiguration? configuration;
}

final class LessonSubmission {
  const LessonSubmission({required this.response, required this.support});

  final LessonResponse response;
  final LessonSupport support;
}

final class LessonSessionState {
  const LessonSessionState({
    required this.mode,
    required this.status,
    this.sessionId,
    this.startedAtUtc,
    this.lastTransitionAtUtc,
    this.itemCount = 0,
    this.committedResponseCount = 0,
  });

  const LessonSessionState.planned(LessonMode mode)
    : this(mode: mode, status: LessonSessionStatus.planned);

  final LessonMode mode;
  final LessonSessionStatus status;
  final String? sessionId;
  final DateTime? startedAtUtc;
  final DateTime? lastTransitionAtUtc;
  final int itemCount;
  final int committedResponseCount;

  double get progress =>
      itemCount == 0 ? 0 : (committedResponseCount / itemCount).clamp(0, 1);

  LessonSessionState copyWith({
    LessonSessionStatus? status,
    String? sessionId,
    DateTime? startedAtUtc,
    DateTime? lastTransitionAtUtc,
    int? itemCount,
    int? committedResponseCount,
  }) => LessonSessionState(
    mode: mode,
    status: status ?? this.status,
    sessionId: sessionId ?? this.sessionId,
    startedAtUtc: startedAtUtc ?? this.startedAtUtc,
    lastTransitionAtUtc: lastTransitionAtUtc ?? this.lastTransitionAtUtc,
    itemCount: itemCount ?? this.itemCount,
    committedResponseCount:
        committedResponseCount ?? this.committedResponseCount,
  );
}
