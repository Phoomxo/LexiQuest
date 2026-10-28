import 'voice_audio_cache.dart';
import 'voice_audio_player.dart';
import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_provider_descriptor.dart';
import 'voice_route_handler.dart';
import 'voice_synthesis_provider.dart';

const _engineMismatchFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'Synthesized audio provenance does not match its provider.',
);

const _unsupportedRouteFailure = VoiceFailure(
  category: VoiceFailureCategory.unsupportedCapability,
  message: 'The selected voice provider cannot handle this request.',
);

/// Adapts a byte-producing synthesis provider to the routed playback contract.
final class SynthesizedVoiceRouteHandler implements VoiceRouteHandler {
  SynthesizedVoiceRouteHandler({
    required VoiceSynthesisProvider provider,
    required VoiceAudioPlayer audioPlayer,
    required VoiceAudioCache audioCache,
    required String modelVersion,
  }) : this._(provider, audioPlayer, audioCache, modelVersion);

  SynthesizedVoiceRouteHandler._(
    this._provider,
    this._audioPlayer,
    this._audioCache,
    this._modelVersion,
  );

  final VoiceSynthesisProvider _provider;
  final VoiceAudioPlayer _audioPlayer;
  final VoiceAudioCache _audioCache;
  String _modelVersion;

  @override
  VoiceProviderDescriptor get descriptor => _provider.descriptor;

  @override
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    _validateRoute(request);

    final canCache =
        descriptor.allowsStandardCache &&
        descriptor.privacyScope == VoicePrivacyScope.standardContent &&
        request.privacyScope == VoicePrivacyScope.standardContent;

    if (canCache) {
      final lookupKey = VoiceAudioCacheKey.create(
        request: request,
        engine: descriptor.engine,
        modelVersion: _modelVersion,
      );
      final cachedBytes = await _audioCache.get(lookupKey);
      cancellation.throwIfCancelled();
      if (cachedBytes != null) {
        await _audioPlayer.play(cachedBytes);
        cancellation.throwIfCancelled();
        return _result(
          request: request,
          cacheHit: true,
          modelVersion: _modelVersion,
        );
      }
    }

    final audio = await _provider.synthesize(request);
    cancellation.throwIfCancelled();
    if (audio.engine != descriptor.engine) {
      throw _engineMismatchFailure;
    }

    _modelVersion = audio.modelVersion;
    if (canCache) {
      final storageKey = VoiceAudioCacheKey.create(
        request: request,
        engine: descriptor.engine,
        modelVersion: audio.modelVersion,
      );
      await _audioCache.put(storageKey, audio.bytes);
      cancellation.throwIfCancelled();
    }

    await _audioPlayer.play(audio.bytes);
    cancellation.throwIfCancelled();
    return _result(
      request: request,
      cacheHit: false,
      requestId: audio.requestId,
      modelVersion: audio.modelVersion,
    );
  }

  void _validateRoute(VoiceRequest request) {
    if (!descriptor.supports(request.capability) ||
        descriptor.privacyScope != request.privacyScope) {
      throw _unsupportedRouteFailure;
    }
  }

  VoicePlaybackResult _result({
    required VoiceRequest request,
    required bool cacheHit,
    String? requestId,
    String? modelVersion,
  }) {
    return VoicePlaybackResult(
      requestedEngine: request.assignedEngine ?? descriptor.engine,
      actualEngine: descriptor.engine,
      usedFallback: false,
      cacheHit: cacheHit,
      requestId: requestId,
      modelVersion: modelVersion,
    );
  }

  @override
  Future<void> stop() => _audioPlayer.stop();
}
