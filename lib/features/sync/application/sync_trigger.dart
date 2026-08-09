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
  bool _followUpRequested = false;

  Future<SyncRunResult> request(
    SyncTriggerReason reason, {
    Future<void>? cancelled,
  }) {
    _followUpRequested = true;
    return _running ??= _runUntilSettled(cancelled).whenComplete(() {
      _running = null;
    });
  }

  Future<SyncRunResult> _runUntilSettled(Future<void>? cancelled) async {
    SyncRunResult? last;
    var waited = Duration.zero;
    while (_followUpRequested) {
      _followUpRequested = false;
      while (true) {
        last = await _run();
        if (last.status != SyncRunStatus.alreadyRunning) break;
        if (waited >= maxGateWait) return last;

        final delay = retryDelay(retryInterval);
        if (cancelled == null) {
          await delay;
        } else {
          final wasCancelled = await Future.any<bool>(<Future<bool>>[
            delay.then((_) => false),
            cancelled.then((_) => true),
          ]);
          if (wasCancelled) return last;
        }
        waited += retryInterval;
      }
    }
    return last!;
  }
}

Future<void> _defaultRetryDelay(Duration delay) => Future<void>.delayed(delay);
