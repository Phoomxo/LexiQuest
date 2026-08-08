import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';
import 'package:vocab_learning_app/voice/voice_mirror_gateway.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';

final _baseUri = Uri.parse('https://voice.example.com');

const _sessionId = 'session-abc';
final _wavBytes = Uint8List.fromList(utf8.encode('RIFF\x00\x00\x00\x00WAVE'));
final _generatedWav = Uint8List.fromList(utf8.encode('RIFF-generated'));

Matcher _failure(VoiceFailureCategory category) {
  return isA<VoiceFailure>().having(
    (failure) => failure.category,
    'category',
    category,
  );
}

http.Response _leaseResponse({required int leaseIn, required int absoluteIn}) {
  return http.Response(
    jsonEncode({
      'sessionId': _sessionId,
      'leaseExpiresAtEpochMs': leaseIn,
      'absoluteExpiresAtEpochMs': absoluteIn,
    }),
    201,
    headers: const {'cache-control': 'no-store'},
  );
}

http.Response _wav() => http.Response.bytes(
  _generatedWav,
  200,
  headers: const {
    'content-type': 'audio/wav',
    'x-request-id': 'req-mirror',
    'x-voice-engine': 'voxcpm2-mirror',
    'x-model-version': '2.0.3',
    'x-audio-sample-rate': '48000',
    'cache-control': 'no-store',
  },
);

http.Response _error(int status, String code, {String? message}) {
  return http.Response(
    jsonEncode({
      'detail': {'code': code, 'message': message ?? 'private body'},
    }),
    status,
  );
}

final class _Tokens implements VoiceAuthTokenProvider {
  final calls = <bool>[];

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    calls.add(forceRefresh);
    return forceRefresh ? 'fresh-token' : 'old-token';
  }
}

void main() {
  group('enroll', () {
    test(
      'posts raw WAV bytes with consent header and parses the lease',
      () async {
        http.Request? recorded;
        final tokens = _Tokens();
        final gateway = VoiceMirrorGateway(
          client: MockClient((request) async {
            recorded = request;
            return _leaseResponse(leaseIn: 1, absoluteIn: 2);
          }),
          authTokenProvider: tokens,
          baseUri: _baseUri,
        );

        final lease = await gateway.enroll(wavBytes: _wavBytes);

        expect(recorded?.method, 'POST');
        expect(recorded?.url, _baseUri.resolve('/v1/voice-mirror/sessions'));
        expect(recorded?.headers['authorization'], 'Bearer old-token');
        expect(recorded?.headers['x-voice-mirror-consent'], 'voice-mirror-v1');
        expect(recorded?.headers['content-type'], 'audio/wav');
        expect(recorded?.bodyBytes, _wavBytes);
        expect(tokens.calls, [false]);

        expect(lease.sessionId, _sessionId);
        expect(lease.leaseExpiresAtEpochMs, 1);
        expect(lease.absoluteExpiresAtEpochMs, 2);
      },
    );

    test('maps a missing consent header to consentMissing', () async {
      final gateway = VoiceMirrorGateway(
        client: MockClient((_) async => _error(403, 'CONSENT_MISSING')),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      await expectLater(
        gateway.enroll(wavBytes: _wavBytes),
        throwsA(_failure(VoiceFailureCategory.consentMissing)),
      );
    });

    test('maps invalid audio and oversized payloads to validation', () async {
      for (final response in [
        _error(422, 'INVALID_AUDIO'),
        _error(413, 'PAYLOAD_TOO_LARGE'),
        _error(415, 'UNSUPPORTED_MEDIA_TYPE'),
      ]) {
        final gateway = VoiceMirrorGateway(
          client: MockClient((_) async => response),
          authTokenProvider: _Tokens(),
          baseUri: _baseUri,
        );

        await expectLater(
          gateway.enroll(wavBytes: _wavBytes),
          throwsA(_failure(VoiceFailureCategory.validation)),
        );
      }
    });

    test('maps the provider kill switch to providerDisabled', () async {
      const sentinel = 'private-provider-body';
      final gateway = VoiceMirrorGateway(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":{"code":"PROVIDER_DISABLED","message":"$sentinel"}}',
            503,
          ),
        ),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      VoiceFailure? failure;
      try {
        await gateway.enroll(wavBytes: _wavBytes);
      } on VoiceFailure catch (error) {
        failure = error;
      }

      expect(failure?.category, VoiceFailureCategory.providerDisabled);
      expect(failure.toString(), isNot(contains(sentinel)));
    });
  });

  group('heartbeat', () {
    test('renews the lease and parses the refreshed timestamps', () async {
      http.Request? recorded;
      final gateway = VoiceMirrorGateway(
        client: MockClient((request) async {
          recorded = request;
          return http.Response(
            jsonEncode({
              'sessionId': _sessionId,
              'leaseExpiresAtEpochMs': 3,
              'absoluteExpiresAtEpochMs': 2,
            }),
            200,
            headers: const {'cache-control': 'no-store'},
          );
        }),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      final lease = await gateway.heartbeat(sessionId: _sessionId);

      expect(recorded?.method, 'POST');
      expect(
        recorded?.url,
        _baseUri.resolve('/v1/voice-mirror/sessions/$_sessionId/heartbeat'),
      );
      expect(lease.leaseExpiresAtEpochMs, 3);
      expect(lease.absoluteExpiresAtEpochMs, 2);
    });

    test('maps an expired session to sessionExpired', () async {
      final gateway = VoiceMirrorGateway(
        client: MockClient((_) async => _error(410, 'SESSION_EXPIRED')),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      await expectLater(
        gateway.heartbeat(sessionId: _sessionId),
        throwsA(_failure(VoiceFailureCategory.sessionExpired)),
      );
    });
  });

  group('synthesize', () {
    test(
      'posts the bounded mirror fields and parses binary WAV provenance',
      () async {
        http.Request? recorded;
        final gateway = VoiceMirrorGateway(
          client: MockClient((request) async {
            recorded = request;
            return _wav();
          }),
          authTokenProvider: _Tokens(),
          baseUri: _baseUri,
        );

        final audio = await gateway.synthesize(
          sessionId: _sessionId,
          contentId: 'word-cat',
          text: 'Cat',
          language: 'en',
        );

        expect(
          recorded?.url,
          _baseUri.resolve('/v1/voice-mirror/sessions/$_sessionId/speech'),
        );
        expect(recorded?.headers['content-type'], 'application/json');
        expect(jsonDecode(recorded!.body), {
          'contentId': 'word-cat',
          'text': 'Cat',
          'language': 'en',
        });
        expect(audio.engine, VoiceEngine.voxCpmMirror);
        expect(audio.requestId, 'req-mirror');
        expect(audio.modelVersion, '2.0.3');
        expect(audio.sampleRate, 48000);
        expect(audio.bytes, _generatedWav);
      },
    );

    test('maps session busy and rate limits to rateLimited', () async {
      for (final response in [
        _error(409, 'SESSION_BUSY'),
        _error(429, 'RATE_LIMITED'),
      ]) {
        final gateway = VoiceMirrorGateway(
          client: MockClient((_) async => response),
          authTokenProvider: _Tokens(),
          baseUri: _baseUri,
        );

        await expectLater(
          gateway.synthesize(
            sessionId: _sessionId,
            contentId: 'word-cat',
            text: 'Cat',
            language: 'en',
          ),
          throwsA(_failure(VoiceFailureCategory.rateLimited)),
        );
      }
    });

    test('maps over-long text to validation', () async {
      final gateway = VoiceMirrorGateway(
        client: MockClient((_) async => _error(422, 'TEXT_TOO_LONG')),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      await expectLater(
        gateway.synthesize(
          sessionId: _sessionId,
          contentId: 'word-cat',
          text: 'Cat',
          language: 'en',
        ),
        throwsA(_failure(VoiceFailureCategory.validation)),
      );
    });

    test('maps synthesis failure to synthesis without leaking detail', () async {
      const sentinel = 'private-synthesis-body';
      final gateway = VoiceMirrorGateway(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":{"code":"SYNTHESIS_FAILED","message":"$sentinel","request_id":"secret-id"}}',
            503,
            headers: {'x-request-id': 'secret-id'},
          ),
        ),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      VoiceFailure? failure;
      try {
        await gateway.synthesize(
          sessionId: _sessionId,
          contentId: 'word-cat',
          text: 'Cat',
          language: 'en',
        );
      } on VoiceFailure catch (error) {
        failure = error;
      }

      expect(failure?.category, VoiceFailureCategory.synthesis);
      expect(failure.toString(), isNot(contains(sentinel)));
      expect(failure.toString(), isNot(contains('secret-id')));
    });
  });

  group('delete', () {
    test('deletes the session idempotently', () async {
      http.Request? recorded;
      final gateway = VoiceMirrorGateway(
        client: MockClient((request) async {
          recorded = request;
          return http.Response('', 204);
        }),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      await gateway.delete(sessionId: _sessionId);
      expect(recorded?.method, 'DELETE');
      expect(
        recorded?.url,
        _baseUri.resolve('/v1/voice-mirror/sessions/$_sessionId'),
      );
    });

    test(
      'treats a session-not-found as a successful idempotent delete',
      () async {
        var sends = 0;
        final gateway = VoiceMirrorGateway(
          client: MockClient((_) async {
            sends++;
            return _error(404, 'SESSION_NOT_FOUND');
          }),
          authTokenProvider: _Tokens(),
          baseUri: _baseUri,
        );

        await gateway.delete(sessionId: _sessionId);

        expect(sends, 1);
      },
    );
  });

  group('authentication', () {
    test('refreshes the token exactly once after the first 401', () async {
      var calls = 0;
      final tokens = _Tokens();
      final gateway = VoiceMirrorGateway(
        client: MockClient((request) async {
          calls++;
          if (request.url.path.endsWith('/sessions') &&
              request.method == 'POST' &&
              request.headers['content-type'] != 'application/json') {
            return calls == 1
                ? http.Response('', 401)
                : _leaseResponse(leaseIn: 1, absoluteIn: 2);
          }
          return _leaseResponse(leaseIn: 1, absoluteIn: 2);
        }),
        authTokenProvider: tokens,
        baseUri: _baseUri,
      );

      await gateway.enroll(wavBytes: _wavBytes);

      expect(calls, 2);
      expect(tokens.calls, [false, true]);
    });

    test('gives up with authentication failure after a second 401', () async {
      final tokens = _Tokens();
      final gateway = VoiceMirrorGateway(
        client: MockClient((_) async => http.Response('', 401)),
        authTokenProvider: tokens,
        baseUri: _baseUri,
      );

      await expectLater(
        gateway.enroll(wavBytes: _wavBytes),
        throwsA(_failure(VoiceFailureCategory.authentication)),
      );
      expect(tokens.calls, [false, true]);
    });

    test('does not refresh on auth unavailability', () async {
      final tokens = _Tokens();
      final gateway = VoiceMirrorGateway(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":{"code":"AUTH_UNAVAILABLE","message":"down"}}',
            503,
          ),
        ),
        authTokenProvider: tokens,
        baseUri: _baseUri,
      );

      await expectLater(
        gateway.enroll(wavBytes: _wavBytes),
        throwsA(_failure(VoiceFailureCategory.authentication)),
      );
      expect(tokens.calls, [false]);
    });
  });

  group('privacy', () {
    test('keeps the bearer token out of the request url and body', () async {
      http.Request? recorded;
      final gateway = VoiceMirrorGateway(
        client: MockClient((request) async {
          recorded = request;
          return _leaseResponse(leaseIn: 1, absoluteIn: 2);
        }),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      await gateway.enroll(wavBytes: _wavBytes);

      expect(recorded!.url.toString(), isNot(contains('old-token')));
      // The WAV body bytes are non-text; ensure no token leaks via body.
      expect(
        utf8.decode(recorded!.bodyBytes, allowMalformed: true),
        isNot(contains('old-token')),
      );
    });

    test('never leaks failure detail into the failure message', () async {
      const sentinel = 'never-leak-this';
      final gateway = VoiceMirrorGateway(
        client: MockClient(
          (_) async => http.Response(
            '{"detail":{"code":"SESSION_NOT_FOUND","message":"$sentinel"}}',
            404,
          ),
        ),
        authTokenProvider: _Tokens(),
        baseUri: _baseUri,
      );

      VoiceFailure? failure;
      try {
        await gateway.heartbeat(sessionId: _sessionId);
      } on VoiceFailure catch (error) {
        failure = error;
      }

      expect(failure?.category, VoiceFailureCategory.unknown);
      expect(failure.toString(), isNot(contains(sentinel)));
    });
  });
}
