import 'dart:convert';
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_compatible_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

Matcher _failure(GeminiFailureCode code) =>
    isA<GeminiException>().having((e) => e.code, 'code', code);

http.Response _chatResponse(String text) => http.Response(
  jsonEncode({
    'choices': [
      {
        'message': {'role': 'assistant', 'content': text},
      },
    ],
  }),
  200,
);

void main() {
  const key = 'test-key-sentinel';
  final baseUri = Uri.https('api.openai.com', '/v1/');

  test('declares the openai-compatible provider id', () {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((_) async => _chatResponse('hi')),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
    );
    expect(gateway.providerId, AiProvider.openai);
    expect(gateway.model, 'gpt-4o-mini');
  });

  test('validates key without billable inference', () async {
    late http.Request captured;
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      }),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
    );

    await gateway.validateKey(key);

    expect(captured.method, 'GET');
    expect(captured.url, baseUri.resolve('models'));
    expect(captured.headers['authorization'], 'Bearer $key');
    expect(captured.headers['content-type'], 'application/json');
    expect(captured.url.toString(), isNot(contains(key)));
  });

  test('lists provider models without exposing the key in the URI', () async {
    late http.Request captured;
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'model-b'},
              {'id': 'model-a'},
            ],
          }),
          200,
        );
      }),
      baseUri: baseUri,
      model: 'model-a',
    );

    final models = await gateway.listModels(key);

    expect(models.map((model) => model.id), ['model-a', 'model-b']);
    expect(captured.headers['authorization'], 'Bearer $key');
    expect(captured.url.toString(), isNot(contains(key)));
  });

  test(
    'generateTutorReply sends OpenAI-shaped body and parses content',
    () async {
      late http.Request captured;
      final gateway = OpenAiCompatibleGateway(
        client: MockClient((request) async {
          captured = request;
          return _chatResponse('Great job! Try adding more detail.');
        }),
        baseUri: baseUri,
        model: 'gpt-4o-mini',
      );

      final reply = await gateway.generateTutorReply(
        key: key,
        scenario: 'Job Interview',
        learnerMessage: 'Hello',
      );

      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['model'], 'gpt-4o-mini');
      final messages = body['messages'] as List;
      expect(messages, hasLength(2));
      expect((messages[0] as Map)['role'], 'system');
      expect((messages[1] as Map)['role'], 'user');
      expect(captured.headers['authorization'], 'Bearer $key');
      expect(reply.text, 'Great job! Try adding more detail.');
    },
  );

  test('maps 401 to invalidKey without leaking the body', () async {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient(
        (_) async =>
            http.Response(jsonEncode({'error': 'secret-key-detail'}), 401),
      ),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
    );

    GeminiException? failure;
    try {
      await gateway.listModels(key);
    } on GeminiException catch (e) {
      failure = e;
    }

    expect(failure?.code, GeminiFailureCode.invalidKey);
    expect(failure.toString(), isNot(contains('secret-key-detail')));
  });

  test('maps 429 to rateLimited', () async {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((_) async => http.Response('', 429)),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
    );

    await expectLater(
      gateway.validateKey(key),
      throwsA(_failure(GeminiFailureCode.rateLimited)),
    );
  });

  test('maps 503 to providerUnavailable', () async {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((_) async => http.Response('', 503)),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
    );

    await expectLater(
      gateway.validateKey(key),
      throwsA(_failure(GeminiFailureCode.providerUnavailable)),
    );
  });

  test('treats malformed response as malformedResponse', () async {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((_) async => http.Response('not json', 200)),
      baseUri: baseUri,
      model: 'gpt-4o-mini',
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

  test('supports custom base URL for OpenRouter', () async {
    late http.Request captured;
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'data': <Object>[]}), 200);
      }),
      baseUri: Uri.https('openrouter.ai', '/api/v1/'),
      model: 'openai/gpt-4o-mini',
      providerId: AiProvider.openrouter,
    );

    await gateway.validateKey(key);

    expect(captured.url, Uri.https('openrouter.ai', '/api/v1/models'));
    expect(gateway.providerId, AiProvider.openrouter);
  });

  test('supports customOpenAi provider with arbitrary base URL', () async {
    final gateway = OpenAiCompatibleGateway(
      client: MockClient(
        (_) async => http.Response(jsonEncode({'data': <Object>[]}), 200),
      ),
      baseUri: Uri.https('api.cointh.example', '/v1/'),
      model: 'cointh-chat-v1',
      providerId: AiProvider.customOpenAi,
    );

    expect(gateway.providerId, AiProvider.customOpenAi);
    await gateway.listModels(key); // should not throw
  });

  test('cancellation releases an in-flight request without retrying', () async {
    final release = Completer<void>();
    var calls = 0;
    final cancellation = GeminiCancellation();
    final gateway = OpenAiCompatibleGateway(
      client: MockClient((_) async {
        calls += 1;
        await release.future;
        return _chatResponse('late');
      }),
      baseUri: baseUri,
      model: 'gpt-test',
      requestTimeout: const Duration(milliseconds: 50),
    );
    final operation = gateway.generateTutorReply(
      key: key,
      scenario: 'Interview',
      learnerMessage: 'Hello',
      cancellation: cancellation,
    );
    await Future<void>.delayed(Duration.zero);

    cancellation.cancel();

    await expectLater(
      operation,
      throwsA(_failure(GeminiFailureCode.cancelled)),
    );
    expect(calls, 1);
    release.complete();
  });
}
