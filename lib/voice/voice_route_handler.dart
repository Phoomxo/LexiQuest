import 'voice_models.dart';
import 'voice_provider_descriptor.dart';

/// Cooperative cancellation handle for an in-flight voice request.
///
/// Providers poll [isCancelled] between long-running steps and call
/// [throwIfCancelled] at suspension points so that stop requests from
/// [VoiceRouteHandler.stop] surface promptly.
abstract interface class VoiceCancellationToken {
  /// Whether cancellation has been requested.
  bool get isCancelled;

  /// Throws if cancellation has been requested.
  ///
  /// Intended to be called at suspension points inside [VoiceRouteHandler.speak].
  void throwIfCancelled();
}

/// Provider-neutral contract for routing a [VoiceRequest] through a single
/// voice engine.
///
/// Implementations own one synthesis/playback backend and expose their
/// capabilities via [descriptor]. The orchestrator selects a handler based on
/// the descriptor and drives it with [speak], aborting via [stop].
abstract interface class VoiceRouteHandler {
  /// Describes this handler's engine, capabilities, and caching policy.
  VoiceProviderDescriptor get descriptor;

  /// Synthesizes and plays back [request], honouring [cancellation].
  ///
  /// Implementations must check the token at suspension points and surface a
  /// [VoicePlaybackResult] describing the outcome.
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  );

  /// Requests immediate stop of any in-flight [speak] call.
  Future<void> stop();
}
