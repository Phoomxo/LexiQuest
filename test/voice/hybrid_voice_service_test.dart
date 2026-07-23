import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/hybrid_voice_service.dart';
import 'package:vocab_learning_app/voice/omni_voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

const List<int> _wavBytes = <int>[
  0x52,
  0x49,
  0x46,
  0x46,
  0x2c,
  0x00,
  0x00,
  0x00,
  0x57,
  0x41,
  0x56,
  0x45,
];

const String _omniRequestId = 'req-123';
const String _omniModelVersion = 'omnivoice-2026-07';

VoiceRequest _practiceRequest() {
  return VoiceRequest.create(
    text: 'Hello world.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1.0,
    contentId: 'word-001',
    contentType: 'word',
    mode: VoiceMode.practice,
  );
}

VoiceRequest _researchRequest(VoiceEngine engine) {
  return VoiceRequest.create(
    text: 'Hello world.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1.0,
    contentId: 'word-001',
    contentType: 'word',
    mode: VoiceMode.researchEvaluation,
    assignedEngine: engine,
  );
}

OmniVoiceAudio _omniAudio({
  String modelVersion = _omniModelVersion,
  List<int> bytes = _wavBytes,
}) {
  return OmniVoiceAudio(
    bytes: Uint8List.fromList(bytes),
    requestId: _omniRequestId,
    engine: 'omnivoice-prod',
    modelVersion: modelVersion,
    sampleRate: 24000,
  );
}

HybridVoiceService _buildService({
  required _RecordingNativeProvider nativeProvider,
  required _RecordingOmniVoiceSynthesizer omniVoiceProvider,
  required _RecordingAudioPlayer audioPlayer,
  VoiceAudioCache? audioCache,
  String omniVoiceModelVersion = _omniModelVersion,
}) {
  return HybridVoiceService(
    nativeProvider: nativeProvider,
    omniVoiceProvider: omniVoiceProvider,
    audioPlayer: audioPlayer,
    audioCache:
        audioCache ??
        MemoryVoiceAudioCache(maxEntries: 16, maxBytes: 1024 * 1024),
    omniVoiceModelVersion: omniVoiceModelVersion,
  );
}

Future<VoiceFailure> _captureFailure(Future<void> Function() action) async {
  try {
    await action();
    fail('Expected a VoiceFailure.');
  } on VoiceFailure catch (failure) {
    return failure;
  }
}

void main() {
  test('practice request with no assigned engine routes through OmniVoice '
      'synthesis and playback once', () async {
    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
    );

    final result = await service.speak(_practiceRequest());

    expect(omni.synthesizeCalls, hasLength(1));
    expect(player.playCalls, hasLength(1));
    expect(player.playCalls.single, Uint8List.fromList(_wavBytes));
    expect(native.speakCalls, isEmpty);
    expect(result.requestedEngine, VoiceEngine.omniVoice);
    expect(result.actualEngine, VoiceEngine.omniVoice);
    expect(result.usedFallback, isFalse);
    expect(result.cacheHit, isFalse);
    expect(result.requestId, _omniRequestId);
    expect(result.modelVersion, _omniModelVersion);
  });

  test(
    'research request assigned nativeTts routes through native speak only',
    () async {
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
      );

      final result = await service.speak(
        _researchRequest(VoiceEngine.nativeTts),
      );

      expect(native.speakCalls, hasLength(1));
      expect(omni.synthesizeCalls, isEmpty);
      expect(player.playCalls, isEmpty);
      expect(result.requestedEngine, VoiceEngine.nativeTts);
      expect(result.actualEngine, VoiceEngine.nativeTts);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, isNull);
      expect(result.modelVersion, isNull);
    },
  );

  test(
    'research request assigned omniVoice routes through remote synthesis and '
    'playback only',
    () async {
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
      );

      final result = await service.speak(
        _researchRequest(VoiceEngine.omniVoice),
      );

      expect(omni.synthesizeCalls, hasLength(1));
      expect(player.playCalls, hasLength(1));
      expect(player.playCalls.single, Uint8List.fromList(_wavBytes));
      expect(native.speakCalls, isEmpty);
      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, _omniRequestId);
      expect(result.modelVersion, _omniModelVersion);
    },
  );

  test('OmniVoice synthesis failure during research omniVoice surfaces its '
      'category without crossing over', () async {
    const remoteFailure = VoiceFailure(
      category: VoiceFailureCategory.modelUnavailable,
      message: 'remote synthesis failed',
    );
    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(failure: remoteFailure);
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
    );

    final failure = await _captureFailure(
      () => service.speak(_researchRequest(VoiceEngine.omniVoice)),
    );

    expect(failure.category, VoiceFailureCategory.modelUnavailable);
    expect(omni.synthesizeCalls, hasLength(1));
    expect(native.speakCalls, isEmpty);
    expect(player.playCalls, isEmpty);
  });

  test('practice request plays cached bytes without synthesizing or speaking '
      'native', () async {
    const configuredModel = _omniModelVersion;
    final request = _practiceRequest();
    final cachedBytes = Uint8List.fromList(<int>[0x10, 0x20, 0x30, 0x40]);
    final cache = MemoryVoiceAudioCache(maxEntries: 16, maxBytes: 1024 * 1024);
    await cache.put(
      VoiceAudioCacheKey.create(
        request: request,
        modelVersion: configuredModel,
      ),
      cachedBytes,
    );

    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
      audioCache: cache,
      omniVoiceModelVersion: configuredModel,
    );

    final result = await service.speak(request);

    expect(player.playCalls, hasLength(1));
    expect(player.playCalls.single, cachedBytes);
    expect(omni.synthesizeCalls, isEmpty);
    expect(native.speakCalls, isEmpty);
    expect(result.requestedEngine, VoiceEngine.omniVoice);
    expect(result.actualEngine, VoiceEngine.omniVoice);
    expect(result.usedFallback, isFalse);
    expect(result.cacheHit, isTrue);
    expect(result.requestId, isNull);
    expect(result.modelVersion, configuredModel);
  });

  test('practice remote success populates cache and the next identical speak '
      'uses it', () async {
    const responseModel = 'omnivoice-2026-08';
    final request = _practiceRequest();

    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(
      audio: _omniAudio(modelVersion: responseModel),
    );
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
    );

    final first = await service.speak(request);

    expect(omni.synthesizeCalls, hasLength(1));
    expect(player.playCalls, hasLength(1));
    expect(player.playCalls.single, Uint8List.fromList(_wavBytes));
    expect(native.speakCalls, isEmpty);
    expect(first.requestedEngine, VoiceEngine.omniVoice);
    expect(first.actualEngine, VoiceEngine.omniVoice);
    expect(first.usedFallback, isFalse);
    expect(first.cacheHit, isFalse);
    expect(first.requestId, _omniRequestId);
    expect(first.modelVersion, responseModel);

    final second = await service.speak(request);

    expect(omni.synthesizeCalls, hasLength(1));
    expect(player.playCalls, hasLength(2));
    expect(player.playCalls.last, Uint8List.fromList(_wavBytes));
    expect(second.cacheHit, isTrue);
    expect(second.requestId, isNull);
    expect(second.modelVersion, responseModel);
  });

  test(
    'research request assigned omniVoice bypasses a matching populated cache',
    () async {
      const configuredModel = _omniModelVersion;
      final request = _researchRequest(VoiceEngine.omniVoice);
      final cachedBytes = Uint8List.fromList(<int>[0x01, 0x02, 0x03, 0x04]);
      final cache = MemoryVoiceAudioCache(
        maxEntries: 16,
        maxBytes: 1024 * 1024,
      );
      await cache.put(
        VoiceAudioCacheKey.create(
          request: request,
          modelVersion: configuredModel,
        ),
        cachedBytes,
      );

      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        audioCache: cache,
        omniVoiceModelVersion: configuredModel,
      );

      final result = await service.speak(request);

      expect(omni.synthesizeCalls, hasLength(1));
      expect(player.playCalls, hasLength(1));
      expect(player.playCalls.single, Uint8List.fromList(_wavBytes));
      expect(native.speakCalls, isEmpty);
      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(result.cacheHit, isFalse);
      expect(result.requestId, _omniRequestId);
      expect(result.modelVersion, _omniModelVersion);
    },
  );
}

class _RecordingNativeProvider implements VoiceProvider {
  final List<VoiceRequest> speakCalls = <VoiceRequest>[];
  int stopCount = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    speakCalls.add(request);
    return VoicePlaybackResult(
      requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

class _RecordingOmniVoiceSynthesizer implements OmniVoiceSynthesizer {
  _RecordingOmniVoiceSynthesizer({this.audio, this.failure});

  final OmniVoiceAudio? audio;
  final VoiceFailure? failure;
  final List<VoiceRequest> synthesizeCalls = <VoiceRequest>[];

  @override
  Future<OmniVoiceAudio> synthesize(VoiceRequest request) async {
    synthesizeCalls.add(request);
    if (failure != null) {
      throw failure!;
    }
    return audio!;
  }
}

class _RecordingAudioPlayer implements VoiceAudioPlayer {
  final List<Uint8List> playCalls = <Uint8List>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes) async {
    playCalls.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}
