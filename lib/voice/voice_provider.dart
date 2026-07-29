import 'voice_models.dart';

/// Provider-neutral boundary for synthesizing and controlling speech playback.
abstract interface class VoiceProvider {
  Future<VoicePlaybackResult> speak(VoiceRequest request);

  Future<void> stop();
}
