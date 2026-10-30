import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/focus/application/focus_timer.dart';

void main() {
  test('a fresh timer is configured for 25 minutes', () {
    final timer = FocusTimer(monotonicMicros: () => 0);
    _expectSnapshot(
      timer,
      FocusTimerState.configured,
      minutes: 25,
      revision: 0,
    );
  });

  for (final minutes in [1, 180]) {
    test('constructor accepts the $minutes minute boundary', () {
      final timer = FocusTimer(monotonicMicros: () => 0, minutes: minutes);
      _expectSnapshot(timer, FocusTimerState.configured, minutes: minutes);
    });
  }

  for (final minutes in [-1, 0, 181]) {
    test('constructor rejects $minutes minutes', () {
      expect(
        () => FocusTimer(monotonicMicros: () => 0, minutes: minutes),
        throwsArgumentError,
      );
    });
  }

  test('configuration replaces the duration and only a change revises it', () {
    final timer = FocusTimer(monotonicMicros: () => 0);
    expect(timer.configureMinutes(1), isTrue);
    _expectSnapshot(timer, FocusTimerState.configured, minutes: 1, revision: 1);
    expect(timer.configureMinutes(1), isTrue);
    _expectSnapshot(timer, FocusTimerState.configured, minutes: 1, revision: 1);
    expect(timer.configureMinutes(180), isTrue);
    _expectSnapshot(
      timer,
      FocusTimerState.configured,
      minutes: 180,
      revision: 2,
    );
  });

  for (final state in FocusTimerState.values) {
    test('invalid configuration leaves the $state interval untouched', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      _prepareState(timer, state);
      final before = _snapshotValues(timer.snapshot!);
      now += const Duration(minutes: 2).inMicroseconds;
      for (final minutes in [-1, 0, 181]) {
        expect(timer.configureMinutes(minutes), isFalse);
        expect(_snapshotValues(timer.snapshot!), before);
      }
    });
  }

  for (final paused in [false, true]) {
    test('configuration cannot replace an active interval paused=$paused', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now = const Duration(seconds: 10).inMicroseconds;
      if (paused) {
        timer.pause();
      }
      expect(timer.configureMinutes(2), isFalse);
      _expectSnapshot(
        timer,
        paused ? FocusTimerState.paused : FocusTimerState.running,
        minutes: 1,
        elapsed: const Duration(seconds: 10),
        revision: paused ? 2 : 1,
      );
    });
  }

  test(
    'polling reads exact monotonic microseconds without revising controls',
    () {
      var now = 9000000;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now += 1234567;
      timer.poll();
      _expectSnapshot(
        timer,
        FocusTimerState.running,
        minutes: 1,
        elapsed: const Duration(microseconds: 1234567),
        revision: 1,
      );
      now += 2000000;
      timer.poll();
      _expectSnapshot(
        timer,
        FocusTimerState.running,
        minutes: 1,
        elapsed: const Duration(microseconds: 3234567),
        revision: 1,
      );
    },
  );

  test('repeated Start and Resume preserve a running interval', () {
    var now = 0;
    final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
    timer.start();
    now = const Duration(seconds: 10).inMicroseconds;
    timer.start();
    now = const Duration(seconds: 15).inMicroseconds;
    timer.resume();
    now = const Duration(seconds: 20).inMicroseconds;
    timer.poll();
    _expectSnapshot(
      timer,
      FocusTimerState.running,
      minutes: 1,
      elapsed: const Duration(seconds: 20),
      revision: 1,
    );
  });

  test('multiple running segments exclude all paused time', () {
    var now = 0;
    final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
    timer.start();
    now += const Duration(seconds: 10).inMicroseconds;
    timer.pause();
    now += const Duration(hours: 1).inMicroseconds;
    timer.pause();
    timer.start();
    timer.poll();
    _expectSnapshot(
      timer,
      FocusTimerState.paused,
      minutes: 1,
      elapsed: const Duration(seconds: 10),
      revision: 2,
    );
    timer.resume();
    now += const Duration(seconds: 15).inMicroseconds;
    timer.pause();
    now += const Duration(hours: 2).inMicroseconds;
    timer.resume();
    now += const Duration(seconds: 35).inMicroseconds;
    timer.poll();
    _expectSnapshot(
      timer,
      FocusTimerState.finished,
      minutes: 1,
      elapsed: const Duration(minutes: 1),
      revision: 6,
      reason: FocusFinishReason.elapsed,
    );
  });

  for (final paused in [false, true]) {
    test(
      'Stop discards elapsed time and permits a fresh Start paused=$paused',
      () {
        var now = 0;
        final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
        timer.start();
        now += const Duration(seconds: 10).inMicroseconds;
        if (paused) {
          timer.pause();
        }
        timer.stop();
        final stoppedRevision = paused ? 3 : 2;
        _expectSnapshot(
          timer,
          FocusTimerState.stopped,
          minutes: 1,
          revision: stoppedRevision,
        );
        timer.stop();
        timer.finish();
        _expectSnapshot(
          timer,
          FocusTimerState.stopped,
          minutes: 1,
          revision: stoppedRevision,
        );
        now += const Duration(hours: 1).inMicroseconds;
        timer.start();
        now += const Duration(seconds: 5).inMicroseconds;
        timer.poll();
        _expectSnapshot(
          timer,
          FocusTimerState.running,
          minutes: 1,
          elapsed: const Duration(seconds: 5),
          revision: stoppedRevision + 1,
        );
      },
    );
  }

  for (final paused in [false, true]) {
    test('manual Finish retains the local elapsed summary paused=$paused', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now += const Duration(seconds: 10).inMicroseconds;
      if (paused) {
        timer.pause();
        now += const Duration(hours: 1).inMicroseconds;
      }
      timer.finish();
      final revision = paused ? 3 : 2;
      _expectSnapshot(
        timer,
        FocusTimerState.finished,
        minutes: 1,
        elapsed: const Duration(seconds: 10),
        revision: revision,
        reason: FocusFinishReason.manual,
      );
      for (final command in [
        timer.start,
        timer.pause,
        timer.resume,
        timer.stop,
        timer.finish,
        timer.poll,
      ]) {
        now += const Duration(hours: 1).inMicroseconds;
        command();
        _expectSnapshot(
          timer,
          FocusTimerState.finished,
          minutes: 1,
          elapsed: const Duration(seconds: 10),
          revision: revision,
          reason: FocusFinishReason.manual,
        );
      }
    });
  }

  test('manual Finish can retain a zero-duration interval', () {
    final timer = FocusTimer(monotonicMicros: () => 0, minutes: 1);
    timer.start();
    timer.finish();
    _expectSnapshot(
      timer,
      FocusTimerState.finished,
      minutes: 1,
      revision: 2,
      reason: FocusFinishReason.manual,
    );
  });

  for (final minutes in [1, 180]) {
    test('a delayed poll clamps expiry at exactly $minutes minutes once', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: minutes);
      timer.start();
      now += const Duration(days: 5).inMicroseconds;
      timer.poll();
      _expectSnapshot(
        timer,
        FocusTimerState.finished,
        minutes: minutes,
        elapsed: Duration(minutes: minutes),
        revision: 2,
        reason: FocusFinishReason.elapsed,
      );
      final expired = _snapshotValues(timer.snapshot!);
      timer.poll();
      timer.start();
      timer.stop();
      timer.finish();
      expect(_snapshotValues(timer.snapshot!), expired);
    });
  }

  for (final command in ['start', 'pause', 'resume', 'stop', 'finish']) {
    test('$command at expiry preserves natural completion', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now = const Duration(minutes: 1).inMicroseconds;
      switch (command) {
        case 'start':
          timer.start();
        case 'pause':
          timer.pause();
        case 'resume':
          timer.resume();
        case 'stop':
          timer.stop();
        case 'finish':
          timer.finish();
      }
      _expectSnapshot(
        timer,
        FocusTimerState.finished,
        minutes: 1,
        elapsed: const Duration(minutes: 1),
        revision: 2,
        reason: FocusFinishReason.elapsed,
      );
    });
  }

  for (final state in [FocusTimerState.stopped, FocusTimerState.finished]) {
    test('explicit configuration prepares a new interval from $state', () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now += const Duration(seconds: 10).inMicroseconds;
      if (state == FocusTimerState.stopped) {
        timer.stop();
      } else {
        timer.finish();
      }
      expect(timer.configureMinutes(1), isTrue);
      _expectSnapshot(
        timer,
        FocusTimerState.configured,
        minutes: 1,
        revision: 3,
      );
      timer.start();
      _expectSnapshot(timer, FocusTimerState.running, minutes: 1, revision: 4);
    });
  }

  test(
    'explicit configuration polls expiry before preparing a new interval',
    () {
      var now = 0;
      final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
      timer.start();
      now = const Duration(minutes: 1).inMicroseconds;
      expect(timer.configureMinutes(2), isTrue);
      _expectSnapshot(
        timer,
        FocusTimerState.configured,
        minutes: 2,
        revision: 3,
      );
    },
  );

  test('inactive commands cannot start a configured interval', () {
    final timer = FocusTimer(monotonicMicros: () => 0, minutes: 1);
    timer.pause();
    timer.resume();
    timer.stop();
    timer.finish();
    timer.poll();
    _expectSnapshot(timer, FocusTimerState.configured, minutes: 1, revision: 0);
  });

  test('previously returned snapshots retain their original values', () {
    var now = 0;
    final timer = FocusTimer(monotonicMicros: () => now, minutes: 1);
    final configured = timer.snapshot!;
    timer.start();
    now += const Duration(seconds: 10).inMicroseconds;
    timer.pause();
    final paused = timer.snapshot!;
    timer.dispose();
    expect(configured.state, FocusTimerState.configured);
    expect(configured.elapsed, Duration.zero);
    expect(configured.remaining, const Duration(minutes: 1));
    expect(configured.revision, 0);
    expect(paused.state, FocusTimerState.paused);
    expect(paused.elapsed, const Duration(seconds: 10));
    expect(paused.remaining, const Duration(seconds: 50));
    expect(paused.revision, 2);
  });

  for (final state in FocusTimerState.values) {
    test('dispose clears $state and makes every late command inert', () {
      var clockAvailable = true;
      final timer = FocusTimer(
        monotonicMicros: () {
          if (!clockAvailable) {
            throw StateError('Disposed clock');
          }
          return 0;
        },
        minutes: 1,
      );
      _prepareState(timer, state);
      timer.dispose();
      clockAvailable = false;
      timer.dispose();
      timer.start();
      timer.pause();
      timer.resume();
      timer.stop();
      timer.finish();
      timer.poll();
      expect(timer.configureMinutes(2), isFalse);
      expect(timer.snapshot, isNull);
    });
  }
}

void _prepareState(FocusTimer timer, FocusTimerState state) {
  switch (state) {
    case FocusTimerState.configured:
      return;
    case FocusTimerState.running:
      timer.start();
    case FocusTimerState.paused:
      timer.start();
      timer.pause();
    case FocusTimerState.stopped:
      timer.start();
      timer.stop();
    case FocusTimerState.finished:
      timer.start();
      timer.finish();
  }
}

void _expectSnapshot(
  FocusTimer timer,
  FocusTimerState state, {
  required int minutes,
  Duration elapsed = Duration.zero,
  int? revision,
  FocusFinishReason? reason,
}) {
  final snapshot = timer.snapshot!;
  expect(snapshot.state, state);
  expect(snapshot.minutes, minutes);
  expect(snapshot.elapsed, elapsed);
  expect(snapshot.remaining, Duration(minutes: minutes) - elapsed);
  expect(snapshot.elapsed + snapshot.remaining, Duration(minutes: minutes));
  expect(snapshot.elapsed.isNegative, isFalse);
  expect(snapshot.remaining.isNegative, isFalse);
  expect(snapshot.finishReason, reason);
  if (revision != null) {
    expect(snapshot.revision, revision);
  }
}

Object _snapshotValues(FocusTimerSnapshot snapshot) => (
  snapshot.minutes,
  snapshot.state,
  snapshot.elapsed,
  snapshot.remaining,
  snapshot.finishReason,
  snapshot.revision,
);
