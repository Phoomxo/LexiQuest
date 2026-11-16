import 'package:vocab_learning_app/features/ai_tutor/application/menu_action_registry.dart';
import 'package:vocab_learning_app/features/ai_tutor/presentation/menu_action_binding.dart';
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
import 'package:vocab_learning_app/navigation/navigation_glossary.dart';
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
  for (final (action, screen) in [
    ('study-planning/open-catalog', LearningPackCatalogScreen),
    ('study-planning/open-goals', LearningGoalsScreen),
    ('study-planning/open-learning-preferences', LearningPreferenceQuizScreen),
  ]) {
    testWidgets('MCP executes actual planning control $action', (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final registry = MenuActionRegistry(currentOwner: () => 'fixture');
      await tester.pumpWidget(
        MenuActionScope(
          registry: registry,
          child: AppDependenciesScope(
            dependencies: _dependencies(database),
            child: const MaterialApp(home: StudyPlanningHubScreen()),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final snapshot = registry.snapshot();
      expect(
        (snapshot['actions'] as List).any((a) => a['id'] == action),
        isTrue,
      );
      final result = await registry.execute(
        id: action,
        owner: 'fixture',
        revision: snapshot['revision'] as int,
        requestId: 'mcp-test',
      );
      await tester.pumpAndSettle();
      expect(result['status'], 'invoked');
      expect(find.byType(screen), findsOneWidget);
      expect(
        (registry.snapshot()['actions'] as List).any((a) => a['id'] == action),
        isFalse,
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Thai glossary planning actions expose one semantic action', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    try {
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database),
          child: const MaterialApp(home: StudyPlanningHubScreen()),
        ),
      );
      await tester.pumpAndSettle();

      for (final entryId in NavigationGlossary.studyPlanningActionIds) {
        _expectSingleThaiGlossaryAction(
          action: find.byKey(ValueKey<String>(entryId)),
          entryId: entryId,
        );
      }
    } finally {
      semantics.dispose();
    }
  });

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
            initialIndex: 0,
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
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
    expect(find.widgetWithText(AppBar, 'วางแผนการเรียน'), findsOneWidget);
    expect(find.byType(LearningPackCatalogScreen), findsNothing);
    final catalogAction = find.byKey(
      const ValueKey<String>('study-planning/open-catalog'),
    );
    expect(catalogAction, findsOneWidget);
    expect(
      find.descendant(
        of: catalogAction,
        matching: find.text('เลือกชุดเนื้อหาการเรียน'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: catalogAction,
        matching: find.byIcon(Icons.menu_book_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(catalogAction);
    await tester.pumpAndSettle();

    expect(
      find.byType(StudyPlanningHubScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
    expect(
      ModalRoute.of(
        tester.element(find.byType(LearningPackCatalogScreen)),
      )?.settings.name,
      'study-planning/catalog',
    );
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
    final goalsAction = find.byKey(
      const ValueKey<String>('study-planning/open-goals'),
    );
    expect(goalsAction, findsOneWidget);
    expect(
      find.descendant(of: goalsAction, matching: find.text('เป้าหมายการเรียน')),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: goalsAction,
        matching: find.byIcon(Icons.flag_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(goalsAction);
    await tester.pumpAndSettle();
    expect(find.byType(LearningGoalsScreen), findsOneWidget);
    expect(
      ModalRoute.of(
        tester.element(find.byType(LearningGoalsScreen)),
      )?.settings.name,
      'study-planning/goals',
    );
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
    final preferencesAction = find.byKey(
      const ValueKey<String>('study-planning/open-learning-preferences'),
    );
    expect(preferencesAction, findsOneWidget);
    expect(
      find.descendant(
        of: preferencesAction,
        matching: find.text('การตั้งค่าการเรียน'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: preferencesAction,
        matching: find.byIcon(Icons.tune_outlined),
      ),
      findsOneWidget,
    );
    await tester.tap(preferencesAction);
    await tester.pumpAndSettle();

    expect(find.byType(LearningPreferenceQuizScreen), findsOneWidget);
    expect(
      find.byType(StudyPlanningHubScreen, skipOffstage: false),
      findsOneWidget,
    );
    expect(
      ModalRoute.of(
        tester.element(find.byType(LearningPreferenceQuizScreen)),
      )?.settings.name,
      'study-planning/learning-preferences',
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
          home: MainNavigationScreen(
            initialIndex: 0,
            featureRegistry: registry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
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
          home: MainNavigationScreen(
            initialIndex: 0,
            featureRegistry: registry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
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
          home: MainNavigationScreen(
            initialIndex: 0,
            featureRegistry: registry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
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
    await _selectGoalLocalDateTime(tester);
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
          home: MainNavigationScreen(
            initialIndex: 0,
            featureRegistry: registry,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('legacy-drawer-button')));
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

  for (final action in [
    'open-catalog',
    'open-goals',
    'open-learning-preferences',
    'open-plan',
    'open-personal-sets',
  ]) {
    testWidgets('AO $action admits one child and returns to original parent', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final observer = _PushObserver();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database),
          child: MaterialApp(
            navigatorObservers: [observer],
            home: const StudyPlanningHubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final parent = tester.element(find.byType(StudyPlanningHubScreen));
      final invoke = _planningAction(tester, action);
      final before = observer.pushes;
      invoke();
      invoke();
      await tester.pumpAndSettle();
      expect(observer.pushes, before + 1);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(tester.element(find.byType(StudyPlanningHubScreen)), same(parent));
      _planningAction(tester, action)();
      await tester.pumpAndSettle();
      expect(observer.pushes, before + 2);
      expect(tester.takeException(), isNull);
    });
  }

  for (final boundary in [
    'tab',
    'cover',
    'inactive',
    'dispose',
    'pop',
    'dependencies',
  ]) {
    testWidgets('AO detached parent callback is fenced after $boundary', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final observer = _PushObserver();
      final navigator = GlobalKey<NavigatorState>();
      var dependencies = _dependencies(database);
      var active = true;
      var show = true;
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                navigatorKey: navigator,
                navigatorObservers: [observer],
                home: const Scaffold(body: Text('root')),
              ),
            );
          },
        ),
      );
      navigator.currentState!.push(
        MaterialPageRoute<void>(
          builder: (_) => StatefulBuilder(
            builder: (context, setState) {
              if (boundary == 'tab' || boundary == 'dispose') update = setState;
              return TickerMode(
                enabled: active,
                child: show ? const StudyPlanningHubScreen() : const Scaffold(),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final stale = _planningAction(tester, 'open-catalog');
      switch (boundary) {
        case 'tab':
          update(() => active = false);
          await tester.pumpAndSettle();
        case 'dispose':
          update(() => show = false);
          await tester.pumpAndSettle();
        case 'cover':
          navigator.currentState!.push(
            MaterialPageRoute<void>(
              builder: (_) => const Scaffold(body: Text('cover')),
            ),
          );
          await tester.pumpAndSettle();
        case 'pop':
          navigator.currentState!.pop();
        case 'inactive':
          tester.binding.handleAppLifecycleStateChanged(
            AppLifecycleState.inactive,
          );
          await tester.pump();
        case 'dependencies':
          update(() => dependencies = _dependencies(database));
          await tester.pumpAndSettle();
      }
      final before = observer.pushes;
      stale();
      await tester.pumpAndSettle();
      expect(observer.pushes, before);
      expect(tester.takeException(), isNull);
      if (boundary == 'inactive') {
        tester.binding.handleAppLifecycleStateChanged(
          AppLifecycleState.resumed,
        );
        await tester.pumpAndSettle();
        stale();
        await tester.pumpAndSettle();
        expect(observer.pushes, before);
        _planningAction(tester, 'open-catalog')();
        await tester.pumpAndSettle();
        expect(observer.pushes, before + 1);
      }
    });
  }

  for (final (action, screen) in [
    ('open-catalog', LearningPackCatalogScreen),
    ('open-goals', LearningGoalsScreen),
    ('open-learning-preferences', LearningPreferenceQuizScreen),
  ]) {
    testWidgets(
      'AO $action child follows replacement registry and stays usable',
      (tester) async {
        final database = AppDatabase(NativeDatabase.memory());
        addTearDown(database.close);
        final old = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        final replacement = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.allEnabled(),
        );
        addTearDown(old.dispose);
        addTearDown(replacement.dispose);
        var dependencies = _dependencies(database, features: old);
        late StateSetter update;
        await tester.pumpWidget(
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return AppDependenciesScope(
                dependencies: dependencies,
                child: const MaterialApp(home: StudyPlanningHubScreen()),
              );
            },
          ),
        );
        await tester.pumpAndSettle();
        _planningAction(tester, action)();
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget);
        replacement.emergencyOff(Feature.studyPlanning);
        update(
          () => dependencies = _dependencies(database, features: replacement),
        );
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsNothing);
        expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
        replacement.setOverride(Feature.studyPlanning, FeatureState.enabled);
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget);
        old.emergencyOff(Feature.studyPlanning);
        await tester.pumpAndSettle();
        expect(find.byType(screen), findsOneWidget);
        await tester.pageBack();
        await tester.pumpAndSettle();
        expect(find.byType(StudyPlanningHubScreen), findsOneWidget);
        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'AO real Drift goal child remains editable after single parent admission',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final goals = await _realGoalUseCases(database);
      final goal = await goals.create(
        kind: LearningGoalKind.languageTest,
        title: 'Planning lifetime goal',
        deadlineAtUtc: DateTime.utc(2026, 9, 1, 5),
        timezone: const LearningGoalTimezoneContext(
          timezoneId: 'Asia/Bangkok',
          utcOffsetMinutes: 420,
        ),
      );
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database, learningGoals: goals),
          child: const MaterialApp(home: StudyPlanningHubScreen()),
        ),
      );
      await tester.pumpAndSettle();
      final open = _planningAction(tester, 'open-goals');
      open();
      open();
      await tester.pumpAndSettle();
      expect(
        find.byType(LearningGoalsScreen, skipOffstage: false),
        findsOneWidget,
      );
      await tester.tap(find.byKey(ValueKey('learning-goal/${goal.id}/status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('สำเร็จแล้ว').last);
      await tester.pumpAndSettle();
      final row = await database.select(database.learningGoals).getSingle();
      expect(row.status, 'completed');
      expect(row.localRevision, 2);
      expect(
        (await database.select(database.outboxOperations).get()).where(
          (r) => r.entityType == 'learningGoal',
        ),
        hasLength(2),
      );
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(StudyPlanningHubScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('AO compact Thai controls and semantic action retain one route', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final semantics = tester.ensureSemantics();
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    try {
      final observer = _PushObserver();
      await tester.pumpWidget(
        AppDependenciesScope(
          dependencies: _dependencies(database),
          child: MaterialApp(
            navigatorObservers: [observer],
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: const TextScaler.linear(2)),
              child: child!,
            ),
            home: const StudyPlanningHubScreen(),
          ),
        ),
      );
      await tester.pumpAndSettle();
      for (final id in NavigationGlossary.studyPlanningActionIds) {
        final action = find.byKey(ValueKey(id));
        await tester.ensureVisible(action);
        await tester.pumpAndSettle();
        _expectSingleThaiGlossaryAction(action: action, entryId: id);
        expect(tester.takeException(), isNull);
      }
      final action = find.byKey(const ValueKey('study-planning/open-catalog'));
      await tester.ensureVisible(action);
      await tester.pumpAndSettle();
      final button = tester.widget<FilledButton>(action).onPressed!;
      final semantic = find
          .ancestor(of: action, matching: find.byType(Semantics))
          .evaluate()
          .map((e) => e.widget)
          .whereType<Semantics>()
          .firstWhere((w) => w.properties.onTap != null)
          .properties
          .onTap!;
      button();
      semantic();
      _planningAction(tester, 'open-goals')();
      await tester.pumpAndSettle();
      expect(observer.pushes, 2);
      expect(find.byType(LearningPackCatalogScreen), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final action in [
    'open-catalog',
    'open-goals',
    'open-learning-preferences',
  ]) {
    testWidgets('AO $action child rebuild survives removed parent', (
      tester,
    ) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final navigator = GlobalKey<NavigatorState>();
      var dependencies = _dependencies(database);
      late StateSetter update;
      await tester.pumpWidget(
        StatefulBuilder(
          builder: (_, setState) {
            update = setState;
            return AppDependenciesScope(
              dependencies: dependencies,
              child: MaterialApp(
                navigatorKey: navigator,
                home: const Scaffold(body: Text('root')),
              ),
            );
          },
        ),
      );
      final parentRoute = MaterialPageRoute<void>(
        builder: (_) => const StudyPlanningHubScreen(),
      );
      navigator.currentState!.push(parentRoute);
      await tester.pumpAndSettle();
      _planningAction(tester, action)();
      await tester.pumpAndSettle();
      navigator.currentState!.removeRoute(parentRoute);
      await tester.pumpAndSettle();
      update(() => dependencies = _dependencies(database));
      await tester.pumpAndSettle();
      expect(
        find.byType(StudyPlanningHubScreen, skipOffstage: false),
        findsNothing,
      );
      expect(find.byType(ProductionFeatureUnavailable), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.text('root'), findsOneWidget);
    });
  }
}

void _expectSingleThaiGlossaryAction({
  required Finder action,
  required String entryId,
}) {
  final entry = NavigationGlossary.require(entryId);
  final tooltip = find.ancestor(
    of: action,
    matching: find.byWidgetPredicate(
      (widget) => widget is Tooltip && widget.message == entry.tooltip,
    ),
  );
  expect(tooltip, findsOneWidget);
  expect(
    find.descendant(of: tooltip, matching: find.text(entry.fullThaiLabel)),
    findsOneWidget,
  );
  final semanticActions = find
      .ancestor(of: action, matching: find.byType(Semantics))
      .evaluate()
      .map((element) => element.widget)
      .whereType<Semantics>()
      .where(
        (semantics) =>
            semantics.properties.label == entry.semanticsLabel &&
            semantics.properties.onTap != null &&
            semantics.excludeSemantics,
      )
      .toList(growable: false);
  expect(semanticActions, hasLength(1));
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
          activeOwnerId: () async => 'synthetic-owner-a',
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
    activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
    repository: onSaveAttempt == null
        ? durableRepository
        : _ObservedGoals(durableRepository, onSaveAttempt),
    nowUtc: () => DateTime.utc(2026, 8, 25, 12),
    generateId: () => 'goal:real',
  );
}

Future<void> _selectGoalLocalDateTime(WidgetTester tester) async {
  final date = find.byKey(const ValueKey('learning-goals/deadline/date'));
  await tester.ensureVisible(date);
  await tester.tap(date);
  await tester.pumpAndSettle();
  await tester.enterText(
    find
        .descendant(
          of: find.byType(DatePickerDialog),
          matching: find.byType(TextField),
        )
        .first,
    '09/01/2026',
  );
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(const ValueKey('learning-goals/deadline/time')));
  await tester.pumpAndSettle();
  final times = find.descendant(
    of: find.byType(TimePickerDialog),
    matching: find.byType(TextField),
  );
  await tester.enterText(times.at(0), '12');
  await tester.enterText(times.at(1), '00');
  await tester.tap(find.widgetWithText(TextButton, 'ตกลง').last);
  await tester.pumpAndSettle();
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
    String? expectedOwnerId,
  }) {
    onSaveAttempt();
    return delegate.save(
      goal,
      mutationAllowed: mutationAllowed,
      expectedOwnerId: expectedOwnerId,
    );
  }
}

final class _Goals implements LearningGoalRepository {
  @override
  Future<List<LearningGoal>> list() async => const [];

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
    String? expectedOwnerId,
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
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = LearnerPreferences(
      ownerId: current.ownerId,
      preferenceVersion: current.preferenceVersion,
      goal: current.goal,
      availableMinutesPerDay: current.availableMinutesPerDay,
      activityPreference: current.activityPreference,
      updatedAtUtc: current.updatedAtUtc,
      display: display,
    );
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

MenuAction _planningAction(WidgetTester tester, String action) => tester
    .widget<MenuActionBinding>(
      find.byWidgetPredicate(
        (w) => w is MenuActionBinding && w.id == 'study-planning/$action',
      ),
    )
    .onInvoke!;

class _PushObserver extends NavigatorObserver {
  int pushes = 0;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushes++;
  }
}
