import 'dart:async';

import 'sync_engine.dart';

enum SyncTriggerReason {
  startup,
  localMutation,
  accountBinding,
  appResume,
  manualRetry,
  backgroundWork,
}

typedef SyncRunner = Future<SyncRunResult> Function();
typedef SyncTriggerDelay = Future<void> Function(Duration delay);

final class SyncTrigger {
  SyncTrigger(
    this._run, {
    this.retryDelay = _defaultRetryDelay,
    this.retryInterval = const Duration(milliseconds: 100),
    this.maxGateWait = const Duration(seconds: 30),
  }) {
    if (retryInterval <= Duration.zero) {
      throw ArgumentError.value(retryInterval, 'retryInterval');
    }
    if (maxGateWait < Duration.zero) {
      throw ArgumentError.value(maxGateWait, 'maxGateWait');
    }
  }

  final SyncRunner _run;
  final SyncTriggerDelay retryDelay;
  final Duration retryInterval;
  final Duration maxGateWait;
  Future<SyncRunResult>? _running;
  Future<void>? _disposeFuture;
  final Completer<void> _disposeSignal = Completer<void>();
  var _requestGeneration = 0;
  var _disposed = false;

  Future<SyncRunResult> request(
    SyncTriggerReason reason, {
    Future<void>? cancelled,
  }) {
    if (_disposed) {
      return Future<SyncRunResult>.error(
        StateError('SyncTrigger has been disposed'),
      );
    }
    _requestGeneration += 1;
    return _running ??= _runUntilSettled(cancelled).whenComplete(() {
      _running = null;
    });
  }

  void requestDetached(SyncTriggerReason reason, {Future<void>? cancelled}) {
    unawaited(
      request(
        reason,
        cancelled: cancelled,
      ).then<void>((_) {}, onError: (Object _, StackTrace _) {}),
    );
  }

  Future<void> dispose() {
    final existing = _disposeFuture;
    if (existing != null) return existing;
    _disposed = true;
    if (!_disposeSignal.isCompleted) _disposeSignal.complete();
    final disposal = _drainActiveRun();
    _disposeFuture = disposal;
    return disposal;
  }

  Future<void> _drainActiveRun() async {
    final active = _running;
    if (active == null) return;
    try {
      await active;
    } catch (_) {
      // Awaited callers retain the run failure; lifecycle cleanup is complete.
    }
  }

  Future<SyncRunResult> _runUntilSettled(Future<void>? cancelled) async {
    SyncRunResult? last;
    var waited = Duration.zero;
    while (true) {
      final generationAtRunStart = _requestGeneration;
      last = await _run();
      if (_disposed) return last;
      if (last.status != SyncRunStatus.alreadyRunning) {
        if (_requestGeneration > generationAtRunStart) continue;
        return last;
      }
      if (waited >= maxGateWait) return last;

      final delay = retryDelay(retryInterval);
      final stopWaiting = await Future.any<bool>(<Future<bool>>[
        delay.then((_) => false),
        ?cancelled?.then((_) => true),
        _disposeSignal.future.then((_) => true),
      ]);
      if (stopWaiting) return last;
      waited += retryInterval;
    }
  }
}

Future<void> _defaultRetryDelay(Duration delay) => Future<void>.delayed(delay);
