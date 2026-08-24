import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/time_tracking/application/active_learning_time_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_controller.dart';
import 'package:vocab_learning_app/features/time_tracking/application/focus_timer_rollout.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/focus_timer.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_repository.dart';
import 'package:vocab_learning_app/features/time_tracking/domain/learning_time_segment.dart';

void main() {
  test(
    'focus rollout is implemented-off by default and emergency-off wins',
    () {
      expect(
        const FocusTimerRollout.implementedOff().allowsFocusTimer,
        isFalse,
      );
      expect(const FocusTimerRollout.internal().allowsFocusTimer, isTrue);
      expect(
        const FocusTimerRollout.internal(emergencyOff: true).allowsFocusTimer,
        isFalse,
      );
    },
  );

  test(
    'explicit transitions keep wall time separate from monotonic focus time',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final activeTime = _activeTime(repository, clock);
      final timer = FocusTimerController(timeAuthority: activeTime);
      await activeTime.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      timer.attachSession('session-1');

      clock.advance(const Duration(seconds: 5));
      await timer.start(occurredAtUtc: clock.utc);
      clock
        ..monotonicMicros += const Duration(seconds: 30).inMicroseconds
        ..utc = DateTime.utc(2026, 8, 24, 8, 59, 55);
      await timer.pause(occurredAtUtc: clock.utc);
      clock
        ..monotonicMicros += const Duration(seconds: 2).inMicroseconds
        ..utc = DateTime.utc(2026, 8, 24, 9, 1);
      await timer.resume(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 20));
      await timer.finish(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 3));
      await activeTime.finish(occurredAtUtc: clock.utc);

      expect(timer.snapshot.status, FocusTimerStatus.finished);
      expect(timer.snapshot.activeDuration, const Duration(seconds: 50));
      expect(timer.snapshot.startedAtUtc, DateTime.utc(2026, 8, 24, 9, 0, 5));
      expect(
        timer.snapshot.lastTransitionAtUtc,
        clock.utc.subtract(const Duration(seconds: 3)),
      );
      expect(
        repository.segments.map((segment) => segment.captureSource),
        <LearningTimeCaptureSource>[
          LearningTimeCaptureSource.automaticLesson,
          LearningTimeCaptureSource.focusTimer,
          LearningTimeCaptureSource.automaticLesson,
          LearningTimeCaptureSource.focusTimer,
          LearningTimeCaptureSource.automaticLesson,
        ],
      );
      expect(
        repository.segments.map((segment) => segment.activeDuration),
        <Duration>[
          const Duration(seconds: 5),
          const Duration(seconds: 30),
          const Duration(seconds: 2),
          const Duration(seconds: 20),
          const Duration(seconds: 3),
        ],
      );
    },
  );

  test('background pauses focus and excludes the suspended interval', () async {
    final repository = _MemoryRepository();
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final activeTime = _activeTime(repository, clock);
    final timer = FocusTimerController(timeAuthority: activeTime);
    await activeTime.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
    timer.attachSession('session-1');
    clock.advance(const Duration(seconds: 1));
    await timer.start(occurredAtUtc: clock.utc);
    clock.advance(const Duration(seconds: 10));

    final background = activeTime.observe(clock.utc);
    await timer.pauseForBackgroundObserved(background);
    await activeTime.pauseObserved(background);
    clock.advance(const Duration(hours: 1));
    await activeTime.resume(occurredAtUtc: clock.utc);
    clock.advance(const Duration(seconds: 5));
    await timer.resume(occurredAtUtc: clock.utc);
    clock.advance(const Duration(seconds: 2));
    await timer.finish(occurredAtUtc: clock.utc);
    await activeTime.finish(occurredAtUtc: clock.utc);

    expect(timer.snapshot.status, FocusTimerStatus.finished);
    expect(timer.snapshot.activeDuration, const Duration(seconds: 12));
    expect(timer.snapshot.pauseReason, FocusTimerPauseReason.processBackground);
    expect(
      await repository.activeDuration('session-1'),
      const Duration(seconds: 18),
    );
    expect(
      repository.segments.any(
        (segment) => segment.activeDuration >= const Duration(hours: 1),
      ),
      isFalse,
    );
  });

  test(
    'idle time is bounded while interaction resumes the focus interval',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final activeTime = _activeTime(repository, clock);
      final timer = FocusTimerController(timeAuthority: activeTime);
      await activeTime.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      timer.attachSession('session-1');
      await timer.start(occurredAtUtc: clock.utc);

      clock.advance(const Duration(hours: 1));
      await timer.recordInteraction(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 10));
      await timer.finish(occurredAtUtc: clock.utc);
      await activeTime.finish(occurredAtUtc: clock.utc);

      expect(
        timer.snapshot.activeDuration,
        const Duration(minutes: 5, seconds: 10),
      );
      expect(
        repository.segments
            .where(
              (segment) =>
                  segment.captureSource == LearningTimeCaptureSource.focusTimer,
            )
            .every(
              (segment) =>
                  segment.activeDuration <=
                  LearningTimeSegment.maximumActiveDuration,
            ),
        isTrue,
      );
    },
  );

  test(
    'failed transition retries its frozen segment and duplicate finish is inert',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final activeTime = _activeTime(repository, clock);
      final timer = FocusTimerController(timeAuthority: activeTime);
      await activeTime.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
      timer.attachSession('session-1');
      await timer.start(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 10));
      repository.failNextAppend = true;

      await expectLater(
        timer.pause(occurredAtUtc: clock.utc),
        throwsStateError,
      );
      final frozenAttempt = repository.attempts.single;
      clock.advance(const Duration(minutes: 5));
      await timer.pause(occurredAtUtc: clock.utc);
      expect(repository.attempts.last, same(frozenAttempt));
      expect(timer.snapshot.activeDuration, const Duration(seconds: 10));

      await timer.resume(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 5));
      await timer.finish(occurredAtUtc: clock.utc);
      final segmentCount = repository.segments.length;
      await timer.finish(occurredAtUtc: clock.utc);

      expect(repository.segments, hasLength(segmentCount));
      expect(timer.snapshot.activeDuration, const Duration(seconds: 15));
    },
  );

  test('concurrent duplicate finish reuses one accepted transition', () async {
    final repository = _MemoryRepository();
    final clock = _FakeTimeAuthority(
      utc: DateTime.utc(2026, 8, 24, 9),
      monotonicMicros: 0,
    );
    final activeTime = _activeTime(repository, clock);
    final timer = FocusTimerController(timeAuthority: activeTime);
    await activeTime.start(sessionId: 'session-1', occurredAtUtc: clock.utc);
    timer.attachSession('session-1');
    await timer.start(occurredAtUtc: clock.utc);
    clock.advance(const Duration(seconds: 5));

    final first = timer.finish(occurredAtUtc: clock.utc);
    final duplicate = timer.finish(occurredAtUtc: clock.utc);

    expect(duplicate, same(first));
    await Future.wait(<Future<void>>[first, duplicate]);
    expect(timer.snapshot.status, FocusTimerStatus.finished);
    expect(repository.segments, hasLength(1));
  });

  test(
    'restart drops unknown open time and appends after immutable durable segments',
    () async {
      final repository = _MemoryRepository();
      final clock = _FakeTimeAuthority(
        utc: DateTime.utc(2026, 8, 24, 9),
        monotonicMicros: 0,
      );
      final firstAuthority = _activeTime(repository, clock);
      final first = FocusTimerController(timeAuthority: firstAuthority);
      await firstAuthority.start(
        sessionId: 'session-1',
        occurredAtUtc: clock.utc,
      );
      first.attachSession('session-1');
      await first.start(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 10));
      await first.pause(occurredAtUtc: clock.utc);
      final immutable = List<LearningTimeSegment>.of(repository.segments);
      await first.resume(occurredAtUtc: clock.utc);
      clock.advance(const Duration(hours: 1));
      first.dispose();
      firstAuthority.dispose();

      final restartedAuthority = _activeTime(repository, clock);
      final restarted = FocusTimerController(timeAuthority: restartedAuthority);
      await restartedAuthority.start(
        sessionId: 'session-1',
        occurredAtUtc: clock.utc,
      );
      restarted.attachSession('session-1');
      await restarted.start(occurredAtUtc: clock.utc);
      clock.advance(const Duration(seconds: 5));
      await restarted.finish(occurredAtUtc: clock.utc);
      await restartedAuthority.finish(occurredAtUtc: clock.utc);

      expect(repository.segments.take(immutable.length), immutable);
      expect(restarted.snapshot.activeDuration, const Duration(seconds: 5));
      expect(
        await repository.activeDuration('session-1'),
        const Duration(seconds: 15),
      );
      expect(
        repository.segments.any(
          (segment) => segment.activeDuration >= const Duration(hours: 1),
        ),
        isFalse,
      );
    },
  );
}

ActiveLearningTimeController _activeTime(
  LearningTimeRepository repository,
  _FakeTimeAuthority clock,
) => ActiveLearningTimeController(
  repository: repository,
  monotonicMicros: () => clock.monotonicMicros,
  nowUtc: () => clock.utc,
  timezoneContext: (_) => const LearningTimeZoneContext(
    timezoneId: 'Asia/Bangkok',
    utcOffsetMinutes: 420,
  ),
);

final class _FakeTimeAuthority {
  _FakeTimeAuthority({required this.utc, required this.monotonicMicros});

  DateTime utc;
  int monotonicMicros;

  void advance(Duration duration) {
    monotonicMicros += duration.inMicroseconds;
    utc = utc.add(duration);
  }
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
    final expectedOffset = segments
        .where((candidate) => candidate.sessionId == segment.sessionId)
        .fold<Duration>(
          Duration.zero,
          (total, candidate) => total + candidate.activeDuration,
        );
    if (segment.activeStartOffset != expectedOffset) {
      throw StateError('noncontiguous focus segment');
    }
    segments.add(segment);
  }

  @override
  Future<Duration> activeDuration(String sessionId) async => segments
      .where((segment) => segment.sessionId == sessionId)
      .fold<Duration>(
        Duration.zero,
        (total, segment) => total + segment.activeDuration,
      );
}
