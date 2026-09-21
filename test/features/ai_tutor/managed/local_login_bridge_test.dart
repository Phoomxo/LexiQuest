import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/managed_tutor_transport.dart';

void main() {
  test('explicit new login reloads rotated private pairing', () async {
    final fresh = List.filled(43, 'b').join();
    final bridge = LocalLoginBridge(
      token: 'old-capability',
      reloadPairing: () async => fresh,
      client: MockClient((request) async {
        expect(request.headers['authorization'], 'Bearer $fresh');
        return http.Response('{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}', 200);
      }),
    );
    addTearDown(bridge.dispose);
    expect((await bridge.login()).userCode, 'TEST-CODE');
  });
  test('expired or removed pairing cannot reuse cached capability for login', () async {
    var calls = 0;
    final bridge = LocalLoginBridge(
      token: 'old-capability',
      reloadPairing: () async => null,
      client: MockClient((request) async {
        calls++;
        return http.Response('{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}', 200);
      }),
    );
    addTearDown(bridge.dispose);
    await expectLater(bridge.login(), throwsA(isA<AiTutorException>()));
    expect(calls, 0);
  });
  test('capability is header only; fixed loopback and empty request', () async {
    final bridge = LocalLoginBridge(
      token: 'private-local-capability',
      client: MockClient((request) async {
        expect(request.url.toString(), 'http://127.0.0.1:8765/login');
        expect(
          request.headers['authorization'],
          'Bearer private-local-capability',
        );
        expect(request.body, '{}');
        return http.Response(
          jsonEncode({
            'verificationUrl': 'https://auth.openai.com/codex/device',
            'userCode': 'TEST-CODE',
          }),
          200,
        );
      }),
    );
    addTearDown(bridge.dispose);
    expect((await bridge.login()).userCode, 'TEST-CODE');
  });
  test('foreign verification URL and malformed status fail closed', () async {
    final bridge = LocalLoginBridge(
      token: 'local',
      client: MockClient(
        (_) async => http.Response(
          '{"verificationUrl":"https://evil.test","userCode":"X"}',
          200,
        ),
      ),
    );
    addTearDown(bridge.dispose);
    await expectLater(bridge.login(), throwsA(isA<AiTutorException>()));
    await expectLater(bridge.status(), throwsA(isA<AiTutorException>()));
  });
  test('authenticated login never claims inference ready', () async {
    final paths = <String>[];
    final bridge = LocalLoginBridge(
      token: 'local',
      client: MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          '{"authenticated":true,"inferenceEnabled":false}',
          200,
        );
      }),
    );
    addTearDown(bridge.dispose);
    expect(await bridge.status(), isTrue);
    await expectLater(
      bridge.connect(
        binding: const ManagedTutorBinding(
          ownerId: 'a',
          accountId: 'a',
          generation: 0,
        ),
        cancellation: AiCancellation(),
      ),
      throwsA(isA<AiTutorException>()),
    );
    await expectLater(
      bridge.reply(
        binding: const ManagedTutorBinding(
          ownerId: 'a',
          accountId: 'a',
          generation: 0,
        ),
        learnerMessage: 'bottle',
        cancellation: AiCancellation(),
      ),
      throwsA(isA<AiTutorException>()),
    );
    expect(paths, [
      '/status',
      '/status',
    ]); // No connect/reply without readiness.
  });
  test(
    'disconnect clears on bridge and dispose rejects later requests',
    () async {
      final paths = <String>[];
      final bridge = LocalLoginBridge(
        token: 'local',
        client: MockClient((r) async {
          paths.add(r.url.path);
          return http.Response('{}', 200);
        }),
      );
      await bridge.disconnect();
      bridge.dispose();
      await expectLater(bridge.status(), throwsA(isA<AiTutorException>()));
      expect(paths, ['/disconnect']);
    },
  );
}
