import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/study_planning_hub_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets('the composed parent owns one canonical study-planning entry', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database),
        child: const MaterialApp(
          home: MainNavigationScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final entry = find.byKey(const ValueKey<String>('home/study-planning'));
    expect(entry, findsOneWidget);
    await tester.tap(entry);
    await tester.pumpAndSettle();
    expect(find.byType(StudyPlanningHubScreen), findsOneWidget);
  });

  testWidgets('the hub is the only parent that opens the catalog', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final dependencies = _dependencies(database);

    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: dependencies,
        child: const MaterialApp(home: StudyPlanningHubScreen()),
      ),
    );

    expect(
      find.byType(StudyPlanningHubScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(LearningPackCatalogScreen), findsNothing);
    await tester.tap(
      find.byKey(const ValueKey<String>('study-planning/open-catalog')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byType(StudyPlanningHubScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
  });

  testWidgets('an open catalog child follows the live parent kill switch', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(registry.dispose);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, features: registry),
        child: MaterialApp(
          home: MainNavigationScreen(featureRegistry: registry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('home/study-planning')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('study-planning/open-catalog')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
    expect(find.text('Travel basics'), findsOneWidget);

    registry.setOverride(Feature.studyPlanning, FeatureState.disabled);
    await tester.pump();

    expect(find.byType(LearningPackCatalogScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(find.text('Travel basics'), findsNothing);
  });

  testWidgets('a direct stale catalog child fails closed without dependency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: ProductionFeatureGate(
          feature: Feature.studyPlanning,
          registry: BuildFeatureRegistry.allEnabled(),
          builder: _catalogChild,
        ),
      ),
    );

    expect(find.byType(LearningPackCatalogScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
  });
}

Widget _catalogChild(BuildContext context) => const LearningPackCatalogScreen();

AppDependencies _dependencies(
  AppDatabase database, {
  FeatureRegistry features = const BuildFeatureRegistry.allEnabled(),
}) {
  final research = InertResearchDependencies(database);
  final owner = _Owner();
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
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
    studyPlanning: StudyPlanningUseCases(
      packs: _Packs(),
      progress: ProgressUseCases(
        owners: owner,
        queries: DriftProgressQueries(database),
        nowUtc: () => DateTime.utc(2026, 8, 24),
      ),
    ),
  );
}

final class _Packs implements LearningPackRepository {
  @override
  Future<Never> getVersion(String packId, int revision) => Future<Never>.error(
    StateError('Catalog-only test repository has no pack-detail content.'),
  );

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async => [
    LearningPackSummary(
      packId: 'pack:travel',
      revision: 1,
      title: 'Travel basics',
      cefrLevel: 'A1',
      topic: 'travel',
      skill: 'vocabulary',
      goal: 'recognition',
      contentIdentity: ContentIdentity(
        type: ContentType.learningPack,
        id: 'pack:travel',
        revision: 1,
      ),
    ),
  ];
}

final class _Owner implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:study-planning',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _GuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'study-planning');
}
