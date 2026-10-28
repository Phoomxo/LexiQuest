import 'voice_models.dart';

/// Provider-neutral boundary for synthesizing and controlling speech playback.
abstract interface class VoiceProvider {
  Future<VoicePlaybackResult> speak(VoiceRequest request);

  Future<void> stop();
}

/// A provider whose external resources are owned by the composition root.
abstract interface class ManagedVoiceProvider implements VoiceProvider {
  Future<void> dispose();
}
