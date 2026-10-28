import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/learning_time_capture_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';

void main() {
  test('capture rollout is off by default and emergency-off wins', () {
    expect(
      const LearningTimeCaptureRollout.implementedOff().allowsCapture,
      isFalse,
    );
    expect(const LearningTimeCaptureRollout.internal().allowsCapture, isTrue);
    expect(
      const LearningTimeCaptureRollout.internal(
        emergencyOff: true,
      ).allowsCapture,
      isFalse,
    );
  });

  test(
    'pause resume and finish use monotonic duration despite wall rollback',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 1000,
      );
      final controller = _controller(repository, clock);

      await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock
        ..monotonicMicros += const Duration(seconds: 30).inMicroseconds
        ..utc = DateTime.utc(2026, 8, 24, 8, 59, 55);
      await controller.pause(occurredAtUtc: clock.utc);

      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 1)
        ..monotonicMicros += const Duration(seconds: 2).inMicroseconds;
      await controller.resume(occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 1, 20)
        ..monotonicMicros += const Duration(seconds: 20).inMicroseconds;
      await controller.finish(occurredAtUtc: clock.utc);

      expect(repository.segments, hasLength(2));
      expect(
        repository.segments.first.activeDuration,
        const Duration(seconds: 30),
      );
      expect(
        repository.segments.last.activeStartOffset,
        const Duration(seconds: 30),
      );
      expect(
        repository.segments.last.activeDuration,
        const Duration(seconds: 20),
      );
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 50),
      );
    },
  );

  test(
    'idle timeout closes a bounded segment and excludes later idle time',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final scheduler = _FakeIdleScheduler();
      final controller = _controller(
        repository,
        clock,
        idleTimeout: const Duration(minutes: 5),
        scheduleIdle: scheduler.schedule,
      );

      await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 5)
        ..monotonicMicros = const Duration(minutes: 5).inMicroseconds;
      await scheduler.fire();
      clock
        ..utc = DateTime.utc(2026, 8, 24, 10)
        ..monotonicMicros = const Duration(hours: 1).inMicroseconds;
      await controller.recordInteraction(occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 10, 0, 10)
        ..monotonicMicros += const Duration(seconds: 10).inMicroseconds;
      await controller.finish(occurredAtUtc: clock.utc);

      expect(
        await repository.activeDuration('session-1'),
        const Duration(minutes: 5, seconds: 10),
      );
      expect(repository.segments, hasLength(2));
    },
  );

  test(
    'repeated interactions retain long trustworthy effort in bounded segments',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final controller = _controller(repository, clock);

      await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      for (final minutes in const <int>[4, 8, 12]) {
        clock
          ..utc = DateTime.utc(2026, 8, 24, 9).add(Duration(minutes: minutes))
          ..monotonicMicros = Duration(minutes: minutes).inMicroseconds;
        await controller.recordInteraction(occurredAtUtc: clock.utc);
      }
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 13)
        ..monotonicMicros = const Duration(minutes: 13).inMicroseconds;
      await controller.finish(occurredAtUtc: clock.utc);

      expect(
        await repository.activeDuration('session-1'),
        const Duration(minutes: 13),
      );
      expect(
        repository.segments.every(
          (segment) => segment.activeDuration <= const Duration(minutes: 5),
        ),
        isTrue,
      );
      expect(
        repository.segments.map((segment) => segment.activeStartOffset),
        <Duration>[
          Duration.zero,
          const Duration(minutes: 5),
          const Duration(minutes: 10),
        ],
      );
    },
  );

  test(
    'delayed idle callback never turns the return interaction into active gap',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final controller = _controller(repository, clock);

      await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 10)
        ..monotonicMicros = const Duration(hours: 1).inMicroseconds;
      await controller.recordInteraction(occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 10, 0, 10)
        ..monotonicMicros += const Duration(seconds: 10).inMicroseconds;
      await controller.finish(occurredAtUtc: clock.utc);

      expect(
        await repository.activeDuration('session-1'),
        const Duration(minutes: 5, seconds: 10),
      );
      expect(repository.segments, hasLength(2));
    },
  );

  test('stale idle callback cannot overtake a newer interaction', () async {
    final repository = _MemoryRepository();
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final scheduler = _FakeIdleScheduler();
    final controller = _controller(
      repository,
      clock,
      scheduleIdle: scheduler.schedule,
    );

    await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
    final staleCallback = scheduler.takeCallback();
    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 0, 10)
      ..monotonicMicros = const Duration(seconds: 10).inMicroseconds;
    await controller.recordInteraction(occurredAtUtc: clock.utc);
    await staleCallback();

    expect(controller.state, ActiveLearningTimeState.active);
    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 0, 20)
      ..monotonicMicros = const Duration(seconds: 20).inMicroseconds;
    await controller.finish(occurredAtUtc: clock.utc);
    expect(
      await repository.activeDuration('session-1'),
      const Duration(seconds: 20),
    );
  });

  test('dispose during blocked start cannot open or arm capture', () async {
    final repository = _BlockingStartRepository();
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final scheduler = _FakeIdleScheduler();
    final controller = _controller(
      repository,
      clock,
      scheduleIdle: scheduler.schedule,
    );

    final start = controller.start(
      sessionId: 'session-1',
      occurredAtUtc: clock.utc,
    );
    await repository.readStarted.future;
    controller.dispose();
    repository.release();

    await expectLater(start, throwsStateError);
    expect(controller.state, ActiveLearningTimeState.inactive);
    expect(scheduler.hasCallback, isFalse);
  });

  test('queued pause freezes monotonic time before a slow append', () async {
    final repository = _BlockingAppendRepository();
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final controller = _controller(repository, clock);
    await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 5)
      ..monotonicMicros = const Duration(minutes: 5).inMicroseconds;
    final interaction = controller.recordInteraction(occurredAtUtc: clock.utc);
    await repository.appendStarted.future;

    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 5, 10)
      ..monotonicMicros = const Duration(
        minutes: 5,
        seconds: 10,
      ).inMicroseconds;
    final pause = controller.pause(occurredAtUtc: clock.utc);
    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 9)
      ..monotonicMicros = const Duration(minutes: 9).inMicroseconds;
    repository.release();

    await interaction;
    await pause;
    expect(
      await repository.activeDuration('session-1'),
      const Duration(minutes: 5, seconds: 10),
    );
  });

  test(
    'failed append retries the frozen segment and restart resumes at durable offset',
    () async {
      final repository = _MemoryRepository()..failNextAppend = true;
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final first = _controller(repository, clock);
      await first.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 0, 10)
        ..monotonicMicros = const Duration(seconds: 10).inMicroseconds;

      await expectLater(
        first.pause(occurredAtUtc: clock.utc),
        throwsStateError,
      );
      final frozen = repository.attempts.single;
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 5)
        ..monotonicMicros += const Duration(minutes: 5).inMicroseconds;
      await first.pause(occurredAtUtc: clock.utc);
      expect(repository.attempts.last, same(frozen));

      final restarted = _controller(repository, clock);
      await restarted.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock
        ..utc = DateTime.utc(2026, 8, 24, 9, 5, 5)
        ..monotonicMicros += const Duration(seconds: 5).inMicroseconds;
      await restarted.finish(occurredAtUtc: clock.utc);

      expect(
        repository.segments.last.activeStartOffset,
        const Duration(seconds: 10),
      );
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 15),
      );
    },
  );

  test('finish commits a failed pending pause before terminating', () async {
    final repository = _MemoryRepository()..failNextAppend = true;
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final controller = _controller(repository, clock);
    await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
    clock
      ..utc = DateTime.utc(2026, 8, 24, 9, 0, 10)
      ..monotonicMicros = const Duration(seconds: 10).inMicroseconds;
    await expectLater(
      controller.pause(occurredAtUtc: clock.utc),
      throwsStateError,
    );

    await controller.finish(occurredAtUtc: clock.utc);

    expect(controller.state, ActiveLearningTimeState.finished);
    expect(repository.segments, hasLength(1));
    expect(repository.attempts, hasLength(2));
    expect(repository.attempts.last, same(repository.attempts.first));
  });

  test(
    'capture-source transition rejects a monotonic clock rollback',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 10,
      );
      final controller = _controller(repository, clock);
      await controller.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      clock.monotonicMicros = 5;

      await expectLater(
        controller.transitionCaptureSource(
          captureSource: LearningTimeCaptureSource.automaticLesson,
          occurredAtUtc: clock.utc,
        ),
        throwsStateError,
      );
    },
  );
}

ActiveLearningTimeController _controller(
  LearningTimeRepository repository,
  _FakeTimeAuthority clock, {
  Duration idleTimeout = const Duration(minutes: 5),
  LearningTimeIdleScheduler? scheduleIdle,
}) => ActiveLearningTimeController(
  repository: repository,
  monotonicMicros: () => clock.monotonicMicros,
  nowUtc: () => clock.utc,
  timezoneContext: (_) => const LearningTimeZoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
  idleTimeout: idleTimeout,
  scheduleIdle: scheduleIdle,
);

final class _FakeTimeAuthority {
  _FakeTimeAuthority({required this.utc, required this.monotonicMicros});

  DateTime utc;
  int monotonicMicros;
}

final class _FakeIdleScheduler {
  FutureOr<void> Function()? _callback;

  LearningTimeIdleCancellation schedule(
    Duration _,
    FutureOr<void> Function() callback,
  ) {
    _callback = callback;
    return () => _callback = null;
  }

  Future<void> fire() async {
    final callback = _callback;
    _callback = null;
    await callback?.call();
  }

  FutureOr<void> Function() takeCallback() {
    final callback = _callback;
    if (callback == null) throw StateError('no idle callback is armed');
    _callback = null;
    return callback;
  }

  bool get hasCallback => _callback != null;
}

final class _MemoryRepository implements LearningTimeRepository {
  final segments = <LearningTimeSegment>[];
  final attempts = <LearningTimeSegment>[];
  bool failNextAppend = false;

  @override
  Future<void> append(LearningTimeSegment segment) async {
    attempts.add(segment);
    if (failNextAppend) {
      failNextAppend = false;
      throw StateError('injected append failure');
    }
    final existing = segments.where((candidate) => candidate.id == segment.id);
    if (existing.isNotEmpty) {
      if (existing.single != segment) throw StateError('identity mismatch');
      return;
    }
    segments.add(segment);
  }

  @override
  Future<Duration> activeDuration(String sessionId) async => Duration(
    milliseconds: segments
        .where((segment) => segment.sessionId == sessionId)
        .fold<int>(
          0,
          (sum, segment) => sum + segment.activeDuration.inMilliseconds,
        ),
  );
}

final class _BlockingStartRepository implements LearningTimeRepository {
  final readStarted = Completer<void>();
  final _release = Completer<void>();

  void release() => _release.complete();

  @override
  Future<void> append(LearningTimeSegment segment) async {}

  @override
  Future<Duration> activeDuration(String sessionId) async {
    readStarted.complete();
    await _release.future;
    return Duration.zero;
  }
}

final class _BlockingAppendRepository implements LearningTimeRepository {
  final appendStarted = Completer<void>();
  final _release = Completer<void>();
  final _delegate = _MemoryRepository();
  bool _blocked = false;

  void release() => _release.complete();

  @override
  Future<void> append(LearningTimeSegment segment) async {
    if (!_blocked) {
      _blocked = true;
      appendStarted.complete();
      await _release.future;
    }
    await _delegate.append(segment);
  }

  @override
  Future<Duration> activeDuration(String sessionId) =>
      _delegate.activeDuration(sessionId);
}
