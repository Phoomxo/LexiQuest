import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_host.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'support.dart';

void main() {
  testWidgets('navigation tombstones delayed login and closes it after arrival', (
    tester,
  ) async {
    final h = Harness();
    final identity = ValueNotifier<ManagedTutorIdentity?>(
      const ManagedTutorIdentity('owner-a', 'a'),
    );
    final pending = Completer<http.Response>();
    final paths = <String>[];
    final bridge = LocalLoginBridge(
      token: 'local',
      client: MockClient((r) async {
        paths.add(r.url.path);
        if (r.url.path == '/login') return pending.future;
        return http.Response('{}', 200);
      }),
    );
    final host = ManagedTutorHost(
      controller: h.controller,
      identity: identity,
      network: const Stream.empty(),
      enabled: true,
      clearSession: () async {},
    );
    final nav = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: nav,
        navigatorObservers: [appRouteObserver],
        home: ManagedTutorTestScreen(
          host: host,
          bridge: bridge,
          openLogin: (_) async {},
        ),
      ),
    );
    await tester.tap(find.text('เชื่อมบัญชี ChatGPT'));
    await tester.pump();
    unawaited(
      nav.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => const Scaffold(body: Text('other')),
        ),
      ),
    );
    await tester.pump();
    pending.complete(
      http.Response(
        '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}',
        200,
      ),
    );
    await tester.pumpAndSettle();
    nav.currentState!.pop();
    await tester.pumpAndSettle();
    expect(find.text('TEST-CODE'), findsNothing);
    expect(paths, ['/login', '/disconnect']);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpAndSettle();
    identity.dispose();
  });
  testWidgets(
    'login is private and requires explicit return check; route clears',
    (tester) async {
      final h = Harness();
      final identity = ValueNotifier<ManagedTutorIdentity?>(
        const ManagedTutorIdentity('owner-a', 'a'),
      );
      final paths = <String>[];
      final bridge = LocalLoginBridge(
        token: 'private',
        client: MockClient((r) async {
          paths.add(r.url.path);
          return http.Response(switch (r.url.path) {
            '/login' =>
              '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}',
            '/status' => '{"authenticated":true,"inferenceEnabled":false}',
            _ => '{}',
          }, 200);
        }),
      );
      final host = ManagedTutorHost(
        controller: h.controller,
        identity: identity,
        network: const Stream.empty(),
        enabled: true,
        clearSession: () async {},
      );
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: ManagedTutorTestScreen(
            host: host,
            bridge: bridge,
            openLogin: (uri) async {
              expect(uri.host, 'auth.openai.com');
              opened++;
            },
          ),
        ),
      );
      await tester.tap(find.text('เชื่อมบัญชี ChatGPT'));
      await tester.pumpAndSettle();
      expect(find.text('TEST-CODE'), findsOneWidget);
      await tester.tap(find.text('เปิดหน้า OpenAI'));
      await tester.pumpAndSettle();
      expect(opened, 1);
      expect(paths, [
        '/login',
      ]); // No automatic auth inspection during credentials.
      await tester.tap(find.text('กรอกเสร็จแล้ว ตรวจสถานะ'));
      await tester.pumpAndSettle();
      expect(find.textContaining('ยังไม่เปิดการส่งคำถามจริง'), findsWidgets);
      expect(find.text('พร้อมสนทนา'), findsNothing);
      expect(find.text('TEST-CODE'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      expect(paths.last, '/disconnect');
      identity.dispose();
    },
  );
  testWidgets(
    'background clears active tutor and route cover cancels pending work',
    (tester) async {
      final h = Harness();
      final identity = ValueNotifier<ManagedTutorIdentity?>(
        const ManagedTutorIdentity('owner-a', 'a'),
      );
      final bridge = LocalLoginBridge(
        token: 'local',
        client: MockClient((_) async => http.Response('{}', 200)),
      );
      final host = ManagedTutorHost(
        controller: h.controller,
        identity: identity,
        network: const Stream.empty(),
        enabled: true,
        clearSession: () async {},
      );
      await tester.pumpWidget(
        MaterialApp(
          navigatorObservers: [appRouteObserver],
          home: ManagedTutorTestScreen(
            host: host,
            bridge: bridge,
            openLogin: (_) async {},
          ),
        ),
      );
      final pending = host.connect();
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      expect(h.transport.cancellations.single.isCancelled, isTrue);
      h.transport.connections.single.complete();
      await pending;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(h.transport.connections.length, 1);
      await tester.pumpWidget(const SizedBox());
      await tester.pumpAndSettle();
      identity.dispose();
    },
  );
}
