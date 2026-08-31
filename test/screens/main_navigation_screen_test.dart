import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/history/application/learning_history_use_cases.dart';
import 'package:vocab_learning_app/features/history/domain/learning_history_models.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/lesson_mode_registry.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/lesson_session_state.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/content_manifest.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
import 'package:vocab_learning_app/features/recommendation/application/recommendation_use_cases.dart';
import 'package:vocab_learning_app/features/review/application/review_center_use_cases.dart';
import 'package:vocab_learning_app/features/review/domain/review_queue_item.dart';
import 'package:vocab_learning_app/features/today_hub/application/today_hub_use_cases.dart';
import 'package:vocab_learning_app/features/today_hub/domain/today_hub_models.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_category.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/today_hub_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
  testWidgets(
    'f42 Today delivery fails closed for default-off or missing dependency',
    (tester) async {
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.fieldDefaults(),
          todayHub: loader,
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
      expect(loader.calls, 0);

      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
    },
  );

  testWidgets(
    'f42 live Today delivery opens the real Hub and emergency-off removes it',
    (tester) async {
      final features = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      addTearDown(features.dispose);
      final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());
      await tester.pumpWidget(_mainNavigationApp(features, todayHub: loader));
      await tester.pumpAndSettle();

      final entry = find.byKey(const ValueKey<String>('home/today'));
      expect(entry, findsOneWidget);
      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((destination) => destination.label),
        contains('วันนี้'),
      );

      await tester.tap(entry);
      await tester.pumpAndSettle();
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(loader.calls, 1);

      features.emergencyOff(Feature.dailyContinuity);
      await tester.pump();
      expect(find.byKey(const ValueKey<String>('home/today')), findsNothing);
      expect(find.byType(TodayHubScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(loader.calls, 1);
    },
  );

  testWidgets(
    'f42 signoff Today delivery requires its Hub review and history authorities',
    (tester) async {
      for (final missing in <String>['review', 'history']) {
        AppDependencies? composed;
        final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: loader,
            includeReviewCenter: missing != 'review',
            includeLearningHistory: missing != 'history',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          composed!.hasComposedDependencyFor(Feature.dailyContinuity),
          isFalse,
          reason: 'missing $missing authority must fail closed',
        );
        expect(
          find.byKey(const ValueKey<String>('home/today')),
          findsNothing,
          reason: 'missing $missing authority must hide Today delivery',
        );
        expect(loader.calls, 0);
      }
    },
  );

  testWidgets(
    'f42 signoff Today owner validation never invokes the creating owner API',
    (tester) async {
      final owner = _NavigationOwner(ownerId: 'owner:different');
      final loader = _NavigationTodayHubLoader(
        _emptyTodayHubSnapshot(
          resumableSession: LearningSessionSummary(
            id: 'session:today-owner-check',
            ownerId: 'owner:main-navigation',
            activityType: 'meaningQuiz',
            state: 'active',
            startedAtUtc: DateTime.utc(2026, 8, 31, 7, 55),
            correctCount: 0,
            wrongCount: 0,
            score: 0,
          ),
        ),
      );

      await tester.pumpWidget(
        _mainNavigationApp(
          const BuildFeatureRegistry.allEnabled(),
          todayHub: loader,
          localOwners: owner,
          activeOwnerIdentities: const _UnavailableNavigationOwnerIdentities(),
        ),
      );
      await tester.pumpAndSettle();
      final callsBeforeTodayAction = owner.getOrCreateCalls;

      await tester.tap(find.byKey(const ValueKey<String>('home/today')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('today-hub-resume-action')));
      await tester.pumpAndSettle();

      expect(
        owner.getOrCreateCalls,
        callsBeforeTodayAction,
        reason: 'a read-only owner check must not create an owner',
      );
      expect(find.byType(TodayHubScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
    },
  );

  testWidgets(
    'f42 final signoff Today delivery requires every learning launch authority and identity',
    (tester) async {
      for (final missing in <String>[
        'learning',
        'lessonModes',
        'createLessonController',
        'reviewSessionAuthority',
        'historySessionAuthority',
      ]) {
        AppDependencies? composed;
        final loader = _NavigationTodayHubLoader(_emptyTodayHubSnapshot());

        await tester.pumpWidget(
          _mainNavigationApp(
            const BuildFeatureRegistry.allEnabled(),
            todayHub: loader,
            includeLearning: missing != 'learning',
            includeLessonModes: missing != 'lessonModes',
            includeCreateLessonController: missing != 'createLessonController',
            mismatchReviewSessionAuthority: missing == 'reviewSessionAuthority',
            mismatchHistorySessionAuthority:
                missing == 'historySessionAuthority',
            onDependencies: (value) => composed = value,
          ),
        );
        await tester.pumpAndSettle();

        expect(
          composed!.hasComposedDependencyFor(Feature.dailyContinuity),
          isFalse,
          reason: '$missing must fail closed',
        );
        expect(
          find.byKey(const ValueKey<String>('home/today')),
          findsNothing,
          reason: '$missing must hide Today delivery',
        );
        expect(loader.calls, 0);
      }
    },
  );

  testWidgets(
    'all-enabled composition renders seven destinations and switches tabs',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((destination) => destination.label),
        <String>[
          'คลังคำศัพท์',
          'เรียนรู้',
          'แผนการเรียน',
          'สถิติ',
          'จุดอ่อน',
          'รางวัล',
          'โปรไฟล์',
        ],
      );

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('ภาพรวมการเรียน'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(5));
      await tester.pumpAndSettle();
      expect(find.text('ความสำเร็จ'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(6));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('field composition exposes completed field destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
    );
    await tester.pumpAndSettle();

    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      <String>[
        'คลังคำศัพท์',
        'เรียนรู้',
        'สถิติ',
        'จุดอ่อน',
        'รางวัล',
        'โปรไฟล์',
      ],
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ร้านค้า'), findsOneWidget);
    expect(find.text('สแกนวัตถุ'), findsOneWidget);
    expect(find.text('ฝึกพูดตามเสียง'), findsOneWidget);
    expect(find.text('AI Tutor'), findsOneWidget);
  });

  testWidgets(
    'study-planning has one canonical entry and fails closed when unavailable',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
      );
      await tester.pumpAndSettle();

      expect(
        find.byKey(const ValueKey<String>('home/study-planning')),
        findsNothing,
      );

      var builds = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: ProductionFeatureGate(
            feature: Feature.studyPlanning,
            registry: registry,
            builder: (_) {
              builds += 1;
              return const Text('study-planning must not build');
            },
          ),
        ),
      );
      expect(builds, 0);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);

      registry.emergencyOff(Feature.studyPlanning);
      await tester.pump();
      expect(
        find.byKey(const ValueKey<String>('home/study-planning')),
        findsNothing,
      );
    },
  );

  testWidgets('only the selected indexed destination keeps tickers active', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(const BuildFeatureRegistry.allEnabled()),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('home/mastery')));
    await tester.pump();

    final masteryContext = tester.element(find.byType(MasteryDashboardScreen));
    expect(TickerMode.valuesOf(masteryContext).enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('home/vocabulary')));
    await tester.pump();
    expect(TickerMode.valuesOf(masteryContext).enabled, isFalse);
  });

  testWidgets('live emergency-off rebuilds mounted navigation', (
    WidgetTester tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(_mainNavigationApp(registry));
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(7));

    registry.emergencyOff(Feature.weakness);
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(6));
  });

  testWidgets(
    'removing an earlier entry preserves the selected feature and State',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      final selectedState = tester.state(find.byType(WeaknessClinicScreen));

      registry.emergencyOff(Feature.vocabulary);
      await tester.pump();

      expect(find.byType(WeaknessClinicScreen), findsOneWidget);
      expect(
        tester.state(find.byType(WeaknessClinicScreen)),
        same(selectedState),
      );
    },
  );

  testWidgets(
    'disabling the selected entry removes its destination but gates its view',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);

      registry.emergencyOff(Feature.weakness);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(6));
      expect(find.byType(WeaknessClinicScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    },
  );

  testWidgets(
    'disabling every selected Learning capability shows unavailable only',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(_mainNavigationApp(registry));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.byType(ChooseModeScreen), findsOneWidget);

      registry.emergencyOff(Feature.quiz);
      registry.emergencyOff(Feature.srs);
      registry.emergencyOff(Feature.reading);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(6));
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
      expect(find.text('Associative Reading'), findsNothing);
      expect(find.text('Word Scramble'), findsNothing);
    },
  );

  testWidgets(
    'missing or all-hidden registries keep a one-entry Profile shell',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationScreen(
            featureRegistry: BuildFeatureRegistry(<Feature, FeatureState>{}),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
    },
  );

  testWidgets('one-entry fallback can leave a retained unavailable view', (
    tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(_mainNavigationApp(registry));
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(4));
    await tester.pumpAndSettle();
    for (final feature in <Feature>[
      Feature.vocabulary,
      Feature.quiz,
      Feature.srs,
      Feature.reading,
      Feature.mastery,
      Feature.weakness,
      Feature.achievements,
      Feature.studyPlanning,
    ]) {
      registry.emergencyOff(feature);
    }
    await tester.pump();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    final profileFallback = find.byKey(
      const ValueKey<String>('profile-fallback-destination'),
    );
    expect(profileFallback, findsOneWidget);

    await tester.tap(profileFallback);
    await tester.pump();
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.byType(ProductionFeatureUnavailable), findsNothing);
  });

  testWidgets('AI settings drawer route uses provider-neutral screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      _mainNavigationApp(const BuildFeatureRegistry.fieldDefaults()),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.key_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AiTutorSettingsScreen), findsOneWidget);
  });
}

Widget _mainNavigationApp(
  FeatureRegistry registry, {
  TodayHubSnapshotLoader? todayHub,
  LocalOwnerRepository? localOwners,
  ReviewOwnerIdentityReader? activeOwnerIdentities,
  bool includeReviewCenter = true,
  bool includeLearningHistory = true,
  bool includeLearning = true,
  bool includeLessonModes = true,
  bool includeCreateLessonController = true,
  bool mismatchReviewSessionAuthority = false,
  bool mismatchHistorySessionAuthority = false,
  ValueSetter<AppDependencies>? onDependencies,
}) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owner = localOwners ?? _NavigationOwner();
  final ownerIdentities =
      activeOwnerIdentities ?? const _NavigationReviewOwnerIdentities();
  final progress = ProgressUseCases(
    owners: owner,
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
  );
  final learning = LearningUseCases(
    owners: owner,
    repository: _NavigationLearningRepository(),
    generateId: () => 'navigation-learning',
    nowUtc: () => DateTime.utc(2026, 8, 24),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  final otherLearning = LearningUseCases(
    owners: owner,
    repository: _NavigationLearningRepository(),
    generateId: () => 'navigation-other-learning',
    nowUtc: () => DateTime.utc(2026, 8, 24),
    buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
  );
  final dependencies = AppDependencies(
    initialRoute: AppRoute.home,
    runtimeStatus: const AppRuntimeStatus(
      localData: RuntimeAvailability.ready,
      firebase: RuntimeAvailability.ready,
      supabase: RuntimeAvailability.ready,
      backends: RuntimeAvailability.ready,
    ),
    config: null,
    guestSessionService: _NavigationGuestSession(),
    quest: testQuestUseCases(),
    features: registry,
    experiments: research.experiments,
    consents: research.consents,
    experimentAssignments: research.experimentAssignments,
    assignedLearningEventContext: research.assignedLearningEventContext,
    evidencePolicyRolloutModeProvider:
        research.evidencePolicyRolloutModeProvider,
    vocabulary: VocabularyUseCases(
      owners: owner,
      vocabulary: _NavigationVocabularyRepository(),
      generateId: () => 'navigation-vocabulary',
      nowUtc: () => DateTime.utc(2026, 8, 24),
    ),
    localOwners: owner,
    learning: includeLearning ? learning : null,
    lessonModes: includeLessonModes ? buildLessonModeRegistry() : null,
    createLessonController: includeCreateLessonController
        ? (adapter) =>
              UnifiedLessonController(learning: learning, adapter: adapter)
        : null,
    progress: progress,
    todayHub: todayHub,
    activeOwnerIdentities: ownerIdentities,
    reviewCenter: includeReviewCenter
        ? ReviewCenterUseCases(
            reader: const _NavigationReviewReader(),
            ownerIdentities: ownerIdentities,
            sessionLauncher: _NavigationReviewSessionLauncher(
              mismatchReviewSessionAuthority ? otherLearning : learning,
            ),
            nowUtc: () => DateTime.utc(2026, 8, 24),
            timezoneId: 'Asia/Bangkok',
          )
        : null,
    learningHistory: includeLearningHistory
        ? LearningHistoryUseCases(
            owners: owner,
            reader: const _NavigationHistoryReader(),
            sessionLauncher: _NavigationHistorySessionLauncher(
              mismatchHistorySessionAuthority ? otherLearning : learning,
            ),
          )
        : null,
    studyPlanning: StudyPlanningUseCases(
      packs: _NavigationLearningPacks(),
      progress: progress,
    ),
    aiTutor: _NavigationAiTutor(),
  );
  onDependencies?.call(dependencies);
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
  );
}

TodayHubSnapshot _emptyTodayHubSnapshot({
  LearningSessionSummary? resumableSession,
}) => TodayHubSnapshot(
  ownerId: 'owner:main-navigation',
  evaluatedAtUtc: DateTime.utc(2026, 8, 31, 8),
  sectionOrder: TodayHubSectionKind.values,
  resumableSession: resumableSession,
  assignedAssessment: null,
  reviewWork: const <TodayHubReviewWorkItem>[],
  recommendation: TodayHubRecommendation(
    result: RecommendationPanelResult.unavailable(
      ownerId: 'owner:main-navigation',
      reason: RecommendationPanelReason.noEligibleActivity,
      freshness: RecommendationEvidenceFreshness.missing,
      protocolConstraint: RecommendationProtocolConstraint.open,
    ),
    isAuthoritative: false,
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

final class _NavigationTodayHubLoader implements TodayHubSnapshotLoader {
  _NavigationTodayHubLoader(this.snapshot);

  final TodayHubSnapshot snapshot;
  int calls = 0;

  @override
  Future<TodayHubSnapshot> load() async {
    calls += 1;
    return snapshot;
  }
}

final class _NavigationReviewReader implements ReviewCenterReader {
  const _NavigationReviewReader();

  @override
  Future<List<ReviewQueueItem>> compose(ReviewQueueFilter filter) async =>
      const <ReviewQueueItem>[];
}

final class _NavigationReviewOwnerIdentities
    implements ReviewOwnerIdentityReader {
  const _NavigationReviewOwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() async => 'owner:main-navigation';
}

final class _UnavailableNavigationOwnerIdentities
    implements ReviewOwnerIdentityReader {
  const _UnavailableNavigationOwnerIdentities();

  @override
  Future<String> requireSingleActiveOwnerId() =>
      Future<String>.error(StateError('no active owner'));
}

final class _NavigationReviewSessionLauncher implements ReviewSessionLauncher {
  const _NavigationReviewSessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<PinnedReviewSessionLaunch> start({
    required String ownerId,
    required List<ReviewedLexicalContentSnapshot> items,
  }) => Future<PinnedReviewSessionLaunch>.error(
    StateError('The navigation fixture has no review work.'),
  );

  @override
  Future<void> abandon({
    required String ownerId,
    required String sessionId,
    required DateTime abandonedAtUtc,
  }) async {}
}

final class _NavigationHistoryReader implements LearningHistoryReader {
  const _NavigationHistoryReader();

  @override
  Future<List<LearningHistoryEntry>> list(HistoryFilter filter) async =>
      const <LearningHistoryEntry>[];

  @override
  Future<LessonStartCommand> replayAsNewSession(
    String sourceSessionId, {
    required String replayOperationId,
  }) => Future<LessonStartCommand>.error(
    StateError('The navigation fixture has no history work.'),
  );
}

final class _NavigationHistorySessionLauncher
    implements LearningHistorySessionLauncher {
  const _NavigationHistorySessionLauncher(this.learning);

  final LearningUseCases learning;

  @override
  Object get authorityIdentity => learning;

  @override
  Future<void> start(LessonStartCommand command) => Future<void>.error(
    StateError('The navigation fixture cannot start history work.'),
  );
}

final class _NavigationOwner implements LocalOwnerRepository {
  _NavigationOwner({this.ownerId = 'owner:main-navigation'});

  final String ownerId;
  int getOrCreateCalls = 0;

  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async {
    getOrCreateCalls += 1;
    return identity.LocalOwner(
      id: ownerId,
      createdAtUtc: DateTime.utc(2026, 8, 24),
    );
  }

  @override
  Future<identity.LocalOwner> bindFirebaseUid(
    String ownerId,
    String firebaseUid,
  ) => getOrCreateActiveOwner();
}

final class _NavigationGuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'main-navigation');
}

final class _NavigationVocabularyRepository implements VocabularyRepository {
  @override
  Stream<List<VocabularyCategory>> watchCategories(String ownerId) =>
      Stream.value(const []);

  @override
  Stream<List<VocabularyWord>> watchWords(String ownerId, String categoryId) =>
      Stream.value(const []);

  @override
  Future<List<VocabularyWord>> listAllWords(String ownerId) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationLearningRepository implements LearningRepository {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _NavigationLearningPacks implements LearningPackRepository {
  @override
  Future<Never> getVersion(String packId, int revision) => Future<Never>.error(
    StateError('Navigation test repository has no pack-detail content.'),
  );

  @override
  Future<List<LearningPackSummary>> list(LearningPackFilter filter) async =>
      const [];
}

final class _NavigationAiTutor implements AiTutorController {
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
  Future<List<AiUsageSummary>> loadUsage() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
