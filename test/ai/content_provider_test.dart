import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/voice/voice_auth_token_provider.dart';

final Uri _baseUri = Uri.parse('https://ai.example.com');
final Uri _contentUri = _baseUri.resolve('/v1/content');

const String _oldToken = 'expired-id-token-payload';
const String _freshToken = 'refreshed-id-token-payload';
const String _authBodySentinel = 'UNAUTHENTICATED-7c9f3a-body';

ContentRequest _validRequest({
  String text = 'cat',
  ContentKind kind = ContentKind.sentence,
  CefrLevel cefr = CefrLevel.a1,
  String language = 'en',
}) {
  return ContentRequest.create(
    text: text,
    kind: kind,
    cefr: cefr,
    language: language,
  );
}

/// Token provider that returns a known token; if forceRefresh is true it
/// returns the "fresh" token so a 401-retry test can prove the refresh
/// happened.
class _StubTokenProvider implements VoiceAuthTokenProvider {
  _StubTokenProvider({this.firstToken = _oldToken});

  final String firstToken;
  int refreshCalls = 0;

  @override
  Future<String> getIdToken({bool forceRefresh = false}) async {
    if (forceRefresh) refreshCalls++;
    return forceRefresh ? _freshToken : firstToken;
  }
}

/// Token provider that never refreshes; used to verify the retry-once-then-fail
/// behaviour when the second 401 also fails.
class _NeverRefreshTokenProvider implements VoiceAuthTokenProvider {
  @override
  Future<String> getIdToken({bool forceRefresh = false}) async => _oldToken;
}

class _CallbackTokenProvider implements VoiceAuthTokenProvider {
  _CallbackTokenProvider(this.read);
  final Future<String> Function(bool forceRefresh) read;
  @override
  Future<String> getIdToken({bool forceRefresh = false}) => read(forceRefresh);
}

http.Response _okResponse({
  String text = 'The cat sleeps peacefully.',
  String kind = 'sentence',
  String cefr = 'a1',
  String language = 'en',
  String modelVersion = 'lexiquest-lm-0.1',
  bool cached = false,
}) {
  return http.Response(
    jsonEncode({
      'text': text,
      'kind': kind,
      'cefr': cefr,
      'language': language,
      'model_version': modelVersion,
      'cached': cached,
    }),
    200,
    headers: const {'content-type': 'application/json'},
  );
}

http.Response _unauthorizedResponse({String body = _authBodySentinel}) {
  return http.Response(
    '{"detail":{"code":"UNAUTHENTICATED","message":"$body"}}',
    401,
    headers: const {'content-type': 'application/json'},
  );
}

http.Response _statusResponse(int status, {required String code}) {
  return http.Response(
    jsonEncode({
      'detail': {'code': code, 'message': 'msg'},
    }),
    status,
    headers: const {'content-type': 'application/json'},
  );
}

void main() {
  test(
    'authenticated content requests disable redirects at the configured origin',
    () async {
      final client = MockClient((request) async {
        expect(request.url, _contentUri);
        expect(request.headers['authorization'], 'Bearer $_oldToken');
        expect(request.headers['idempotency-key'], isNotEmpty);
        expect(
          request.followRedirects,
          isFalse,
          reason: 'a redirect must not forward a paid command or bearer token',
        );
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _StubTokenProvider(),
        baseUri: _baseUri,
      );

      expect(
        (await provider.generate(_validRequest())).text,
        'The cat sleeps peacefully.',
      );
    },
  );

  test(
    'retiring a content command while its token is pending prevents every POST',
    () async {
      final pending = Completer<String>();
      var current = true;
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _CallbackTokenProvider((_) => pending.future),
        baseUri: _baseUri,
      );
      final result = provider.generate(
        ContentRequest.create(
          text: 'cat',
          kind: ContentKind.sentence,
          stillCurrent: () => current,
        ),
      );
      current = false;
      pending.complete(_oldToken);
      await expectLater(
        result,
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.cancelled,
          ),
        ),
      );
      expect(posts, 0);
    },
  );

  test(
    'an A-B-A auth generation cannot submit a retired paid content command',
    () async {
      final pending = Completer<String>();
      Object binding = ('synthetic-a', 0);
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _CallbackTokenProvider((_) => pending.future),
        baseUri: _baseUri,
        readAuthBinding: () => binding,
      );
      final result = provider.generate(_validRequest());
      binding = ('synthetic-b', 1);
      binding = ('synthetic-a', 2);
      pending.complete(_oldToken);
      await expectLater(
        result,
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.cancelled,
          ),
        ),
      );
      expect(posts, 0);
    },
  );

  test(
    'switching auth during a 401 refresh cannot send the second POST',
    () async {
      Object binding = ('synthetic-a', 0);
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return _unauthorizedResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _CallbackTokenProvider((refresh) async {
          if (refresh) binding = ('synthetic-b', 1);
          return refresh ? _freshToken : _oldToken;
        }),
        baseUri: _baseUri,
        readAuthBinding: () => binding,
      );
      await expectLater(
        provider.generate(_validRequest()),
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.cancelled,
          ),
        ),
      );
      expect(posts, 1);
    },
  );

  test(
    'a missing current auth binding does not acquire a token or POST',
    () async {
      var tokenReads = 0;
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _CallbackTokenProvider((_) async {
          tokenReads++;
          return _oldToken;
        }),
        baseUri: _baseUri,
        readAuthBinding: () => null,
      );
      await expectLater(
        provider.generate(_validRequest()),
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.authentication,
          ),
        ),
      );
      expect((tokenReads, posts), (0, 0));
    },
  );

  test(
    'content returned after the caller is retired cannot be accepted',
    () async {
      var current = true;
      final client = MockClient((_) async {
        current = false;
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _StubTokenProvider(),
        baseUri: _baseUri,
      );
      await expectLater(
        provider.generate(
          ContentRequest.create(
            text: 'cat',
            kind: ContentKind.sentence,
            stillCurrent: () => current,
          ),
        ),
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.cancelled,
          ),
        ),
      );
    },
  );

  test(
    'token failures and token timeouts have fixed safe errors and never POST',
    () async {
      var posts = 0;
      final client = MockClient((_) async {
        posts++;
        return _okResponse();
      });
      addTearDown(client.close);
      for (final hanging in [false, true]) {
        final provider = HttpContentProvider(
          client: client,
          authTokenProvider: _CallbackTokenProvider((_) {
            if (hanging) return Completer<String>().future;
            throw StateError('PRIVATE-CREDENTIAL-SENTINEL');
          }),
          baseUri: _baseUri,
          timeout: const Duration(milliseconds: 5),
        );
        await expectLater(
          provider.generate(_validRequest()),
          throwsA(
            isA<AiFailure>()
                .having(
                  (failure) => failure.category,
                  'category',
                  hanging
                      ? AiFailureCategory.timeout
                      : AiFailureCategory.authentication,
                )
                .having(
                  (failure) => failure.toString(),
                  'safe error',
                  isNot(contains('PRIVATE-CREDENTIAL-SENTINEL')),
                ),
          ),
        );
      }
      expect(posts, 0);
    },
  );

  for (final (status, code, category) in [
    (402, 'BILLING_ENTITLEMENT_REQUIRED', AiFailureCategory.paymentRequired),
    (403, 'BILLING_ENTITLEMENT_REQUIRED', AiFailureCategory.paymentRequired),
    (403, 'BILLING_ACCOUNT_REQUIRED', AiFailureCategory.authentication),
    (429, 'BILLING_QUOTA_EXHAUSTED', AiFailureCategory.quotaExhausted),
    (409, 'BILLING_OPERATION_UNCERTAIN', AiFailureCategory.operationUncertain),
    (409, 'BILLING_REQUEST_CONFLICT', AiFailureCategory.validation),
  ]) {
    test(
      '$status $code preserves a typed managed content outcome without leaking the response',
      () async {
        var posts = 0;
        final client = MockClient((_) async {
          posts++;
          return http.Response(
            jsonEncode({
              'detail': {
                'code': code,
                'message': 'PRIVATE-MANAGED-CONTENT-SENTINEL',
              },
            }),
            status,
          );
        });
        addTearDown(client.close);
        final provider = HttpContentProvider(
          client: client,
          authTokenProvider: _StubTokenProvider(),
          baseUri: _baseUri,
        );
        await expectLater(
          provider.generate(_validRequest()),
          throwsA(
            isA<AiFailure>()
                .having((failure) => failure.category, 'category', category)
                .having(
                  (failure) => failure.toString(),
                  'safe error',
                  isNot(contains('PRIVATE-MANAGED-CONTENT-SENTINEL')),
                ),
          ),
        );
        expect(posts, 1);
      },
    );
  }

  test(
    'one content intent keeps its operation identity through auth and manual retries',
    () async {
      final requests = <http.Request>[];
      final client = MockClient((request) async {
        requests.add(request);
        if (requests.length == 1) return _unauthorizedResponse();
        if (requests.length == 2) {
          throw http.ClientException('synthetic response lost');
        }
        return _okResponse();
      });
      addTearDown(client.close);
      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: _StubTokenProvider(),
        baseUri: _baseUri,
      );
      final original = _validRequest();
      await expectLater(
        provider.generate(original),
        throwsA(
          isA<AiFailure>().having(
            (failure) => failure.category,
            'category',
            AiFailureCategory.network,
          ),
        ),
      );
      await provider.generate(original);
      await provider.generate(_validRequest());

      expect(requests, hasLength(4));
      final identities = requests
          .map((request) => request.headers['idempotency-key'])
          .toList();
      for (final identity in identities) {
        expect(
          identity,
          matches(
            RegExp(
              r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
            ),
          ),
        );
      }
      expect(identities.take(3).toSet(), hasLength(1));
      expect(identities.last, isNot(identities.first));
      expect(requests.map((request) => request.body).toSet(), hasLength(1));
    },
  );

  test('posts to /v1/content and parses a successful response', () async {
    final tokenProvider = _StubTokenProvider();
    String? sentToken;
    String? sentBody;

    final client = MockClient((request) async {
      sentToken = request.headers['authorization'];
      sentBody = request.body;
      expect(request.url, _contentUri);
      expect(request.headers['content-type'], 'application/json');
      return _okResponse();
    });

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    final response = await provider.generate(_validRequest());

    expect(sentToken, 'Bearer $_oldToken');
    expect(sentBody, contains('"text":"cat"'));
    expect(response.text, 'The cat sleeps peacefully.');
    expect(response.kind, ContentKind.sentence);
    expect(response.cefr, CefrLevel.a1);
    expect(response.cached, isFalse);
    expect(response.modelVersion, 'lexiquest-lm-0.1');
  });

  test('refreshes the token exactly once after a first 401', () async {
    final tokenProvider = _StubTokenProvider();
    final seenTokens = <String>[];

    final client = MockClient((request) async {
      seenTokens.add(request.headers['authorization']!);
      // First call (stale token) -> 401; second call (refreshed token) -> OK.
      if (seenTokens.length == 1) return _unauthorizedResponse();
      return _okResponse();
    });

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    final response = await provider.generate(_validRequest());

    expect(seenTokens, ['Bearer $_oldToken', 'Bearer $_freshToken']);
    expect(tokenProvider.refreshCalls, 1);
    expect(response.text, 'The cat sleeps peacefully.');
  });

  test(
    'throws authentication failure when 401 persists after refresh',
    () async {
      final tokenProvider = _NeverRefreshTokenProvider();

      final client = MockClient((request) async => _unauthorizedResponse());

      final provider = HttpContentProvider(
        client: client,
        authTokenProvider: tokenProvider,
        baseUri: _baseUri,
      );

      expect(
        () => provider.generate(_validRequest()),
        throwsA(
          isA<AiFailure>().having(
            (f) => f.category,
            'category',
            AiFailureCategory.authentication,
          ),
        ),
      );
    },
  );

  test('maps 400 detail code to validation failure', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async => _statusResponse(400, code: 'INVALID_REQUEST'),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.validation,
        ),
      ),
    );
  });

  test('maps 429 to rateLimited', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async => _statusResponse(429, code: 'RATE_LIMITED'),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.rateLimited,
        ),
      ),
    );
  });

  test('maps 503 PROVIDER_UNAVAILABLE to providerUnavailable', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async => _statusResponse(503, code: 'PROVIDER_UNAVAILABLE'),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.providerUnavailable,
        ),
      ),
    );
  });

  test('maps 503 CONTENT_GENERATION_FAILED to generation', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async =>
          _statusResponse(503, code: 'CONTENT_GENERATION_FAILED'),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.generation,
        ),
      ),
    );
  });

  test('timeout throws the typed timeout failure', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient((request) async {
      await Future<void>.delayed(const Duration(seconds: 5));
      return _okResponse();
    });

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
      timeout: const Duration(milliseconds: 50),
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.timeout,
        ),
      ),
    );
  });

  test('network error throws the typed network failure', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient((request) async {
      throw http.ClientException('connection reset');
    });

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.network,
        ),
      ),
    );
  });

  test('unexpected transport error becomes typed network failure', () async {
    const secret = 'private-transport-detail';
    final client = MockClient((request) async {
      throw Exception(secret);
    });
    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: _StubTokenProvider(),
      baseUri: Uri.parse('https://ai.example.test'),
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>()
            .having(
              (failure) => failure.category,
              'category',
              AiFailureCategory.network,
            )
            .having(
              (failure) => failure.message,
              'message',
              isNot(contains(secret)),
            ),
      ),
    );
  });

  test('does not leak the bearer token into the thrown failure', () async {
    final secretToken = 'super-secret-id-token-7c9f3a';
    final tokenProvider = _StubTokenProvider(firstToken: secretToken);
    final client = MockClient((request) async => _unauthorizedResponse());

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    try {
      await provider.generate(_validRequest());
      fail('expected AiFailure');
    } on AiFailure catch (failure) {
      final repr = '${failure.message}\n${failure.toString()}';
      expect(
        repr.contains(secretToken),
        isFalse,
        reason: 'token must not appear in failure message or toString',
      );
    }
  });

  test('rejects a 200 response missing required fields', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async => http.Response(
        '{"text":"ok"}',
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(
        isA<AiFailure>().having(
          (f) => f.category,
          'category',
          AiFailureCategory.generation,
        ),
      ),
    );
  });

  test('rejects a 200 response with empty text', () async {
    final tokenProvider = _StubTokenProvider();
    final client = MockClient(
      (request) async => http.Response(
        jsonEncode({
          'text': '   ',
          'kind': 'sentence',
          'cefr': 'a1',
          'language': 'en',
          'model_version': 'lexiquest-lm-0.1',
          'cached': false,
        }),
        200,
        headers: const {'content-type': 'application/json'},
      ),
    );

    final provider = HttpContentProvider(
      client: client,
      authTokenProvider: tokenProvider,
      baseUri: _baseUri,
    );

    await expectLater(
      () => provider.generate(_validRequest()),
      throwsA(isA<AiFailure>()),
    );
  });
}
