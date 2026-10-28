import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/gemini/data/gemini_rest_gateway.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

void main() {
  const key = 'test-key-that-is-long-enough-123456';

  test('validates key in header without putting it in URI', () async {
    late http.Request captured;
    final gateway = GeminiRestGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({'name': 'models/gemini-2.5-flash-lite'}),
          200,
        );
      }),
    );

    await gateway.validateKey(key);

    expect(captured.url.toString(), isNot(contains(key)));
    expect(captured.headers['x-goog-api-key'], key);
    expect(captured.method, 'GET');
  });

  test(
    'generates bounded tutor request and parses real candidate text',
    () async {
      late Map<String, dynamic> body;
      final gateway = GeminiRestGateway(
        client: MockClient((request) async {
          body = jsonDecode(request.body) as Map<String, dynamic>;
          return http.Response(
            jsonEncode({
              'candidates': [
                {
                  'content': {
                    'parts': [
                      {'text': 'Could you give one concrete example?'},
                    ],
                  },
                  'finishReason': 'STOP',
                },
              ],
            }),
            200,
          );
        }),
      );

      final reply = await gateway.generateTutorReply(
        key: key,
        scenario: 'Job Interview',
        learnerMessage: 'I enjoy solving problems.',
        learningSummary: 'answers=5;accuracy=80%;weaknesses=apple:40%(n=5)',
      );

      expect(reply, 'Could you give one concrete example?');
      expect(body['generationConfig'], {
        'candidateCount': 1,
        'maxOutputTokens': 120,
      });
      expect(jsonEncode(body), contains('Consented learning summary'));
      expect(jsonEncode(body), isNot(contains(key)));
    },
  );

  test(
    'maps invalid key, quota, provider, malformed and offline distinctly',
    () async {
      Future<void> expectCode(
        int status,
        GeminiFailureCode code, {
        String body = '{}',
      }) async {
        final gateway = GeminiRestGateway(
          client: MockClient((_) async => http.Response(body, status)),
        );
        await expectLater(
          gateway.validateKey(key),
          throwsA(
            isA<GeminiException>().having((error) => error.code, 'code', code),
          ),
        );
      }

      await expectCode(403, GeminiFailureCode.invalidKey);
      await expectCode(429, GeminiFailureCode.quota);
      await expectCode(503, GeminiFailureCode.providerUnavailable);
      await expectCode(200, GeminiFailureCode.malformedResponse);

      final offline = GeminiRestGateway(
        client: MockClient((_) async => throw StateError('must not call')),
        isOffline: () async => true,
      );
      await expectLater(
        offline.validateKey(key),
        throwsA(
          isA<GeminiException>().having(
            (error) => error.code,
            'code',
            GeminiFailureCode.offline,
          ),
        ),
      );
    },
  );

  test('aborts an in-flight request on cancellation', () async {
    final cancellation = GeminiCancellation();
    final gateway = GeminiRestGateway(client: _AbortAwareClient());

    final validation = gateway.validateKey(key, cancellation: cancellation);
    await Future<void>.delayed(Duration.zero);
    cancellation.cancel();

    await expectLater(
      validation,
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.cancelled,
        ),
      ),
    );
  });

  test('aborts a stalled request at the configured timeout', () async {
    final gateway = GeminiRestGateway(
      client: _AbortAwareClient(),
      requestTimeout: const Duration(milliseconds: 20),
    );

    await expectLater(
      gateway.validateKey(key),
      throwsA(
        isA<GeminiException>().having(
          (error) => error.code,
          'code',
          GeminiFailureCode.timeout,
        ),
      ),
    );
  });
}

final class _AbortAwareClient extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final abortable = request as http.Abortable;
    await abortable.abortTrigger;
    throw http.RequestAbortedException(request.url);
  }
}
