import 'dart:convert';
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/managed_tutor_controller.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/local_login_bridge.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/managed_tutor_test_screen.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main_ari_test.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_preference_quiz_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../../../../integration_test/support/field_trial_external_fakes.dart';

void main() {
  for (final transition in ['disconnect', 'background']) {
    testWidgets('W02 composed navigation and questionnaire survive $transition', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(1000, 1400));
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ari-optional-'),
      );
      final dependencies = await tester.runAsync(
        () => AppBootstrap(
          initializeFirebase: () async => throw StateError('fixture offline'),
          initializeSupabase: () async => throw StateError('fixture offline'),
          loadConfig: () => throw StateError('fixture offline'),
          guestSessionService: _Guest(),
          createDatabase: () => AppDatabase(
            NativeDatabase(File('${directory!.path}/app.sqlite')),
          ),
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

      final paths = <String>[];
      var authenticated = true;
      Future<void> settle() async {
        for (var i = 0; i < 15; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(tester.takeException(), isNull);
      }

      Future<void> tapText(String text) async {
        final target = find.text(text);
        await Scrollable.ensureVisible(tester.element(target), alignment: .5);
        await tester.pumpAndSettle();
        await tester.tap(target);
        await settle();
      }

      try {
        await tester.pumpWidget(
          AriTestApp(
            loadDependencies: () async => dependencies!,
            loadBridge: () async => LocalLoginBridge(
              token: 'fixture-token',
              client: MockClient((request) async {
                paths.add(request.url.path);
                if (request.url.path == '/disconnect') authenticated = false;
                return http.Response(switch (request.url.path) {
                  '/login' =>
                    '{"verificationUrl":"https://auth.openai.com/codex/device","userCode":"TEST-CODE"}',
                  '/status' =>
                    '{"authenticated":$authenticated,"inferenceEnabled":$authenticated}',
                  '/connect' => '{"ready":$authenticated}',
                  _ => '{}',
                }, 200);
              }),
            ),
          ),
        );
        await settle();
        expect(paths, isEmpty);
        await tester.tap(find.byKey(const ValueKey('ari-toggle-chat')));
        await settle();
        await tapText('เปิดห้องสนทนา');
        final panel = tester.widget<ManagedTutorTestScreen>(
          find.byType(ManagedTutorTestScreen),
        );
        expect(panel.host.controller.state, ManagedTutorState.ready);
        final registry = tester
            .widget<MenuActionScope>(find.byType(MenuActionScope))
            .registry;
        final owner = await tester.runAsync(
          () => dependencies!.localOwners!.getOrCreateActiveOwner(),
        );
        var sequence = 0;
        Future<void> invoke(String id) async {
          final snapshot = registry.snapshot();
          expect(
            (snapshot['actions'] as List).map((a) => a['id']),
            contains(id),
          );
          final result = await registry.execute(
            id: id,
            owner: owner!.id,
            revision: snapshot['revision'] as int,
            requestId: 'w02-${sequence++}',
          );
          expect(result['status'], 'invoked', reason: id);
          await settle();
        }

        for (final (index, id)
            in NavigationGlossary.mainDestinationIds.indexed) {
          await invoke(id);
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            index,
          );
          expect(
            panel.host.controller.state,
            ManagedTutorState.ready,
            reason: 'Embedded AI intentionally remains active across core tabs',
          );
        }
        await invoke('navigation/open-menu');
        expect(find.byType(Drawer), findsOneWidget);
        await invoke('drawer/settings');
        expect(find.byType(SettingScreen), findsOneWidget);
        // The offline guest fixture has no authenticated app account. These
        // controls are conditionally absent, not declared globally inapplicable.
        expect(
          (registry.snapshot()['actions'] as List).map((a) => a['id']),
          isNot(contains('settings/change-password')),
        );
        expect(
          (registry.snapshot()['actions'] as List).map((a) => a['id']),
          isNot(contains('settings/logout')),
        );
        await invoke('navigation/back');
        await invoke('home/learn');
        await invoke('home/study-planning');
        await invoke('study-planning/open-learning-preferences');
        expect(find.byType(LearningPreferenceQuizScreen), findsOneWidget);
        final field = find.descendant(
          of: find.byType(LearningPreferenceQuizScreen),
          matching: find.byType(TextField),
        );
        await tester.enterText(field, '47');
        await tester.pump();
        Map<String, dynamic> preferencesContext() =>
            jsonDecode(
                  (registry.snapshot()['context'] as List).singleWhere(
                        (r) =>
                            r['id'] ==
                            'study-planning/learning-preferences/context',
                      )['value']
                      as String,
                )
                as Map<String, dynamic>;
        final before = await tester.runAsync(
          () => dependencies!.database!
              .select(dependencies.database!.learnerPreferences)
              .get(),
        );
        final connects = paths.where((p) => p == '/connect').length;
        if (transition == 'background') {
          for (final state in [
            AppLifecycleState.inactive,
            AppLifecycleState.hidden,
            AppLifecycleState.paused,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
            await settle();
          }
          for (final state in [
            AppLifecycleState.hidden,
            AppLifecycleState.inactive,
            AppLifecycleState.resumed,
          ]) {
            tester.binding.handleAppLifecycleStateChanged(state);
            await settle();
          }
        } else {
          await tapText('ออกจากระบบทดสอบ');
        }
        expect(panel.host.controller.state, ManagedTutorState.disconnected);
        expect(paths.where((p) => p == '/connect'), hasLength(connects));
        expect(tester.widget<TextField>(field).controller!.text, '47');
        final afterDisconnect = await tester.runAsync(
          () => dependencies!.database!
              .select(dependencies.database!.learnerPreferences)
              .get(),
        );
        expect(afterDisconnect, before);
        final save = find.byKey(const ValueKey('learning-preferences/save'));
        await tester.ensureVisible(save);
        await tester.tap(save);
        await settle();
        final saved = await tester.runAsync(
          () => dependencies!.database!
              .select(dependencies.database!.learnerPreferences)
              .get(),
        );
        expect(saved!.single.availableMinutesPerDay, 47);
        expect(paths, isNot(contains('/reply')));
        // Explicit simulated reauthentication, then a fresh connect.
        await tapText('เชื่อมบัญชี ChatGPT');
        authenticated = true;
        await tapText('กรอกเสร็จแล้ว ตรวจสถานะ');
        expect(panel.host.controller.state, ManagedTutorState.ready);
        expect(paths.where((p) => p == '/connect'), hasLength(connects + 1));
        expect(preferencesContext()['lastConfirmed']['minutes'], 47);
        await invoke('navigation/back');
        await invoke('study-planning/open-learning-preferences');
        expect(tester.widget<TextField>(field).controller!.text, '47');
        final durable = await tester.runAsync(
          () => dependencies!.database!
              .select(dependencies.database!.learnerPreferences)
              .get(),
        );
        expect(durable, saved);
      } finally {
        await tester.pumpWidget(const SizedBox());
        await settle();
        await tester.runAsync(() => directory!.delete(recursive: true));
        await tester.binding.setSurfaceSize(null);
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
