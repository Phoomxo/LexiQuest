import 'dart:typed_data';

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
import 'package:vocab_learning_app/features/export/application/export_use_cases.dart';
import 'package:vocab_learning_app/features/export/data/drift_export_reader.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/learning/application/current_activity_evidence.dart';
import 'package:vocab_learning_app/features/learning/application/legacy_lesson_mode_adapters.dart';
import 'package:vocab_learning_app/features/learning/application/learning_layer_adapter.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/application/unified_lesson_controller.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_repository.dart';
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
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_screen.dart';
import 'package:vocab_learning_app/screens/associative_reading_launcher_screen.dart';
import 'package:vocab_learning_app/screens/categories_page.dart';
import 'package:vocab_learning_app/screens/export_center_screen.dart';
import 'package:vocab_learning_app/screens/ghost_shadow_duel_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/object_scanner_screen.dart';
import 'package:vocab_learning_app/screens/quest_status_screen.dart';
import 'package:vocab_learning_app/screens/quiz_screen.dart';
import 'package:vocab_learning_app/screens/shadowing_challenge_screen.dart';
import 'package:vocab_learning_app/screens/shop_page.dart';
import 'package:vocab_learning_app/screens/srs_flashcards_screen.dart';
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
          _expectEnabledDestination(tester, entryCase);
          features.emergencyOff(entryCase.feature);
          await tester.pump();
          _expectUnavailableGate(tester, entryCase);
        case _EntrySurface.learning:
          await tester.tap(find.byKey(const ValueKey<String>('home/learn')));
          await tester.pump();
          final entry = find.byKey(ValueKey<String>(entryCase.id));
          expect(entry, findsOneWidget);
          await tester.ensureVisible(entry);
          await tester.tap(entry);
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 500));
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
          _expectEnabledDestination(tester, entryCase);
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
}

void _expectEnabledDestination(
  WidgetTester tester,
  _ProductionEntryCase entryCase,
) {
  final destination = find.byType(entryCase.destinationType);
  expect(destination, findsOneWidget);
  if (entryCase.routeName != null) {
    final route = ModalRoute.of(tester.element(destination));
    expect(route?.settings.name, entryCase.routeName);
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
  _QuestRepositoryFake repository,
) {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
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
  final lessonModes = buildLegacyLessonModeRegistry();
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
    createLessonController: (adapter) =>
        UnifiedLessonController(learning: learning, adapter: adapter),
    vocabulary: vocabulary,
    associativeLearning: InMemoryAssociativeLearningAdapter(),
    currentActivityEvidence: CurrentActivityEvidenceAdapter(learning: learning),
    progress: ProgressUseCases(
      owners: owners,
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.utc(2026, 8, 11),
    ),
    rewards: RewardUseCases(
      owners: owners,
      repository: DriftRewardRepository(database),
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

final class _NavigationObjectScannerController
    implements ObjectScannerController {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

final class _LearningRepositoryFake implements LearningRepository {
  @override
  Future<List<QuizWord>> listQuizWords({
    required String ownerId,
    String? categoryId,
    required int limit,
  }) async => const [];

  @override
  Future<List<QuizWord>> listDueWords({
    required String ownerId,
    required DateTime nowUtc,
    required int limit,
  }) async => const [];

  @override
  Future<void> startSession(LearningSessionDraft session) async {}

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
