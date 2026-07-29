import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/voice/native_tts_provider.dart';
import 'package:vocab_learning_app/voice/voice_audio_player.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_service_factory.dart';
import 'package:vocab_learning_app/voice/voice_telemetry.dart';

const _wavBytes = <int>[
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
const _idToken = 'id-token';
const _requestId = 'req-123';
const _modelVersion = 'omnivoice-2026-07';

AppConfig _config() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  isDebug: true,
);

VoiceRequest _request() => VoiceRequest.create(
  text: 'Hello world.',
  language: 'en',
  voiceId: 'teacher_female',
  speed: 1.0,
  contentId: 'word-001',
  contentType: 'word',
  mode: VoiceMode.practice,
);

http.Response _wavResponse() => http.Response.bytes(
  Uint8List.fromList(_wavBytes),
  200,
  headers: const <String, String>{
    'content-type': 'audio/wav',
    'x-request-id': _requestId,
    'x-voice-engine': 'omnivoice-prod',
    'x-model-version': _modelVersion,
    'x-audio-sample-rate': '24000',
  },
);

void main() {
  test(
    'factory wires authenticated OmniVoice playback and telemetry',
    () async {
      final config = _config();
      final tokenReader = _RecordingTokenReader(_idToken);
      final client = _RecordingHttpClient((_) async => _wavResponse());
      final native = _RecordingNativeTtsAdapter();
      final player = _RecordingAudioPlayerAdapter();
      final sink = _RecordingTelemetrySink();

      final service = VoiceServiceFactory.create(
        config: config,
        client: client,
        firebaseTokenReader: tokenReader,
        nativeTtsAdapter: native,
        audioPlayerAdapter: player,
        telemetrySink: sink,
      );

      expect(service, isA<ManagedVoiceService>());
      expect(service, isA<VoiceProvider>());

      final result = await service.speak(_request());

      expect(client.requests, hasLength(1));
      final request = client.requests.single;
      expect(request.method, 'POST');
      expect(request.url, config.voiceApiBaseUri.resolve('/v1/speech'));
      expect(request.headers['authorization'], 'Bearer $_idToken');
      expect(request.headers['content-type'], 'application/json');
      expect(tokenReader.forceRefreshFlags, <bool>[false]);
      expect(jsonDecode(request.body), <String, Object>{
        'text': 'Hello world.',
        'language': 'en',
        'voice': 'teacher_female',
        'speed': 1.0,
        'format': 'wav',
      });

      expect(player.playBytesCalls, hasLength(1));
      expect(player.playBytesCalls.single, Uint8List.fromList(_wavBytes));
      expect(native.speakCalls, isEmpty);
      expect(result.requestedEngine, VoiceEngine.omniVoice);
      expect(result.actualEngine, VoiceEngine.omniVoice);
      expect(result.usedFallback, isFalse);
      expect(result.requestId, _requestId);
      expect(result.modelVersion, _modelVersion);

      expect(sink.events, hasLength(1));
      final event = sink.events.single;
      expect(event.outcome, VoiceTelemetryOutcome.succeeded);
      expect(event.actualEngine, VoiceEngine.omniVoice);
      expect(event.usedFallback, isFalse);
      expect(event.requestId, _requestId);
      expect(event.modelVersion, _modelVersion);
    },
  );

  test('factory-wired network failure falls back to native TTS', () async {
    final tokenReader = _RecordingTokenReader(_idToken);
    final client = _RecordingHttpClient(
      (_) async => throw http.ClientException('network sentinel'),
    );
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final sink = _RecordingTelemetrySink();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: tokenReader,
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
      telemetrySink: sink,
    );

    final result = await service.speak(_request());

    expect(client.sendCount, 1);
    expect(tokenReader.forceRefreshFlags, <bool>[false]);
    expect(native.speakCalls, <String>['Hello world.']);
    expect(player.playBytesCalls, isEmpty);
    expect(result.requestedEngine, VoiceEngine.omniVoice);
    expect(result.actualEngine, VoiceEngine.nativeTts);
    expect(result.usedFallback, isTrue);
    expect(sink.events, hasLength(1));
    expect(sink.events.single.actualEngine, VoiceEngine.nativeTts);
    expect(sink.events.single.fallbackReason, VoiceFailureCategory.network);
  });

  test('dispose owns every resource exactly once and is idempotent', () async {
    final client = _RecordingHttpClient((_) async => _wavResponse());
    final native = _RecordingNativeTtsAdapter();
    final player = _RecordingAudioPlayerAdapter();
    final service = VoiceServiceFactory.create(
      config: _config(),
      client: client,
      firebaseTokenReader: _RecordingTokenReader(_idToken),
      nativeTtsAdapter: native,
      audioPlayerAdapter: player,
    );

    await service.dispose();
    await service.dispose();

    expect(client.sendCount, 0);
    expect(native.stopCount, 1);
    expect(player.stopCount, 1);
    expect(player.disposeCount, 1);
    expect(client.closeCount, 1);
  });
}

final class _RecordedRequest {
  _RecordedRequest(http.Request request)
    : method = request.method,
      url = request.url,
      headers = <String, String>{
        for (final entry in request.headers.entries)
          entry.key.toLowerCase(): entry.value,
      },
      body = request.body;

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

final class _RecordingHttpClient extends http.BaseClient {
  _RecordingHttpClient(this._handler);

  final Future<http.Response> Function(http.Request request) _handler;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  int sendCount = 0;
  int closeCount = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final typedRequest = request as http.Request;
    requests.add(_RecordedRequest(typedRequest));
    sendCount++;
    final response = await _handler(typedRequest);
    return http.StreamedResponse(
      http.ByteStream(Stream<List<int>>.value(response.bodyBytes)),
      response.statusCode,
      contentLength: response.bodyBytes.length,
      headers: response.headers,
    );
  }

  @override
  void close() {
    closeCount++;
  }
}

final class _RecordingTokenReader implements FirebaseTokenReader {
  _RecordingTokenReader(this._token);

  final String _token;
  final List<bool> forceRefreshFlags = <bool>[];

  @override
  Future<String?> readIdToken({required bool forceRefresh}) async {
    forceRefreshFlags.add(forceRefresh);
    return _token;
  }
}

final class _RecordingNativeTtsAdapter implements NativeTtsAdapter {
  final List<String> speakCalls = <String>[];
  int stopCount = 0;

  @override
  Future<void> setLanguage(String language) async {}

  @override
  Future<void> setSpeechRate(double rate) async {}

  @override
  Future<void> setVolume(double volume) async {}

  @override
  Future<void> setPitch(double pitch) async {}

  @override
  Future<void> speak(String text) async {
    speakCalls.add(text);
  }

  @override
  Future<void> stop() async {
    stopCount++;
  }
}

final class _RecordingAudioPlayerAdapter implements AudioPlayerAdapter {
  final List<Uint8List> playBytesCalls = <Uint8List>[];
  int stopCount = 0;
  int disposeCount = 0;

  @override
  Future<void> playBytes(Uint8List bytes) async {
    playBytesCalls.add(Uint8List.fromList(bytes));
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

final class _RecordingTelemetrySink implements VoiceTelemetrySink {
  final List<VoiceTelemetryEvent> events = <VoiceTelemetryEvent>[];

  @override
  Future<void> record(VoiceTelemetryEvent event) {
    events.add(event);
    return Future<void>.value();
  }
}
