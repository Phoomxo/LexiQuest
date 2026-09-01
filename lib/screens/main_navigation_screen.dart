import 'package:flutter/material.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/application/session_configuration_policy.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/session_configuration_sheet.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/learning_packs/domain/learning_pack.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/today_hub/domain/today_hub_models.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../navigation/app_routes.dart';
import '../navigation/navigation_glossary.dart';
import 'achievements_screen.dart';
import 'ai_tutor_screen.dart';
import 'ai_tutor_settings_screen.dart';
import 'categories_page.dart';
import 'choose_mode_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'ghost_shadow_duel_screen.dart';
import 'export_center_screen.dart';
import 'learning_history_screen.dart';
import 'object_scanner_screen.dart';
import 'profile_settings_screen.dart';
import 'pre_post_assessment_screen.dart';
import 'quest_status_screen.dart';
import 'review_center_screen.dart';
import 'setting_screen.dart';
import 'shadowing_challenge_screen.dart';
import 'shop_page.dart';
import 'study_planning_hub_screen.dart';
import 'today_hub_screen.dart';
import 'weakness_clinic_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.featureRegistry,
  });

  final int initialIndex;
  final FeatureRegistry? featureRegistry;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  List<_NavigationEntry> _entries = const [];
  List<_NavigationEntry> _visibleEntries = const [];
  String? _selectedEntryId;
  bool _selectionInitialized = false;
  Listenable? _featureChanges;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final features = _features(context);
    _observeFeatureChanges(features);
    _refreshEntries(features);
  }

  @override
  void didUpdateWidget(MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      final features = _features(context);
      _observeFeatureChanges(features);
      _refreshEntries(features);
    }
  }

  void _observeFeatureChanges(FeatureRegistry? features) {
    final Listenable? next = features is Listenable
        ? features as Listenable
        : null;
    if (identical(next, _featureChanges)) return;
    _featureChanges?.removeListener(_onFeatureChanged);
    _featureChanges = next;
    next?.addListener(_onFeatureChanged);
  }

  void _onFeatureChanged() {
    if (!mounted) return;
    setState(() => _refreshEntries(_features(context)));
  }

  void _refreshEntries(FeatureRegistry? features) {
    _entries = _buildEntries();
    _visibleEntries = _entries
        .where(
          (entry) =>
              entry.isVisible(features, AppDependenciesScope.maybeOf(context)),
        )
        .toList(growable: false);
    if (!_selectionInitialized) {
      final initialIndex = widget.initialIndex.clamp(
        0,
        _visibleEntries.length - 1,
      );
      _selectedEntryId = _visibleEntries[initialIndex].id;
      _selectionInitialized = true;
      return;
    }
    if (!_entries.any((entry) => entry.id == _selectedEntryId)) {
      _selectedEntryId = _visibleEntries.first.id;
    }
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    super.dispose();
  }

  FeatureRegistry? _features(BuildContext context) {
    return widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.features;
  }

  List<_NavigationEntry> _buildEntries() {
    return [
      _NavigationEntry(
        id: 'vocabulary',
        productionEntryId: 'home/vocabulary',
        visibilityFeatures: const [Feature.vocabulary],
        screen: _gate(
          'vocabulary',
          Feature.vocabulary,
          (_) => CategoriesPage(),
        ),
        glossary: NavigationGlossary.require('home/vocabulary'),
      ),
      _NavigationEntry(
        id: 'learning',
        productionEntryId: 'home/learn',
        showUnavailableWhenHidden: true,
        visibilityFeatures: const [Feature.quiz, Feature.srs, Feature.reading],
        screen: KeyedSubtree(
          key: const ValueKey<String>('production-feature-view-learning'),
          child: ChooseModeScreen(featureRegistry: widget.featureRegistry),
        ),
        glossary: NavigationGlossary.require('home/learn'),
      ),
      _NavigationEntry(
        id: 'today',
        productionEntryId: 'home/today',
        visibilityFeatures: const [Feature.dailyContinuity],
        requiresComposedDependency: true,
        screen: _gate('today', Feature.dailyContinuity, _buildTodayHub),
        glossary: NavigationGlossary.require('home/today'),
      ),
      _NavigationEntry(
        id: 'study-planning',
        productionEntryId: 'home/study-planning',
        visibilityFeatures: const [Feature.studyPlanning],
        requiresComposedDependency: true,
        screen: _gate(
          'study-planning',
          Feature.studyPlanning,
          (_) => const StudyPlanningHubScreen(),
        ),
        glossary: NavigationGlossary.require('home/study-planning'),
      ),
      _NavigationEntry(
        id: 'mastery',
        productionEntryId: 'home/mastery',
        visibilityFeatures: const [Feature.mastery],
        screen: _gate(
          'mastery',
          Feature.mastery,
          (_) => const MasteryDashboardScreen(),
        ),
        glossary: NavigationGlossary.require('home/mastery'),
      ),
      _NavigationEntry(
        id: 'weakness',
        productionEntryId: 'home/weakness',
        visibilityFeatures: const [Feature.weakness],
        screen: _gate(
          'weakness',
          Feature.weakness,
          (_) => const WeaknessClinicScreen(),
        ),
        glossary: NavigationGlossary.require('home/weakness'),
      ),
      _NavigationEntry(
        id: 'achievements',
        productionEntryId: 'home/achievements',
        visibilityFeatures: const [Feature.achievements],
        screen: _gate(
          'achievements',
          Feature.achievements,
          (_) => const AchievementsScreen(),
        ),
        glossary: NavigationGlossary.require('home/achievements'),
      ),
      _NavigationEntry(
        id: 'profile',
        productionEntryId: 'home/profile',
        alwaysVisible: true,
        screen: ProfileSettingsScreen(),
        glossary: NavigationGlossary.require('home/profile'),
      ),
    ];
  }

  Widget _gate(String id, Feature feature, WidgetBuilder builder) {
    return ProductionFeatureGate(
      key: ValueKey<String>('production-feature-view-$id'),
      feature: feature,
      registry: widget.featureRegistry,
      builder: builder,
    );
  }

  Widget _buildTodayHub(BuildContext context) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final todayHub = dependencies?.todayHub;
    if (dependencies == null ||
        todayHub == null ||
        !dependencies.hasComposedDependencyFor(Feature.dailyContinuity)) {
      return const ProductionFeatureUnavailable(
        feature: Feature.dailyContinuity,
        reason: ProductionFeatureUnavailableReason.missingDependency,
      );
    }
    return TodayHubScreen(
      useCases: todayHub,
      actions: _MainNavigationTodayHubActions(
        resume: _resumeFromToday,
        startRecommendation: _startTodayRecommendation,
        openReview: _openTodayReview,
        openHistory: _openTodayHistory,
        startAssessment: _openTodayAssessment,
      ),
      features: widget.featureRegistry ?? dependencies.features,
      assessmentAvailable: dependencies.assessment != null,
    );
  }

  Future<void> _resumeFromToday(LearningSessionSummary session) async {
    if (!await _todayOwnerMatches(session.ownerId) || !mounted) {
      throw StateError('Today resume no longer belongs to the active owner.');
    }
    _selectLearningFromToday();
  }

  Future<void> _startTodayRecommendation(
    TodayHubRecommendation recommendation,
  ) async {
    final ownerId = recommendation.result.ownerId;
    if (!recommendation.isAuthoritative ||
        ownerId == null ||
        !await _todayOwnerMatches(ownerId) ||
        !mounted) {
      throw StateError('Today recommendation is no longer authoritative.');
    }
    final mode = recommendation.result.recommendedMode;
    final dependencies = AppDependenciesScope.maybeOf(context);
    final registration = mode == null
        ? null
        : dependencies?.lessonModes?.resolve(mode);
    if (registration == null ||
        dependencies?.features.isEnabled(registration.feature) != true) {
      throw StateError('Today recommendation mode is unavailable.');
    }
    _selectLearningFromToday();
  }

  void _selectLearningFromToday() {
    if (!_visibleEntries.any((entry) => entry.id == 'learning')) {
      throw StateError('The canonical learning destination is unavailable.');
    }
    setState(() => _selectedEntryId = 'learning');
  }

  Future<bool> _todayOwnerMatches(String ownerId) async {
    final identities = AppDependenciesScope.maybeOf(
      context,
    )?.activeOwnerIdentities;
    if (identities == null) return false;
    try {
      return await identities.requireSingleActiveOwnerId() == ownerId;
    } catch (_) {
      return false;
    }
  }

  Future<void> _openTodayReview(List<TodayHubReviewWorkItem> work) async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final reviewCenter = dependencies?.reviewCenter;
    if (reviewCenter == null || !mounted) {
      throw StateError('Review Center is unavailable.');
    }
    _pushDestination(
      'home/today/review',
      (_) => ReviewCenterScreen(
        useCases: reviewCenter,
        lessonShellBuilder: (item) =>
            _buildTodayReviewLesson(dependencies!, item),
      ),
    );
  }

  UnifiedLessonShellLease _buildTodayReviewLesson(
    AppDependencies dependencies,
    ReviewQueueItem item,
  ) {
    final learning = dependencies.learning;
    final createController = dependencies.createLessonController;
    final registration = dependencies.lessonModes?.resolve(
      LessonMode.meaningQuiz,
    );
    if (learning == null || createController == null || registration == null) {
      throw StateError('Review lesson authority is unavailable.');
    }
    final controller = createController(registration.adapter);
    return UnifiedLessonShellLease(
      controller: controller,
      learning: learning,
      nowUtc: () => DateTime.now().toUtc(),
      contrastiveFeedback: dependencies.contrastiveFeedback,
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('ทบทวนคำศัพท์')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text('${item.spelling}\n${item.meaning}'),
          ),
        ),
      ),
    );
  }

  Future<void> _openTodayHistory() async {
    final history = AppDependenciesScope.maybeOf(context)?.learningHistory;
    if (history == null || !mounted) {
      throw StateError('Learning History is unavailable.');
    }
    _pushDestination(
      'home/today/history',
      (_) => LearningHistoryScreen(useCases: history),
    );
  }

  Future<void> _openTodayAssessment(
    TodayHubAssignedAssessment assessment,
  ) async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final useCases = dependencies?.assessment;
    final features = _features(context);
    if (useCases == null ||
        features?.isEnabled(Feature.researchAssessment) != true ||
        !await _todayOwnerMatches(assessment.run.ownerId) ||
        !mounted) {
      throw StateError('Assigned assessment is unavailable.');
    }
    final run = assessment.run;
    _pushDestination(
      'research/assessment',
      (_) => ProductionFeatureGate(
        feature: Feature.researchAssessment,
        registry: widget.featureRegistry ?? dependencies?.features,
        builder: (_) => PrePostAssessmentScreen(
          useCases: useCases,
          command: AssessmentStartCommand(
            runId: run.id,
            learningSessionId: run.learningSessionId,
            studyCycleId: run.studyCycleId,
            phase: run.phase,
            instrumentId: run.instrumentId,
            instrumentVersion: run.instrumentVersion,
            formId: run.formId,
            formVersion: run.formVersion,
          ),
        ),
      ),
    );
  }

  String _runtimeStatusSummary(BuildContext context) {
    final status = AppDependenciesScope.maybeOf(context)?.runtimeStatus;
    if (status == null) {
      return 'โหมดทดสอบ · ระบบภายนอกอาจยังไม่พร้อมใช้งาน';
    }
    if (status.isFullyReady) {
      return 'ระบบภายนอกพร้อมใช้งาน';
    }

    final unavailable = <String>[
      if (status.firebase != RuntimeAvailability.ready) 'Firebase',
      if (status.aiTutor != RuntimeAvailability.ready) 'AI Tutor',
      if (status.voice != RuntimeAvailability.ready) 'Voice',
      if (status.backends != RuntimeAvailability.ready) 'Cloud voice add-ons',
    ];
    return '${unavailable.join(' · ')} ยังไม่พร้อม — การเรียนในเครื่องยังใช้ได้';
  }

  String _buildIdentity(BuildContext context) {
    final buildInfo = AppDependenciesScope.maybeOf(context)?.buildInfo;
    if (buildInfo == null) return '';
    return '${buildInfo.version} · ${buildInfo.buildId}';
  }

  void _pushDestination(String name, WidgetBuilder builder) {
    _scaffoldKey.currentState?.closeDrawer();
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: builder),
    );
  }

  void _pushFeatureDestination(
    String name,
    Feature feature,
    WidgetBuilder builder,
  ) {
    _pushDestination(
      name,
      (_) => ProductionFeatureGate(
        feature: feature,
        registry: widget.featureRegistry,
        builder: builder,
      ),
    );
  }

  Future<void> _pushRegisteredShadowing() async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final registration = dependencies?.lessonModes?.resolve(
      LessonMode.shadowing,
    );
    if (registration?.adapter is! ShadowingModeAdapter) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('This lesson mode is unavailable.')),
      );
      return;
    }
    final adapter = registration!.adapter as ShadowingModeAdapter;
    _scaffoldKey.currentState?.closeDrawer();
    try {
      final initialContext = await _loadSessionConfigurationContext(
        dependencies,
        LessonMode.shadowing,
      );
      if (!mounted) return;
      final configuration = await showSessionConfigurationSheet(
        context: context,
        registration: registration,
        policy: const SessionConfigurationPolicy(),
        limits: initialContext.limits,
        ownerId: initialContext.ownerId,
        packs: initialContext.packs,
        initialConfiguration: initialContext.initialConfiguration,
        initialResetRequired: initialContext.initialResetRequired,
        initialResetCanUseDefaults:
            initialContext.protocolResetRequired == null,
      );
      if (configuration == null || !mounted) return;

      Future<SessionConfiguration> revalidate(
        SessionConfiguration candidate,
      ) async {
        final currentDependencies = AppDependenciesScope.maybeOf(context);
        final currentRegistration = currentDependencies?.lessonModes?.resolve(
          LessonMode.shadowing,
        );
        if (currentRegistration == null ||
            !identical(currentRegistration.adapter, adapter) ||
            currentDependencies?.features.isEnabled(registration.feature) !=
                true) {
          throw const SessionConfigurationResetRequired(
            SessionConfigurationResetReason.modeUnavailable,
          );
        }
        final currentContext = await _loadSessionConfigurationContext(
          currentDependencies,
          LessonMode.shadowing,
        );
        final reset = currentContext.protocolResetRequired;
        if (reset != null) throw reset;
        return const SessionConfigurationPolicy().revalidate(
          configuration: candidate,
          registration: currentRegistration,
          limits: currentContext.limits,
          ownerId: currentContext.ownerId,
          availablePackIdentities: currentContext.packs.map(
            (pack) => pack.identity,
          ),
        );
      }

      final validated = await revalidate(configuration);
      final store = dependencies?.sessionConfigurations;
      if (store == null) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
          'The validated configuration could not be persisted.',
        );
      }
      try {
        await store.save(validated, updatedAtUtc: DateTime.now().toUtc());
      } on SessionConfigurationResetRequired {
        rethrow;
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
          'The validated configuration could not be persisted.',
        );
      }
      if (!mounted) return;
      _pushDestination(
        registration.routeName,
        (_) => ProductionFeatureGate(
          feature: registration.feature,
          registry: widget.featureRegistry ?? dependencies?.features,
          builder: (context) => _buildRegisteredShadowing(
            context,
            adapter: adapter,
            feature: registration.feature,
            configuration: validated,
            revalidateConfiguration: revalidate,
          ),
        ),
      );
    } on SessionConfigurationResetRequired catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(error.promptMessage)));
      }
    }
  }

  Widget _buildRegisteredShadowing(
    BuildContext context, {
    required ShadowingModeAdapter adapter,
    required Feature feature,
    required SessionConfiguration configuration,
    required SessionConfigurationRevalidator revalidateConfiguration,
  }) {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final createController = dependencies?.createLessonController;
    if (createController == null || dependencies?.learning == null) {
      return ProductionFeatureUnavailable(
        feature: feature,
        reason: ProductionFeatureUnavailableReason.missingDependency,
      );
    }
    return UnifiedLessonModeHost(
      adapter: adapter,
      createController: createController,
      feature: feature,
      featureRegistry: widget.featureRegistry ?? dependencies?.features,
      learning: dependencies!.learning,
      configuration: configuration,
      revalidateConfiguration: revalidateConfiguration,
      builder: (_) => NativeVocabularyLessonModeLoader(
        sessionConfiguration: configuration,
        builder: (_, session, question) => ShadowingChallengeScreen(
          referenceSentence: question.word.spelling,
          sessionId: session.id,
          ownerId: session.ownerId,
          wordId: question.word.id,
          modeAdapter: adapter,
        ),
      ),
    );
  }

  Future<_MainSessionConfigurationContext> _loadSessionConfigurationContext(
    AppDependencies? dependencies,
    LessonMode mode,
  ) async {
    var ownerId = 'owner:local-compatibility';
    final owners = dependencies?.localOwners;
    if (owners != null) {
      try {
        ownerId = (await owners.getOrCreateActiveOwner()).id;
        SessionConfigurationPolicy.requireCanonical(ownerId, 'ownerId');
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.ownerDrift,
        );
      }
    }
    try {
      SessionConfigurationPolicy.requireCanonical(ownerId, 'ownerId');
      var limits = const SessionConfigurationProtocolLimits.standard();
      SessionConfigurationResetRequired? protocolReset;
      try {
        limits =
            await dependencies?.sessionConfigurationProtocols?.resolveForOwner(
              ownerId,
            ) ??
            limits;
      } on SessionConfigurationResetRequired catch (error) {
        protocolReset = error;
      } catch (_) {
        protocolReset = const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.invalidProtocol,
        );
      }
      SessionConfiguration? initial;
      SessionConfigurationResetRequired? storedReset;
      try {
        initial = await dependencies?.sessionConfigurations?.read(
          ownerId: ownerId,
          mode: mode,
        );
      } on SessionConfigurationResetRequired catch (error) {
        storedReset = error;
      } catch (_) {
        storedReset = const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.tampered,
        );
      }
      final planning = dependencies?.studyPlanning;
      final List<SessionConfigurationPackOption> packs;
      try {
        packs = planning == null
            ? const <SessionConfigurationPackOption>[]
            : (await planning.listPacks(LearningPackFilter())).packs
                  .where(
                    (pack) =>
                        limits.pinnedPackIdentities.isEmpty ||
                        limits.pinnedPackIdentities.contains(
                          pack.contentIdentity,
                        ),
                  )
                  .map(
                    (pack) => SessionConfigurationPackOption(
                      identity: pack.contentIdentity,
                      label: '${pack.title} revision ${pack.revision}',
                    ),
                  )
                  .toList(growable: false);
      } catch (_) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.packDrift,
        );
      }
      return _MainSessionConfigurationContext(
        ownerId: ownerId,
        limits: limits,
        packs: packs,
        initialConfiguration: initial,
        initialResetRequired: protocolReset ?? storedReset,
        protocolResetRequired: protocolReset,
      );
    } on SessionConfigurationResetRequired {
      rethrow;
    } catch (_) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.packDrift,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = _features(context);
    final shadowingRegistration = AppDependenciesScope.maybeOf(
      context,
    )?.lessonModes?.resolve(LessonMode.shadowing);
    final shadowingFeature =
        shadowingRegistration?.adapter is ShadowingModeAdapter
        ? shadowingRegistration!.feature
        : null;
    final selectedStackIndex = _entries.indexWhere(
      (entry) => entry.id == _selectedEntryId,
    );
    final selectedDestinationIndex = _visibleEntries.indexWhere(
      (entry) => entry.id == _selectedEntryId,
    );
    final selectedEntry = _entries[selectedStackIndex];
    final showAggregateUnavailable =
        selectedEntry.showUnavailableWhenHidden &&
        !selectedEntry.isVisible(
          features,
          AppDependenciesScope.maybeOf(context),
        );
    final status = AppDependenciesScope.maybeOf(context)?.runtimeStatus;
    final showBanner = status != null && !status.isFullyReady;
    return Scaffold(
      key: _scaffoldKey,
      body: Column(
        children: [
          if (showBanner)
            Material(
              color: Theme.of(context).colorScheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off,
                      size: 18,
                      color: Theme.of(context).colorScheme.onErrorContainer,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _runtimeStatusSummary(context),
                        key: const ValueKey<String>('runtime-status-banner'),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onErrorContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Offstage(
                  offstage: showAggregateUnavailable,
                  child: IndexedStack(
                    index: selectedStackIndex,
                    children: [
                      for (var index = 0; index < _entries.length; index++)
                        TickerMode(
                          enabled: index == selectedStackIndex,
                          child: _entries[index].screen,
                        ),
                    ],
                  ),
                ),
                if (showAggregateUnavailable)
                  ProductionFeatureUnavailable(
                    feature: selectedEntry.visibilityFeatures.first,
                    reason: ProductionFeatureUnavailableReason.unavailableState,
                    state: features?.stateOf(
                      selectedEntry.visibilityFeatures.first,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.small(
        key: const ValueKey<String>('legacy-drawer-button'),
        heroTag: 'main-navigation-drawer',
        tooltip: 'เปิดเมนูเพิ่มเติม',
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
        child: const Icon(Icons.menu),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startTop,
      drawer: Drawer(
        child: SafeArea(
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              DrawerHeader(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primaryContainer,
                ),
                child: Text(
                  'LexiQuest',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onPrimaryContainer,
                    fontSize: 22,
                  ),
                ),
              ),
              if (features?.isVisible(Feature.vocabulary) == true)
                _glossaryDrawerTile(
                  entry: NavigationGlossary.require('home/vocabulary'),
                  onTap: () {
                    _scaffoldKey.currentState?.closeDrawer();
                    setState(() {
                      _selectedEntryId = 'vocabulary';
                    });
                  },
                ),
              if (features?.isVisible(Feature.shop) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/rewards/shop'),
                  entry: NavigationGlossary.require('drawer/rewards/shop'),
                  onTap: () => _pushFeatureDestination(
                    'rewards/shop',
                    Feature.shop,
                    (_) => const ShopPage(),
                  ),
                ),
              if (features?.isVisible(Feature.objectScanner) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/practice/object-scanner'),
                  entry: NavigationGlossary.require(
                    'drawer/practice/object-scanner',
                  ),
                  onTap: () => _pushFeatureDestination(
                    'practice/object-scanner',
                    Feature.objectScanner,
                    (_) => const ObjectScannerScreen(),
                  ),
                ),
              if (shadowingFeature != null &&
                  features?.isVisible(shadowingFeature) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/practice/shadowing'),
                  entry: NavigationGlossary.require(
                    'drawer/practice/shadowing',
                  ),
                  onTap: _pushRegisteredShadowing,
                ),
              if (features?.isVisible(Feature.ghostDuel) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/learning/ghost-duel'),
                  entry: NavigationGlossary.require(
                    'drawer/learning/ghost-duel',
                  ),
                  onTap: () => _pushFeatureDestination(
                    'learning/ghost-duel',
                    Feature.ghostDuel,
                    (_) => const GhostShadowDuelScreen(),
                  ),
                ),
              if (features?.isVisible(Feature.aiTutor) == true) ...[
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/ai-tutor/chat'),
                  entry: NavigationGlossary.require('drawer/ai-tutor/chat'),
                  onTap: () => _pushFeatureDestination(
                    'ai-tutor/chat',
                    Feature.aiTutor,
                    (_) => const AiTutorScreen(),
                  ),
                ),
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/ai-tutor/settings'),
                  entry: NavigationGlossary.require('drawer/ai-tutor/settings'),
                  onTap: () => _pushFeatureDestination(
                    'ai-tutor/settings',
                    Feature.aiTutor,
                    (_) => const AiTutorSettingsScreen(),
                  ),
                ),
              ],
              if (features?.isVisible(Feature.export) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/export/center'),
                  entry: NavigationGlossary.require('drawer/export/center'),
                  onTap: () => _pushFeatureDestination(
                    'export/center',
                    Feature.export,
                    (_) => const ExportCenterScreen(),
                  ),
                ),
              if (features?.isVisible(Feature.questV2) == true)
                _glossaryDrawerTile(
                  key: const ValueKey<String>('drawer/rewards/quests'),
                  entry: NavigationGlossary.require('drawer/rewards/quests'),
                  onTap: () => _pushFeatureDestination(
                    'rewards/quests',
                    Feature.questV2,
                    (_) => const QuestStatusScreen(),
                  ),
                ),
              _glossaryDrawerTile(
                key: const ValueKey<String>('drawer/settings'),
                entry: NavigationGlossary.require('drawer/settings'),
                onTap: () =>
                    _pushDestination('settings', (_) => const SettingScreen()),
              ),
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                child: Text(
                  _runtimeStatusSummary(context),
                  key: const ValueKey<String>('runtime-status-summary'),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  _buildIdentity(context),
                  key: const ValueKey<String>('build-identity'),
                ),
              ),
            ],
          ),
        ),
      ),
      bottomNavigationBar: _visibleEntries.length < 2
          ? BottomAppBar(
              child: SizedBox(
                height: 64,
                child: Tooltip(
                  message: NavigationGlossary.require('home/profile').tooltip,
                  child: TextButton.icon(
                    key: const ValueKey<String>('profile-fallback-destination'),
                    onPressed: () {
                      setState(() => _selectedEntryId = 'profile');
                    },
                    icon: Icon(NavigationGlossary.require('home/profile').icon),
                    label: Text(
                      NavigationGlossary.require('home/profile').fullThaiLabel,
                    ),
                  ),
                ),
              ),
            )
          : NavigationBar(
              selectedIndex: selectedDestinationIndex < 0
                  ? 0
                  : selectedDestinationIndex,
              onDestinationSelected: (index) {
                setState(() {
                  _selectedEntryId = _visibleEntries[index].id;
                });
              },
              destinations: [
                for (final entry in _visibleEntries)
                  NavigationDestination(
                    key: ValueKey<String>(entry.productionEntryId),
                    icon: Icon(entry.glossary.icon),
                    selectedIcon: Icon(entry.glossary.selectedIcon!),
                    label: entry.glossary.shortThaiLabel,
                    tooltip: entry.glossary.tooltip,
                  ),
              ],
            ),
    );
  }
}

final class _MainNavigationTodayHubActions implements TodayHubActionDelegate {
  const _MainNavigationTodayHubActions({
    required this._resume,
    required this._startRecommendation,
    required this._openReview,
    required this._openHistory,
    required this._startAssessment,
  });

  final Future<void> Function(LearningSessionSummary session) _resume;
  final Future<void> Function(TodayHubRecommendation recommendation)
  _startRecommendation;
  final Future<void> Function(List<TodayHubReviewWorkItem> work) _openReview;
  final Future<void> Function() _openHistory;
  final Future<void> Function(TodayHubAssignedAssessment assessment)
  _startAssessment;

  @override
  Future<void> resume(LearningSessionSummary session) => _resume(session);

  @override
  Future<void> startRecommendation(TodayHubRecommendation recommendation) =>
      _startRecommendation(recommendation);

  @override
  Future<void> openReview(List<TodayHubReviewWorkItem> work) =>
      _openReview(work);

  @override
  Future<void> openHistory() => _openHistory();

  @override
  Future<void> startAssessment(TodayHubAssignedAssessment assessment) =>
      _startAssessment(assessment);
}

final class _MainSessionConfigurationContext {
  const _MainSessionConfigurationContext({
    required this.ownerId,
    required this.limits,
    required this.packs,
    required this.initialConfiguration,
    required this.initialResetRequired,
    required this.protocolResetRequired,
  });

  final String ownerId;
  final SessionConfigurationProtocolLimits limits;
  final List<SessionConfigurationPackOption> packs;
  final SessionConfiguration? initialConfiguration;
  final SessionConfigurationResetRequired? initialResetRequired;
  final SessionConfigurationResetRequired? protocolResetRequired;
}

Widget _glossaryDrawerTile({
  required NavigationGlossaryEntry entry,
  required VoidCallback onTap,
  Key? key,
}) {
  return Tooltip(
    message: entry.tooltip,
    child: ListTile(
      key: key,
      leading: Icon(entry.icon),
      title: Text(entry.fullThaiLabel),
      onTap: onTap,
    ),
  );
}

final class _NavigationEntry {
  const _NavigationEntry({
    required this.id,
    required this.productionEntryId,
    required this.screen,
    required this.glossary,
    this.visibilityFeatures = const [],
    this.alwaysVisible = false,
    this.showUnavailableWhenHidden = false,
    this.requiresComposedDependency = false,
  });

  final String id;
  final String productionEntryId;
  final Widget screen;
  final NavigationGlossaryEntry glossary;
  final List<Feature> visibilityFeatures;
  final bool alwaysVisible;
  final bool showUnavailableWhenHidden;
  final bool requiresComposedDependency;

  bool isVisible(FeatureRegistry? features, AppDependencies? dependencies) {
    if (alwaysVisible) return true;
    if (features == null) return false;
    return visibilityFeatures.any(features.isVisible) &&
        (!requiresComposedDependency ||
            dependencies?.hasComposedDependencyFor(visibilityFeatures.single) ==
                true);
  }
}
