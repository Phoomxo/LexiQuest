class ResponseTimeTracker {
  Stopwatch? _stopwatch;

  void startTiming() {
    _stopwatch = Stopwatch()..start();
  }

  int stopTimingMs() {
    if (_stopwatch == null) return 0;
    _stopwatch!.stop();
    final elapsed = _stopwatch!.elapsedMilliseconds;
    _stopwatch = null;
    return elapsed;
  }

  /// Classifies response hesitation based on threshold (default 5000 ms = 5s).
  static bool isHesitantResponse(int elapsedMs, {int thresholdMs = 5000}) {
    return elapsedMs >= thresholdMs;
  }
}
