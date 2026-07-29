import 'dart:async';
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

const Duration _tinyTimeout = Duration(milliseconds: 1);

http.Response _errorResponse(
  int status, {
  String? code,
  String message = 'error-message',
  String? detailTrace,
}) {
  final detail = <String, Object>{'message': message};
  if (code != null) detail['code'] = code;
  if (detailTrace != null) detail['trace'] = detailTrace;
  return http.Response(
    jsonEncode(<String, Object>{'detail': detail}),
    status,
    headers: const <String, String>{'content-type': 'application/json'},
  );
}

http.Response _wavResponseWith({
  String contentType = 'audio/wav',
  List<int>? bytes,
  String? requestId = 'req-123',
  String? engine = 'omnivoice-prod',
  String? modelVersion = 'omnivoice-2026-07',
  String? sampleRate = '24000',
}) {
  return http.Response.bytes(
    bytes ?? _wavBytes,
    200,
    headers: <String, String>{
      if (contentType.isNotEmpty) 'content-type': contentType,
      'x-request-id': ?requestId,
      'x-voice-engine': ?engine,
      'x-model-version': ?modelVersion,
      'x-audio-sample-rate': ?sampleRate,
    },
  );
}

List<({String name, http.Response response})> _malformedWavCases() {
  return <({String name, http.Response response})>[
    (
      name: 'non-WAV content type',
      response: _wavResponseWith(contentType: 'audio/mpeg'),
    ),
    (name: 'empty bytes', response: _wavResponseWith(bytes: <int>[])),
    (name: 'blank request id', response: _wavResponseWith(requestId: '   ')),
    (name: 'missing request id', response: _wavResponseWith(requestId: null)),
    (name: 'blank voice engine', response: _wavResponseWith(engine: '   ')),
    (name: 'missing voice engine', response: _wavResponseWith(engine: null)),
    (
      name: 'blank model version',
      response: _wavResponseWith(modelVersion: '   '),
    ),
    (
      name: 'missing model version',
      response: _wavResponseWith(modelVersion: null),
    ),
    (name: 'missing sample rate', response: _wavResponseWith(sampleRate: null)),
    (
      name: 'non-integer sample rate',
      response: _wavResponseWith(sampleRate: 'not-a-number'),
    ),
    (
      name: 'non-positive sample rate',
      response: _wavResponseWith(sampleRate: '0'),
    ),
  ];
}

OmniVoiceProvider _providerWith({
  required http.Client client,
  Duration timeout = const Duration(seconds: 30),
  _RecordingTokenProvider? tokenProvider,
}) {
  return OmniVoiceProvider(
    client: client,
    authTokenProvider: tokenProvider ?? _RecordingTokenProvider(),
    baseUri: _baseUri,
    timeout: timeout,
  );
}

class _ErrorOutcome {
  const _ErrorOutcome({
    this.failure,
    required this.server,
    required this.tokens,
  });

  final VoiceFailure? failure;
  final _SpeechServer server;
  final _RecordingTokenProvider tokens;
}

Future<_ErrorOutcome> _runResponse(http.Response response) async {
  final server = _SpeechServer(<http.Response>[response]);
  final tokens = _RecordingTokenProvider();
  try {
    await _provider(
      server: server,
      tokenProvider: tokens,
    ).synthesize(_validRequest());
    return _ErrorOutcome(server: server, tokens: tokens);
  } on VoiceFailure catch (failure) {
    return _ErrorOutcome(failure: failure, server: server, tokens: tokens);
  }
}

Future<VoiceFailure> _failureFromResponse(http.Response response) async {
  final outcome = await _runResponse(response);
  expect(outcome.failure, isNotNull, reason: 'Expected a VoiceFailure.');
  return outcome.failure!;
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

  test('maps backend status/code to VoiceFailure categories', () async {
    const cases = <(int, String?, VoiceFailureCategory)>[
      (400, null, VoiceFailureCategory.validation),
      (422, 'TEXT_TOO_LONG', VoiceFailureCategory.validation),
      (422, null, VoiceFailureCategory.validation),
      (429, 'RATE_LIMITED', VoiceFailureCategory.rateLimited),
      (503, 'MODEL_UNAVAILABLE', VoiceFailureCategory.modelUnavailable),
      (503, 'SYNTHESIS_FAILED', VoiceFailureCategory.synthesis),
      (503, 'AUTH_UNAVAILABLE', VoiceFailureCategory.authentication),
      (500, 'UNRECOGNIZED_CODE', VoiceFailureCategory.unknown),
    ];

    for (final (status, code, expected) in cases) {
      final failure = await _failureFromResponse(
        _errorResponse(status, code: code),
      );
      expect(failure.category, expected, reason: 'status $status code $code');
    }
  });

  test('malformed 200 responses map to synthesis', () async {
    for (final testCase in _malformedWavCases()) {
      final outcome = await _runResponse(testCase.response);

      expect(outcome.failure, isNotNull, reason: testCase.name);
      expect(
        outcome.failure!.category,
        VoiceFailureCategory.synthesis,
        reason: testCase.name,
      );
    }
  });

  test('non-401 errors never refresh the token or retry', () async {
    final responses = <http.Response>[
      _errorResponse(429, code: 'RATE_LIMITED'),
      _errorResponse(503, code: 'MODEL_UNAVAILABLE'),
    ];

    for (final response in responses) {
      final outcome = await _runResponse(response);

      expect(outcome.failure, isNotNull);
      expect(outcome.tokens.forceRefreshFlags, <bool>[false]);
      expect(outcome.server.requests, hasLength(1));
    }
  });

  test('timeout maps to a timeout VoiceFailure', () async {
    final client = MockClient((_) => Completer<http.Response>().future);
    final provider = _providerWith(client: client, timeout: _tinyTimeout);

    await expectLater(
      provider.synthesize(_validRequest()),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.timeout,
        ),
      ),
    );
  });

  test('timeout uses one fixed safe message', () async {
    Future<VoiceFailure> capture() async {
      final client = MockClient((_) => Completer<http.Response>().future);
      final provider = _providerWith(client: client, timeout: _tinyTimeout);
      return _captureFailure(() => provider.synthesize(_validRequest()));
    }

    final first = await capture();
    final second = await capture();

    expect(first.toString(), second.toString());
  });

  test('http.ClientException maps to a network VoiceFailure', () async {
    final client = MockClient(
      (_) async =>
          throw http.ClientException('credential-sentinel-7c9f3a body-leak'),
    );
    final provider = _providerWith(client: client);

    await expectLater(
      provider.synthesize(_validRequest()),
      throwsA(
        isA<VoiceFailure>().having(
          (failure) => failure.category,
          'category',
          VoiceFailureCategory.network,
        ),
      ),
    );
  });

  test('network failure uses a fixed safe message and leaks nothing', () async {
    Future<VoiceFailure> capture(String message) async {
      final client = MockClient(
        (_) async => throw http.ClientException(message),
      );
      final provider = _providerWith(client: client);
      return _captureFailure(() => provider.synthesize(_validRequest()));
    }

    final first = await capture('credential-sentinel-aaa');
    final second = await capture('different-body-bbb');

    expect(first.toString(), second.toString());
    expect(first.toString(), isNot(contains('credential-sentinel-aaa')));
    expect(first.toString(), isNot(contains('different-body-bbb')));
  });

  test('failure never exposes error body, code, or message', () async {
    final failure = await _failureFromResponse(
      _errorResponse(
        429,
        code: 'RATE_LIMITED-LEAK',
        message: 'leaky-message-7c9f3a',
        detailTrace: 'leaky-trace-body-7c9f3a',
      ),
    );
    final text = failure.toString();

    expect(text, isNot(contains('RATE_LIMITED-LEAK')));
    expect(text, isNot(contains('leaky-message-7c9f3a')));
    expect(text, isNot(contains('leaky-trace-body-7c9f3a')));
  });

  test('same source category yields identical safe toString', () async {
    final first = await _failureFromResponse(
      _errorResponse(429, code: 'RATE_LIMITED', message: 'first detail'),
    );
    final second = await _failureFromResponse(
      _errorResponse(429, code: 'RATE_LIMITED', message: 'second detail'),
    );

    expect(first.toString(), second.toString());
  });

  test('mutating a returned bytes copy cannot alter later reads', () async {
    final server = _SpeechServer(<http.Response>[_wavResponse()]);
    final audio = await _provider(
      server: server,
      tokenProvider: _RecordingTokenProvider(),
    ).synthesize(_validRequest());

    final firstRead = audio.bytes;
    firstRead[0] = 0xFF;

    expect(audio.bytes, Uint8List.fromList(_wavBytes));
  });
}
