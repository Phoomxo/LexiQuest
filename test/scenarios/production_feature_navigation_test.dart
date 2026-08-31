import 'dart:typed_data';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide
        LocalOwner,
        QuestDefinition,
        QuestInstance,
        VocabularyCategory,
        VocabularyWord;
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_use_cases.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/evidence_policy_rollout.dart';
import 'package:vocab_learning_app/features/learning/application/session_configuration_policy.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_mode.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning/domain/session_configuration.dart';
import 'package:vocab_learning_app/features/learning/presentation/session_configuration_sheet.dart';
import 'package:vocab_learning_app/features/learning/presentation/unified_lesson_shell.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/media_practice/application/object_scanner_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/application/speech_practice_use_cases.dart';
import 'package:vocab_learning_app/features/media_practice/domain/media_practice_contracts.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_repository.dart';
import 'package:vocab_learning_app/features/rewards/application/reward_use_cases.dart';
import 'package:vocab_learning_app/features/rewards/data/drift_reward_repository.dart';
import 'package:vocab_learning_app/features/research/domain/research_protocol_mode_catalog.dart';
import 'package:vocab_learning_app/features/research/data/drift_experiment_assignment_repository.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/main.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_contract.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/runtime/registries/experiment_registry.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/screens/ghost_shadow_duel_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/learning_history_screen.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
import 'package:vocab_learning_app/screens/study_planning_hub_screen.dart';
import 'package:vocab_learning_app/screens/pre_post_assessment_screen.dart';
import 'package:vocab_learning_app/screens/review_center_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';

void main() {
  final productionEntries = <_ProductionEntryCase>[
    const _ProductionEntryCase(
      feature: Feature.vocabulary,
      id: 'home/vocabulary',
      surface: _EntrySurface.bottom,
      destinationType: CategoriesPage,
    ),
    const _ProductionEntryCase(
      feature: Feature.quiz,
      id: 'home/learn/quiz',
      surface: _EntrySurface.learning,
      destinationType: QuizScreen,
      routeName: 'learning/quiz',
    ),
    const _ProductionEntryCase(
      feature: Feature.srs,
      id: 'home/learn/srs',
      surface: _EntrySurface.learning,
      destinationType: SrsFlashcardsScreen,
      routeName: 'learning/srs',
    ),
    const _ProductionEntryCase(
      feature: Feature.reading,
      id: 'home/learn/associative-reading',
      surface: _EntrySurface.learning,
      destinationType: AssociativeReadingLauncherScreen,
      routeName: 'learning/associative-reading',
    ),
    const _ProductionEntryCase(
      feature: Feature.mastery,
      id: 'home/mastery',
      surface: _EntrySurface.bottom,
      destinationType: MasteryDashboardScreen,
    ),
    const _ProductionEntryCase(
      feature: Feature.weakness,
      id: 'home/weakness',
      surface: _EntrySurface.bottom,
      destinationType: WeaknessClinicScreen,
    ),
    const _ProductionEntryCase(
      feature: Feature.ghostDuel,
      id: 'drawer/learning/ghost-duel',
      surface: _EntrySurface.drawer,
      destinationType: GhostShadowDuelScreen,
      routeName: 'learning/ghost-duel',
    ),
    const _ProductionEntryCase(
      feature: Feature.achievements,
      id: 'home/achievements',
      surface: _EntrySurface.bottom,
      destinationType: AchievementsScreen,
    ),
    const _ProductionEntryCase(
      feature: Feature.shop,
      id: 'drawer/rewards/shop',
      surface: _EntrySurface.drawer,
      destinationType: ShopPage,
      routeName: 'rewards/shop',
    ),
    const _ProductionEntryCase(
      feature: Feature.objectScanner,
      id: 'drawer/practice/object-scanner',
      surface: _EntrySurface.drawer,
      destinationType: ObjectScannerScreen,
      routeName: 'practice/object-scanner',
    ),
    const _ProductionEntryCase(
      feature: Feature.speechPractice,
      id: 'drawer/practice/shadowing',
      surface: _EntrySurface.drawer,
      destinationType: ShadowingChallengeScreen,
      routeName: 'practice/shadowing',
    ),
    const _ProductionEntryCase(
      feature: Feature.aiTutor,
      id: 'drawer/ai-tutor/chat',
      surface: _EntrySurface.drawer,
      destinationType: AiTutorScreen,
      routeName: 'ai-tutor/chat',
    ),
    const _ProductionEntryCase(
      feature: Feature.export,
      id: 'drawer/export/center',
      surface: _EntrySurface.drawer,
      destinationType: ExportCenterScreen,
      routeName: 'export/center',
    ),
    const _ProductionEntryCase(
      feature: Feature.questV2,
      id: 'drawer/rewards/quests',
      surface: _EntrySurface.drawer,
      destinationType: QuestStatusScreen,
      routeName: 'rewards/quests',
    ),
  ];

  test('entry cases exactly cover every visible production contract row', () {
    const defaults = BuildFeatureRegistry.fieldDefaults();
    final expected = productionFeatureContract.values
        .where((delivery) => defaults.isEnabled(delivery.feature))
        .map((delivery) => (delivery.feature, delivery.productionEntryId))
        .toSet();
    final actual = productionEntries
        .map((entry) => (entry.feature, entry.id))
        .toSet();

    expect(actual, expected);
  });

  for (final entryCase in productionEntries) {
    testWidgets('${entryCase.id} reaches its exact fail-closed V2 gate', (
      tester,
    ) async {
      final delivery = productionFeatureContract[entryCase.feature]!;
      expect(delivery.productionEntryId, entryCase.id);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        MyApp(dependencies: _dependencies(features, _QuestRepositoryFake())),
      );
      await tester.pumpAndSettle();

      switch (entryCase.surface) {
        case _EntrySurface.bottom:
          final entry = find.byKey(ValueKey<String>(entryCase.id));
          expect(entry, findsOneWidget);
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (entryCase.feature == Feature.speechPractice) {
            expect(find.byType(SessionConfigurationSheet), findsOneWidget);
            final start = find.byKey(
              const ValueKey<String>('session-config-start'),
            );
            await tester.ensureVisible(start);
            await tester.pump();
            await tester.tap(start);
            for (
              var attempt = 0;
              attempt < 20 &&
                  find.byType(entryCase.destinationType).evaluate().isEmpty;
              attempt += 1
            ) {
              await tester.pump(const Duration(milliseconds: 100));
            }
            expect(find.text('This lesson mode is unavailable.'), findsNothing);
            expect(
              find.byKey(
                const ValueKey<String>('session-configuration-reset-prompt'),
              ),
              findsNothing,
            );
          }
          _expectEnabledDestination(tester, entryCase);
          features.emergencyOff(entryCase.feature);
          await tester.pump();
          _expectUnavailableGate(tester, entryCase);
        case _EntrySurface.learning:
          await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
          await tester.pump();
          final entry = find.byKey(ValueKey<String>(entryCase.id));
          await tester.scrollUntilVisible(
            entry,
            120,
            scrollable: find.descendant(
              of: find.byType(ChooseModeScreen),
              matching: find.byType(Scrollable),
            ),
            maxScrolls: 12,
          );
          expect(entry, findsOneWidget);
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          await _startConfiguredLessonIfPresent(
            tester,
            entryCase.destinationType,
          );
          _expectEnabledDestination(tester, entryCase);
          features.emergencyOff(entryCase.feature);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          _expectUnavailableGate(tester, entryCase);
        case _EntrySurface.drawer:
          await tester.tap(
            find.byKey(const ValueKey<String>('legacy-drawer-button')),
          );
          await tester.pumpAndSettle();
          final entry = find.byKey(ValueKey<String>(entryCase.id));
          await tester.scrollUntilVisible(
            entry,
            150,
            scrollable: find.descendant(
              of: find.byType(Drawer),
              matching: find.byType(Scrollable),
            ),
          );
          await tester.ensureVisible(entry);
          await tester.pumpAndSettle();
          expect(entry, findsOneWidget);
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          if (entryCase.feature == Feature.speechPractice) {
            expect(find.byType(SessionConfigurationSheet), findsOneWidget);
            final start = find.byKey(
              const ValueKey<String>('session-config-start'),
            );
            await tester.ensureVisible(start);
            await tester.tap(start);
            for (
              var attempt = 0;
              attempt < 20 &&
                  find.byType(entryCase.destinationType).evaluate().isEmpty;
              attempt += 1
            ) {
              await tester.pump(const Duration(milliseconds: 100));
            }
          }
          _expectEnabledDestination(tester, entryCase);
          if (entryCase.feature == Feature.speechPractice) {
            expect(
              tester
                  .widget<ShadowingChallengeScreen>(
                    find.byType(ShadowingChallengeScreen),
                  )
                  .ownerId,
              _OwnerRepository.owner.id,
            );
          }
          features.emergencyOff(entryCase.feature);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
          _expectUnavailableGate(tester, entryCase);
      }
    });
  }

  testWidgets(
    'hidden shadow delivery has no entry and direct use fails closed',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.fieldDefaults(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        MyApp(dependencies: _dependencies(features, _QuestRepositoryFake())),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<ProductionFeatureGate>(
              find.byType(ProductionFeatureGate, skipOffstage: false),
            )
            .where((gate) => gate.feature == Feature.shadowRewardV2),
        isEmpty,
      );

      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.shadowRewardV2,
            registry: features,
            builder: (_) {
              builds += 1;
              return const Text('shadow delivery');
            },
          ),
        ),
      );
      expect(builds, 0);
      final unavailable = tester.widget<ProductionFeatureUnavailable>(
        find.byType(ProductionFeatureUnavailable),
      );
      expect(unavailable.feature, Feature.shadowRewardV2);
      expect(unavailable.state, FeatureState.hidden);
    },
  );

  testWidgets('MyApp quest route is exact, bounded, and live fail-closed', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    final repository = _QuestRepositoryFake();

    await tester.pumpWidget(
      MyApp(dependencies: _dependencies(features, repository)),
    );
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    final entry = find.byKey(const ValueKey<String>('drawer/rewards/quests'));
    await tester.scrollUntilVisible(
      entry,
      200,
      scrollable: find.descendant(
        of: find.byType(Drawer),
        matching: find.byType(Scrollable),
      ),
    );
    await tester.tap(entry);
    await tester.pumpAndSettle();

    expect(find.byType(QuestStatusScreen), findsOneWidget);
    final route = ModalRoute.of(tester.element(find.byType(QuestStatusScreen)));
    expect(route?.settings.name, 'rewards/quests');
    expect(repository.readCalls, 1);
    expect(repository.lastLimit, 50);

    features.emergencyOff(Feature.questV2);
    await tester.pump();

    expect(find.byType(QuestStatusScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    expect(repository.readCalls, 1);
  });

  testWidgets('MyApp reading route and entry respond to a live kill switch', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );

    await tester.pumpWidget(
      MyApp(dependencies: _dependencies(features, _QuestRepositoryFake())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump();
    await tester.tap(find.text('Associative Reading'));
    await tester.pumpAndSettle();
    await _startConfiguredLessonIfPresent(
      tester,
      AssociativeReadingLauncherScreen,
    );

    expect(find.byType(AssociativeReadingLauncherScreen), findsOneWidget);
    final route = ModalRoute.of(
      tester.element(find.byType(AssociativeReadingLauncherScreen)),
    );
    expect(route?.settings.name, 'learning/associative-reading');

    features.emergencyOff(Feature.reading);
    await tester.pump();

    expect(find.byType(AssociativeReadingLauncherScreen), findsNothing);
    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);

    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text('Associative Reading'), findsNothing);
  });

  testWidgets('production Learning excludes demo-only campaign entries', (
    tester,
  ) async {
    final features = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    await tester.pumpWidget(
      MyApp(dependencies: _dependencies(features, _QuestRepositoryFake())),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(1));
    await tester.pump();

    expect(find.text('Associative Reading'), findsOneWidget);
    expect(find.text('World Map'), findsNothing);
    expect(find.text('CEFR Diagnostic'), findsNothing);
  });

  testWidgets(
    'study planning has one composed parent entry and live kill switch',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      await tester.pumpWidget(
        MyApp(dependencies: _dependencies(features, _QuestRepositoryFake())),
      );
      await tester.pumpAndSettle();

      final entry = find.byKey(const ValueKey<String>('home/study-planning'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(StudyPlanningHubScreen), findsOneWidget);

      features.emergencyOff(Feature.studyPlanning);
      await tester.pump();
      expect(find.byType(StudyPlanningHubScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    },
  );

  testWidgets(
    'f42 production Today delivery is read-only and assessment gates independently',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      await _seedF42NavigationAuthority(database);
      final before = await _f42NavigationAuthorityRows(database);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final loader = _F42TodayHubLoader(_f42TodayHubSnapshot());

      await tester.pumpWidget(
        MyApp(
          dependencies: _dependencies(
            features,
            _QuestRepositoryFake(),
            databaseOverride: database,
            todayHub: loader,
            includeAssessment: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final entry = find.byKey(const ValueKey<String>('home/today'));
      expect(entry, findsOneWidget);
      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(loader.calls, 1);
      expect(
        find.byKey(const ValueKey('today-hub-assessment-action')),
        findsOneWidget,
      );

      features.emergencyOff(Feature.researchAssessment);
      await tester.pump();
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(find.byKey(const ValueKey<String>('home/today')), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-hub-assessment-action')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('today-hub-open-review')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('today-hub-open-history')),
        findsOneWidget,
      );
      expect(await _f42NavigationAuthorityRows(database), before);
    },
  );

  testWidgets(
    'f42 final signoff Today keeps review and history live while assessment dependency fails closed',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final loader = _F42TodayHubLoader(_f42TodayHubSnapshot());

      await tester.pumpWidget(
        MyApp(
          dependencies: _dependencies(
            features,
            _QuestRepositoryFake(),
            todayHub: loader,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-hub-assessment-action')),
        findsNothing,
      );
      for (final key in <String>[
        'today-hub-open-review',
        'today-hub-open-history',
      ]) {
        final action = find.byKey(ValueKey<String>(key));
        expect(action, findsOneWidget);
        expect(tester.widget<OutlinedButton>(action).onPressed, isNotNull);
      }

      await tester.pumpWidget(
        MyApp(
          dependencies: _dependencies(
            features,
            _QuestRepositoryFake(),
            todayHub: loader,
            includeAssessment: true,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();

      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(
        find.byKey(const ValueKey('today-hub-assessment-action')),
        findsOneWidget,
      );
    },
  );

  testWidgets(
    'f42 Today child actions route through existing typed production screens',
    (tester) async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final loader = _F42TodayHubLoader(_f42TodayHubSnapshot());
      await tester.pumpWidget(
        MyApp(
          dependencies: _dependencies(
            features,
            _QuestRepositoryFake(),
            databaseOverride: database,
            todayHub: loader,
            includeAssessment: true,
          ),
        ),
      );
      await tester.pumpAndSettle();

      Future<void> openToday() async {
        await tester.tap(find.byKey(const ValueKey<String>('home/today')));
        await tester.pumpAndSettle();
        expect(find.byType(TodayHubScreen), findsOneWidget);
      }

      await openToday();
      await _tapF42Action(tester, 'today-hub-resume-action');
      expect(find.byType(ChooseModeScreen), findsOneWidget);

      await openToday();
      await _tapF42Action(tester, 'today-hub-start-recommendation');
      expect(find.byType(ChooseModeScreen), findsOneWidget);

      await openToday();
      await _tapF42Action(tester, 'today-hub-open-review');
      expect(find.byType(ReviewCenterScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapF42Action(tester, 'today-hub-open-history');
      expect(find.byType(LearningHistoryScreen), findsOneWidget);
      await tester.pageBack();
      await tester.pumpAndSettle();

      await _tapF42Action(tester, 'today-hub-assessment-action');
      expect(find.byType(PrePostAssessmentScreen), findsOneWidget);
    },
  );
}

void _expectEnabledDestination(
  WidgetTester tester,
  _ProductionEntryCase entryCase,
) {
  final destination = find.byType(entryCase.destinationType);
  expect(destination, findsOneWidget);
  if (entryCase.feature == Feature.speechPractice) {
    expect(find.byType(UnifiedLessonShell), findsOneWidget);
  }
  if (entryCase.routeName != null) {
    final route = ModalRoute.of(tester.element(destination));
    expect(route?.settings.name, entryCase.routeName);
  }
}

Future<void> _tapF42Action(WidgetTester tester, String key) async {
  final action = find.byKey(ValueKey<String>(key));
  expect(action, findsOneWidget);
  await tester.ensureVisible(action);
  await tester.pump();
  await tester.tap(action);
  await tester.pumpAndSettle();
}

Future<void> _startConfiguredLessonIfPresent(
  WidgetTester tester,
  Type destinationType,
) async {
  if (find.byType(SessionConfigurationSheet).evaluate().isNotEmpty) {
    final start = find.byKey(const ValueKey<String>('session-config-start'));
    expect(start, findsOneWidget);
    await tester.ensureVisible(start);
    await tester.pump();
    await tester.tap(start);
  }
  for (
    var attempt = 0;
    attempt < 20 && find.byType(destinationType).evaluate().isEmpty;
    attempt += 1
  ) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void _expectUnavailableGate(
  WidgetTester tester,
  _ProductionEntryCase entryCase,
) {
  expect(find.byType(entryCase.destinationType), findsNothing);
  final unavailableFinder = find.byWidgetPredicate(
    (widget) =>
        widget is ProductionFeatureUnavailable &&
        widget.feature == entryCase.feature,
  );
  expect(unavailableFinder, findsOneWidget);
  if (entryCase.routeName != null) {
    final route = ModalRoute.of(tester.element(unavailableFinder));
    expect(route?.settings.name, entryCase.routeName);
  }
}

enum _EntrySurface { bottom, learning, drawer }

final class _ProductionEntryCase {
  const _ProductionEntryCase({
    required this.feature,
    required this.id,
    required this.surface,
    required this.destinationType,
    this.routeName,
  });

  final Feature feature;
  final String id;
  final _EntrySurface surface;
  final Type destinationType;
  final String? routeName;
}

AppDependencies _dependencies(
  FeatureRegistry features,
  _QuestRepositoryFake repository, {
  AppDatabase? databaseOverride,
  TodayHubSnapshotLoader? todayHub,
  bool includeAssessment = false,
}) {
  final database = databaseOverride ?? AppDatabase(NativeDatabase.memory());
  if (databaseOverride == null) addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owners = _OwnerRepository();
  final learning = LearningUseCases(
    owners: owners,
    repository: _LearningRepositoryFake(),
    generateId: () => 'navigation-id',
    nowUtc: () => DateTime.utc(2026, 8, 11),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  final vocabulary = VocabularyUseCases(
    owners: owners,
    vocabulary: _NavigationVocabularyRepository(),
    generateId: () => 'navigation-vocabulary-id',
    nowUtc: () => DateTime.utc(2026, 8, 11),
  );
  final lessonModes = buildLessonModeRegistry();
  final progress = ProgressUseCases(
    owners: owners,
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 11),
  );
  const activeOwnerIdentities = _F42ReviewOwnerIdentities();
  final reviewCenter = ReviewCenterUseCases(
    reader: const _F42ReviewReader(),
    ownerIdentities: activeOwnerIdentities,
    sessionLauncher: _F42ReviewSessionLauncher(learning),
    nowUtc: () => DateTime.utc(2026, 8, 31, 8),
    timezoneId: 'Asia/Bangkok',
  );
  final learningHistory = LearningHistoryUseCases(
    owners: owners,
    reader: const _F42HistoryReader(),
    sessionLauncher: _F42HistorySessionLauncher(learning),
  );
  return AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _GuestSessionService(),
    database: database,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    features: features,
    localOwners: owners,
    learning: learning,
    lessonModes: lessonModes,
    sessionConfigurationProtocols:
        const _NavigationSessionConfigurationProtocols(),
    sessionConfigurations: _NavigationSessionConfigurationStore(),
    createLessonController: (adapter) =>
        UnifiedLessonController(learning: learning, adapter: adapter),
    vocabulary: vocabulary,
    associativeLearning: InMemoryAssociativeLearningAdapter(),
    currentActivityEvidence: CurrentActivityEvidenceAdapter(learning: learning),
    assessment: includeAssessment
        ? _buildF42InjectedAssessment(database)
        : null,
    todayHub: todayHub,
    activeOwnerIdentities: activeOwnerIdentities,
    reviewCenter: reviewCenter,
    learningHistory: learningHistory,
    progress: progress,
    studyPlanning: StudyPlanningUseCases(
      packs: _NavigationLearningPackRepository(),
      progress: progress,
    ),
    rewards: RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
      progress: progress,
      generateId: () => 'navigation-reward-id',
      nowUtc: () => DateTime.utc(2026, 8, 11),
    ),
    objectScanner: _NavigationObjectScannerController(),
    speechPractice: SpeechPracticeUseCases(_NavigationSpeechGateway()),
    aiTutor: _NavigationAiTutorController(),
    exports: ExportUseCases(
      reader: DriftExportReader(database),
      store: _NavigationExportStore(),
      nowUtc: () => DateTime.utc(2026, 8, 11),
      loadThaiFont: () async => ByteData(0),
    ),
    quest: QuestUseCases(
      repository: repository,
      owners: owners,
      generateId: () => 'unused',
      nowUtc: () => DateTime.utc(2026, 8, 11),
      timezoneId: 'Asia/Bangkok',
    ),
  );
}

const _f42Checksum =
    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';
final _f42Now = DateTime.utc(2026, 8, 31, 8);

TodayHubSnapshot _f42TodayHubSnapshot() => TodayHubSnapshot(
  ownerId: _OwnerRepository.owner.id,
  evaluatedAtUtc: _f42Now,
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: LearningSessionSummary(
    id: 'session:f42-resume',
    ownerId: _OwnerRepository.owner.id,
    activityType: 'meaningQuiz',
    state: 'active',
    startedAtUtc: _f42Now.subtract(const Duration(minutes: 10)),
    correctCount: 1,
    wrongCount: 1,
    score: 50,
  ),
  assignedAssessment: TodayHubAssignedAssessment(
    run: AssessmentRun(
      id: 'assessment:f42',
      ownerId: _OwnerRepository.owner.id,
      learningSessionId: 'session:f42-assessment',
      studyCycleId: 'cycle:f42',
      phase: AssessmentPhase.pre,
      state: AssessmentRunState.active,
      protocolId: 'protocol:f42',
      protocolVersion: '1.0.0',
      experimentId: 'experiment:f42',
      experimentVersion: 1,
      assignmentId: 'assignment:f42',
      cohort: 'enforced',
      consentVersion: 1,
      consentDecidedAtUtc: _f42Now.subtract(const Duration(days: 2)),
      instrumentId: 'instrument:f42',
      instrumentVersion: '1.0.0',
      formId: 'form:f42-pre',
      formVersion: '1.0.0',
      instrumentChecksumSha256: _f42Checksum,
      formChecksumSha256: _f42Checksum,
      appVersion: '1.0.0',
      buildId: 'f42-navigation',
      databaseSchemaVersion: AppDatabase.currentSchemaVersion,
      contentRevision: 'content-f42-r1',
      evidencePolicyVersion: 'evidence-v2',
      featureContractRevision: '1.0.0',
      featureContractHash: _f42Checksum,
      startedAtUtc: _f42Now.subtract(const Duration(hours: 1)),
      completedAtUtc: null,
      abandonedAtUtc: null,
    ),
  ),
  reviewWork: const <TodayHubReviewWorkItem>[],
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.recommended(
      ownerId: _OwnerRepository.owner.id,
      mode: LessonMode.typedRecall,
      reason: RecommendationPanelReason.weakEvidence,
      freshness: RecommendationEvidenceFreshness.current,
      protocolConstraint: RecommendationProtocolConstraint.open,
      alternatives: const <LessonMode>[LessonMode.meaningQuiz],
    ),
    isAuthoritative: true,
    mergedInto: null,
  ),
  goals: const [],
  reminders: const [],
  quests: const [],
  gentleStreak: null,
  dependencyStates: <TodayHubDependency, TodayHubDependencyState>{
    for (final dependency in TodayHubDependency.values)
      dependency: TodayHubDependencyState.ready,
  },
);

final class _F42TodayHubLoader implements TodayHubSnapshotLoader {
  _F42TodayHubLoader(this.snapshot);

  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _F42ReviewReader implements ReviewCenterReader {
  const _F42ReviewReader();

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async =>
      const <ReviewQueueItem>[];
}

final class _F42ReviewOwnerIdentities implements ReviewOwnerIdentityReader {
  const _F42ReviewOwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() async =>
      _OwnerRepository.owner.id;
}

final class _F42ReviewSessionLauncher implements ReviewSessionLauncher {
  const _F42ReviewSessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) => Future<PinnedReviewSessionLaunch>.error(
    StateError('The empty f42 review fixture cannot launch a session.'),
  );

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}

final class _F42HistoryReader implements LearningHistoryReader {
  const _F42HistoryReader();

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async =>
      const <LearningHistoryEntry>[];

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) => Future<LessonStartCommand>.error(
    StateError('The empty f42 history fixture cannot replay a session.'),
  );
}

final class _F42HistorySessionLauncher
    implements LearningHistorySessionLauncher {
  const _F42HistorySessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<void> start(LessonStartCommand command) => Future<void>.error(
    StateError('The empty f42 history fixture cannot launch a session.'),
  );
}

AssessmentUseCases _buildF42InjectedAssessment(AppDatabase database) {
  final owners = DriftLocalOwnerRepository(
    database,
    generateId: () => 'f42-assessment-owner',
    nowUtc: () => _f42Now,
  );
  final learning = LearningUseCases(
    owners: owners,
    repository: DriftLearningRepository(database),
    generateId: () => 'f42-assessment-evidence',
    nowUtc: () => _f42Now,
    buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'f42-navigation'),
  );
  return AssessmentUseCases(
    owners: owners,
    repository: DriftAssessmentRepository(database),
    learning: learning,
    experimentRegistry: const NoOpExperimentRegistry(),
    consentRegistry: const NoOpConsentRegistry(),
    rolloutModeProvider: const FixedEvidencePolicyRolloutModeProvider.legacy(),
    protocolModeCatalog: const ResearchProtocolModeCatalog(
      mappings: <ResearchProtocolModeMapping>[],
    ),
    instrumentCatalog: AssessmentInstrumentCatalog(entries: const []),
    buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'f42-navigation'),
    databaseSchemaVersion: AppDatabase.currentSchemaVersion,
    nowUtc: () => _f42Now,
  );
}

Future<void> _seedF42NavigationAuthority(AppDatabase database) async {
  final assignmentId =
      DriftExperimentAssignmentRepository.canonicalAssignmentId(
        ownerId: _OwnerRepository.owner.id,
        experimentId: 'experiment:f42-source',
        experimentVersion: 1,
      );
  await database.customInsert(
    'INSERT INTO local_owners '
    '(id, account_state, created_at_utc_ms, is_active) VALUES (?, ?, ?, 1)',
    variables: [
      Variable<String>(_OwnerRepository.owner.id),
      const Variable<String>('localGuest'),
      const Variable<int>(1),
    ],
  );
  await database.customInsert(
    'INSERT INTO experiment_assignments '
    '(id, owner_id, experiment_id, experiment_version, cohort, '
    'protocol_version, assigned_at_utc_ms) VALUES (?, ?, ?, 1, ?, ?, ?)',
    variables: [
      Variable<String>(assignmentId),
      Variable<String>(_OwnerRepository.owner.id),
      const Variable<String>('experiment:f42-source'),
      const Variable<String>('control'),
      const Variable<String>('protocol-1'),
      Variable<int>(
        _f42Now.subtract(const Duration(days: 1)).millisecondsSinceEpoch,
      ),
    ],
  );
  await database.customInsert(
    'INSERT INTO learning_sessions '
    '(id, owner_id, activity_type, state, started_at_utc_ms, app_version, '
    'build_id) VALUES (?, ?, ?, ?, ?, ?, ?)',
    variables: [
      const Variable<String>('session:f42-source'),
      Variable<String>(_OwnerRepository.owner.id),
      const Variable<String>('meaningQuiz'),
      const Variable<String>('active'),
      Variable<int>(
        _f42Now.subtract(const Duration(minutes: 5)).millisecondsSinceEpoch,
      ),
      const Variable<String>('1.0.0'),
      const Variable<String>('f42-navigation'),
    ],
  );
}

Future<Map<String, List<Map<String, Object?>>>> _f42NavigationAuthorityRows(
  AppDatabase database,
) async {
  const tables = <String>[
    'experiment_assignments',
    'learning_sessions',
    'answer_attempts',
    'events_v2',
    'assessment_runs',
    'outbox_operations',
  ];
  return <String, List<Map<String, Object?>>>{
    for (final table in tables)
      table: await database
          .customSelect('SELECT * FROM $table ORDER BY rowid')
          .map((row) => Map<String, Object?>.unmodifiable(row.data))
          .get(),
  };
}

final class _NavigationObjectScannerController
    implements ObjectScannerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationLearningPackRepository
    implements LearningPackRepository {
  @override
  Future<Never> getVersion(String packId, int revision) => Future<Never>.error(
    StateError('Navigation test repository has no pack-detail content.'),
  );

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      const [];
}

final class _NavigationVocabularyRepository implements VocabularyRepository {
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) {
    return Stream.value(const []);
  }

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) {
    return Stream.value(const []);
  }

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationSpeechGateway implements SpeechRecognitionGateway {
  @override
  bool get isListening => false;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationAiTutorController implements AiTutorController {
  @override
  Future<AiTutorSettingsStatus> loadSettings() async {
    return const AiTutorSettingsStatus(
      hasKey: false,
      providerConsent: false,
      shareLearningSummary: false,
      providerId: AiProviderId.gemini,
      model: null,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationExportStore implements ExportArtifactStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _LearningRepositoryFake
    implements LearningRepository, SessionConfiguredLearningRepository {
  LearningSessionSummary? _session;

  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async => const <QuizWord>[
    QuizWord(
      id: 'navigation-word',
      categoryId: 'navigation-category',
      spelling: 'hello',
      meaning: 'สวัสดี',
      partOfSpeech: 'interjection',
    ),
  ];

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async => const [];

  @override
  Future<void> startSession(LearningSessionDraft session) async {
    _session = LearningSessionSummary(
      id: session.id,
      ownerId: session.ownerId,
      activityType: session.activityType,
      state: 'active',
      startedAtUtc: session.startedAtUtc!,
      correctCount: 0,
      wrongCount: 0,
      score: 0,
      appVersion: session.appVersion,
      buildId: session.buildId,
      sessionConfiguration: session.sessionConfiguration,
    );
  }

  @override
  Future<LearningSessionSummary?> loadSessionConfigurationState({
    required String ownerId,
    required String sessionId,
  }) async {
    final session = _session;
    return session?.ownerId == ownerId && session?.id == sessionId
        ? session
        : null;
  }

  @override
  Future<Duration> addSessionConfigurationActiveEffort({
    required String ownerId,
    required String sessionId,
    required String configurationIdentity,
    required Duration delta,
  }) async {
    final session = _session;
    if (session == null ||
        session.ownerId != ownerId ||
        session.id != sessionId ||
        session.sessionConfiguration?.contentIdentity !=
            configurationIdentity) {
      throw StateError('navigation session binding is unavailable');
    }
    final total = session.configurationActiveEffort + delta;
    _session = LearningSessionSummary(
      id: session.id,
      ownerId: session.ownerId,
      activityType: session.activityType,
      state: session.state,
      startedAtUtc: session.startedAtUtc,
      endedAtUtc: session.endedAtUtc,
      correctCount: session.correctCount,
      wrongCount: session.wrongCount,
      score: session.score,
      appVersion: session.appVersion,
      buildId: session.buildId,
      sessionConfiguration: session.sessionConfiguration,
      configurationActiveEffort: total,
    );
    return total;
  }

  @override
  Future<AnswerRecordResult> recordAnswer(RecordAnswerCommand command) =>
      throw UnimplementedError();

  @override
  Future<LearningSessionSummary> finishSession({
    required String ownerId,
    required String sessionId,
    required DateTime endedAtUtc,
  }) => throw UnimplementedError();

  @override
  Future<LearningSessionSummary?> getActiveSession({
    required String ownerId,
  }) async => null;

  @override
  Future<void> abandonActiveSessions({required String ownerId}) async {}

  @override
  Future<List<LearningSessionSummary>> listSessionHistory({
    required String ownerId,
    required int limit,
  }) async => const [];

  @override
  Future<ReadingProgressSnapshot?> readReadingProgress({
    required String ownerId,
    required String documentId,
    required int documentRevision,
  }) async => null;

  @override
  Future<ReadingProgressSnapshot> saveReadingProgress(
    ReadingProgressCommand command,
  ) => throw UnimplementedError();
}

final class _NavigationSessionConfigurationProtocols
    implements SessionConfigurationProtocolProvider {
  const _NavigationSessionConfigurationProtocols();

  @override
  Future<SessionConfigurationProtocolLimits> resolveForOwner(
    String ownerId,
  ) async => const SessionConfigurationProtocolLimits.standard();
}

final class _NavigationSessionConfigurationStore
    implements SessionConfigurationStore {
  SessionConfiguration? _configuration;

  @override
  Future<SessionConfiguration?> read({
    required String ownerId,
    required LessonMode mode,
  }) async {
    final configuration = _configuration;
    return configuration?.ownerId == ownerId && configuration?.mode == mode
        ? configuration
        : null;
  }

  @override
  Future<void> save(
    SessionConfiguration configuration, {
    required DateTime updatedAtUtc,
  }) async {
    _configuration = configuration;
  }

  @override
  Future<void> clear({
    required String ownerId,
    required LessonMode mode,
  }) async {
    if (_configuration?.ownerId == ownerId && _configuration?.mode == mode) {
      _configuration = null;
    }
  }
}

final class _GuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionStarted(uid: 'production-navigation-owner');
  }
}

final class _OwnerRepository implements LocalOwnerRepository {
  static final owner = LocalOwner(
    id: 'local:production-navigation-owner',
    createdAtUtc: DateTime.utc(2026, 8, 1),
  );

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => owner;

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) async {
    return owner;
  }
}

final class _QuestRepositoryFake implements QuestRepository {
  int readCalls = 0;
  int? lastLimit;

  @override
  Future<List<QuestInstance>> getAllInstances(
    String ownerId, {
    int limit = 50,
  }) async {
    readCalls += 1;
    lastLimit = limit;
    return const [];
  }

  @override
  Future<List<QuestInstance>> getActiveInstances(String ownerId) async =>
      const [];

  @override
  Future<List<QuestInstance>> getCompletedInstancesForSourceEvent({
    required String ownerId,
    required String sourceEventId,
    required Iterable<String> questIds,
    int limit = 64,
  }) async => const [];

  @override
  Future<QuestDefinition?> getDefinition(String questId) async => null;

  @override
  Future<void> markAbandoned(String instanceId) async {}

  @override
  Future<void> markCompleted(
    String instanceId,
    DateTime completedAtUtc,
  ) async {}

  @override
  Future<void> markExpired(String instanceId, DateTime expiredAtUtc) async {}

  @override
  Future<void> saveProgress(
    String instanceId,
    List<ObjectiveProgress> progress,
  ) async {}

  @override
  Future<void> startInstance(QuestInstance instance) async {}

  @override
  Future<void> upsertDefinition(QuestDefinition def) async {}
}
