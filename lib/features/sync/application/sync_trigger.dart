import 'sync_engine.dart';

enum SyncTriggerReason {
  localMutation,
  accountBinding,
  appResume,
  manualRetry,
  backgroundWork,
}

typedef SyncRunner = Future<SyncRunResult> Function();

final class SyncTrigger {
  SyncTrigger(this._run);

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
    while (_followUpRequested) {
      _followUpRequested = false;
      last = await _run();
    }
    return last!;
  }
}
