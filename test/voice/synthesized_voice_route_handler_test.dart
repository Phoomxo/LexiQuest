// RED phase: defines the behavior contract for SynthesizedVoiceRouteHandler
// before its implementation exists. This file is expected NOT to compile until
// the handler is added under lib/voice/.
//
// Scope: descriptor forwarding, standard-content cache miss/hit lifecycle with
// provider engine and model version keying, participantTransient mirror cache
// bypass, engine-mismatch guarding, and cancellation honoured both before and
// after synthesis. No plugins or network are exercised; deterministic recording
// fakes stand in for the synthesis provider, audio player, and audio cache.
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/synthesized_voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';
import 'package:vocab_learning_app/voice/voice_route_handler.dart';
import 'package:vocab_learning_app/voice/voice_synthesis_provider.dart';

const _modelVersion = 'omni-voice-v1';

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

VoiceRequest _request({
  VoiceCapability capability = VoiceCapability.standardTargetSpeech,
  VoicePrivacyScope privacyScope = VoicePrivacyScope.standardContent,
}) {
  return VoiceRequest.create(
    text: 'Good morning.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1,
    contentId: 'phrase-001',
    contentType: 'phrase',
    mode: VoiceMode.practice,
    capability: capability,
    privacyScope: privacyScope,
  );
}

/// A cancellation handle whose cancelled state can be flipped on demand so a
/// test can simulate cancellation arriving at a specific suspension point.
class _ToggleToken implements VoiceCancellationToken {
  bool _cancelled = false;

  void cancel() => _cancelled = true;

  @override
  bool get isCancelled => _cancelled;

  @override
  void throwIfCancelled() {
    if (_cancelled) {
      throw const VoiceFailure(
        category: VoiceFailureCategory.cancelled,
        message: 'The synthesized voice request was cancelled.',
      );
    }
  }
}

/// A cancellation handle that never reports cancellation.
class _NeverCancelledToken implements VoiceCancellationToken {
  @override
  bool get isCancelled => false;

  @override
  void throwIfCancelled() {}
}

/// A cancellation handle that is always already cancelled, so speak must abort
/// before touching the provider, cache, or player.
class _AlwaysCancelledToken implements VoiceCancellationToken {
  @override
  bool get isCancelled => true;

  @override
  void throwIfCancelled() {
    throw const VoiceFailure(
      category: VoiceFailureCategory.cancelled,
      message: 'The synthesized voice request was cancelled before playback.',
    );
  }
}

/// Deterministic VoiceSynthesisProvider. Records every synthesized request,
/// returns controlled audio provenance, and can optionally flip a toggle token
/// after synthesis completes (to model cancellation between steps) or emit a
/// mismatched engine to exercise the guard.
class _RecordingSynthesisProvider implements VoiceSynthesisProvider {
  _RecordingSynthesisProvider({
    required this.descriptor,
    this.engineOverride,
    this.cancelAfterSynthesis,
  });

  @override
  final VoiceProviderDescriptor descriptor;

  /// When set, the returned [VoiceAudio] reports this engine instead of the
  /// descriptor engine, so the handler must reject it.
  final VoiceEngine? engineOverride;

  /// When set, the token is cancelled after synthesis returns, modelling a
  /// stop request that lands between synthesis and cache/playback.
  final _ToggleToken? cancelAfterSynthesis;

  final List<VoiceRequest> synthesizeCalls = <VoiceRequest>[];

  @override
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    synthesizeCalls.add(request);
    cancelAfterSynthesis?.cancel();
    return VoiceAudio(
      bytes: Uint8List.fromList(const <int>[1, 2, 3, 4]),
      requestId: 'req-${synthesizeCalls.length}',
      engine: engineOverride ?? descriptor.engine,
      modelVersion: _modelVersion,
      sampleRate: 24000,
    );
  }
}

/// Deterministic VoiceAudioPlayer. Records played bytes and stop calls.
class _RecordingAudioPlayer implements VoiceAudioPlayer {
  final List<Uint8List> playCalls = <Uint8List>[];
  int stopCount = 0;

  @override
  Future<void> play(Uint8List bytes) async {
    playCalls.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {}
}

/// Deterministic VoiceAudioCache. Records get/put/clear interactions and serves
/// any previously put payload back from get, keyed on the cache key equality.
class _RecordingAudioCache implements VoiceAudioCache {
  final Map<VoiceAudioCacheKey, Uint8List> _store =
      <VoiceAudioCacheKey, Uint8List>{};
  final List<VoiceAudioCacheKey> getCalls = <VoiceAudioCacheKey>[];
  final List<VoiceAudioCacheKey> putCalls = <VoiceAudioCacheKey>[];
  int clearCount = 0;

  @override
  Future<Uint8List?> get(VoiceAudioCacheKey key) async {
    getCalls.add(key);
    final bytes = _store[key];
    return bytes == null ? null : Uint8List.fromList(bytes);
  }

  @override
  Future<void> put(VoiceAudioCacheKey key, Uint8List bytes) async {
    putCalls.add(key);
    _store[key] = Uint8List.fromList(bytes);
  }

  @override
  Future<void> clear() async {
    clearCount++;
    _store.clear();
  }
}

VoiceProviderDescriptor _standardDescriptor() => VoiceProviderDescriptor(
  engine: VoiceEngine.omniVoice,
  capabilities: {
    VoiceCapability.standardTargetSpeech,
    VoiceCapability.dynamicTargetSpeech,
  },
  privacyScope: VoicePrivacyScope.standardContent,
  allowsStandardCache: true,
);

VoiceProviderDescriptor _mirrorDescriptor() => VoiceProviderDescriptor(
  engine: VoiceEngine.voxCpmMirror,
  capabilities: {VoiceCapability.sessionVoiceMirror},
  privacyScope: VoicePrivacyScope.participantTransient,
  allowsStandardCache: false,
);

void main() {
  group('descriptor', () {
    test('forwards the provider descriptor verbatim', () {
      final provider = _RecordingSynthesisProvider(
        descriptor: _standardDescriptor(),
      );
      final handler = SynthesizedVoiceRouteHandler(
        provider: provider,
        audioPlayer: _RecordingAudioPlayer(),
        audioCache: _RecordingAudioCache(),
        modelVersion: _modelVersion,
      );

      expect(handler.descriptor, same(provider.descriptor));
    });
  });

  group('standard content cache miss', () {
    test('synthesizes, caches with the provider engine and model version, '
        'plays the bytes, and reports provenance', () async {
      final provider = _RecordingSynthesisProvider(
        descriptor: _standardDescriptor(),
      );
      final player = _RecordingAudioPlayer();
      final cache = _RecordingAudioCache();
      final handler = SynthesizedVoiceRouteHandler(
        provider: provider,
        audioPlayer: player,
        audioCache: cache,
        modelVersion: _modelVersion,
      );

      final result = await handler.speak(_request(), _NeverCancelledToken());

      expect(provider.synthesizeCalls, hasLength(1));

      final expectedKey = VoiceAudioCacheKey.create(
        request: _request(),
        engine: VoiceEngine.omniVoice,
        modelVersion: _modelVersion,
      );
      expect(cache.getCalls.single, expectedKey);
      expect(cache.putCalls.single, expectedKey);

      expect(player.playCalls, hasLength(1));
      expect(player.playCalls.single, const <int>[1, 2, 3, 4]);

      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, 'req-1');
      expect(result.modelVersion, _modelVersion);
    });
  });

  group('standard content cache hit', () {
    test('serves the second identical request from cache without synthesizing '
        'again and reports cacheHit true', () async {
      final provider = _RecordingSynthesisProvider(
        descriptor: _standardDescriptor(),
      );
      final player = _RecordingAudioPlayer();
      final cache = _RecordingAudioCache();
      final handler = SynthesizedVoiceRouteHandler(
        provider: provider,
        audioPlayer: player,
        audioCache: cache,
        modelVersion: _modelVersion,
      );

      await handler.speak(_request(), _NeverCancelledToken());
      final result = await handler.speak(_request(), _NeverCancelledToken());

      expect(provider.synthesizeCalls, hasLength(1));
      expect(player.playCalls, hasLength(2));
      expect(result.cacheHit, isTrue);
      expect(result.actualEngine, VoiceEngine.omniVoice);
    });
  });

  group('participant transient mirror', () {
    test(
      'bypasses the cache entirely while still synthesizing and playing',
      () async {
        final provider = _RecordingSynthesisProvider(
          descriptor: _mirrorDescriptor(),
        );
        final player = _RecordingAudioPlayer();
        final cache = _RecordingAudioCache();
        final handler = SynthesizedVoiceRouteHandler(
          provider: provider,
          audioPlayer: player,
          audioCache: cache,
          modelVersion: _modelVersion,
        );

        final result = await handler.speak(
          _request(
            capability: VoiceCapability.sessionVoiceMirror,
            privacyScope: VoicePrivacyScope.participantTransient,
          ),
          _NeverCancelledToken(),
        );

        expect(provider.synthesizeCalls, hasLength(1));
        expect(player.playCalls, hasLength(1));
        expect(cache.getCalls, isEmpty);
        expect(cache.putCalls, isEmpty);

        expect(result.actualEngine, VoiceEngine.voxCpmMirror);
        expect(result.cacheHit, isFalse);
      },
    );
  });

  group('engine mismatch', () {
    test('throws a synthesis failure and neither plays nor caches', () async {
      final provider = _RecordingSynthesisProvider(
        descriptor: _standardDescriptor(),
        engineOverride: VoiceEngine.nativeTts,
      );
      final player = _RecordingAudioPlayer();
      final cache = _RecordingAudioCache();
      final handler = SynthesizedVoiceRouteHandler(
        provider: provider,
        audioPlayer: player,
        audioCache: cache,
        modelVersion: _modelVersion,
      );

      await expectLater(
        handler.speak(_request(), _NeverCancelledToken()),
        throwsA(_failure(VoiceFailureCategory.synthesis)),
      );

      expect(provider.synthesizeCalls, hasLength(1));
      expect(player.playCalls, isEmpty);
      expect(cache.putCalls, isEmpty);
    });
  });

  group('cancellation', () {
    test(
      'before synthesis prevents all synthesis, playback, and cache work',
      () async {
        final provider = _RecordingSynthesisProvider(
          descriptor: _standardDescriptor(),
        );
        final player = _RecordingAudioPlayer();
        final cache = _RecordingAudioCache();
        final handler = SynthesizedVoiceRouteHandler(
          provider: provider,
          audioPlayer: player,
          audioCache: cache,
          modelVersion: _modelVersion,
        );

        await expectLater(
          handler.speak(_request(), _AlwaysCancelledToken()),
          throwsA(_failure(VoiceFailureCategory.cancelled)),
        );

        expect(provider.synthesizeCalls, isEmpty);
        expect(player.playCalls, isEmpty);
        expect(cache.getCalls, isEmpty);
        expect(cache.putCalls, isEmpty);
      },
    );

    test('after synthesis prevents caching and playback', () async {
      final token = _ToggleToken();
      final provider = _RecordingSynthesisProvider(
        descriptor: _standardDescriptor(),
        cancelAfterSynthesis: token,
      );
      final player = _RecordingAudioPlayer();
      final cache = _RecordingAudioCache();
      final handler = SynthesizedVoiceRouteHandler(
        provider: provider,
        audioPlayer: player,
        audioCache: cache,
        modelVersion: _modelVersion,
      );

      await expectLater(
        handler.speak(_request(), token),
        throwsA(_failure(VoiceFailureCategory.cancelled)),
      );

      expect(provider.synthesizeCalls, hasLength(1));
      expect(player.playCalls, isEmpty);
      expect(cache.putCalls, isEmpty);
    });
  });

  group('stop delegation', () {
    test('forwards stop to the audio player exactly once', () async {
      final player = _RecordingAudioPlayer();
      final handler = SynthesizedVoiceRouteHandler(
        provider: _RecordingSynthesisProvider(
          descriptor: _standardDescriptor(),
        ),
        audioPlayer: player,
        audioCache: _RecordingAudioCache(),
        modelVersion: _modelVersion,
      );

      await handler.stop();

      expect(player.stopCount, 1);
    });
  });
}
