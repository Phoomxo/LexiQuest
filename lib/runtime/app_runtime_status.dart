enum RuntimeAvailability { ready, degraded, unavailable }

final class AppRuntimeStatus {
  const AppRuntimeStatus({
    required this.localData,
    required this.firebase,
    required this.supabase,
    required this.backends,
  });

  final RuntimeAvailability localData;
  final RuntimeAvailability firebase;
  final RuntimeAvailability supabase;
  final RuntimeAvailability backends;

  bool get isFullyReady {
    return localData == RuntimeAvailability.ready &&
        firebase == RuntimeAvailability.ready &&
        supabase == RuntimeAvailability.ready &&
        backends == RuntimeAvailability.ready;
  }

  @override
  String toString() => 'AppRuntimeStatus';
}
