import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_responses_gateway.dart';

void main() {
  const key = 'test-key-sentinel';
  final baseUri = Uri.https('api.openai.com', '/v1/');

  test('uses the Responses API for OpenAI tutor generation', () async {
    late http.Request captured;
    final gateway = OpenAiResponsesGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'output_text': 'Good answer.',
            'usage': {
              'input_tokens': 10,
              'output_tokens': 3,
              'total_tokens': 13,
            },
          }),
          200,
        );
      }),
      baseUri: baseUri,
      model: 'gpt-test',
    );

    final reply = await gateway.generateTutorReply(
      key: key,
      scenario: 'Interview',
      learnerMessage: 'Hello',
    );

    expect(captured.url, baseUri.resolve('responses'));
    expect(captured.method, 'POST');
    expect(captured.headers['authorization'], 'Bearer $key');
    expect(reply.text, 'Good answer.');
    expect(reply.usage?.totalTokens, 13);
  });

  test('lists models through a non-inference request', () async {
    late http.Request captured;
    final gateway = OpenAiResponsesGateway(
      client: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode({
            'data': [
              {'id': 'gpt-test'},
            ],
          }),
          200,
        );
      }),
      baseUri: baseUri,
      model: 'gpt-test',
    );

    final models = await gateway.listModels(key);

    expect(captured.method, 'GET');
    expect(captured.url, baseUri.resolve('models'));
    expect(models.single.id, 'gpt-test');
  });
}
