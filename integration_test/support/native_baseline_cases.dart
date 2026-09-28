import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import '../../test/support/inert_research_dependencies.dart';
import 'native_baseline_fixture.dart';

AppDependencies baselineDependencies(NativeBaselineFixture fixture) {
  final research = InertResearchDependencies(fixture.database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      supabase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
      aiTutor: RuntimeAvailability.unavailable,
      voice: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _NoAuthentication(fixture),
    quest: QuestUseCases(
      repository: DriftQuestRepository(fixture.database),
      owners: fixture.owners,
      generateId: () => 'synthetic-bm-unused-quest',
      nowUtc: () => DateTime.utc(2026, 9, 27),
      timezoneId: 'Asia/Bangkok',
    ),
    // Same production registry; only the local offline manager entry is exposed
    // for this bounded test. No instructional preview or research flag is set.
    features: RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
      overrides: {Feature.offlineContent: FeatureState.enabled},
    ),
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    database: fixture.database,
    localOwners: fixture.owners,
    vocabulary: fixture.vocabulary,
    learnerPreferences: fixture.preferences,
    learning: LearningUseCases(
      owners: fixture.owners,
      repository: DriftLearningRepository(fixture.database),
      generateId: () =>
          throw StateError('Navigation harness must not start learning'),
      nowUtc: () => DateTime.utc(2026, 9, 27),
      buildInfo: const AppBuildInfo.fromEnvironment(),
    ),
    displayPreferences: fixture.display,
    offlineContent: fixture.offline,
  );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 80));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  expect(tester.takeException(), isNull);
}

Future<void> _tap(WidgetTester tester, String key) async {
  final target = find.byKey(ValueKey(key));
  expect(target, findsOneWidget);
  await tester.ensureVisible(target);
  await _settle(tester);
  await tester.tap(target);
  await _settle(tester);
}

// SQLite work can depend on transactions started by UI callbacks in the host
// fake clock. Keep pumping that clock while real IO completes; do not suspend
// it inside a long runAsync wait.
Future<T> baselineAwait<T>(
  WidgetTester tester,
  Future<T> Function() action,
) async {
  T? value;
  Object? failure;
  var done = false;
  action().then(
    (result) {
      value = result;
      done = true;
    },
    onError: (Object error) {
      failure = error;
      done = true;
    },
  );
  for (var i = 0; !done && i < 500; i++) {
    await tester.pump(const Duration(milliseconds: 20));
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
  }
  if (!done) {
    throw StateError('Baseline IO did not complete within bounded wait');
  }
  if (failure != null) throw failure!;
  return value as T;
}

Future<void> runBaselineCase(
  WidgetTester tester,
  NativeBaselineFixture fixture,
  AppEntryStateStore entry,
  String phase,
) async {
  expect(await entry.read(), AppEntryMode.guest);
  final dependencies = baselineDependencies(fixture);
  await tester.pumpWidget(
    MyApp(dependencies: dependencies, ownsDependencies: false),
  );
  await _settle(tester);
  expect(find.byType(MainNavigationScreen), findsOneWidget);
  try {
    switch (phase) {
      case 'N01':
        expect(find.byType(NavigationDestination), findsNWidgets(4));
        for (final id in NavigationGlossary.mainDestinationIds) {
          await _tap(tester, id);
          expect(find.byType(MainNavigationScreen), findsOneWidget);
        }
        await _tap(tester, 'home/today');
      case 'N02':
      case 'N03':
        await _tap(tester, 'legacy-drawer-button');
        await _tap(tester, 'drawer/settings');
        expect(find.byType(SettingScreen), findsOneWidget);
        if (phase == 'N02') {
          for (var i = 0; i < 2; i++) {
            await _tap(tester, 'settings/offline-content');
            expect(find.byType(OfflineContentManagerScreen), findsOneWidget);
            expect(
              (await baselineAwait(
                tester,
                fixture.offline.catalog,
              )).single.identity,
              baselineContentIdentity,
            );
            final back = find.descendant(
              of: find.byType(OfflineContentManagerScreen),
              matching: find.byType(BackButton),
            );
            expect(back, findsOneWidget);
            await tester.tap(back);
            await _settle(tester);
            expect(find.byType(SettingScreen), findsOneWidget);
          }
        } else {
          await _tap(tester, 'theme-dark');
          expect(fixture.display.themeMode, ThemeMode.dark);
          await baselineAwait(
            tester,
            () => fixture.changePreferenceAndCreateWord(changeDisplay: false),
          );
          expect(
            (await baselineAwait(tester, fixture.snapshot))['externalCalls'],
            0,
          );
        }
      default:
        throw ArgumentError('Unknown baseline case');
    }
  } catch (error) {
    debugPrint('BM $phase failed: $error');
    rethrow;
  } finally {
    await tester.pumpWidget(const SizedBox.shrink());
    (dependencies.features as RuntimeFeatureRegistry).dispose();
    dependencies.quest.dispose();
  }
}

final class _NoAuthentication implements GuestSessionService {
  _NoAuthentication(this.fixture);
  final NativeBaselineFixture fixture;
  @override
  Future<GuestSessionResult> start() {
    fixture.gatewayCalls++;
    throw StateError(
      'Harness must use durable local guest entry; auth is disabled',
    );
  }
}
