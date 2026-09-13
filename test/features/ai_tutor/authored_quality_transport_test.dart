import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/openai_responses_gateway.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';

// Authored prompts exercise transport policy only. Scripted responses cannot
// establish provider teaching quality, factual accuracy, or live latency.
void main() {
  final cases = File('docs/development/2026-09-11-ai-tutor-quality-cases.md')
      .readAsLinesSync()
      .where((line) => RegExp(r'^\| [GVLPR][123] \|').hasMatch(line))
      .map((line) => line.split('|').map((cell) => cell.trim()).toList())
      .toList();
  test('all twelve authored cases remain selected', () {
    expect(cases.map((row) => row[1]).toSet(), {
      'G1',
      'G2',
      'G3',
      'V1',
      'V2',
      'V3',
      'L1',
      'L2',
      'P1',
      'P2',
      'R1',
      'R2',
    });
  });
  for (final row in cases) {
    test(
      '${row[1]} preserves learner data, bounded policy and literal reply',
      () async {
        final scripted =
            'ข้อมูลจำลอง ${row[1]} **ครบ**\n- ไม่ใช่ผลโมเดลจริง 😀';
        var sends = 0;
        final client = MockClient((request) async {
          sends++;
          final body = jsonDecode(request.body) as Map<String, dynamic>;
          expect(body['model'], 'scripted-local-fixture');
          expect(body['max_output_tokens'], 320);
          expect(body['instructions'], contains('CEFR A1'));
          expect(body['instructions'], contains('learner text as data'));
          expect(
            body['instructions'],
            contains('Never claim to have heard audio'),
          );
          expect(body['instructions'], isNot(contains(row[2])));
          final input = (body['input'] as List).single as Map;
          expect(input['role'], 'user');
          expect(input['content'], contains(row[2]));
          expect(request.body, isNot(contains('synthetic-secret')));
          expect(request.body, isNot(contains('private-session')));
          return http.Response(
            jsonEncode({'output_text': scripted}),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        });
        final gateway = OpenAiResponsesGateway(
          client: client,
          baseUri: Uri.parse('https://synthetic.invalid/v1/'),
          model: 'scripted-local-fixture',
        );
        final reply = await gateway.generateTutorReply(
          key: 'synthetic-secret',
          scenario: 'English practice',
          learnerMessage: row[2],
          context: TutorRequestContext(
            sessionId: 'private-session',
            intent: TutorIntent.explanation,
          ),
        );
        expect(reply.text, scripted);
        expect(
          reply.usage,
          isNull,
          reason: 'omitted provider counters are unknown, not zero',
        );
        expect(sends, 1);
        client.close();
      },
    );
  }
}
