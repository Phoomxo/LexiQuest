typedef FocusMonotonicMicros = int Function();

enum FocusTimerState { configured, running, paused, stopped, finished }

enum FocusFinishReason { elapsed, manual }

final class FocusTimerSnapshot {
  const FocusTimerSnapshot._({
    required this.minutes,
    required this.state,
    required this.elapsed,
    required this.remaining,
    required this.finishReason,
    required this.revision,
  });

  final int minutes;
  final FocusTimerState state;
  final Duration elapsed;
  final Duration remaining;
  final FocusFinishReason? finishReason;
  final int revision;
}

final class FocusTimer {
  FocusTimer({required this._monotonicMicros, int minutes = defaultMinutes}) {
    if (minutes < minimumMinutes || minutes > maximumMinutes) {
      throw RangeError.range(
        minutes,
        minimumMinutes,
        maximumMinutes,
        'minutes',
      );
    }
    _snapshot = FocusTimerSnapshot._(
      minutes: minutes,
      state: FocusTimerState.configured,
      elapsed: Duration.zero,
      remaining: Duration(minutes: minutes),
      finishReason: null,
      revision: 0,
    );
  }

  static const minimumMinutes = 1;
  static const maximumMinutes = 180;
  static const defaultMinutes = 25;

  final FocusMonotonicMicros _monotonicMicros;
  FocusTimerSnapshot? _snapshot;
  int _accumulatedMicros = 0;
  int? _runningSince;

  FocusTimerSnapshot? get snapshot => _snapshot;

  bool configureMinutes(int minutes) {
    if (minutes < minimumMinutes || minutes > maximumMinutes) {
      return false;
    }
    poll();
    final current = _snapshot;
    if (current == null ||
        current.state == FocusTimerState.running ||
        current.state == FocusTimerState.paused) {
      return false;
    }
    if (current.state == FocusTimerState.configured &&
        current.minutes == minutes) {
      return true;
    }
    _accumulatedMicros = 0;
    _runningSince = null;
    _transition(FocusTimerState.configured, minutes: minutes);
    return true;
  }

  void start() {
    poll();
    final state = _snapshot?.state;
    if (state != FocusTimerState.configured &&
        state != FocusTimerState.stopped) {
      return;
    }
    _accumulatedMicros = 0;
    _runningSince = _monotonicMicros();
    _transition(FocusTimerState.running);
  }

  void pause() {
    poll();
    final current = _snapshot;
    if (current == null || current.state != FocusTimerState.running) {
      return;
    }
    _accumulatedMicros = current.elapsed.inMicroseconds;
    _runningSince = null;
    _transition(FocusTimerState.paused);
  }

  void resume() {
    poll();
    if (_snapshot?.state != FocusTimerState.paused) {
      return;
    }
    _runningSince = _monotonicMicros();
    _transition(FocusTimerState.running);
  }

  void stop() {
    poll();
    final state = _snapshot?.state;
    if (state != FocusTimerState.running && state != FocusTimerState.paused) {
      return;
    }
    _accumulatedMicros = 0;
    _runningSince = null;
    _transition(FocusTimerState.stopped);
  }

  void finish() {
    poll();
    final current = _snapshot;
    if (current == null ||
        (current.state != FocusTimerState.running &&
            current.state != FocusTimerState.paused)) {
      return;
    }
    _accumulatedMicros = current.elapsed.inMicroseconds;
    _runningSince = null;
    _transition(
      FocusTimerState.finished,
      finishReason: FocusFinishReason.manual,
    );
  }

  void poll() {
    final current = _snapshot;
    if (current == null || current.state != FocusTimerState.running) {
      return;
    }
    final limit = Duration(minutes: current.minutes).inMicroseconds;
    final elapsedMicros =
        (_accumulatedMicros + _monotonicMicros() - _runningSince!)
            .clamp(0, limit)
            .toInt();
    if (elapsedMicros == current.elapsed.inMicroseconds) {
      return;
    }
    if (elapsedMicros == limit) {
      _accumulatedMicros = limit;
      _runningSince = null;
      _transition(
        FocusTimerState.finished,
        finishReason: FocusFinishReason.elapsed,
      );
      return;
    }
    final elapsed = Duration(microseconds: elapsedMicros);
    _snapshot = FocusTimerSnapshot._(
      minutes: current.minutes,
      state: current.state,
      elapsed: elapsed,
      remaining: Duration(minutes: current.minutes) - elapsed,
      finishReason: null,
      revision: current.revision,
    );
  }

  void _transition(
    FocusTimerState state, {
    int? minutes,
    FocusFinishReason? finishReason,
  }) {
    final current = _snapshot!;
    final configuredMinutes = minutes ?? current.minutes;
    final elapsed = Duration(microseconds: _accumulatedMicros);
    _snapshot = FocusTimerSnapshot._(
      minutes: configuredMinutes,
      state: state,
      elapsed: elapsed,
      remaining: Duration(minutes: configuredMinutes) - elapsed,
      finishReason: finishReason,
      revision: current.revision + 1,
    );
  }

  void dispose() {
    _snapshot = null;
    _accumulatedMicros = 0;
    _runningSince = null;
  }
}
