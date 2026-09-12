import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/features/ai_tutor/data/anthropic_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_compatible_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_responses_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

// Actual local sockets and http.Client; all replies and credentials are
// synthetic. This checks transport, not a live model's teaching quality.
void main() {
  for (final provider in ['responses', 'compatible', 'anthropic']) {
    for (final scenario in [
      'reply',
      'invalid-key',
      'quota',
      'rate-limit',
      'malformed',
      'timeout',
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
          if (scenario == 'timeout') {
            return; // Accepted socket; deliberately no response.
          }
          request.response.headers.contentType = ContentType.json;
          request.response.statusCode = switch (scenario) {
            'invalid-key' => 401,
            'quota' => 402,
            'rate-limit' => 429,
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
        final operation = gateway.generateTutorReply(
          key: 'synthetic-key',
          scenario: 'Cafe',
          learnerMessage: 'ช่วยอธิบาย café',
        );
        if (scenario == 'reply') {
          final reply = await operation;
          expect(reply.text, 'ลองอีกครั้ง — café');
          expect(reply.usage?.totalTokens, 5);
        } else {
          final code = switch (scenario) {
            'invalid-key' => AiFailureCode.invalidKey,
            'quota' => AiFailureCode.quota,
            'rate-limit' => AiFailureCode.rateLimited,
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
