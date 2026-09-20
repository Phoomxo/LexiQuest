import 'dart:async';
import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/managed_tutor_transport.dart';

void main() {
  for (final fence in ['cancel', 'disconnect', 'dispose']) {
    test('late menu delivery cannot act after $fence', () async {
      var effects = 0;
      var postedResults = 0;
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      registry.register(
        id: 'action',
        label: 'action',
        available: () => true,
        invoke: () {
          effects++;
        },
      );
      final polling = Completer<void>();
      final releaseMenu = Completer<void>();
      final releaseReply = Completer<void>();
      final bridge = LocalLoginBridge(
        token: 'test',
        client: MockClient((r) async {
          Map<String, Object?> body = {};
          switch (r.url.path) {
            case '/status':
              body = {'authenticated': true, 'inferenceEnabled': true};
            case '/connect':
              body = {'ready': true};
            case '/reply':
              await releaseReply.future;
              body = {'text': 'done', 'tools': []};
            case '/menu/next':
              polling.complete();
              await releaseMenu.future;
              body = {
                'request': {
                  'requestId': 'late',
                  'name': 'execute_menu_action',
                  'arguments': {
                    'id': 'action',
                    'revision': registry.snapshot()['revision'],
                  },
                },
              };
            case '/menu/result':
              postedResults++;
          }
          return http.Response(
            jsonEncode(body),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..menuActions = registry;
      addTearDown(bridge.dispose);
      const binding = ManagedTutorBinding(
        ownerId: 'a',
        accountId: 'a',
        generation: 1,
      );
      await bridge.connect(binding: binding, cancellation: AiCancellation());
      final cancellation = AiCancellation();
      final reply = bridge
          .reply(
            binding: binding,
            learnerMessage: 'open',
            cancellation: cancellation,
          )
          .then<Object?>((value) => value, onError: (Object error) => error);
      await polling.future.timeout(const Duration(seconds: 2));
      switch (fence) {
        case 'cancel':
          cancellation.cancel();
        case 'disconnect':
          await bridge.disconnect();
        case 'dispose':
          bridge.dispose();
      }
      releaseMenu.complete();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      releaseReply.complete();
      await reply;
      expect(effects, 0);
      expect(postedResults, 0);
    });
  }
  test(
    'pending provider turn receives the result of a real app callback',
    () async {
      var effects = 0;
      final registry = MenuActionRegistry(currentOwner: () => 'a');
      registry.register(
        id: 'theme-dark',
        label: 'มืด',
        available: () => true,
        invoke: () {
          effects++;
        },
      );
      final completed = Completer<void>();
      var delivered = false;
      final bridge = LocalLoginBridge(
        token: 'test',
        client: MockClient((r) async {
          Map<String, Object?> response;
          switch (r.url.path) {
            case '/status':
              response = {'authenticated': true, 'inferenceEnabled': true};
            case '/connect':
              response = {'ready': true};
            case '/reply':
              await completed.future.timeout(
                const Duration(milliseconds: 800),
                onTimeout: () {},
              );
              response = {'text': 'เรียกเมนูแล้ว', 'tools': []};
            case '/menu/next':
              response = {
                'request': delivered
                    ? null
                    : {
                        'requestId': 'menu1',
                        'name': 'execute_menu_action',
                        'arguments': {
                          'id': 'theme-dark',
                          'revision': registry.snapshot()['revision'],
                        },
                      },
              };
              delivered = true;
            case '/menu/result':
              final body = jsonDecode(r.body) as Map;
              expect(body['response']['result'], {
                'status': 'invoked',
                'id': 'theme-dark',
              });
              completed.complete();
              response = {'accepted': true};
            default:
              response = {};
          }
          return http.Response(
            jsonEncode(response),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }),
      )..menuActions = registry;
      addTearDown(bridge.dispose);
      const binding = ManagedTutorBinding(
        ownerId: 'a',
        accountId: 'a',
        generation: 1,
      );
      await bridge.connect(binding: binding, cancellation: AiCancellation());
      await bridge.reply(
        binding: binding,
        learnerMessage: 'เปิดธีมมืด',
        cancellation: AiCancellation(),
      );
      expect(completed.isCompleted, isTrue);
      expect(effects, 1);
      expect(registry.snapshot()['recentActions'], isNotEmpty);
      await bridge.disconnect();
      expect(registry.snapshot()['recentActions'], isEmpty);
    },
  );
}
