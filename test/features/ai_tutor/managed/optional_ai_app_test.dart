import 'dart:async';
import 'dart:io';
import 'package:drift/drift.dart' show Value;
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main_ari_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_flag_namespaces.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../../../../integration_test/support/field_trial_external_fakes.dart';

void main() {
  for (final scenario in ['absent', 'failure', 'pending', 'available', 'recreated']) {
    testWidgets('baseline survives optional AI $scenario without route reset', (
      tester,
    ) async {
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ari-optional-'),
      );
      final dependencies = await tester.runAsync(
        () => AppBootstrap(
          initializeFirebase: () async => throw StateError('fixture offline'),
          initializeSupabase: () async => throw StateError('fixture offline'),
          loadConfig: () => throw StateError('fixture offline'),
          guestSessionService: _Guest(),
          createDatabase: () => AppDatabase(NativeDatabase.memory()),
          createEntryStateStore: () async => _Entry(),
          applicationSupportDirectoryProvider: () async => directory!,
          buildFeatureRegistry: const BuildFeatureRegistry.allEnabled(),
          learningPreviewEnabled: true,
          cloudSyncEnabled: false,
          exportStoreFactory: HostFakeExportStore.new,
          cameraGatewayFactory: HostFakeCameraGateway.new,
          speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
          buildAiTutor: (_) => throw StateError('fixture AI unavailable'),
          buildVoice: (_) => throw StateError('fixture voice unavailable'),
        ).initialize(),
      );
      var pairingCalls = 0;
      var providerAuthenticated = scenario == 'recreated';
      final providerPaths = <String>[];
      final pending = Completer<LocalLoginBridge?>();
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(tester.takeException(), isNull);
      }

      try {
        await tester.pumpWidget(
          AriTestApp(
            loadDependencies: () async => dependencies!,
            loadBridge: () async {
              pairingCalls++;
              if (scenario == 'failure') {
                throw StateError('private pairing failure');
              }
              if (scenario == 'pending') return pending.future;
              if (scenario == 'available' || scenario == 'recreated') {
                return LocalLoginBridge(
                  token: 'fixture-token',
                  client: MockClient((request) async {
                    providerPaths.add(request.url.path);
                    if (request.url.path == '/disconnect') {
                      providerAuthenticated = false;
                    }
                    return http.Response(switch (request.url.path) {
                      '/login' => '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}',
                      '/status' => '{"authenticated":$providerAuthenticated,"inferenceEnabled":$providerAuthenticated}',
                      '/connect' => '{"ready":$providerAuthenticated}',
                      _ => '{}',
                    }, 200);
                  }),
                );
              }
              return null;
            },
          ),
        );
        await settle();
        expect(find.byType(NavigationBar), findsOneWidget);
        expect(
          pairingCalls,
          0,
          reason: 'Baseline startup must not initialize the provider',
        );
        var bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        bar.onDestinationSelected!(1);
        await settle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        await tester.tap(find.byKey(const ValueKey('ari-toggle-chat')));
        await settle();
        expect(pairingCalls, 1);
        if (scenario == 'available' || scenario == 'recreated') {
          expect(find.byType(ManagedTutorTestScreen), findsOneWidget);
        }
      if (scenario == 'recreated') {
          // Simulate a fresh app with an already acknowledged provider session.
          // This fixture resolves canonical ownership before the panel mounts.
          expect(providerPaths, isEmpty);
          final before = await tester.runAsync(() => dependencies!.database!
              .select(dependencies.database!.answerAttempts).get());
          final openChat = find.text('เปิดห้องสนทนา');
          await Scrollable.ensureVisible(tester.element(openChat), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(openChat);
          await settle();
          expect(providerPaths.where((path) => path == '/connect'), hasLength(1),
            reason: 'Requests: $providerPaths; visible text: ${tester.widgetList<Text>(find.byType(Text)).map((t) => t.data).toList()}');
          expect(tester.widget<ManagedTutorTestScreen>(find.byType(ManagedTutorTestScreen))
              .host.controller.state.name, 'ready');
          // A real durable owner epoch change must invalidate that session.
          await tester.runAsync(() => dependencies!.database!.into(
            dependencies.database!.runtimeFlags,
          ).insert(RuntimeFlagsCompanion.insert(
            key: RuntimeFlagNamespaces.ownerGeneration,
            boolValue: true,
            source: const Value('recreated-owner-transition'),
            updatedAtUtcMs: 2,
          )));
          await settle();
          expect(providerPaths, contains('/disconnect'));
          expect(providerAuthenticated, false);
          await Scrollable.ensureVisible(tester.element(openChat), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(openChat);
          await settle();
          expect(find.textContaining('ยังไม่เชื่อมบัญชี หรือรหัสหมดอายุ'), findsOneWidget);
          expect(providerPaths.where((path) => path == '/connect'), hasLength(1));
          final login = find.text('เชื่อมบัญชี ChatGPT');
          await Scrollable.ensureVisible(tester.element(login), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(login);
          await settle();
          expect(find.text('TEST-CODE'), findsOneWidget);
          // Simulated provider acknowledgement, not native/browser evidence.
          providerAuthenticated = true;
          final check = find.text('กรอกเสร็จแล้ว ตรวจสถานะ');
          await Scrollable.ensureVisible(tester.element(check), alignment: .5);
          await tester.pumpAndSettle();
          await tester.tap(check);
          await settle();
          expect(providerPaths.where((path) => path == '/connect'), hasLength(2));
          expect(tester.widget<ManagedTutorTestScreen>(find.byType(ManagedTutorTestScreen))
              .host.controller.state.name, 'ready');
          final after = await tester.runAsync(() => dependencies!.database!
              .select(dependencies.database!.answerAttempts).get());
          expect(after!.length, before!.length);
          expect(providerPaths, isNot(contains('/reply')));
        }
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          1,
        );
        expect(find.textContaining('private pairing failure'), findsNothing);
        await tester.tap(find.byKey(const ValueKey('ari-toggle-chat')));
        await settle();
        bar = tester.widget<NavigationBar>(find.byType(NavigationBar));
        bar.onDestinationSelected!(4);
        await settle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          4,
        );
        if (!pending.isCompleted) pending.complete(null);
        await settle();
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          4,
        );
      } finally {
        if (!pending.isCompleted) pending.complete(null);
        await tester.pumpWidget(const SizedBox());
        await settle();
        await tester.runAsync(() => directory!.delete(recursive: true));
      }
    });
  }
}

class _Entry implements AppEntryStateStore {
  @override
  Future<void> clear() async {}
  @override
  Future<void> markGuest() async {}
  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

class _Guest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}
