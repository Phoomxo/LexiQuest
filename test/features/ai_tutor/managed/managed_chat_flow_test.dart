import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/managed_tutor_transport.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_panel.dart';
import 'support.dart';

void main() {
  test(
    'managed bridge sends bounded text and reuses the authorized binding',
    () async {
      final calls = <http.Request>[];
      final bridge = LocalLoginBridge(
        token: 'private-capability',
        client: MockClient((request) async {
          calls.add(request);
          return http.Response(
            jsonEncode(switch (request.url.path) {
              '/status' => {'authenticated': true, 'inferenceEnabled': true},
              '/connect' => {'ready': true},
              '/reply' => {'text': 'bottle คือขวด', 'tools': <Object>[]},
              _ => <String, dynamic>{},
            }),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      );
      addTearDown(bridge.dispose);
      const binding = ManagedTutorBinding(
        ownerId: 'owner-a',
        accountId: 'local-a',
        generation: 1,
      );
      await bridge.connect(binding: binding, cancellation: AiCancellation());
      final reply = await bridge.reply(
        binding: binding,
        learnerMessage: 'อธิบาย bottle',
        cancellation: AiCancellation(),
      );
      expect(reply.text, 'bottle คือขวด');
      expect(calls.map((x) => x.url.path), ['/status', '/connect', '/reply']);
      final body = jsonDecode(calls.last.body) as Map<String, dynamic>;
      expect(body['message'], 'อธิบาย bottle');
      expect(body['binding'], {
        'ownerId': 'owner-a',
        'accountId': 'local-a',
        'generation': 1,
      });
      expect(body['requestId'], isNotEmpty);
      expect(body.containsKey('apiKey'), isFalse);
    },
  );

  testWidgets(
    'chat preserves two visible turns and clears them on owner change',
    (tester) async {
      final h = Harness();
      addTearDown(h.controller.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ManagedTutorPanel(controller: h.controller),
            ),
          ),
        ),
      );
      final connected = h.controller.connect(
        ownerId: h.owner,
        accountId: 'account-a',
      );
      await tester.pump();
      h.transport.connections.single.complete();
      await tester.pump();
      await connected;
      for (var i = 0; i < 2; i++) {
        final sent = h.controller.send('question-$i');
        await tester.pump();
        h.transport.replies[i].complete(AiGatewayReply(text: 'answer-$i'));
        await tester.pump();
        await sent;
      }
      expect(find.text('question-0'), findsOneWidget);
      expect(find.text('answer-0'), findsOneWidget);
      expect(find.text('question-1'), findsOneWidget);
      expect(find.text('answer-1'), findsOneWidget);
      h.controller.ownerChanged();
      await tester.pump();
      expect(find.text('answer-0'), findsNothing);
      expect(find.text('question-1'), findsNothing);
    },
  );
}
