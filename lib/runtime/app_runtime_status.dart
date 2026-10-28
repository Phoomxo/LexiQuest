enum RuntimeAvailability { ready, degraded, unavailable }

final class AppRuntimeStatus {
  const AppRuntimeStatus({
    required this.firebase,
    required this.backends,
    this.deviceCapabilities = RuntimeAvailability.unavailable,
    this.onDeviceInference = RuntimeAvailability.unavailable,
  });

  final RuntimeAvailability firebase;
  final RuntimeAvailability backends;
  final RuntimeAvailability deviceCapabilities;
  final RuntimeAvailability onDeviceInference;

  bool get isFullyReady =>
      firebase == RuntimeAvailability.ready &&
      backends == RuntimeAvailability.ready &&
      deviceCapabilities == RuntimeAvailability.ready &&
      onDeviceInference == RuntimeAvailability.ready;

  bool get isCoreLearningAvailable => true;

  @override
  String toString() => 'AppRuntimeStatus';
}
