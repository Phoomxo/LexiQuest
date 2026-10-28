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

final class SyncTrigger {
  SyncTrigger(this._run);

  static const int maxAutomaticRuns = 3;

  final SyncRunner _run;
  Future<SyncRunResult>? _running;
  bool _followUpRequested = false;

  Future<SyncRunResult> request(SyncTriggerReason reason) {
    _followUpRequested = true;
    return _running ??= _runUntilSettled().whenComplete(() {
      _running = null;
    });
  }

  Future<SyncRunResult> _runUntilSettled() async {
    SyncRunResult? last;
    var runs = 0;
    var pushed = 0;
    var pulled = 0;
    var conflicts = 0;
    var failures = 0;
    var retryFailure = false;
    while (_followUpRequested) {
      _followUpRequested = false;
      last = await _run();
      runs++;
      pushed += last.pushed;
      pulled += last.pulled;
      conflicts += last.conflicts;
      failures += last.failures;
      retryFailure =
          retryFailure || (last.failures > 0 && last.retryRecommended);
      if (last.hasMoreWork && runs < maxAutomaticRuns) {
        _followUpRequested = true;
      }
    }
    final finalRun = last!;
    return SyncRunResult(
      status: failures > 0 ? SyncRunStatus.partialFailure : finalRun.status,
      pushed: pushed,
      pulled: pulled,
      conflicts: conflicts,
      failures: failures,
      retryRecommended: retryFailure || finalRun.retryRecommended,
      hasMoreWork: finalRun.hasMoreWork,
    );
  }
}
