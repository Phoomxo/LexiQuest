import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/goals/data/drift_learning_goal_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/goals/application/learning_goal_use_cases.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal.dart';
import 'package:vocab_learning_app/features/goals/domain/learning_goal_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/learning_pack_catalog_screen.dart';
import 'package:vocab_learning_app/screens/learning_goals_screen.dart';
import 'package:vocab_learning_app/screens/learning_preference_quiz_screen.dart';
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
    expect(
      find.byKey(const ValueKey<String>('home/learning-preferences')),
      findsNothing,
    );
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

  testWidgets('the hub opens goals as a child without another main entry', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database),
        child: const MaterialApp(home: StudyPlanningHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('home/study-planning')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('study-planning/open-goals')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LearningGoalsScreen), findsOneWidget);
  });

  testWidgets('f35 hub owns the typed preference quiz child action', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database),
        child: const MaterialApp(home: StudyPlanningHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('home/learning-preferences')),
      findsNothing,
    );
    await tester.tap(
      find.byKey(
        const ValueKey<String>('study-planning/open-learning-preferences'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(LearningPreferenceQuizScreen), findsOneWidget);
    expect(
      find.byType(StudyPlanningHubScreen, skipOffstage: false),
      findsOneWidget,
    );
  });

  testWidgets('f35 hub hides preference quiz when dependency is absent', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(database, includeLearnerPreferences: false),
        child: const MaterialApp(home: StudyPlanningHubScreen()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(
        const ValueKey<String>('study-planning/open-learning-preferences'),
      ),
      findsNothing,
    );
    expect(find.byType(LearningPreferenceQuizScreen), findsNothing);
  });

  testWidgets('f35 open preference quiz follows the live parent kill switch', (
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
    await tester.tap(find.byKey(const ValueKey('home/study-planning')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('study-planning/open-learning-preferences')),
    );
    await tester.pumpAndSettle();
    expect(find.byType(LearningPreferenceQuizScreen), findsOneWidget);

    registry.emergencyOff(Feature.studyPlanning);
    await tester.pump();

    expect(find.byType(LearningPreferenceQuizScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
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

  testWidgets('emergency-off fences an already-open create overlay', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(registry.dispose);
    var saveAttempts = 0;
    final goals = await _realGoalUseCases(
      database,
      onSaveAttempt: () => saveAttempts += 1,
    );
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(
          database,
          features: registry,
          learningGoals: goals,
        ),
        child: MaterialApp(
          home: MainNavigationScreen(featureRegistry: registry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home/study-planning')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('study-planning/open-goals')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('learning-goals/add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/title')),
      'IELTS practice target',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/deadline')),
      '2026-09-01T05:00:00Z',
    );
    await tester.enterText(
      find.byKey(const ValueKey('learning-goals/timezone')),
      'Asia/Bangkok',
    );
    final staleSubmit = tester
        .widget<FilledButton>(
          find.byKey(const ValueKey('learning-goals/create')),
        )
        .onPressed!;

    registry.emergencyOff(Feature.studyPlanning);
    staleSubmit();
    await tester.pumpAndSettle();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(saveAttempts, 0);
    expect(await database.select(database.learningGoals).get(), isEmpty);
    expect(
      (await database.select(database.outboxOperations).get()).where(
        (row) => row.entityType == 'learningGoal',
      ),
      isEmpty,
    );
  });

  testWidgets('emergency-off fences an already-open status overlay', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    addTearDown(registry.dispose);
    final goals = await _realGoalUseCases(database);
    final goal = await goals.create(
      kind: LearningGoalKind.languageTest,
      title: 'IELTS practice target',
      deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
      timezone: const LearningGoalTimezoneContext(
        timezoneId: 'Asia/Bangkok',
        utcOffsetMinutes: 420,
      ),
    );
    await tester.pumpWidget(
      AppDependenciesScope(
        dependencies: _dependencies(
          database,
          features: registry,
          learningGoals: goals,
        ),
        child: MaterialApp(
          home: MainNavigationScreen(featureRegistry: registry),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('home/study-planning')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('study-planning/open-goals')));
    await tester.pumpAndSettle();
    final statusFinder = find.byKey(
      ValueKey('learning-goal/${goal.id}/status'),
    );
    final staleSelection = tester
        .widget<PopupMenuButton<LearningGoalStatus>>(statusFinder)
        .onSelected!;
    await tester.tap(statusFinder);
    await tester.pumpAndSettle();

    registry.emergencyOff(Feature.studyPlanning);
    staleSelection(LearningGoalStatus.completed);
    await tester.pumpAndSettle();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    final row = await database.select(database.learningGoals).getSingle();
    expect(row.status, 'active');
    expect(row.localRevision, 1);
    expect(
      (await database.select(database.outboxOperations).get()).where(
        (candidate) => candidate.entityType == 'learningGoal',
      ),
      hasLength(1),
    );
  });
}

Widget _catalogChild(BuildContext context) => const LearningPackCatalogScreen();

AppDependencies _dependencies(
  AppDatabase database, {
  FeatureRegistry features = const BuildFeatureRegistry.allEnabled(),
  LearningGoalUseCases? learningGoals,
  bool includeLearnerPreferences = true,
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
    learningGoals:
        learningGoals ??
        LearningGoalUseCases(
          repository: _Goals(),
          nowUtc: () => DateTime.utc(2026, 8, 25),
          generateId: () => 'goal:test',
        ),
    learnerPreferences: includeLearnerPreferences
        ? LearnerPreferencesUseCases(
            repository: _Preferences(),
            owners: owner,
            nowUtc: () => DateTime.utc(2026, 8, 30),
          )
        : null,
  );
}

Future<LearningGoalUseCases> _realGoalUseCases(
  AppDatabase database, {
  void Function()? onSaveAttempt,
}) async {
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'owner:study-planning-real',
    nowUtc: () => DateTime.utc(2026, 8, 25),
  );
  await owners.getOrCreateActiveOwner();
  final durableRepository = DriftLearningGoalRepository(
    database,
    owners: owners,
  );
  return LearningGoalUseCases(
    repository: onSaveAttempt == null
        ? durableRepository
        : _ObservedGoals(durableRepository, onSaveAttempt),
    nowUtc: () => DateTime.utc(2026, 8, 25, 12),
    generateId: () => 'goal:real',
  );
}

final class _ObservedGoals implements LearningGoalRepository {
  const _ObservedGoals(this.delegate, this.onSaveAttempt);

  final LearningGoalRepository delegate;
  final void Function() onSaveAttempt;

  @override
  Future<List<LearningGoal>> list() => delegate.list();

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
  }) {
    onSaveAttempt();
    return delegate.save(goal, mutationAllowed: mutationAllowed);
  }
}

final class _Goals implements LearningGoalRepository {
  @override
  Future<List<LearningGoal>> list() async => const [];

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
  }) async {}
}

final class _Preferences implements LearnerPreferencesRepository {
  LearnerPreferences current = LearnerPreferences.defaults(
    ownerId: 'local:study-planning',
    updatedAtUtc: DateTime.utc(2026, 8, 30),
  );

  @override
  Future<LearnerPreferences> read(String ownerId) async => current;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
  }
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
