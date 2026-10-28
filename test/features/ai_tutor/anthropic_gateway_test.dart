import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/anthropic_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

Matcher _failure(GeminiFailureCode code) =>
    isA<GeminiException>().having((e) => e.code, 'code', code);

http.Response _claudeResponse(String text) => http.Response(
  jsonEncode({
    'content': [
      {'type': 'text', 'text': text},
    ],
  }),
  200,
);

void main() {
  const key = 'anthropic-test-key';
  final baseUri = Uri.https('api.anthropic.com', '/');

  test('declares the claude provider id', () {
    final gateway = AnthropicGateway(
      client: MockClient((_) async => _claudeResponse('hi')),
      baseUri: baseUri,
      model: 'claude-3-5-haiku-latest',
    );
    expect(gateway.providerId, AiProvider.claude);
    expect(gateway.model, 'claude-3-5-haiku-latest');
  });

  test(
    'validates key through model metadata without billable inference',
    () async {
      late http.Request captured;
      final gateway = AnthropicGateway(
        client: MockClient((request) async {
          captured = request;
          return http.Response(jsonEncode({'data': <Object>[]}), 200);
        }),
        baseUri: baseUri,
        model: 'claude-3-5-haiku-latest',
      );

      await gateway.validateKey(key);

      expect(captured.method, 'GET');
      expect(captured.url, baseUri.resolve('v1/models'));
      expect(captured.headers['x-api-key'], key);
      expect(captured.headers['anthropic-version'], '2023-06-01');
      expect(captured.url.toString(), isNot(contains(key)));
    },
  );

  test(
    'generateTutorReply sends Anthropic-shaped body and parses text',
    () async {
      late http.Request captured;
      final gateway = AnthropicGateway(
        client: MockClient((request) async {
          captured = request;
          return _claudeResponse('Well done! Keep practicing.');
        }),
        baseUri: baseUri,
        model: 'claude-3-5-haiku-latest',
      );

      final reply = await gateway.generateTutorReply(
        key: key,
        scenario: 'Job Interview',
        learnerMessage: 'Hello',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'claude-3-5-haiku-latest');
      expect(body['system'], isA<String>());
      final messages = body['messages'] as List;
      expect(messages, hasLength(1));
      expect((messages[0] as Map)['role'], 'user');
      expect(captured.headers['x-api-key'], key);
      expect(reply.text, 'Well done! Keep practicing.');
    },
  );

  test('maps 401 to invalidKey without leaking the body', () async {
    final gateway = AnthropicGateway(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'secret-key-detail'}), 401),
      ),
      baseUri: baseUri,
      model: 'claude-3-5-haiku-latest',
    );

    GeminiException? failure;
    try {
      await gateway.validateKey(key);
    } on GeminiException catch (e) {
      failure = e;
    }

    expect(failure?.code, GeminiFailureCode.invalidKey);
    expect(failure.toString(), isNot(contains('secret-key-detail')));
  });

  test('maps 429 to rateLimited', () async {
    final gateway = AnthropicGateway(
      client: MockClient((_) async => http.Response('', 429)),
      baseUri: baseUri,
      model: 'claude-3-5-haiku-latest',
    );

    await expectLater(
      gateway.validateKey(key),
      throwsA(_failure(GeminiFailureCode.rateLimited)),
    );
  });

  test('maps 503 to providerUnavailable', () async {
    final gateway = AnthropicGateway(
      client: MockClient((_) async => http.Response('', 503)),
      baseUri: baseUri,
      model: 'claude-3-5-haiku-latest',
    );

    await expectLater(
      gateway.validateKey(key),
      throwsA(_failure(GeminiFailureCode.providerUnavailable)),
    );
  });

  test('treats malformed response as malformedResponse', () async {
    final gateway = AnthropicGateway(
      client: MockClient((_) async => http.Response('not json', 200)),
      baseUri: baseUri,
      model: 'claude-3-5-haiku-latest',
    );

    await expectLater(
      gateway.generateTutorReply(
        key: key,
        scenario: 'Job Interview',
        learnerMessage: 'Hello',
      ),
      throwsA(_failure(GeminiFailureCode.malformedResponse)),
    );
  });
}
