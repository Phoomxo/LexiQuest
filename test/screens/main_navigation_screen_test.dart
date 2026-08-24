import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide VocabularyCategory, VocabularyWord;
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart'
    as identity;
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
import 'package:vocab_learning_app/features/learning_packs/application/learning_pack_use_cases.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack.dart';
import 'package:vocab_learning_app/features/learning_packs/domain/learning_pack_repository.dart';
import 'package:vocab_learning_app/features/progress/application/progress_use_cases.dart';
import 'package:vocab_learning_app/features/progress/data/drift_progress_queries.dart';
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
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

import '../support/inert_research_dependencies.dart';
import '../support/test_quest_use_cases.dart';

void main() {
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

Widget _mainNavigationApp(FeatureRegistry registry) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  final research = InertResearchDependencies(database);
  final owner = _NavigationOwner();
  final progress = ProgressUseCases(
    owners: owner,
    queries: DriftProgressQueries(database),
    nowUtc: () => DateTime.utc(2026, 8, 24),
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
    learning: LearningUseCases(
      owners: owner,
      repository: _NavigationLearningRepository(),
      generateId: () => 'navigation-learning',
      nowUtc: () => DateTime.utc(2026, 8, 24),
      buildInfo: const AppBuildInfo(version: 'test', buildId: 'test'),
    ),
    progress: progress,
    studyPlanning: StudyPlanningUseCases(
      packs: _NavigationLearningPacks(),
      progress: progress,
    ),
    aiTutor: _NavigationAiTutor(),
  );
  return AppDependenciesScope(
    dependencies: dependencies,
    child: MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
  );
}

final class _NavigationOwner implements LocalOwnerRepository {
  @override
  Future<identity.LocalOwner> getOrCreateActiveOwner() async =>
      identity.LocalOwner(
        id: 'owner:main-navigation',
        createdAtUtc: DateTime.utc(2026, 8, 24),
      );

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
