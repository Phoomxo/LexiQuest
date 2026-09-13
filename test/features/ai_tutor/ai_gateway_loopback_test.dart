import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/features/ai_tutor/data/anthropic_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_compatible_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_responses_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/gemini_rest_gateway.dart';
import 'package:vocab_learning_app/features/gemini/data/retry_gemini_gateway.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';

// Actual local sockets and http.Client; all replies and credentials are
// synthetic. This checks transport, not a live model's teaching quality.
void main() {
  for (final cancelBackoff in [false, true]) {
    test(
      'B13 Gemini real socket retry bounded cancel=$cancelBackoff',
      () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = http.Client();
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        var requests = 0;
        server.listen((request) async {
          await request.drain<void>();
          requests++;
          request.response.statusCode = 503;
          request.response.write('{}');
          await request.response.close();
        });
        final cancellation = GeminiCancellation();
        final gateway = RetryGeminiGateway(
          GeminiRestGateway(
            client: client,
            baseUri: Uri.parse('http://127.0.0.1:${server.port}/'),
            model: 'synthetic-model',
          ),
          baseDelay: Duration.zero,
          totalTimeout: const Duration(seconds: 5),
          delay: cancelBackoff
              ? (_, linked) async {
                  cancellation.cancel();
                  await linked!.whenCancelled;
                }
              : null,
        );
        await expectLater(
          gateway.generateTutorReply(
            key: 'synthetic-key-long-enough-123456',
            scenario: 'Cafe',
            learnerMessage: 'hello',
            cancellation: cancellation,
          ),
          throwsA(
            isA<GeminiException>().having(
              (e) => e.code,
              'code',
              cancelBackoff
                  ? GeminiFailureCode.cancelled
                  : GeminiFailureCode.providerUnavailable,
            ),
          ),
        );
        expect(requests, cancelBackoff ? 1 : 3);
      },
    );
  }
  for (final provider in ['responses', 'compatible', 'anthropic']) {
    for (final scenario in [
      'reply',
      'invalid-key',
      'quota',
      'rate-limit',
      'B13-server-error',
      'malformed',
      'timeout',
      'cancel',
    ]) {
      test('$provider actual loopback transport: $scenario', () async {
        final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
        final client = http.Client();
        addTearDown(() async {
          client.close();
          await server.close(force: true);
        });
        final requests = <Map<String, dynamic>>[];
        final paths = <String>[];
        final keys = <String?>[];
        final received = Completer<void>();
        server.listen((request) async {
          paths.add(request.uri.path);
          keys.add(
            request.headers.value(
              provider == 'anthropic' ? 'x-api-key' : 'authorization',
            ),
          );
          requests.add(
            jsonDecode(await utf8.decoder.bind(request).join())
                as Map<String, dynamic>,
          );
          received.complete();
          if (scenario == 'timeout' || scenario == 'cancel') {
            return; // Accepted socket; deliberately no response.
          }
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = switch (scenario) {
            'invalid-key' => 401,
            'quota' => 402,
            'rate-limit' => 429,
            'B13-server-error' => 503,
            _ => 200,
          };
          final body = scenario == 'reply'
              ? switch (provider) {
                  'responses' => {
                    'output_text': 'ลองอีกครั้ง — café',
                    'usage': {
                      'input_tokens': 2,
                      'output_tokens': 3,
                      'total_tokens': 5,
                    },
                  },
                  'compatible' => {
                    'choices': [
                      {
                        'message': {'content': 'ลองอีกครั้ง — café'},
                      },
                    ],
                    'usage': {
                      'prompt_tokens': 2,
                      'completion_tokens': 3,
                      'total_tokens': 5,
                    },
                  },
                  _ => {
                    'content': [
                      {'type': 'text', 'text': 'ลองอีกครั้ง — café'},
                    ],
                    'usage': {'input_tokens': 2, 'output_tokens': 3},
                  },
                }
              : <String, Object?>{};
          request.response.write(
            scenario == 'malformed' ? '{incomplete' : jsonEncode(body),
          );
          await request.response.close();
        });
        final uri = Uri.parse('http://127.0.0.1:${server.port}/proxy');
        final timeout = scenario == 'timeout'
            ? const Duration(milliseconds: 400)
            : const Duration(seconds: 5);
        final AiTutorGateway gateway = switch (provider) {
          'responses' => OpenAiResponsesGateway(
            client: client,
            baseUri: uri,
            model: 'synthetic-model',
            requestTimeout: timeout,
          ),
          'compatible' => OpenAiCompatibleGateway(
            client: client,
            baseUri: uri,
            model: 'synthetic-model',
            requestTimeout: timeout,
          ),
          _ => AnthropicGateway(
            client: client,
            baseUri: uri,
            model: 'synthetic-model',
            requestTimeout: timeout,
          ),
        };
        final cancellation = AiCancellation();
        final operation = gateway.generateTutorReply(
          key: 'synthetic-key',
          scenario: 'Cafe',
          learnerMessage: 'ช่วยอธิบาย café',
          cancellation: cancellation,
          context: TutorRequestContext(
            sessionId: 'not-for-provider',
            cefrLevel: 'A2',
            intent: TutorIntent.explanation,
            priorTurns: const [
              TutorContextTurn(
                role: TutorTurnRole.learner,
                text: 'คำถามก่อน😀',
              ),
              TutorContextTurn(role: TutorTurnRole.tutor, text: 'คำตอบก่อน'),
            ],
          ),
        );
        if (scenario == 'cancel') {
          // Attach the error handler before cancelling an accepted real socket.
          final check = expectLater(
            operation,
            throwsA(
              isA<AiTutorException>().having(
                (e) => e.code,
                'code',
                AiFailureCode.cancelled,
              ),
            ),
          );
          await received.future.timeout(const Duration(seconds: 5));
          cancellation.cancel();
          await check;
        }
        if (scenario == 'reply') {
          final reply = await operation;
          expect(reply.text, 'ลองอีกครั้ง — café');
          expect(reply.usage?.totalTokens, 5);
        } else if (scenario != 'cancel') {
          final code = switch (scenario) {
            'invalid-key' => AiFailureCode.invalidKey,
            'quota' => AiFailureCode.quota,
            'rate-limit' => AiFailureCode.rateLimited,
            'B13-server-error' => AiFailureCode.providerUnavailable,
            'timeout' => AiFailureCode.timeout,
            _ => AiFailureCode.malformedResponse,
          };
          await expectLater(
            operation,
            throwsA(
              isA<AiTutorException>().having(
                (error) => error.code,
                'code',
                code,
              ),
            ),
          );
        }
        expect(
          requests,
          hasLength(1),
          reason: 'No implicit retry or duplicate paid operation.',
        );
        expect(requests.single['model'], 'synthetic-model');
        expect(
          requests.single['max_output_tokens'] ?? requests.single['max_tokens'],
          320,
        );
        expect(jsonEncode(requests.single), contains('คำถามก่อน😀'));
        expect(jsonEncode(requests.single), isNot(contains('synthetic-key')));
        expect(
          jsonEncode(requests.single),
          isNot(contains('not-for-provider')),
        );
        final turns =
            (requests.single['input'] ?? requests.single['messages']) as List;
        expect(
          turns.where((t) => t['role'] != 'system').map((t) => t['role']),
          ['user', 'assistant', 'user'],
        );
        expect(jsonEncode(requests.single), contains('ช่วยอธิบาย café'));
        expect(
          keys.single,
          provider == 'anthropic' ? 'synthetic-key' : 'Bearer synthetic-key',
        );
        expect(paths.single, switch (provider) {
          'responses' => '/proxy/responses',
          'compatible' => '/proxy/chat/completions',
          _ => '/proxy/v1/messages',
        });
      });
    }
  }
}
