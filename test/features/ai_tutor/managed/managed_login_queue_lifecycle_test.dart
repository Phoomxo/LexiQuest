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
  for (final login in [true, false]) {
    testWidgets(
      'valid queued ${login ? "login" : "status"} starts once after cleanup',
      (tester) async {
        final h = Harness();
        final identity = ValueNotifier<ManagedTutorIdentity?>(
          const ManagedTutorIdentity('owner-a', 'account-a'),
        );
        final cleanup = Completer<http.Response>();
        final paths = <String>[];
        final bridge = LocalLoginBridge(
          token: 'local',
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (paths.length == 1) return cleanup.future;
            return http.Response(switch (r.url.path) {
              '/login' =>
                '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"FRESH-CODE"}',
              '/status' => '{"authenticated":false,"inferenceEnabled":false}',
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
        await tester.pumpWidget(
          MaterialApp(
            home: ManagedTutorTestScreen(
              host: host,
              bridge: bridge,
              openLogin: (_) async {},
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester.tap(find.text('ออกจากระบบทดสอบ'));
        await tester.pump();
        final action = login
            ? tester
                  .widget<FilledButton>(
                    find.widgetWithText(FilledButton, 'เชื่อมบัญชี ChatGPT'),
                  )
                  .onPressed!
            : tester
                  .widget<OutlinedButton>(
                    find.widgetWithText(OutlinedButton, 'เปิดห้องสนทนา'),
                  )
                  .onPressed!;
        action();
        // The retained callback simulates a second activation before the rebuild.
        action();
        await tester.pump();
        expect(paths, ['/disconnect']);
        cleanup.complete(http.Response('{}', 200));
        await tester.pumpAndSettle();
        expect(paths, ['/disconnect', login ? '/login' : '/status']);
        if (login) expect(find.text('FRESH-CODE'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        identity.dispose();
      },
    );
    for (final transition in [
      'cancel',
      'cover',
      'owner',
      'background',
      'dispose',
    ]) {
      testWidgets('queued ${login ? "login" : "status"} is fenced by $transition', (
        tester,
      ) async {
        final h = Harness();
        final identity = ValueNotifier<ManagedTutorIdentity?>(
          const ManagedTutorIdentity('owner-a', 'account-a'),
        );
        final cleanup = Completer<http.Response>();
        final paths = <String>[];
        final bridge = LocalLoginBridge(
          token: 'local',
          client: MockClient((r) async {
            paths.add(r.url.path);
            if (paths.length == 1) return cleanup.future;
            return http.Response(switch (r.url.path) {
              '/login' =>
                '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"STALE-CODE"}',
              '/status' => '{"authenticated":false,"inferenceEnabled":false}',
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
        await tester.pumpAndSettle();
        // A real bridge disconnect remains in flight; the explicit next request queues behind it.
        await tester.tap(find.text('ออกจากระบบทดสอบ'));
        await tester.pump();
        expect(paths, ['/disconnect']);
        await tester.tap(
          find.text(login ? 'เชื่อมบัญชี ChatGPT' : 'เปิดห้องสนทนา'),
        );
        await tester.pump();
        expect(paths, ['/disconnect']);
        switch (transition) {
          case 'cancel':
            await tester.tap(
              find.widgetWithText(TextButton, 'ยกเลิก').evaluate().isNotEmpty
                  ? find.widgetWithText(TextButton, 'ยกเลิก')
                  : find.widgetWithText(TextButton, 'ออกจากระบบทดสอบ'),
            );
          case 'cover':
            unawaited(
              nav.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('cover')),
                ),
              ),
            );
          case 'owner':
            identity.value = const ManagedTutorIdentity('owner-b', 'account-b');
          case 'background':
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          case 'dispose':
            await tester.pumpWidget(const SizedBox());
        }
        await tester.pump();
        cleanup.complete(http.Response('{}', 200));
        await tester.pumpAndSettle();
        if (transition == 'cover') {
          expect(find.text('cover'), findsOneWidget);
          nav.currentState!.pop();
          await tester.pumpAndSettle();
        }
        if (transition == 'background') {
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.resumed,
          );
          await tester.pumpAndSettle();
        }
        expect(
          paths.where((p) => p != '/disconnect'),
          isEmpty,
          reason:
              'Invalidated queued work must never call the login/status bridge',
        );
        expect(find.text('STALE-CODE'), findsNothing);
        expect(h.transport.connections, isEmpty);
        expect(tester.takeException(), isNull);
        if (transition != 'dispose') {
          await tester.tap(
            find.text(login ? 'เชื่อมบัญชี ChatGPT' : 'เปิดห้องสนทนา'),
          );
          await tester.pumpAndSettle();
          expect(paths.where((p) => p != '/disconnect'), [
            login ? '/login' : '/status',
          ]);
          if (login) expect(find.text('STALE-CODE'), findsOneWidget);
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pumpAndSettle();
        identity.dispose();
      });
    }
  }
}
