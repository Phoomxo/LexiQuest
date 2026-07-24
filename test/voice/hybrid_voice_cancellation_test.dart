import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/hybrid_voice_service.dart';
import 'package:vocab_learning_app/voice/omni_voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

const List<int> _firstWav = <int>[
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
  0x01,
];

const List<int> _secondWav = <int>[
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
  0x02,
];

const String _omniRequestId = 'req-123';
const String _secondRequestId = 'req-456';
const String _omniModelVersion = 'omnivoice-2026-07';

const VoiceFailure _networkFailure = VoiceFailure(
  category: VoiceFailureCategory.network,
  message: 'The voice service could not be reached.',
);

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

OmniVoiceAudio _firstAudio() {
  return OmniVoiceAudio(
    bytes: Uint8List.fromList(_firstWav),
    requestId: _omniRequestId,
    engine: 'omnivoice-prod',
    modelVersion: _omniModelVersion,
    sampleRate: 24000,
  );
}

OmniVoiceAudio _secondAudio() {
  return OmniVoiceAudio(
    bytes: Uint8List.fromList(_secondWav),
    requestId: _secondRequestId,
    engine: 'omnivoice-prod',
    modelVersion: _omniModelVersion,
    sampleRate: 24000,
  );
}

HybridVoiceService _buildService(
  _RecordingNativeProvider native,
  _QueuedOmniVoiceSynthesizer omni,
  _RecordingAudioPlayer player, {
  VoiceAudioCache? cache,
  String omniVoiceModelVersion = _omniModelVersion,
}) {
  return HybridVoiceService(
    nativeProvider: native,
    omniVoiceProvider: omni,
    audioPlayer: player,
    audioCache:
        cache ?? MemoryVoiceAudioCache(maxEntries: 16, maxBytes: 1024 * 1024),
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
  test('speak stops the player and native engine before synthesizing, then '
      'plays the result bytes', () async {
    final events = <String>[];
    final native = _RecordingNativeProvider(events);
    final omni = _QueuedOmniVoiceSynthesizer(events, expectedCalls: 1);
    final player = _RecordingAudioPlayer(events);
    final service = _buildService(native, omni, player);

    final speak = service.speak(_practiceRequest());
    await omni.started(0);

    expect(events, <String>['player.stop', 'native.stop', 'omni.synthesize']);

    omni.completeResult(0, _firstAudio());
    await speak;

    expect(events.last, 'player.play');
    expect(player.playCalls.single, Uint8List.fromList(_firstWav));
  });

  test('stop after synthesis started cancels the in-flight speak without '
      'playback, native fallback, or a cache entry', () async {
    final events = <String>[];
    final cache = MemoryVoiceAudioCache(maxEntries: 16, maxBytes: 1024 * 1024);
    final native = _RecordingNativeProvider(events);
    final omni = _QueuedOmniVoiceSynthesizer(events, expectedCalls: 1);
    final player = _RecordingAudioPlayer(events);
    final service = _buildService(native, omni, player, cache: cache);

    final speak = service.speak(_practiceRequest());
    await omni.started(0);
    await service.stop();
    omni.completeResult(0, _firstAudio());

    final failure = await _captureFailure(() => speak);

    expect(failure.category, VoiceFailureCategory.cancelled);
    expect(player.playCalls, isEmpty);
    expect(native.speakCalls, isEmpty);
    expect(cache.entryCount, 0);
  });

  test(
    'a second speak supersedes the first and only the second bytes play',
    () async {
      final events = <String>[];
      final native = _RecordingNativeProvider(events);
      final omni = _QueuedOmniVoiceSynthesizer(events, expectedCalls: 2);
      final player = _RecordingAudioPlayer(events);
      final service = _buildService(native, omni, player);

      final firstSpeak = service.speak(_practiceRequest());
      await omni.started(0);
      final secondSpeak = service.speak(_practiceRequest());
      await omni.started(1);

      expect(events, <String>[
        'player.stop',
        'native.stop',
        'omni.synthesize',
        'player.stop',
        'native.stop',
        'omni.synthesize',
      ]);

      omni.completeResult(1, _secondAudio());
      final secondResult = await secondSpeak;
      expect(secondResult.actualEngine, VoiceEngine.omniVoice);

      omni.completeResult(0, _firstAudio());
      final firstFailure = await _captureFailure(() => firstSpeak);
      expect(firstFailure.category, VoiceFailureCategory.cancelled);

      expect(player.playCalls.single, Uint8List.fromList(_secondWav));
      expect(native.speakCalls, isEmpty);
    },
  );

  test('a superseded speak whose remote fails with an operational error is '
      'cancelled instead of falling back to native', () async {
    final events = <String>[];
    final native = _RecordingNativeProvider(events);
    final omni = _QueuedOmniVoiceSynthesizer(events, expectedCalls: 2);
    final player = _RecordingAudioPlayer(events);
    final service = _buildService(native, omni, player);

    final firstSpeak = service.speak(_practiceRequest());
    await omni.started(0);
    final secondSpeak = service.speak(_practiceRequest());
    await omni.started(1);

    omni.completeResult(1, _secondAudio());
    await secondSpeak;

    omni.completeError(0, _networkFailure);
    final firstFailure = await _captureFailure(() => firstSpeak);

    expect(firstFailure.category, VoiceFailureCategory.cancelled);
    expect(native.speakCalls, isEmpty);
    expect(player.playCalls.single, Uint8List.fromList(_secondWav));
  });
}

class _QueuedOmniVoiceSynthesizer implements OmniVoiceSynthesizer {
  _QueuedOmniVoiceSynthesizer(this.events, {required this.expectedCalls})
    : _started = List<Completer<void>>.generate(
        expectedCalls,
        (_) => Completer<void>(),
        growable: false,
      ),
      _results = List<Completer<OmniVoiceAudio>>.generate(
        expectedCalls,
        (_) => Completer<OmniVoiceAudio>(),
        growable: false,
      );

  final List<String> events;
  final int expectedCalls;
  final List<Completer<void>> _started;
  final List<Completer<OmniVoiceAudio>> _results;
  final List<VoiceRequest> synthesizeCalls = <VoiceRequest>[];

  Future<void> started(int index) => _started[index].future;

  void completeResult(int index, OmniVoiceAudio audio) =>
      _results[index].complete(audio);

  void completeError(int index, VoiceFailure failure) =>
      _results[index].completeError(failure);

  @override
  Future<OmniVoiceAudio> synthesize(VoiceRequest request) {
    final index = synthesizeCalls.length;
    if (index >= expectedCalls) {
      throw StateError('Unexpected OmniVoice synthesis call.');
    }
    synthesizeCalls.add(request);
    events.add('omni.synthesize');
    _started[index].complete();
    return _results[index].future;
  }
}

class _RecordingAudioPlayer implements VoiceAudioPlayer {
  _RecordingAudioPlayer(this.events);

  final List<String> events;
  final List<Uint8List> playCalls = <Uint8List>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> play(Uint8List bytes) async {
    playCalls.add(Uint8List.fromList(bytes));
    events.add('player.play');
  }

  @override
  Future<void> stop() async {
    stopCount++;
    events.add('player.stop');
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _RecordingNativeProvider implements VoiceProvider {
  _RecordingNativeProvider(this.events);

  final List<String> events;
  final List<VoiceRequest> speakCalls = <VoiceRequest>[];
  int stopCount = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    speakCalls.add(request);
    events.add('native.speak');
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
    events.add('native.stop');
  }
}
