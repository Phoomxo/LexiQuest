enum RuntimeAvailability { ready, degraded, unavailable }

final class AppRuntimeStatus {
  const AppRuntimeStatus({
    required this.localData,
    required this.firebase,
    required this.backends,
    this.supabase = RuntimeAvailability.ready,
  });

  final RuntimeAvailability localData;
  final RuntimeAvailability firebase;
  final RuntimeAvailability backends;

  /// Supabase is no longer on the critical path. It defaults to [ready]
  /// when not initialized, so its status never blocks [isFullyReady].
  final RuntimeAvailability supabase;

  bool get isFullyReady {
    return localData == RuntimeAvailability.ready &&
        firebase == RuntimeAvailability.ready &&
        backends == RuntimeAvailability.ready;
  }

  @override
  String toString() => 'AppRuntimeStatus';
}
