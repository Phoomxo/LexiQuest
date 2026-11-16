enum FocusState { running, paused, completed, interrupted }

enum FocusStep { pause, resume, finish, recoverInterrupted }

enum FocusSpanKind { active, paused }

final class FocusSample {
  const FocusSample({
    required this.utcMs,
    required this.monotonicUs,
    required this.continuityId,
  });

  final int utcMs;
  final int monotonicUs;
  final String continuityId;

  void validate() {
    if (utcMs < 0 ||
        utcMs > 8640000000000000 ||
        monotonicUs < 0 ||
        monotonicUs > 9007199254740991 ||
        continuityId.trim().isEmpty ||
        continuityId.length > 256) {
      throw ArgumentError('Invalid focus clock sample');
    }
  }
}

abstract interface class FocusClock {
  FocusSample sample();
}

final class MonotonicFocusClock implements FocusClock {
  MonotonicFocusClock({required this.continuityId, DateTime Function()? nowUtc})
    : nowUtc = nowUtc ?? (() => DateTime.now().toUtc());

  final String continuityId;
  final DateTime Function() nowUtc;
  final Stopwatch _stopwatch = Stopwatch()..start();

  @override
  FocusSample sample() {
    final wall = nowUtc();
    if (!wall.isUtc) {
      throw ArgumentError('Focus wall clock must return UTC');
    }
    final sample = FocusSample(
      utcMs: wall.millisecondsSinceEpoch,
      monotonicUs: _stopwatch.elapsedMicroseconds,
      continuityId: continuityId,
    );
    sample.validate();
    return sample;
  }
}

final class FocusSpan {
  const FocusSpan({
    required this.kind,
    required this.observedStartUtcMs,
    required this.observedEndUtcMs,
    required this.elapsedUs,
  });

  final FocusSpanKind kind;
  final int observedStartUtcMs;
  final int observedEndUtcMs;
  final int? elapsedUs;
}

final class FocusSnapshot {
  FocusSnapshot({
    required this.id,
    required this.ownerId,
    required this.originOwnerId,
    required this.targetMs,
    required this.startedAtUtcMs,
    required this.startRuleId,
    required this.startCivilWeek,
    required this.state,
    required this.revision,
    required Iterable<FocusSpan> spans,
    required this.endedAtUtcMs,
    required this.openSample,
  }) : spans = List.unmodifiable(spans);

  final String id;
  final String ownerId;
  final String originOwnerId;
  final int targetMs;
  final int startedAtUtcMs;
  final String? startRuleId;
  final String? startCivilWeek;
  final FocusState state;
  final int revision;
  final List<FocusSpan> spans;
  final int? endedAtUtcMs;
  final FocusSample? openSample;

  int get measuredActiveMs => _elapsed(FocusSpanKind.active) ~/ 1000;
  int get activeMs => measuredActiveMs < targetMs ? measuredActiveMs : targetMs;
  int get pausedMs => _elapsed(FocusSpanKind.paused) ~/ 1000;
  bool get hasUnknownGap =>
      state == FocusState.interrupted ||
      (state == FocusState.paused && openSample == null) ||
      spans.any((span) => span.elapsedUs == null);

  int _elapsed(FocusSpanKind kind) => spans
      .where((span) => span.kind == kind)
      .fold(0, (total, span) => total + (span.elapsedUs ?? 0));
}

final class FocusWeek {
  FocusWeek({
    required this.civilMonday,
    required Iterable<FocusSnapshot> sessions,
    required Iterable<FocusSnapshot> unattributed,
  }) : sessions = List.unmodifiable(sessions),
       unattributed = List.unmodifiable(unattributed);

  final DateTime civilMonday;
  final List<FocusSnapshot> sessions;
  final List<FocusSnapshot> unattributed;

  int get completedActiveMs => sessions
      .where((session) => session.state == FocusState.completed)
      .fold(0, (total, session) => total + session.activeMs);
}
