import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

void main() {
  test('AI Tutor Gemini path uses bounded retry before succeeding', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      if (attempts < 3) {
        return http.Response('', 503);
      }
      return http.Response(
        jsonEncode({
          'candidates': [
            {
              'content': {
                'parts': [
                  {'text': 'Keep going.'},
                ],
              },
            },
          ],
        }),
        200,
        headers: const {'content-type': 'application/json'},
      );
    });
    final gateway = AiTutorGatewayFactory(
      client: client,
      requestTimeout: const Duration(seconds: 2),
    ).create(providerId: AiProviderId.gemini, model: 'gemini-test-model');

    final reply = await gateway.generateTutorReply(
      key: 'a' * 24,
      scenario: 'practice',
      learnerMessage: 'I am learning.',
    );

    expect(reply.text, 'Keep going.');
    expect(attempts, 3);
  });
}
