import 'dart:async';

import '../domain/learning_time_repository.dart';
import '../domain/learning_time_segment.dart';

typedef LearningTimeMonotonicMicros = int Function();
typedef LearningTimeUtcNow = DateTime Function();
typedef LearningTimeZoneContextProvider =
    LearningTimeZoneContext Function(DateTime occurredAtUtc);
typedef LearningTimeIdleCancellation = void Function();
typedef LearningTimeIdleScheduler =
    LearningTimeIdleCancellation Function(
      Duration delay,
      FutureOr<void> Function() callback,
    );
typedef ActiveLearningTimeControllerFactory =
    ActiveLearningTimeController Function();

enum ActiveLearningTimeState { inactive, active, paused, idle, finished }

final class ActiveLearningTimeController {
  ActiveLearningTimeController({
    required this.repository,
    required this.monotonicMicros,
    required this.nowUtc,
    required this.timezoneContext,
    this.idleTimeout = const Duration(minutes: 5),
    LearningTimeIdleScheduler? scheduleIdle,
  }) : scheduleIdle = scheduleIdle ?? _systemIdleScheduler {
    if (idleTimeout <= Duration.zero) {
      throw ArgumentError.value(idleTimeout, 'idleTimeout', 'must be positive');
    }
    if (idleTimeout > LearningTimeSegment.maximumActiveDuration) {
      throw ArgumentError.value(
        idleTimeout,
        'idleTimeout',
        'must not exceed five minutes',
      );
    }
  }

  final LearningTimeRepository repository;
  final LearningTimeMonotonicMicros monotonicMicros;
  final LearningTimeUtcNow nowUtc;
  final LearningTimeZoneContextProvider timezoneContext;
  final Duration idleTimeout;
  final LearningTimeIdleScheduler scheduleIdle;

  ActiveLearningTimeState _state = ActiveLearningTimeState.inactive;
  String? _sessionId;
  Duration _activeOffset = Duration.zero;
  _OpenLearningTimeSegment? _open;
  int? _lastInteractionMonotonicMicros;
  _PendingLearningTimeClose? _pending;
  LearningTimeIdleCancellation? _cancelIdle;
  Future<void> _mutationTail = Future<void>.value();
  Object? _lastIdleFailure;
  bool _disposed = false;
  int _idleGeneration = 0;
  final Object _observationAuthority = Object();

  ActiveLearningTimeState get state => _state;
  String? get sessionId => _sessionId;
  Object? get lastIdleFailure => _lastIdleFailure;
  LearningTimeCaptureSource get captureSource => _captureSource;

  LearningTimeCaptureSource _captureSource =
      LearningTimeCaptureSource.automaticLesson;

  Future<void> start({
    required String sessionId,
    required DateTime occurredAtUtc,
  }) {
    try {
      _requireId(sessionId);
      final occurrence = observe(occurredAtUtc);
      return _serialize(() async {
        if (_state != ActiveLearningTimeState.inactive) {
          if (_state == ActiveLearningTimeState.active &&
              _sessionId == sessionId) {
            return;
          }
          throw StateError('active learning-time capture has already started');
        }
        final activeOffset = await repository.activeDuration(sessionId);
        _requireNotDisposed();
        _sessionId = sessionId;
        _activeOffset = activeOffset;
        _openAt(occurrence);
        _state = ActiveLearningTimeState.active;
        _armIdleTimer();
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> pause({required DateTime occurredAtUtc}) {
    try {
      return pauseObserved(observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> pauseObserved(LearningTimeObservation occurrence) {
    try {
      _requireObservation(occurrence);
      return _serialize(() async {
        if (_state == ActiveLearningTimeState.paused && _pending == null) {
          return;
        }
        if (_state == ActiveLearningTimeState.idle && _pending == null) {
          _state = ActiveLearningTimeState.paused;
          return;
        }
        await _close(occurrence, ActiveLearningTimeState.paused);
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> resume({required DateTime occurredAtUtc}) {
    try {
      return resumeObserved(observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> resumeObserved(LearningTimeObservation occurrence) {
    try {
      _requireObservation(occurrence);
      return _serialize(() {
        if (_state == ActiveLearningTimeState.active) {
          _armIdleTimer();
          return;
        }
        if (_state != ActiveLearningTimeState.paused) {
          throw StateError('learning-time capture is not paused');
        }
        _openAt(occurrence);
        _state = ActiveLearningTimeState.active;
        _armIdleTimer();
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> recordInteraction({required DateTime occurredAtUtc}) {
    try {
      return recordInteractionObserved(observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> recordInteractionObserved(LearningTimeObservation occurrence) {
    try {
      _requireObservation(occurrence);
      return _serialize(
        () => _recordInteractionObserved(
          occurrence,
          resumePausedAutomaticCapture: false,
        ),
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> recordAutomaticInteractionObserved(
    LearningTimeObservation occurrence,
  ) {
    try {
      _requireObservation(occurrence);
      return _serialize(
        () => _recordInteractionObserved(
          occurrence,
          resumePausedAutomaticCapture: true,
        ),
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> transitionCaptureSource({
    required LearningTimeCaptureSource captureSource,
    required DateTime occurredAtUtc,
  }) {
    try {
      return transitionCaptureSourceObserved(
        captureSource,
        observe(occurredAtUtc),
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> transitionCaptureSourceObserved(
    LearningTimeCaptureSource captureSource,
    LearningTimeObservation occurrence,
  ) {
    try {
      _requireObservation(occurrence);
      return _serialize(() async {
        final pending = _pending;
        if (pending != null) await _commitPending(pending);
        if (_state == ActiveLearningTimeState.idle) {
          _captureSource = captureSource;
          _openAt(occurrence);
          _state = ActiveLearningTimeState.active;
          _armIdleTimer();
          return;
        }
        if (_state != ActiveLearningTimeState.active &&
            !(_state == ActiveLearningTimeState.paused && pending != null)) {
          throw StateError('learning-time capture is not active');
        }
        if (_state == ActiveLearningTimeState.active &&
            _captureSource == captureSource) {
          _requireMonotonicNotBeforeOpen(occurrence.monotonicMicros);
          _lastInteractionMonotonicMicros = occurrence.monotonicMicros;
          _armIdleTimer();
          return;
        }
        if (_state == ActiveLearningTimeState.active) {
          await _close(occurrence, ActiveLearningTimeState.paused);
        }
        _captureSource = captureSource;
        _openAt(occurrence);
        _state = ActiveLearningTimeState.active;
        _armIdleTimer();
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> selectCaptureSourceWhileSuspended(
    LearningTimeCaptureSource captureSource,
  ) {
    try {
      return _serialize(() async {
        final pending = _pending;
        if (pending != null) await _commitPending(pending);
        if (_state != ActiveLearningTimeState.paused &&
            _state != ActiveLearningTimeState.idle) {
          throw StateError('learning-time capture is not suspended');
        }
        _captureSource = captureSource;
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> settleCaptureSourceWithoutInteraction(
    LearningTimeCaptureSource captureSource,
  ) {
    try {
      return _serialize(() async {
        final pending = _pending;
        if (pending != null) await _commitPending(pending);
        if (_state == ActiveLearningTimeState.active) {
          if (_captureSource != captureSource) {
            throw StateError(
              'an active capture source requires an observed transition',
            );
          }
          return;
        }
        if (_state != ActiveLearningTimeState.paused &&
            _state != ActiveLearningTimeState.idle) {
          throw StateError('learning-time capture cannot settle its source');
        }
        _captureSource = captureSource;
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> finish({required DateTime occurredAtUtc}) {
    try {
      return finishObserved(observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> finishObserved(LearningTimeObservation occurrence) {
    try {
      _requireObservation(occurrence);
      return _serialize(() async {
        if (_state == ActiveLearningTimeState.finished) return;
        if (_state == ActiveLearningTimeState.inactive) {
          throw StateError('learning-time capture has not started');
        }
        if (_state == ActiveLearningTimeState.active || _pending != null) {
          await _close(occurrence, ActiveLearningTimeState.finished);
          return;
        }
        _cancelIdleTimer();
        _state = ActiveLearningTimeState.finished;
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> onIdleTimeout() {
    try {
      final occurrence = observe(nowUtc());
      final anchor = _lastInteractionMonotonicMicros;
      return _serialize(() => _closeIfIdleDeadlineReached(anchor, occurrence));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> restoreAfterFailedTerminal({
    required ActiveLearningTimeState previousState,
    required DateTime occurredAtUtc,
  }) {
    try {
      final occurrence = observe(occurredAtUtc);
      return _serialize(() {
        if (_state != ActiveLearningTimeState.finished || _pending != null) {
          throw StateError('only a completed time close can be restored');
        }
        switch (previousState) {
          case ActiveLearningTimeState.active:
            _openAt(occurrence);
            _state = ActiveLearningTimeState.active;
            _armIdleTimer();
            return;
          case ActiveLearningTimeState.paused:
            _state = ActiveLearningTimeState.paused;
            return;
          case ActiveLearningTimeState.idle:
            _state = ActiveLearningTimeState.idle;
            return;
          case ActiveLearningTimeState.inactive ||
              ActiveLearningTimeState.finished:
            throw StateError('terminal restore source state is invalid');
        }
      });
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _cancelIdleTimer();
  }

  Future<void> _close(
    LearningTimeObservation occurrence,
    ActiveLearningTimeState target,
  ) async {
    if (_state == target && _pending == null) return;
    final existingPending = _pending;
    if (existingPending != null) {
      await _commitPending(existingPending);
      if (_state == target) return;
    }
    if (_state == ActiveLearningTimeState.idle &&
        target != ActiveLearningTimeState.idle) {
      _state = target;
      return;
    }
    if (_state == ActiveLearningTimeState.paused &&
        target == ActiveLearningTimeState.finished) {
      _state = ActiveLearningTimeState.finished;
      return;
    }
    if (_state != ActiveLearningTimeState.active) {
      throw StateError('learning-time capture is not active');
    }
    _cancelIdleTimer();
    final pending = _freezeClose(occurrence, target);
    _pending = pending;
    await _commitPending(pending);
  }

  Future<void> _recordInteractionObserved(
    LearningTimeObservation occurrence, {
    required bool resumePausedAutomaticCapture,
  }) async {
    final pending = _pending;
    if (pending != null) await _commitPending(pending);
    if (_state == ActiveLearningTimeState.idle ||
        (resumePausedAutomaticCapture &&
            _state == ActiveLearningTimeState.paused)) {
      if (resumePausedAutomaticCapture &&
          _captureSource != LearningTimeCaptureSource.automaticLesson) {
        throw StateError(
          'only automatic capture can resume from learner interaction',
        );
      }
      _openAt(occurrence);
      _state = ActiveLearningTimeState.active;
      _armIdleTimer();
      return;
    }
    if (_state != ActiveLearningTimeState.active) return;
    final interactionMonotonicMicros = occurrence.monotonicMicros;
    _requireMonotonicNotBeforeOpen(interactionMonotonicMicros);
    final priorInteractionMonotonicMicros = _lastInteractionMonotonicMicros;
    if (priorInteractionMonotonicMicros == null) {
      throw StateError('active learning-time interaction anchor is missing');
    }
    if (interactionMonotonicMicros >
        priorInteractionMonotonicMicros + idleTimeout.inMicroseconds) {
      await _close(occurrence, ActiveLearningTimeState.idle);
      _openAt(occurrence);
      _state = ActiveLearningTimeState.active;
      _armIdleTimer();
      return;
    }
    _lastInteractionMonotonicMicros = interactionMonotonicMicros;
    await _flushCompleteChunks(
      occurrence: occurrence,
      throughMonotonicMicros: interactionMonotonicMicros,
    );
    _armIdleTimer();
  }

  _PendingLearningTimeClose _freezeClose(
    LearningTimeObservation occurrence,
    ActiveLearningTimeState target,
  ) {
    final open = _open;
    if (open == null) {
      throw StateError('active learning-time anchor is missing');
    }
    final observedMonotonicMicros = occurrence.monotonicMicros;
    _requireMonotonicNotBeforeOpen(observedMonotonicMicros);
    final lastInteraction = _lastInteractionMonotonicMicros;
    if (lastInteraction == null || lastInteraction < open.monotonicMicros) {
      throw StateError('active learning-time interaction anchor is missing');
    }
    final idleBound = lastInteraction + idleTimeout.inMicroseconds;
    final trustworthyEnd = observedMonotonicMicros < idleBound
        ? observedMonotonicMicros
        : idleBound;
    return _freezeSegments(
      totalDurationMs: (trustworthyEnd - open.monotonicMicros) ~/ 1000,
      endedAtUtc: occurrence.occurredAtUtc,
      target: target,
    );
  }

  Future<void> _flushCompleteChunks({
    required LearningTimeObservation occurrence,
    required int throughMonotonicMicros,
  }) async {
    final open = _open;
    if (open == null) {
      throw StateError('active learning-time anchor is missing');
    }
    final elapsedMs = (throughMonotonicMicros - open.monotonicMicros) ~/ 1000;
    final chunkMs = LearningTimeSegment.maximumActiveDuration.inMilliseconds;
    final completeMs = (elapsedMs ~/ chunkMs) * chunkMs;
    if (completeMs == 0) return;
    final reopen = _OpenLearningTimeSegment(
      startedAtUtc: occurrence.occurredAtUtc,
      monotonicMicros: open.monotonicMicros + completeMs * 1000,
      timezone: timezoneContext(occurrence.occurredAtUtc),
    );
    final pending = _freezeSegments(
      totalDurationMs: completeMs,
      endedAtUtc: occurrence.occurredAtUtc,
      target: ActiveLearningTimeState.active,
      reopen: reopen,
      resumedLastInteractionMonotonicMicros: throughMonotonicMicros,
    );
    _pending = pending;
    await _commitPending(pending);
  }

  _PendingLearningTimeClose _freezeSegments({
    required int totalDurationMs,
    required DateTime endedAtUtc,
    required ActiveLearningTimeState target,
    _OpenLearningTimeSegment? reopen,
    int? resumedLastInteractionMonotonicMicros,
  }) {
    final open = _open;
    if (open == null) {
      throw StateError('active learning-time anchor is missing');
    }
    final segments = <LearningTimeSegment>[];
    var consumedMs = 0;
    final maximumMs = LearningTimeSegment.maximumActiveDuration.inMilliseconds;
    while (consumedMs < totalDurationMs) {
      final remainingMs = totalDurationMs - consumedMs;
      final durationMs = remainingMs > maximumMs ? maximumMs : remainingMs;
      segments.add(
        LearningTimeSegment(
          sessionId: _sessionId!,
          activeStartOffset: _activeOffset + Duration(milliseconds: consumedMs),
          activeDuration: Duration(milliseconds: durationMs),
          startedAtUtc: consumedMs == 0 ? open.startedAtUtc : endedAtUtc,
          endedAtUtc: endedAtUtc,
          timezone: consumedMs == 0
              ? open.timezone
              : timezoneContext(endedAtUtc),
          captureSource: _captureSource,
        ),
      );
      consumedMs += durationMs;
    }
    return _PendingLearningTimeClose(
      segments: List<LearningTimeSegment>.unmodifiable(segments),
      target: target,
      reopen: reopen,
      resumedLastInteractionMonotonicMicros:
          resumedLastInteractionMonotonicMicros,
    );
  }

  Future<void> _commitPending(_PendingLearningTimeClose pending) async {
    if (!identical(_pending, pending)) {
      throw StateError('learning-time close identity changed');
    }
    for (final segment in pending.segments) {
      await repository.append(segment);
    }
    _activeOffset += Duration(
      milliseconds: pending.segments.fold<int>(
        0,
        (sum, segment) => sum + segment.activeDuration.inMilliseconds,
      ),
    );
    _pending = null;
    _open = pending.reopen;
    _lastInteractionMonotonicMicros =
        pending.resumedLastInteractionMonotonicMicros;
    _state = pending.target;
  }

  void _openAt(LearningTimeObservation occurrence) {
    _open = _OpenLearningTimeSegment(
      startedAtUtc: occurrence.occurredAtUtc,
      monotonicMicros: occurrence.monotonicMicros,
      timezone: timezoneContext(occurrence.occurredAtUtc),
    );
    _lastInteractionMonotonicMicros = occurrence.monotonicMicros;
  }

  void _requireMonotonicNotBeforeOpen(int value) {
    final open = _open;
    if (open == null) {
      throw StateError('active learning-time anchor is missing');
    }
    if (value < open.monotonicMicros) {
      throw StateError('monotonic learning-time clock moved backwards');
    }
  }

  void _armIdleTimer() {
    final anchor = _lastInteractionMonotonicMicros;
    if (_disposed || anchor == null) return;
    _scheduleIdleTimer(idleTimeout, anchor);
  }

  void _scheduleIdleTimer(Duration delay, int anchor) {
    _cancelIdleTimer();
    final generation = ++_idleGeneration;
    _cancelIdle = scheduleIdle(delay, () async {
      try {
        final occurrence = observe(nowUtc());
        await _serialize(() async {
          if (_disposed ||
              generation != _idleGeneration ||
              anchor != _lastInteractionMonotonicMicros) {
            return;
          }
          await _closeIfIdleDeadlineReached(anchor, occurrence);
        });
      } catch (error) {
        _lastIdleFailure = error;
      }
    });
  }

  Future<void> _closeIfIdleDeadlineReached(
    int? anchor,
    LearningTimeObservation occurrence,
  ) async {
    if (_state != ActiveLearningTimeState.active ||
        anchor == null ||
        anchor != _lastInteractionMonotonicMicros) {
      return;
    }
    final remainingMicros =
        anchor + idleTimeout.inMicroseconds - occurrence.monotonicMicros;
    if (remainingMicros > 0) {
      _scheduleIdleTimer(Duration(microseconds: remainingMicros), anchor);
      return;
    }
    await _close(occurrence, ActiveLearningTimeState.idle);
  }

  void _cancelIdleTimer() {
    _idleGeneration += 1;
    _cancelIdle?.call();
    _cancelIdle = null;
  }

  Future<void> _serialize(FutureOr<void> Function() operation) {
    final result = Completer<void>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        _requireNotDisposed();
        await operation();
        result.complete();
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('active learning-time capture is disposed');
  }

  LearningTimeObservation observe(DateTime occurredAtUtc) {
    _requireNotDisposed();
    _requireUtc(occurredAtUtc, 'occurredAtUtc');
    final monotonic = monotonicMicros();
    if (monotonic < 0) {
      throw StateError('monotonic learning-time clock must be nonnegative');
    }
    return LearningTimeObservation._(
      authority: _observationAuthority,
      occurredAtUtc: occurredAtUtc,
      monotonicMicros: monotonic,
    );
  }

  void _requireObservation(LearningTimeObservation occurrence) {
    _requireNotDisposed();
    if (!identical(occurrence.authority, _observationAuthority)) {
      throw ArgumentError.value(
        occurrence,
        'occurrence',
        'must come from this learning-time authority',
      );
    }
  }

  void _requireUtc(DateTime value, String field) {
    if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
      throw ArgumentError.value(value, field, 'must be nonnegative UTC');
    }
  }

  void _requireId(String value) {
    if (value.isEmpty || value != value.trim() || value.runes.length > 256) {
      throw ArgumentError.value(value, 'sessionId', 'must be canonical text');
    }
  }
}

final class LearningTimeObservation {
  const LearningTimeObservation._({
    required this.authority,
    required this.occurredAtUtc,
    required this.monotonicMicros,
  });

  final Object authority;
  final DateTime occurredAtUtc;
  final int monotonicMicros;
}

final class _OpenLearningTimeSegment {
  const _OpenLearningTimeSegment({
    required this.startedAtUtc,
    required this.monotonicMicros,
    required this.timezone,
  });

  final DateTime startedAtUtc;
  final int monotonicMicros;
  final LearningTimeZoneContext timezone;
}

final class _PendingLearningTimeClose {
  const _PendingLearningTimeClose({
    required this.segments,
    required this.target,
    required this.reopen,
    required this.resumedLastInteractionMonotonicMicros,
  });

  final List<LearningTimeSegment> segments;
  final ActiveLearningTimeState target;
  final _OpenLearningTimeSegment? reopen;
  final int? resumedLastInteractionMonotonicMicros;
}

LearningTimeIdleCancellation _systemIdleScheduler(
  Duration delay,
  FutureOr<void> Function() callback,
) {
  final timer = Timer(delay, () => unawaited(Future<void>.sync(callback)));
  return timer.cancel;
}
