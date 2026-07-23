import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/voice/omni_voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

final Uri _baseUri = Uri.parse('https://voice.example.com');
final Uri _speechUri = _baseUri.resolve('/v1/speech');

const String _oldToken = 'expired-id-token-payload';
const String _freshToken = 'refreshed-id-token-payload';
const String _authBodySentinel = 'UNAUTHENTICATED-7c9f3a-body';
final List<int> _wavBytes = utf8.encode('RIFF-test-wav');

http.Response _wavResponse() {
  return http.Response.bytes(
    _wavBytes,
    200,
    headers: const <String, String>{
      'content-type': 'audio/wav',
      'x-request-id': 'req-123',
      'x-voice-engine': 'omnivoice-prod',
      'x-model-version': 'omnivoice-2026-07',
      'x-audio-sample-rate': '24000',
      'cache-control': 'no-store',
    },
  );
}

http.Response _unauthorizedResponse({String body = _authBodySentinel}) {
  return http.Response(
    '{"detail":{"code":"UNAUTHENTICATED","message":"$body"}}',
    401,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

VoiceRequest _validRequest({
  String text = 'Hello world.',
  String language = 'en',
  String voiceId = 'teacher_female',
  double speed = 1.0,
}) {
  return VoiceRequest.create(
    text: text,
    language: language,
    voiceId: voiceId,
    speed: speed,
    contentId: 'word-001',
    contentType: 'word',
    mode: VoiceMode.practice,
  );
}

class _RecordingTokenProvider implements VoiceAuthTokenProvider {
  _RecordingTokenProvider({this.token = _oldToken, this.refreshedToken});

  final String token;
  final String? refreshedToken;
  final List<bool> forceRefreshFlags = <bool>[];

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    forceRefreshFlags.add(forceRefresh);
    if (forceRefresh && refreshedToken != null) {
      return refreshedToken!;
    }
    return token;
  }
}

class _RecordedRequest {
  _RecordedRequest(http.Request request)
    : method = request.method,
      url = request.url,
      headers = <String, String>{
        for (final MapEntry<String, String> entry in request.headers.entries)
          entry.key.toLowerCase(): entry.value,
      },
      body = request.body;

  final String method;
  final Uri url;
  final Map<String, String> headers;
  final String body;
}

class _SpeechServer {
  _SpeechServer(this._responses);

  final List<http.Response> _responses;
  final List<_RecordedRequest> requests = <_RecordedRequest>[];
  int _next = 0;

  Future<http.Response> handle(http.Request request) async {
    requests.add(_RecordedRequest(request));
    final http.Response response = _responses[_next];
    _next += 1;
    return response;
  }

  http.Client asClient() => MockClient(handle);
}

class _AuthRetryOutcome {
  const _AuthRetryOutcome({
    required this.failure,
    required this.server,
    required this.tokenProvider,
  });

  final VoiceFailure failure;
  final _SpeechServer server;
  final _RecordingTokenProvider tokenProvider;
}

OmniVoiceProvider _provider({
  required _SpeechServer server,
  required _RecordingTokenProvider tokenProvider,
}) {
  return OmniVoiceProvider(
    client: server.asClient(),
    authTokenProvider: tokenProvider,
    baseUri: _baseUri,
  );
}

Future<_AuthRetryOutcome> _runSecondUnauthorized({
  required String token,
  required String refreshedToken,
  String bodySentinel = _authBodySentinel,
}) async {
  final server = _SpeechServer(<http.Response>[
    _unauthorizedResponse(body: bodySentinel),
    _unauthorizedResponse(body: bodySentinel),
  ]);
  final tokenProvider = _RecordingTokenProvider(
    token: token,
    refreshedToken: refreshedToken,
  );
  try {
    await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());
    fail('Expected a VoiceFailure after a second 401.');
  } on VoiceFailure catch (failure) {
    return _AuthRetryOutcome(
      failure: failure,
      server: server,
      tokenProvider: tokenProvider,
    );
  }
}

void main() {
  test('POSTs exactly to baseUri.resolve("/v1/speech")', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final tokenProvider = _RecordingTokenProvider(token: 'id-token');

    await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());

    expect(server.requests, hasLength(1));
    expect(server.requests.single.method, 'POST');
    expect(server.requests.single.url, _speechUri);
  });

  test('first token request does not force a refresh', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final tokenProvider = _RecordingTokenProvider(token: 'id-token');

    await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());

    expect(tokenProvider.forceRefreshFlags, <bool>[false]);
  });

  test('sends bearer authorization and JSON content type', () async {
    const token = 'id-token';
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final tokenProvider = _RecordingTokenProvider(token: token);

    await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());

    expect(server.requests.single.headers['authorization'], 'Bearer $token');
    expect(server.requests.single.headers['content-type'], 'application/json');
  });

  test('sends only the backend speech fields', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    await _provider(
      server: server,
      tokenProvider: _RecordingTokenProvider(token: 'id-token'),
    ).synthesize(
      _validRequest(text: 'Hello world.', language: 'th', speed: 0.9),
    );

    final Map<String, dynamic> decoded =
        jsonDecode(server.requests.single.body) as Map<String, dynamic>;
    expect(decoded, <String, Object>{
      'text': 'Hello world.',
      'language': 'th',
      'voice': 'teacher_female',
      'speed': 0.9,
      'format': 'wav',
    });

    for (final String excluded in <String>[
      'contentId',
      'contentType',
      'mode',
      'assignedEngine',
    ]) {
      expect(decoded.containsKey(excluded), isFalse, reason: excluded);
    }
  });

  test('parses WAV bytes and every provenance header', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final audio = await _provider(
      server: server,
      tokenProvider: _RecordingTokenProvider(token: 'id-token'),
    ).synthesize(_validRequest());

    expect(audio.bytes, Uint8List.fromList(_wavBytes));
    expect(audio.requestId, 'req-123');
    expect(audio.engine, 'omnivoice-prod');
    expect(audio.modelVersion, 'omnivoice-2026-07');
    expect(audio.sampleRate, 24000);
  });

  test('does not refresh or retry on first success', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final tokenProvider = _RecordingTokenProvider(token: 'id-token');

    await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());

    expect(tokenProvider.forceRefreshFlags, <bool>[false]);
    expect(server.requests, hasLength(1));
  });

  test('first 401 forces one refresh and retries once', () async {
    final server = _SpeechServer(<http.Response>[
      _unauthorizedResponse(),
      _wavResponse(),
    ]);
    final tokenProvider = _RecordingTokenProvider(
      token: _oldToken,
      refreshedToken: _freshToken,
    );

    final audio = await _provider(
      server: server,
      tokenProvider: tokenProvider,
    ).synthesize(_validRequest());

    expect(tokenProvider.forceRefreshFlags, <bool>[false, true]);
    expect(server.requests, hasLength(2));
    expect(server.requests[0].headers['authorization'], 'Bearer $_oldToken');
    expect(server.requests[1].headers['authorization'], 'Bearer $_freshToken');
    expect(audio.bytes, Uint8List.fromList(_wavBytes));
    expect(audio.requestId, 'req-123');
  });

  group('second 401 after refresh', () {
    test('throws authentication after exactly two requests', () async {
      final outcome = await _runSecondUnauthorized(
        token: _oldToken,
        refreshedToken: _freshToken,
      );

      expect(outcome.failure.category, VoiceFailureCategory.authentication);
      expect(outcome.server.requests, hasLength(2));
      expect(outcome.tokenProvider.forceRefreshFlags, <bool>[false, true]);
    });

    test('uses one fixed safe message', () async {
      final first = await _runSecondUnauthorized(
        token: 'secret-old-aaa',
        refreshedToken: 'secret-fresh-bbb',
        bodySentinel: 'body-sentinel-one',
      );
      final second = await _runSecondUnauthorized(
        token: 'different-old-ccc',
        refreshedToken: 'different-fresh-ddd',
        bodySentinel: 'body-sentinel-two',
      );

      expect(first.failure.toString(), second.failure.toString());
    });

    test('never leaks tokens or response body', () async {
      final outcome = await _runSecondUnauthorized(
        token: 'secret-old-aaa',
        refreshedToken: 'secret-fresh-bbb',
        bodySentinel: 'UNAUTH-BODY-LEAK',
      );

      expect(outcome.failure.toString(), isNot(contains('secret-old-aaa')));
      expect(outcome.failure.toString(), isNot(contains('secret-fresh-bbb')));
      expect(outcome.failure.toString(), isNot(contains('UNAUTH-BODY-LEAK')));
    });
  });

  test('synthesize returns OmniVoiceAudio', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final audio = await _provider(
      server: server,
      tokenProvider: _RecordingTokenProvider(token: 'id-token'),
    ).synthesize(_validRequest());

    expect(audio, isA<OmniVoiceAudio>());
  });
}
