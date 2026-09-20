import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/screens/study_plan_screen.dart';
import 'package:vocab_learning_app/screens/personal_sets_screen.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import '../../../../integration_test/support/field_trial_external_fakes.dart';

void main() {
  testWidgets(
    'MCP controls every main tab and drawer destination in the composed app',
    (tester) async {
      debugPrint('MCP fixture: bootstrap');
      final directory = await tester.runAsync(
        () => Directory.systemTemp.createTemp('ari-menu-fixture-'),
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
          buildAiTutor: (_) =>
              throw StateError('fixture external AI unavailable'),
          buildVoice: (_) =>
              throw StateError('fixture external voice unavailable'),
        ).initialize(),
      );
      debugPrint('MCP fixture: owner');
      final owner = await tester.runAsync(
        () => dependencies!.localOwners!.getOrCreateActiveOwner(),
      );
      debugPrint('MCP fixture: mounted setup');
      final registry = MenuActionRegistry(currentOwner: () => owner!.id);
      final navigator = GlobalKey<NavigatorState>();
      var request = 0;
      Future<void> settle() async {
        for (var i = 0; i < 20; i++) {
          await tester.pump(const Duration(milliseconds: 50));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(tester.takeException(), isNull);
      }

      Future<void> invoke(String id) async {
        debugPrint('MCP fixture: invoke $id');
        final snapshot = registry.snapshot();
        expect(
          (snapshot['actions'] as List).any((a) => a['id'] == id),
          isTrue,
          reason:
              'Actual composed action missing: $id; available: ${snapshot['actions']}',
        );
        final result = await registry
            .execute(
              id: id,
              owner: owner!.id,
              revision: snapshot['revision'] as int,
              requestId: 'request-${request++}',
            )
            .timeout(const Duration(seconds: 3));
        expect(result['status'], 'invoked', reason: id);
        await settle();
      }

      try {
        await tester.pumpWidget(
          MenuActionScope(
            registry: registry,
            child: MyApp(
              dependencies: dependencies!,
              ownsDependencies: false,
              navigatorKey: navigator,
              additionalNavigatorObservers: [MenuRouteObserver(registry)],
            ),
          ),
        );
        await settle();
        for (final (index, id)
            in NavigationGlossary.mainDestinationIds.indexed) {
          await invoke(id);
          expect(
            tester
                .widget<NavigationBar>(find.byType(NavigationBar))
                .selectedIndex,
            index,
          );
        }
        for (final id in NavigationGlossary.drawerDestinationIds) {
          await invoke('navigation/open-menu');
          expect(find.byType(Drawer), findsOneWidget);
          await invoke(id);
          expect(
            navigator.currentState!.canPop(),
            isTrue,
            reason: '$id must open a real destination',
          );
          if (id == 'drawer/settings') {
            await invoke('settings/offline-content');
            expect(find.text('เนื้อหาออฟไลน์'), findsWidgets);
          }
          navigator.currentState!.popUntil((route) => route.isFirst);
          await settle();
        }
        for (final id in NavigationGlossary.secondaryDestinationIds) {
          await invoke(id == 'home/weakness' ? 'home/mastery' : 'home/learn');
          await invoke(id);
          expect(navigator.currentState!.canPop(), isTrue, reason: id);
          if (id == 'home/study-planning') {
            for (final extra in [
              'study-planning/open-plan',
              'study-planning/open-personal-sets',
            ]) {
              await invoke(extra);
              expect(
                find.byType(
                  extra == 'study-planning/open-plan'
                      ? StudyPlanScreen
                      : PersonalSetsScreen,
                ),
                findsOneWidget,
              );
              navigator.currentState!.pop();
              await settle();
              expect(navigator.currentState!.canPop(), isTrue);
            }
          }
          navigator.currentState!.popUntil((route) => route.isFirst);
          await settle();
        }
        await invoke('home/profile');
        await invoke('profile-open-mastery');
        expect(
          tester
              .widget<NavigationBar>(find.byType(NavigationBar))
              .selectedIndex,
          2,
        );
        await invoke('mastery-open-review');
        expect(navigator.currentState!.canPop(), isTrue);
        navigator.currentState!.popUntil((route) => route.isFirst);
        await settle();
        await invoke('home/learn');
        for (final id in NavigationGlossary.learningModeIds) {
          await invoke(id);
          expect(navigator.currentState!.canPop(), isTrue, reason: id);
          navigator.currentState!.popUntil((route) => route.isFirst);
          await settle();
        }
      } finally {
        await tester.pumpWidget(const SizedBox());
        debugPrint('MCP fixture: cleanup');
        var disposed = false;
        Object? disposalError;
        final disposal = dependencies!.dispose().then(
          (_) {
            disposed = true;
          },
          onError: (Object error) {
            disposalError = error;
            disposed = true;
          },
        );
        for (var i = 0; i < 200 && !disposed; i++) {
          await tester.pump(const Duration(milliseconds: 20));
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
        }
        expect(
          disposed,
          isTrue,
          reason: 'All composed resource cleanup must drain',
        );
        expect(disposalError, isNull);
        await disposal;
        debugPrint('MCP fixture: disposed');
        await tester.runAsync(() => directory!.delete(recursive: true));
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
  );
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
