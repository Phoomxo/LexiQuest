enum RuntimeAvailability { ready, degraded, unavailable }

final class AppRuntimeStatus {
  const AppRuntimeStatus({
    required this.localData,
    required this.firebase,
    required this.backends,
    this.supabase = RuntimeAvailability.ready,
    this.aiTutor = RuntimeAvailability.ready,
    this.voice = RuntimeAvailability.ready,
  });

  final RuntimeAvailability localData;
  final RuntimeAvailability firebase;
  final RuntimeAvailability backends;

  /// Actual composed application capabilities. These are intentionally
  /// independent from [backends]: BYOK AI and on-device speech remain usable
  /// when optional Cloud configuration is absent.
  final RuntimeAvailability aiTutor;
  final RuntimeAvailability voice;

  /// Supabase is no longer on the critical path. It defaults to [ready]
  /// when not initialized, so its status never blocks [isFullyReady].
  final RuntimeAvailability supabase;

  bool get isFullyReady {
    return localData == RuntimeAvailability.ready &&
        firebase == RuntimeAvailability.ready &&
        backends == RuntimeAvailability.ready &&
        aiTutor == RuntimeAvailability.ready &&
        voice == RuntimeAvailability.ready;
  }

  @override
  String toString() => 'AppRuntimeStatus';
}
