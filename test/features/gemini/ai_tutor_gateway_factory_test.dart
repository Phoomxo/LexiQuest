import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';

void main() {
  test(
    'R15 Gemini factory forwards bounded context through retry adapter',
    () async {
      late Map<String, dynamic> body;
      final client = MockClient((request) async {
        body = jsonDecode(request.body) as Map<String, dynamic>;
        return http.Response(
          jsonEncode({
            'candidates': [
              {
                'content': {
                  'parts': [
                    {'text': 'คำตอบ'},
                  ],
                },
              },
            ],
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      });
      addTearDown(client.close);
      final gateway = AiTutorGatewayFactory(
        client: client,
      ).create(providerId: AiProviderId.gemini, model: 'synthetic-model');
      await gateway.generateTutorReply(
        key: 's' * 24,
        scenario: 'Cafe',
        learnerMessage: 'latest',
        context: TutorRequestContext(
          sessionId: 'local-only',
          cefrLevel: 'A2',
          intent: TutorIntent.practice,
          priorTurns: const [
            TutorContextTurn(role: TutorTurnRole.learner, text: 'ถาม😀'),
            TutorContextTurn(role: TutorTurnRole.tutor, text: 'ตอบ'),
          ],
        ),
      );
      expect(body['generationConfig']['maxOutputTokens'], 480);
      expect((body['contents'] as List).map((t) => t['role']), [
        'user',
        'model',
        'user',
      ]);
      expect(jsonEncode(body['systemInstruction']), contains('CEFR A2'));
      expect(jsonEncode(body), isNot(contains('local-only')));
      expect(jsonEncode(body), isNot(contains('s' * 24)));
    },
  );
  test('AI Tutor Gemini path retries transient failures', () async {
    var attempts = 0;
    final client = MockClient((_) async {
      attempts++;
      if (attempts < 3) return http.Response('', 503);
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
      requestTimeout: const Duration(seconds: 5),
    ).create(providerId: AiProvider.gemini, model: 'gemini-test-model');

    final reply = await gateway.generateTutorReply(
      key: 'a' * 24,
      scenario: 'practice',
      learnerMessage: 'I am learning.',
    );

    expect(reply.text, 'Keep going.');
    expect(attempts, 3);
  });

  test('factory reuses provider breaker across resolved gateways', () async {
    var attempts = 0;
    final factory = AiTutorGatewayFactory(
      client: MockClient((_) async {
        attempts++;
        return http.Response('', 503);
      }),
      requestTimeout: const Duration(seconds: 5),
      geminiBreaker: CircuitBreaker(threshold: 1),
    );
    final first = factory.create(
      providerId: AiProvider.gemini,
      model: 'gemini-model-a',
    );
    final second = factory.create(
      providerId: AiProvider.gemini,
      model: 'gemini-model-b',
    );

    await expectLater(
      first.generateTutorReply(
        key: 'a' * 24,
        scenario: 'practice',
        learnerMessage: 'first',
      ),
      throwsA(isA<AiTutorException>()),
    );
    await expectLater(
      second.generateTutorReply(
        key: 'a' * 24,
        scenario: 'practice',
        learnerMessage: 'second',
      ),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.circuitOpen,
        ),
      ),
    );

    expect(attempts, 3);
  });
}
