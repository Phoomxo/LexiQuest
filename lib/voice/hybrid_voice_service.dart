import 'omni_voice_provider.dart';
import 'voice_audio_player.dart';
import 'voice_models.dart';
import 'voice_provider.dart';

/// Routes a [VoiceRequest] between the native on-device TTS engine and the
/// OmniVoice remote synthesis API based on the request mode and assigned
/// engine.
final class HybridVoiceService implements VoiceProvider {
  HybridVoiceService({
    required VoiceProvider nativeProvider,
    required OmniVoiceSynthesizer omniVoiceProvider,
    required VoiceAudioPlayer audioPlayer,
  }) : this._(nativeProvider, omniVoiceProvider, audioPlayer);

  HybridVoiceService._(
    this._nativeProvider,
    this._omniVoiceProvider,
    this._audioPlayer,
  );

  final VoiceProvider _nativeProvider;
  final OmniVoiceSynthesizer _omniVoiceProvider;
  final VoiceAudioPlayer _audioPlayer;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    if (request.mode == VoiceMode.researchEvaluation &&
        request.assignedEngine == VoiceEngine.nativeTts) {
      return _nativeProvider.speak(request);
    }

    final audio = await _omniVoiceProvider.synthesize(request);
    await _audioPlayer.play(audio.bytes);
    return VoicePlaybackResult(
      requestedEngine: VoiceEngine.omniVoice,
      actualEngine: VoiceEngine.omniVoice,
      usedFallback: false,
      cacheHit: false,
      requestId: audio.requestId,
      modelVersion: audio.modelVersion,
    );
  }

  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
    await _nativeProvider.stop();
  }
}
