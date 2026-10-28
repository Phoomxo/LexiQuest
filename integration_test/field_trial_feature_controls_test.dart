import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import 'support/field_trial_external_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'operator override survives a production-shell restart',
    (tester) async {
      final directory = await Directory.systemTemp.createTemp(
        'lexiquest-field-controls-',
      );
      final databasePath =
          '${directory.path}${Platform.pathSeparator}lexiquest.sqlite';
      final entryState = _GuestEntryStateStore();
      AppDependencies? mountedDependencies;

      try {
        final first = await _bootstrap(databasePath, entryState).initialize();
        mountedDependencies = first;
        await tester.pumpWidget(MyApp(dependencies: first));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        await _openDrawer(tester);
        await _scrollDrawerTo(
          tester,
          find.byKey(const ValueKey('drawer/ai-tutor/chat')),
        );
        expect(
          find.byKey(const ValueKey('drawer/ai-tutor/chat')),
          findsOneWidget,
        );

        await tester.runAsync(
          () => first.featureControls!.emergencyOff(
            Feature.aiTutor,
            source: 'field-operator',
          ),
        );
        await tester.pump();
        expect(
          first.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(
          find.byKey(const ValueKey('drawer/ai-tutor/chat')),
          findsNothing,
        );

        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        await tester.runAsync(first.dispose);
        mountedDependencies = null;

        final reopened = await _bootstrap(
          databasePath,
          entryState,
        ).initialize();
        mountedDependencies = reopened;
        await tester.pumpWidget(MyApp(dependencies: reopened));
        await _pumpUntilFound(tester, find.byType(MainNavigationScreen));
        await _openDrawer(tester);
        expect(
          reopened.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(
          find.byKey(const ValueKey('drawer/ai-tutor/chat')),
          findsNothing,
        );
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        if (mountedDependencies case final dependencies?) {
          await tester.runAsync(dependencies.dispose);
        }
        if (await directory.exists()) {
          await directory.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}

AppBootstrap _bootstrap(
  String databasePath,
  _GuestEntryStateStore entryState,
) => AppBootstrap(
  initializeFirebase: () async => throw StateError('firebase unavailable'),
  initializeSupabase: () async => throw StateError('supabase unavailable'),
  loadConfig: () => throw StateError('backend config unavailable'),
  guestSessionService: _GuestSession(),
  createDatabase: () => AppDatabase(NativeDatabase(File(databasePath))),
  createEntryStateStore: () async => entryState,
  exportStoreFactory: HostFakeExportStore.new,
  cameraGatewayFactory: HostFakeCameraGateway.new,
  speechRecognitionGatewayFactory: HostFakeSpeechRecognitionGateway.new,
  buildAiTutor: (_) => throw StateError('host fake: AI unavailable'),
  buildVoice: (_) => throw StateError('host fake: voice unavailable'),
);

Future<void> _pumpUntilFound(
  WidgetTester tester,
  Finder finder, {
  int maxPumps = 250,
}) async {
  for (var index = 0; index < maxPumps; index++) {
    await tester.pump(const Duration(milliseconds: 20));
    if (finder.evaluate().isNotEmpty) return;
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  fail('Widget did not appear after $maxPumps bounded pumps: $finder');
}

Future<void> _openDrawer(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
  await tester.pumpAndSettle();
  expect(find.byType(Drawer), findsOneWidget);
}

Future<void> _scrollDrawerTo(WidgetTester tester, Finder target) async {
  await tester.scrollUntilVisible(
    target,
    180,
    scrollable: find.descendant(
      of: find.byType(Drawer),
      matching: find.byType(Scrollable),
    ),
  );
}

final class _GuestEntryStateStore implements AppEntryStateStore {
  @override
  Future<void> clear() async {}

  @override
  Future<void> markGuest() async {}

  @override
  Future<AppEntryMode> read() async => AppEntryMode.guest;
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}
