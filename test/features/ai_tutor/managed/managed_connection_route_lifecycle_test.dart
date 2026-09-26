import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_host.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'support.dart';

void main() {
  for (final stage in ['status', 'connect', 'reply']) {
    for (final cover in [true, false]) {
      testWidgets(
        '$stage completion after ${cover ? "route cover" : "background"} stays disconnected until explicit recovery',
        (tester) async {
          final h = Harness();
          final identity = ValueNotifier<ManagedTutorIdentity?>(
            const ManagedTutorIdentity('owner-a', 'account-a'),
          );
          final status = Completer<http.Response>();
          final paths = <String>[];
          var checks = 0;
          final bridge = LocalLoginBridge(
            token: 'local',
            client: MockClient((r) async {
              paths.add(r.url.path);
              if (r.url.path == '/status') {
                checks++;
                if (stage == 'status' && checks == 1) return status.future;
                return http.Response(
                  '{"authenticated":true,"inferenceEnabled":true}',
                  200,
                );
              }
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
          await tester.pumpAndSettle();
          await tester.tap(find.text('เปิดห้องสนทนา'));
          await tester.pump();
          expect(checks, 1);
          Future<void>? replying;
          if (stage != 'status') {
            expect(h.transport.connections, hasLength(1));
            if (stage == 'reply') {
              h.transport.connections.single.complete();
              await tester.pump();
              expect(h.controller.state, ManagedTutorState.ready);
              replying = h.controller.send('bottle');
              await tester.pump();
              expect(h.transport.replies, hasLength(1));
            }
          }
          if (cover) {
            unawaited(
              nav.currentState!.push(
                MaterialPageRoute<void>(
                  builder: (_) => const Scaffold(body: Text('cover')),
                ),
              ),
            );
          } else {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.paused,
            );
          }
          await tester.pump();
          expect(h.controller.state, ManagedTutorState.disconnected);
          if (stage == 'status') {
            status.complete(
              http.Response(
                '{"authenticated":true,"inferenceEnabled":true}',
                200,
              ),
            );
          } else {
            expect(h.transport.cancellations.last.isCancelled, isTrue);
            if (stage == 'connect') {
              h.transport.connections.single.complete();
            } else {
              h.transport.replies.single.complete(
                const AiGatewayReply(text: 'STALE-REPLY'),
              );
              await replying;
            }
          }
          await tester.pumpAndSettle();
          if (cover) {
            expect(find.text('cover'), findsOneWidget);
            nav.currentState!.pop();
          } else {
            tester.binding.handleAppLifecycleStateChanged(
              AppLifecycleState.resumed,
            );
          }
          await tester.pumpAndSettle();
          expect(h.controller.state, ManagedTutorState.disconnected);
          expect(h.controller.replyText, isNull);
          expect(find.text('STALE-REPLY'), findsNothing);
          expect(h.transport.connections, hasLength(stage == 'status' ? 0 : 1));
          expect(checks, 1, reason: 'Returning must not poll or reconnect');
          expect(paths.where((p) => p == '/disconnect'), isNotEmpty);
          // New explicit admission works after cleanup; no stale reply survives it.
          await tester.tap(find.text('เปิดห้องสนทนา'));
          await tester.pump();
          expect(checks, 2);
          expect(h.transport.connections, hasLength(stage == 'status' ? 1 : 2));
          h.transport.connections.last.complete();
          await tester.pump();
          expect(h.controller.state, ManagedTutorState.ready);
          expect(h.controller.replyText, isNull);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
          await tester.pumpAndSettle();
          identity.dispose();
        },
      );
    }
  }
}
