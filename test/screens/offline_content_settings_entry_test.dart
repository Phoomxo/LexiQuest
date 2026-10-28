import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/offline_content/application/offline_content_manager.dart';
import 'package:vocab_learning_app/features/offline_content/domain/offline_content_state.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/offline_content_manager_screen.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets('f44 settings entry is dependency and runtime gated', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(registry.dispose);
    final manager = _SettingsManager();
    final dependencies = _dependencies(database, registry, manager);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingScreen()),
      ),
    );

    final entry = find.byKey(const ValueKey('settings/offline-content'));
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(OfflineContentManagerScreen), findsOneWidget);

    registry.emergencyOff(Feature.offlineContent);
    await tester.pump();
    expect(find.byType(OfflineContentManagerScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
  });

  testWidgets('f44 settings hides entry when dependency is absent', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dependencies = _dependencies(
      database,
      const BuildFeatureRegistry.allEnabled(),
      null,
    );
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: SettingScreen()),
      ),
    );
    expect(
      find.byKey(const ValueKey('settings/offline-content')),
      findsNothing,
    );
  });
}

AppDependencies _dependencies(
  AppDatabase database,
  FeatureRegistry features,
  OfflineContentManager? offlineContent,
) {
  final research = InertResearchDependencies(database);
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.unavailable,
      backends: RuntimeAvailability.unavailable,
    ),
    config: null,
    guestSessionService: _GuestSession(),
    quest: testQuestUseCases(),
    features: features,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    database: database,
    offlineContent: offlineContent,
  );
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'f44-guest');
}

final class _SettingsManager implements OfflineContentManager {
  @override
  Future<bool> canRemove(ContentIdentity identity) async => false;

  @override
  Future<List<OfflineContentState>> catalog() async => const [];

  @override
  Future<int> cleanupForDiskPressure({required int bytesToFree}) async => 0;

  @override
  Future<void> dispose() async {}

  @override
  Future<OfflineContentState> download(ContentIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<int> removeBytes(ContentIdentity identity) async => 0;

  @override
  Future<void> reconcile() async {}

  @override
  Future<OfflineContentState> repair(ContentIdentity identity) =>
      throw UnimplementedError();

  @override
  Future<OfflineContentState> verify(ContentIdentity identity) =>
      throw UnimplementedError();
}
