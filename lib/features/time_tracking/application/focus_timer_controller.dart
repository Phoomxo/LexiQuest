import 'dart:async';

import 'package:flutter/foundation.dart';

import '../domain/focus_timer.dart';
import '../domain/learning_time_segment.dart';
import 'active_learning_time_controller.dart';

final class FocusTimerController extends ChangeNotifier {
  FocusTimerController({required this.timeAuthority});

  final ActiveLearningTimeController timeAuthority;

  FocusTimerStatus _status = FocusTimerStatus.notStarted;
  FocusTimerPauseReason? _pauseReason;
  String? _sessionId;
  DateTime? _startedAtUtc;
  DateTime? _lastTransitionAtUtc;
  int _completedActiveMicros = 0;
  int? _openMonotonicMicros;
  int? _lastInteractionMonotonicMicros;
  _PendingFocusTransition? _pending;
  Future<void>? _pendingTransitionFuture;
  Future<void> _mutationTail = Future<void>.value();
  bool _disposed = false;

  FocusTimerSnapshot get snapshot {
    final activeMicros = _completedActiveMicros + _openActiveMicrosNow();
    return FocusTimerSnapshot(
      status: _status,
      sessionId: _sessionId,
      startedAtUtc: _startedAtUtc,
      lastTransitionAtUtc: _lastTransitionAtUtc,
      activeDuration: Duration(microseconds: activeMicros),
      pauseReason: _pauseReason,
    );
  }

  void attachSession(String sessionId) {
    _requireNotDisposed();
    if (_status != FocusTimerStatus.notStarted || _sessionId != null) {
      throw StateError('focus timer is already attached');
    }
    if (sessionId.isEmpty ||
        sessionId != sessionId.trim() ||
        sessionId.runes.length > 256) {
      throw ArgumentError.value(sessionId, 'sessionId', 'must be canonical');
    }
    if (timeAuthority.sessionId != sessionId ||
        timeAuthority.state == ActiveLearningTimeState.inactive) {
      throw StateError('focus timer requires the active lesson time authority');
    }
    _sessionId = sessionId;
  }

  Future<void> start({required DateTime occurredAtUtc}) {
    try {
      return startObserved(timeAuthority.observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> startObserved(LearningTimeObservation occurrence) =>
      _requestTransition(_FocusTransitionKind.start, occurrence);

  Future<void> pause({required DateTime occurredAtUtc}) {
    try {
      final occurrence = timeAuthority.observe(occurredAtUtc);
      return _requestTransition(
        _FocusTransitionKind.pause,
        occurrence,
        pauseReason: FocusTimerPauseReason.explicit,
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> pauseObserved(LearningTimeObservation occurrence) =>
      _requestTransition(
        _FocusTransitionKind.pause,
        occurrence,
        pauseReason: FocusTimerPauseReason.explicit,
      );

  Future<void> pauseForBackgroundObserved(LearningTimeObservation occurrence) =>
      _requestTransition(
        _FocusTransitionKind.pause,
        occurrence,
        pauseReason: FocusTimerPauseReason.processBackground,
      );

  Future<void> pauseForFeatureDisabled({required DateTime occurredAtUtc}) {
    try {
      return _requestTransition(
        _FocusTransitionKind.pause,
        timeAuthority.observe(occurredAtUtc),
        pauseReason: FocusTimerPauseReason.featureDisabled,
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> pauseForFeatureDisabledObserved(
    LearningTimeObservation occurrence,
  ) => _requestTransition(
    _FocusTransitionKind.pause,
    occurrence,
    pauseReason: FocusTimerPauseReason.featureDisabled,
  );

  Future<void> resume({required DateTime occurredAtUtc}) {
    try {
      return resumeObserved(timeAuthority.observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> resumeObserved(LearningTimeObservation occurrence) =>
      _requestTransition(_FocusTransitionKind.resume, occurrence);

  Future<void> finish({required DateTime occurredAtUtc}) {
    try {
      if (_status == FocusTimerStatus.finished && _pending == null) {
        return Future<void>.value();
      }
      return _requestTransition(
        _FocusTransitionKind.finish,
        timeAuthority.observe(occurredAtUtc),
      );
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> finishObserved(LearningTimeObservation occurrence) {
    if (_status == FocusTimerStatus.notStarted ||
        _status == FocusTimerStatus.finished) {
      return Future<void>.value();
    }
    return _requestTransition(_FocusTransitionKind.finish, occurrence);
  }

  Future<void> recordInteraction({required DateTime occurredAtUtc}) {
    try {
      return recordInteractionObserved(timeAuthority.observe(occurredAtUtc));
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  Future<void> recordInteractionObserved(LearningTimeObservation occurrence) =>
      _serialize(() async {
        final pending = _pending;
        if (pending != null) await _executePending(pending);
        if (_status != FocusTimerStatus.running) return;
        await timeAuthority.recordInteractionObserved(occurrence);
        _recordInteraction(occurrence.monotonicMicros);
        _notifyChanged();
      });

  bool get hasFailedEntryIntent {
    final pending = _pending;
    return _pendingTransitionFuture == null &&
        pending != null &&
        (pending.kind == _FocusTransitionKind.start ||
            pending.kind == _FocusTransitionKind.resume);
  }

  Future<bool> supersedeFailedEntryObserved(
    LearningTimeObservation boundary, {
    FocusTimerPauseReason? pauseReason,
  }) {
    try {
      _requireNotDisposed();
      return _serialize(() {
        final pending = _pending;
        if (pending == null ||
            (pending.kind != _FocusTransitionKind.start &&
                pending.kind != _FocusTransitionKind.resume)) {
          return false;
        }
        if (_pendingTransitionFuture != null) {
          throw StateError('cannot supersede an in-flight focus transition');
        }
        _pending = null;
        if (_status == FocusTimerStatus.paused && pauseReason != null) {
          _lastTransitionAtUtc = boundary.occurredAtUtc;
          _pauseReason = pauseReason;
        }
        _notifyChanged();
        return true;
      });
    } catch (error, stackTrace) {
      return Future<bool>.error(error, stackTrace);
    }
  }

  Future<void> _requestTransition(
    _FocusTransitionKind kind,
    LearningTimeObservation occurrence, {
    FocusTimerPauseReason? pauseReason,
  }) {
    try {
      _requireNotDisposed();
      final existing = _pending;
      if (existing != null &&
          (existing.kind != kind || existing.pauseReason != pauseReason)) {
        throw StateError('the exact failed focus transition must be retried');
      }
      if (existing != null) {
        final inFlight = _pendingTransitionFuture;
        if (inFlight != null) return inFlight;
      }
      final pending =
          existing ??
          _freezeTransition(kind, occurrence, pauseReason: pauseReason);
      _pending = pending;
      late final Future<void> future;
      future = _serialize(() => _executePending(pending)).whenComplete(() {
        if (identical(_pendingTransitionFuture, future)) {
          _pendingTransitionFuture = null;
        }
      });
      _pendingTransitionFuture = future;
      return future;
    } catch (error, stackTrace) {
      return Future<void>.error(error, stackTrace);
    }
  }

  _PendingFocusTransition _freezeTransition(
    _FocusTransitionKind kind,
    LearningTimeObservation occurrence, {
    FocusTimerPauseReason? pauseReason,
  }) {
    if (_sessionId == null) {
      throw StateError('focus timer is not attached to a lesson session');
    }
    switch (kind) {
      case _FocusTransitionKind.start:
        if (_status != FocusTimerStatus.notStarted) {
          throw StateError('focus timer has already started');
        }
        break;
      case _FocusTransitionKind.pause:
        if (_status == FocusTimerStatus.paused) {
          return _PendingFocusTransition.noOp(
            kind: kind,
            occurrence: occurrence,
            pauseReason: pauseReason ?? _pauseReason,
          );
        }
        if (_status != FocusTimerStatus.running) {
          throw StateError('focus timer is not running');
        }
        break;
      case _FocusTransitionKind.resume:
        if (_status != FocusTimerStatus.paused) {
          throw StateError('focus timer is not paused');
        }
        break;
      case _FocusTransitionKind.finish:
        if (_status == FocusTimerStatus.finished) {
          return _PendingFocusTransition.noOp(
            kind: kind,
            occurrence: occurrence,
          );
        }
        if (_status != FocusTimerStatus.running &&
            _status != FocusTimerStatus.paused) {
          throw StateError('focus timer has not started');
        }
        break;
    }
    return _PendingFocusTransition(
      kind: kind,
      occurrence: occurrence,
      pauseReason: pauseReason,
      noOp: false,
    );
  }

  Future<void> _executePending(_PendingFocusTransition pending) async {
    if (!identical(_pending, pending)) {
      throw StateError('focus transition identity changed');
    }
    if (!pending.noOp) {
      switch (pending.kind) {
        case _FocusTransitionKind.start || _FocusTransitionKind.resume:
          if (timeAuthority.state == ActiveLearningTimeState.paused) {
            throw StateError('cannot run focus while the lesson is paused');
          }
          await timeAuthority.transitionCaptureSourceObserved(
            LearningTimeCaptureSource.focusTimer,
            pending.occurrence,
          );
          break;
        case _FocusTransitionKind.pause || _FocusTransitionKind.finish:
          if (_status == FocusTimerStatus.running) {
            if (timeAuthority.state == ActiveLearningTimeState.active) {
              await timeAuthority.transitionCaptureSourceObserved(
                LearningTimeCaptureSource.automaticLesson,
                pending.occurrence,
              );
            } else if (timeAuthority.state == ActiveLearningTimeState.idle ||
                timeAuthority.state == ActiveLearningTimeState.paused) {
              await timeAuthority.selectCaptureSourceWhileSuspended(
                LearningTimeCaptureSource.automaticLesson,
              );
            } else {
              throw StateError('lesson time authority is unavailable');
            }
          }
          break;
      }
    }
    _applyTransition(pending);
    _pending = null;
    _notifyChanged();
  }

  void _applyTransition(_PendingFocusTransition pending) {
    final occurredAtUtc = pending.occurrence.occurredAtUtc;
    final monotonicMicros = pending.occurrence.monotonicMicros;
    switch (pending.kind) {
      case _FocusTransitionKind.start:
        _startedAtUtc ??= occurredAtUtc;
        _lastTransitionAtUtc = occurredAtUtc;
        _openAt(monotonicMicros);
        _status = FocusTimerStatus.running;
        break;
      case _FocusTransitionKind.pause:
        if (_status == FocusTimerStatus.running) {
          _freezeOpen(monotonicMicros);
        }
        _lastTransitionAtUtc = occurredAtUtc;
        _pauseReason = pending.pauseReason ?? FocusTimerPauseReason.explicit;
        _status = FocusTimerStatus.paused;
        break;
      case _FocusTransitionKind.resume:
        _lastTransitionAtUtc = occurredAtUtc;
        _openAt(monotonicMicros);
        _status = FocusTimerStatus.running;
        break;
      case _FocusTransitionKind.finish:
        if (_status == FocusTimerStatus.running) {
          _freezeOpen(monotonicMicros);
        }
        _lastTransitionAtUtc = occurredAtUtc;
        _status = FocusTimerStatus.finished;
        break;
    }
  }

  void _recordInteraction(int monotonicMicros) {
    final open = _openMonotonicMicros;
    final last = _lastInteractionMonotonicMicros;
    if (open == null || last == null || monotonicMicros < open) {
      throw StateError('focus timer monotonic anchor is invalid');
    }
    final idleDeadline = last + timeAuthority.idleTimeout.inMicroseconds;
    if (monotonicMicros > idleDeadline) {
      _completedActiveMicros += idleDeadline - open;
      _openAt(monotonicMicros);
      return;
    }
    _lastInteractionMonotonicMicros = monotonicMicros;
  }

  void _openAt(int monotonicMicros) {
    _openMonotonicMicros = monotonicMicros;
    _lastInteractionMonotonicMicros = monotonicMicros;
  }

  void _freezeOpen(int monotonicMicros) {
    final open = _openMonotonicMicros;
    final last = _lastInteractionMonotonicMicros;
    if (open == null || last == null || monotonicMicros < open) {
      throw StateError('focus timer monotonic anchor is invalid');
    }
    final idleDeadline = last + timeAuthority.idleTimeout.inMicroseconds;
    final trustworthyEnd = monotonicMicros < idleDeadline
        ? monotonicMicros
        : idleDeadline;
    _completedActiveMicros += trustworthyEnd - open;
    _openMonotonicMicros = null;
    _lastInteractionMonotonicMicros = null;
  }

  int _openActiveMicrosNow() {
    if (_status != FocusTimerStatus.running) return 0;
    final open = _openMonotonicMicros;
    final last = _lastInteractionMonotonicMicros;
    if (open == null || last == null) return 0;
    final now = timeAuthority.monotonicMicros();
    if (now <= open) return 0;
    final idleDeadline = last + timeAuthority.idleTimeout.inMicroseconds;
    final trustworthyEnd = now < idleDeadline ? now : idleDeadline;
    return trustworthyEnd > open ? trustworthyEnd - open : 0;
  }

  Future<T> _serialize<T>(FutureOr<T> Function() operation) {
    final result = Completer<T>();
    _mutationTail = _mutationTail.then((_) async {
      try {
        _requireNotDisposed();
        result.complete(await operation());
      } catch (error, stackTrace) {
        result.completeError(error, stackTrace);
      }
    });
    return result.future;
  }

  void _requireNotDisposed() {
    if (_disposed) throw StateError('focus timer is disposed');
  }

  void _notifyChanged() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    super.dispose();
  }
}

enum _FocusTransitionKind { start, pause, resume, finish }

final class _PendingFocusTransition {
  const _PendingFocusTransition({
    required this.kind,
    required this.occurrence,
    required this.pauseReason,
    required this.noOp,
  });

  const _PendingFocusTransition.noOp({
    required this.kind,
    required this.occurrence,
    this.pauseReason,
  }) : noOp = true;

  final _FocusTransitionKind kind;
  final LearningTimeObservation occurrence;
  final FocusTimerPauseReason? pauseReason;
  final bool noOp;
}
