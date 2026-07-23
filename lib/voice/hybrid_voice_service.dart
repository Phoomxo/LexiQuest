import 'omni_voice_provider.dart';
import 'voice_audio_cache.dart';
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
    required VoiceAudioCache audioCache,
    required String omniVoiceModelVersion,
  }) : this._(
         nativeProvider,
         omniVoiceProvider,
         audioPlayer,
         audioCache,
         omniVoiceModelVersion,
       );

  HybridVoiceService._(
    this._nativeProvider,
    this._omniVoiceProvider,
    this._audioPlayer,
    this._audioCache,
    this._activeOmniVoiceModelVersion,
  );

  final VoiceProvider _nativeProvider;
  final OmniVoiceSynthesizer _omniVoiceProvider;
  final VoiceAudioPlayer _audioPlayer;
  final VoiceAudioCache _audioCache;
  String _activeOmniVoiceModelVersion;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    if (request.mode == VoiceMode.researchEvaluation &&
        request.assignedEngine == VoiceEngine.nativeTts) {
      return _nativeProvider.speak(request);
    }

    if (request.mode == VoiceMode.researchEvaluation) {
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

    return _speakPractice(request);
  }

  /// Practice path: prefer cached OmniVoice audio, then synthesize and play.
  /// Operational and playback failures fall back to native TTS once; failures
  /// that reflect caller intent (validation, cancelled) are rethrown.
  Future<VoicePlaybackResult> _speakPractice(VoiceRequest request) async {
    final cacheKey = VoiceAudioCacheKey.create(
      request: request,
      modelVersion: _activeOmniVoiceModelVersion,
    );
    final cachedBytes = await _audioCache.get(cacheKey);

    try {
      if (cachedBytes != null) {
        await _audioPlayer.play(cachedBytes);
        return VoicePlaybackResult(
          requestedEngine: VoiceEngine.omniVoice,
          actualEngine: VoiceEngine.omniVoice,
          usedFallback: false,
          cacheHit: true,
          requestId: null,
          modelVersion: cacheKey.modelVersion,
        );
      }

      final audio = await _omniVoiceProvider.synthesize(request);
      final storageKey = VoiceAudioCacheKey.create(
        request: request,
        modelVersion: audio.modelVersion,
      );
      await _audioCache.put(storageKey, audio.bytes);
      _activeOmniVoiceModelVersion = storageKey.modelVersion;
      await _audioPlayer.play(audio.bytes);
      return VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
        requestId: audio.requestId,
        modelVersion: audio.modelVersion,
      );
    } on VoiceFailure catch (failure) {
      switch (failure.category) {
        // Surface failures that reflect caller intent unchanged.
        case VoiceFailureCategory.validation:
        case VoiceFailureCategory.cancelled:
          rethrow;
        // Fall back to on-device TTS for operational and playback failures.
        case VoiceFailureCategory.authentication:
        case VoiceFailureCategory.network:
        case VoiceFailureCategory.timeout:
        case VoiceFailureCategory.rateLimited:
        case VoiceFailureCategory.modelUnavailable:
        case VoiceFailureCategory.synthesis:
        case VoiceFailureCategory.playback:
        case VoiceFailureCategory.configuration:
        case VoiceFailureCategory.unknown:
          await _nativeProvider.speak(request);
          return VoicePlaybackResult(
            requestedEngine: VoiceEngine.omniVoice,
            actualEngine: VoiceEngine.nativeTts,
            usedFallback: true,
            cacheHit: cachedBytes != null,
          );
      }
    }
  }

  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
    await _nativeProvider.stop();
  }
}
