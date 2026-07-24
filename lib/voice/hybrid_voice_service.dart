import 'omni_voice_provider.dart';
import 'voice_audio_cache.dart';
import 'voice_audio_player.dart';
import 'voice_models.dart';
import 'voice_provider.dart';
import 'voice_telemetry.dart';

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
    VoiceTelemetrySink telemetrySink = const NoopVoiceTelemetrySink(),
  }) : this._(
         nativeProvider,
         omniVoiceProvider,
         audioPlayer,
         audioCache,
         omniVoiceModelVersion,
         telemetrySink,
       );

  HybridVoiceService._(
    this._nativeProvider,
    this._omniVoiceProvider,
    this._audioPlayer,
    this._audioCache,
    this._activeOmniVoiceModelVersion,
    this._telemetrySink,
  );

  final VoiceProvider _nativeProvider;
  final OmniVoiceSynthesizer _omniVoiceProvider;
  final VoiceAudioPlayer _audioPlayer;
  final VoiceAudioCache _audioCache;
  final VoiceTelemetrySink _telemetrySink;
  String _activeOmniVoiceModelVersion;

  /// Monotonic token bumped at the start of each [speak] and [stop] so an
  /// in-flight request can detect that it was superseded or cancelled.
  int _generation = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    final stopwatch = Stopwatch()..start();
    final generation = ++_generation;
    VoiceFailureCategory? fallbackReason;

    try {
      final result = await _routeSpeak(request, generation, (category) {
        fallbackReason = category;
      });
      await _telemetrySink.record(
        VoiceTelemetryEvent.succeeded(
          request: request,
          result: result,
          fallbackReason: result.usedFallback ? fallbackReason : null,
          latency: stopwatch.elapsed,
          occurredAtUtc: DateTime.now().toUtc(),
        ),
      );
      return result;
    } on VoiceFailure catch (failure) {
      await _telemetrySink.record(
        VoiceTelemetryEvent.failed(
          request: request,
          requestedEngine: _requestedEngineFor(request),
          failure: failure,
          latency: stopwatch.elapsed,
          occurredAtUtc: DateTime.now().toUtc(),
        ),
      );
      rethrow;
    }
  }

  /// The telemetry requested engine: practice always requests OmniVoice, while
  /// research evaluation requests the assigned engine (validated non-null).
  VoiceEngine _requestedEngineFor(VoiceRequest request) {
    return request.mode == VoiceMode.practice
        ? VoiceEngine.omniVoice
        : request.assignedEngine!;
  }

  /// Stops active playback, then routes the request to the strict research or
  /// practice path. [noteFallback] records the operational failure category
  /// when the practice path falls back to native TTS.
  Future<VoicePlaybackResult> _routeSpeak(
    VoiceRequest request,
    int generation,
    void Function(VoiceFailureCategory) noteFallback,
  ) async {
    await _audioPlayer.stop();
    _requireCurrentGeneration(generation);
    await _nativeProvider.stop();
    _requireCurrentGeneration(generation);

    // Strict research/native route: synthesize on-device with no fallback;
    // guard generation so a stopped or superseded request resolves as cancelled.
    if (request.mode == VoiceMode.researchEvaluation &&
        request.assignedEngine == VoiceEngine.nativeTts) {
      try {
        final result = await _nativeProvider.speak(request);
        _requireCurrentGeneration(generation);
        return result;
      } on VoiceFailure {
        _requireCurrentGeneration(generation);
        rethrow;
      }
    }

    // Strict research/OmniVoice route: synthesize and play, no cache/fallback;
    // guard generation after each await so stops and supersede resolve cancelled.
    if (request.mode == VoiceMode.researchEvaluation) {
      try {
        final audio = await _omniVoiceProvider.synthesize(request);
        _requireCurrentGeneration(generation);
        await _audioPlayer.play(audio.bytes);
        _requireCurrentGeneration(generation);
        return VoicePlaybackResult(
          requestedEngine: VoiceEngine.omniVoice,
          actualEngine: VoiceEngine.omniVoice,
          usedFallback: false,
          cacheHit: false,
          requestId: audio.requestId,
          modelVersion: audio.modelVersion,
        );
      } on VoiceFailure {
        _requireCurrentGeneration(generation);
        rethrow;
      }
    }

    return _speakPractice(request, generation, noteFallback);
  }

  /// Practice path: prefer cached OmniVoice audio, then synthesize and play.
  /// Operational and playback failures fall back to native TTS once; failures
  /// that reflect caller intent (validation, cancelled) are rethrown.
  Future<VoicePlaybackResult> _speakPractice(
    VoiceRequest request,
    int generation,
    void Function(VoiceFailureCategory) noteFallback,
  ) async {
    final cacheKey = VoiceAudioCacheKey.create(
      request: request,
      modelVersion: _activeOmniVoiceModelVersion,
    );
    var cacheHit = false;

    try {
      final cachedBytes = await _audioCache.get(cacheKey);
      _requireCurrentGeneration(generation);
      if (cachedBytes != null) {
        cacheHit = true;
        await _audioPlayer.play(cachedBytes);
        _requireCurrentGeneration(generation);
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
      _requireCurrentGeneration(generation);
      final storageKey = VoiceAudioCacheKey.create(
        request: request,
        modelVersion: audio.modelVersion,
      );
      await _audioCache.put(storageKey, audio.bytes);
      _requireCurrentGeneration(generation);
      _activeOmniVoiceModelVersion = storageKey.modelVersion;
      await _audioPlayer.play(audio.bytes);
      _requireCurrentGeneration(generation);
      return VoicePlaybackResult(
        requestedEngine: VoiceEngine.omniVoice,
        actualEngine: VoiceEngine.omniVoice,
        usedFallback: false,
        cacheHit: false,
        requestId: audio.requestId,
        modelVersion: audio.modelVersion,
      );
    } on VoiceFailure catch (failure) {
      _requireCurrentGeneration(generation);
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
          noteFallback(failure.category);
          try {
            await _nativeProvider.speak(request);
          } on VoiceFailure {
            _requireCurrentGeneration(generation);
            rethrow;
          }
          _requireCurrentGeneration(generation);
          return VoicePlaybackResult(
            requestedEngine: VoiceEngine.omniVoice,
            actualEngine: VoiceEngine.nativeTts,
            usedFallback: true,
            cacheHit: cacheHit,
          );
      }
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _audioPlayer.stop();
    await _nativeProvider.stop();
  }

  /// Throws [_cancelledFailure] when [generation] is no longer current,
  /// indicating the request was superseded or stopped.
  void _requireCurrentGeneration(int generation) {
    if (generation != _generation) {
      throw _cancelledFailure;
    }
  }
}

const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'The voice request was cancelled.',
);
