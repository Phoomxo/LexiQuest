import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/hybrid_voice_service.dart';
import 'package:vocab_learning_app/voice/omni_voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_cache.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

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
const String _contentId = 'word-001';
const String _contentType = 'word';

VoiceRequest _practiceRequest() {
  return VoiceRequest.create(
    text: 'Hello world.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1.0,
    contentId: _contentId,
    contentType: _contentType,
    mode: VoiceMode.practice,
  );
}

VoiceRequest _researchRequest(VoiceEngine engine) {
  return VoiceRequest.create(
    text: 'Hello world.',
    language: 'en',
    voiceId: 'teacher_female',
    speed: 1.0,
    contentId: _contentId,
    contentType: _contentType,
    mode: VoiceMode.researchEvaluation,
    assignedEngine: engine,
  );
}

OmniVoiceAudio _omniAudio() {
  return OmniVoiceAudio(
    bytes: Uint8List.fromList(_wavBytes),
    requestId: _omniRequestId,
    engine: 'omnivoice-prod',
    modelVersion: _omniModelVersion,
    sampleRate: 24000,
  );
}

HybridVoiceService _buildService({
  required _RecordingNativeProvider nativeProvider,
  required _RecordingOmniVoiceSynthesizer omniVoiceProvider,
  required _RecordingAudioPlayer audioPlayer,
  required VoiceTelemetrySink telemetrySink,
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
    telemetrySink: telemetrySink,
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
  test(
    'a successful practice OmniVoice synthesis and playback emits exactly '
    'one succeeded event whose safe fields match the request and result',
    () async {
      final sink = _RecordingTelemetrySink();
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        telemetrySink: sink,
      );

      final result = await service.speak(_practiceRequest());

      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event.outcome, VoiceTelemetryOutcome.succeeded);
      expect(event.mode, VoiceMode.practice);
      expect(event.requestedEngine, VoiceEngine.omniVoice);
      expect(event.actualEngine, VoiceEngine.omniVoice);
      expect(event.usedFallback, isFalse);
      expect(event.fallbackReason, isNull);
      expect(event.failureCategory, isNull);
      expect(event.cacheHit, isFalse);
      expect(event.contentId, _contentId);
      expect(event.contentType, _contentType);
      expect(event.requestId, _omniRequestId);
      expect(event.modelVersion, _omniModelVersion);
      expect(event.latency.isNegative, isFalse);
      expect(event.occurredAtUtc.isUtc, isTrue);

      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.requestId, _omniRequestId);
    },
  );

  test('a practice operational failure followed by a successful native '
      'fallback emits exactly one succeeded event carrying the native engine '
      'and authentication fallback reason', () async {
    const authFailure = VoiceFailure(
      category: VoiceFailureCategory.authentication,
      message: 'Voice authentication is unavailable.',
    );
    final sink = _RecordingTelemetrySink();
    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(failure: authFailure);
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
      telemetrySink: sink,
    );

    final result = await service.speak(_practiceRequest());

    expect(omni.synthesizeCalls, hasLength(1));
    expect(native.speakCalls, hasLength(1));

    expect(sink.events, hasLength(1));
    final event = sink.events.single;
    expect(event.outcome, VoiceTelemetryOutcome.succeeded);
    expect(event.mode, VoiceMode.practice);
    expect(event.requestedEngine, VoiceEngine.omniVoice);
    expect(event.actualEngine, VoiceEngine.nativeTts);
    expect(event.usedFallback, isTrue);
    expect(event.fallbackReason, VoiceFailureCategory.authentication);
    expect(event.failureCategory, isNull);
    expect(event.cacheHit, isFalse);
    expect(event.requestId, isNull);
    expect(event.modelVersion, isNull);
    expect(event.latency.isNegative, isFalse);
    expect(event.occurredAtUtc.isUtc, isTrue);

    expect(result.actualEngine, VoiceEngine.nativeTts);
    expect(result.usedFallback, isTrue);
  });

  test('a strict researchEvaluation OmniVoice failure is rethrown unchanged '
      'and emits exactly one failed event with the source failure category, no '
      'fallback, and no cache', () async {
    const remoteFailure = VoiceFailure(
      category: VoiceFailureCategory.modelUnavailable,
      message: 'The voice model is currently unavailable.',
    );
    final sink = _RecordingTelemetrySink();
    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(failure: remoteFailure);
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
      telemetrySink: sink,
    );

    final failure = await _captureFailure(
      () => service.speak(_researchRequest(VoiceEngine.omniVoice)),
    );

    expect(identical(failure, remoteFailure), isTrue);
    expect(failure.category, VoiceFailureCategory.modelUnavailable);
    expect(native.speakCalls, isEmpty);
    expect(player.playCalls, isEmpty);

    expect(sink.events, hasLength(1));
    final event = sink.events.single;
    expect(event.outcome, VoiceTelemetryOutcome.failed);
    expect(event.mode, VoiceMode.researchEvaluation);
    expect(event.requestedEngine, VoiceEngine.omniVoice);
    expect(event.actualEngine, isNull);
    expect(event.usedFallback, isFalse);
    expect(event.fallbackReason, isNull);
    expect(event.failureCategory, VoiceFailureCategory.modelUnavailable);
    expect(event.cacheHit, isFalse);
    expect(event.requestId, isNull);
    expect(event.modelVersion, isNull);
    expect(event.latency.isNegative, isFalse);
    expect(event.occurredAtUtc.isUtc, isTrue);
  });

  test(
    'a successful practice speak stays successful when telemetry record fails '
    'with a non-VoiceFailure error, returning the original result and '
    'recording exactly once',
    () async {
      final sink = _RecordingTelemetrySink(
        recordError: StateError('telemetry sink failed'),
      );
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        telemetrySink: sink,
      );

      final result = await service.speak(_practiceRequest());

      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(result.requestId, _omniRequestId);
      expect(sink.recordCalls, 1);
      expect(player.playCalls, hasLength(1));
    },
  );

  test(
    'a successful practice speak stays successful when telemetry record fails '
    'with a VoiceFailure, never entering the source-failure telemetry path '
    'and recording exactly once',
    () async {
      final sink = _RecordingTelemetrySink(
        recordError: const VoiceFailure(
          category: VoiceFailureCategory.unknown,
          message: 'Telemetry sink failed.',
        ),
      );
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        telemetrySink: sink,
      );

      final result = await service.speak(_practiceRequest());

      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(sink.recordCalls, 1);
      expect(sink.events.single.outcome, VoiceTelemetryOutcome.succeeded);
      expect(sink.events.single.failureCategory, isNull);
    },
  );

  test('a strict research source VoiceFailure is rethrown identical when '
      'telemetry record fails, so telemetry never masks the source failure and '
      'records exactly once', () async {
    const remoteFailure = VoiceFailure(
      category: VoiceFailureCategory.modelUnavailable,
      message: 'The voice model is currently unavailable.',
    );
    final sink = _RecordingTelemetrySink(
      recordError: StateError('telemetry sink failed'),
    );
    final native = _RecordingNativeProvider();
    final omni = _RecordingOmniVoiceSynthesizer(failure: remoteFailure);
    final player = _RecordingAudioPlayer();
    final service = _buildService(
      nativeProvider: native,
      omniVoiceProvider: omni,
      audioPlayer: player,
      telemetrySink: sink,
    );

    final failure = await _captureFailure(
      () => service.speak(_researchRequest(VoiceEngine.omniVoice)),
    );

    expect(identical(failure, remoteFailure), isTrue);
    expect(failure.category, VoiceFailureCategory.modelUnavailable);
    expect(sink.recordCalls, 1);
    expect(sink.events.single.outcome, VoiceTelemetryOutcome.failed);
    expect(
      sink.events.single.failureCategory,
      VoiceFailureCategory.modelUnavailable,
    );
  });

  test(
    'a successful practice speak completes within a bounded timeout even when '
    'the telemetry record future never completes, while still invoking record '
    'exactly once',
    () async {
      final sink = _RecordingTelemetrySink(neverComplete: true);
      final native = _RecordingNativeProvider();
      final omni = _RecordingOmniVoiceSynthesizer(audio: _omniAudio());
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        telemetrySink: sink,
      );

      final result = await service
          .speak(_practiceRequest())
          .timeout(const Duration(seconds: 1));

      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.requestId, _omniRequestId);
      expect(sink.recordCalls, 1);
    },
  );

  test(
    'a practice request cancelled after remote synthesis begins emits exactly '
    'one cancelled telemetry event without playing, falling back, or caching',
    () async {
      final cache = MemoryVoiceAudioCache(
        maxEntries: 16,
        maxBytes: 1024 * 1024,
      );
      final sink = _RecordingTelemetrySink();
      final native = _RecordingNativeProvider();
      final omniPending = Completer<OmniVoiceAudio>();
      final omni = _RecordingOmniVoiceSynthesizer(
        audio: _omniAudio(),
        pending: omniPending,
      );
      final player = _RecordingAudioPlayer();
      final service = _buildService(
        nativeProvider: native,
        omniVoiceProvider: omni,
        audioPlayer: player,
        audioCache: cache,
        telemetrySink: sink,
      );

      final speak = service.speak(_practiceRequest());
      await omni.started;
      await service.stop();
      omniPending.complete(_omniAudio());

      final failure = await _captureFailure(() => speak);

      expect(failure.category, VoiceFailureCategory.cancelled);
      expect(sink.recordCalls, 1);
      expect(sink.events.single.outcome, VoiceTelemetryOutcome.cancelled);
      expect(
        sink.events.single.failureCategory,
        VoiceFailureCategory.cancelled,
      );
      expect(player.playCalls, isEmpty);
      expect(native.speakCalls, isEmpty);
      expect(cache.entryCount, 0);
    },
  );
}

class _RecordingTelemetrySink implements VoiceTelemetrySink {
  _RecordingTelemetrySink({this.recordError, this.neverComplete = false});

  final Object? recordError;
  final bool neverComplete;
  final List<VoiceTelemetryEvent> events = <VoiceTelemetryEvent>[];
  int recordCalls = 0;

  @override
  Future<void> record(VoiceTelemetryEvent event) {
    recordCalls++;
    events.add(event);
    if (neverComplete) {
      return Completer<void>().future;
    }
    final error = recordError;
    if (error != null) {
      return Future<void>.error(error);
    }
    return Future<void>.value();
  }
}

class _RecordingNativeProvider implements VoiceProvider {
  final List<VoiceRequest> speakCalls = <VoiceRequest>[];

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
  Future<void> stop() async {}
}

class _RecordingOmniVoiceSynthesizer implements OmniVoiceSynthesizer {
  _RecordingOmniVoiceSynthesizer({this.audio, this.failure, this.pending});

  final OmniVoiceAudio? audio;
  final VoiceFailure? failure;
  final Completer<OmniVoiceAudio>? pending;
  final List<VoiceRequest> synthesizeCalls = <VoiceRequest>[];
  final Completer<void> _started = Completer<void>();

  Future<void> get started => _started.future;

  @override
  Future<OmniVoiceAudio> synthesize(VoiceRequest request) async {
    synthesizeCalls.add(request);
    if (!_started.isCompleted) {
      _started.complete();
    }
    final pendingCompleter = pending;
    if (pendingCompleter != null) {
      await pendingCompleter.future;
    }
    if (failure != null) {
      throw failure!;
    }
    return audio!;
  }
}

class _RecordingAudioPlayer implements VoiceAudioPlayer {
  final List<Uint8List> playCalls = <Uint8List>[];

  @override
  Future<void> play(Uint8List bytes) async {
    playCalls.add(Uint8List.fromList(bytes));
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {}
}
