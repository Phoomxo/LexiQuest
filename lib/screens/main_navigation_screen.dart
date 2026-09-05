import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:uuid/uuid.dart';

import '../features/assessment/domain/assessment_models.dart';
import '../features/adventure/application/adventure_entry_use_cases.dart';
import '../features/adventure/application/adventure_mixed_review_prompt_catalog.dart';
import '../features/adventure/application/adventure_presentation_preferences.dart';
import '../features/adventure/application/adventure_recovery_use_cases.dart';
import '../features/adventure/domain/adventure_journey.dart';
import '../features/adventure/domain/adventure_session_plan.dart';
import '../features/adventure/presentation/adventure_mixed_review_screen.dart';
import '../features/adventure/presentation/adventure_today_entry_card.dart';
import '../features/adventure/presentation/adventure_result_lifecycle_screen.dart';
import '../features/adventure/presentation/today_experience_host.dart';
import '../features/adventure/presentation/widgets/adventure_companion_panel.dart';
import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/application/cloze_mode_adapter.dart';
import '../features/learning/application/definition_quiz_mode_adapter.dart';
import '../features/learning/application/meaning_quiz_mode_adapter.dart';
import '../features/learning/application/session_configuration_policy.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/application/typed_recall_mode_adapter.dart';
import '../features/learning/domain/learning_models.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning/presentation/session_configuration_sheet.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../features/learning_packs/domain/learning_pack.dart';
import '../features/learning_packs/domain/content_manifest.dart';
import '../features/review/domain/review_queue_item.dart';
import '../features/rewards/domain/reward_models.dart';
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
import 'score_screen.dart';
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
          child: _buildLearningSurface(),
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

  Widget _buildLearningSurface() {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final features = _features(context);
    final eligible =
        features?.isVisible(Feature.adventureMotivation) == true &&
        dependencies?.hasComposedDependencyFor(Feature.adventureMotivation) ==
            true;
    final canDiscoverTerminalRecovery =
        dependencies?.learning != null &&
        dependencies?.currentActivityEvidence != null &&
        dependencies?.createLessonController != null &&
        dependencies?.lessonModes != null &&
        dependencies?.activeOwnerIdentities != null;
    return ChooseModeScreen(
      featureRegistry: widget.featureRegistry,
      leadingCards: <Widget>[
        if (canDiscoverTerminalRecovery)
          _PendingMixedReviewRecoveryCard(
            key: const ValueKey<String>('mixed-review-terminal-recovery-card'),
            load: () async {
              final ownerId = await dependencies!.activeOwnerIdentities!
                  .requireSingleActiveOwnerId();
              final discovery = AdventureRecoveryUseCases(
                learning: dependencies.learning!,
                evidence: dependencies.currentActivityEvidence!,
                canStartNewMission: () => false,
                isRepairModeEligible: (_, _, _) => false,
              );
              return discovery.findLatestPendingTerminal(ownerId: ownerId);
            },
            onResume: _resumeFromToday,
          ),
        if (eligible) AdventureTodayEntryCard(onOpen: _openTodayExperience),
      ],
    );
  }

  Future<void> _openTodayExperience() async {
    final dependencies = AppDependenciesScope.maybeOf(context);
    final identities = dependencies?.activeOwnerIdentities;
    final features = widget.featureRegistry ?? dependencies?.features;
    if (dependencies == null ||
        identities == null ||
        features?.isEnabled(Feature.adventureMotivation) != true ||
        !dependencies.hasComposedDependencyFor(Feature.adventureMotivation)) {
      throw StateError('Adventure Today entry is unavailable.');
    }
    final ownerId = await identities.requireSingleActiveOwnerId();
    if (!mounted) return;
    _pushDestination(
      'home/learn/today-experience',
      (_) => _AdventureTodayRouteGuard(
        features: widget.featureRegistry ?? dependencies.features,
        onDisabled: _selectLearningFromToday,
        child: TodayExperienceHost(
          ownerId: ownerId,
          entry: dependencies.adventureEntry! as AdventureEntryUseCases,
          activePermits: dependencies.adventurePresentationPermits!,
          todayHub: dependencies.todayHub!,
          catalog: dependencies.adventureCatalog!,
          journey: dependencies.adventureJourney!,
          rewardAccounts: dependencies.rewardAccounts!,
          createEntryAttemptId: const Uuid().v4,
          nowUtc: _adventureNowUtc,
          actions: _todayActions(),
          features: widget.featureRegistry ?? dependencies.features,
          assessmentAvailable: dependencies.assessment != null,
          presentationPreferences:
              (dependencies.adventureEntry! as AdventureEntryUseCases)
                      .preferences
                  as LearnerAdventurePresentationPreferences,
          onStartMission: _startAdventureMission,
        ),
      ),
    );
  }

  Future<void> _startAdventureMission(
    AdventureMissionLaunchContext launch,
  ) async {
    final mission = launch.mission;
    if (!await _todayOwnerMatches(mission.ownerId) || !mounted) {
      throw StateError('Adventure mission no longer belongs to this owner.');
    }
    if (mission.kind == AdventureMissionKind.resume) {
      final resumable = launch.today.resumableSession;
      if (resumable == null || resumable.id != mission.sourceId) {
        throw StateError('The accepted learning session is no longer active.');
      }
      if (mounted) Navigator.of(context).maybePop();
      await _resumeFromToday(resumable);
      return;
    }

    final dependencies = AppDependenciesScope.maybeOf(context);
    final features = dependencies == null
        ? null
        : widget.featureRegistry ?? dependencies.features;
    final mode = mission.suggestedMode ?? LessonMode.typedRecall;
    final registration = dependencies?.lessonModes?.resolve(mode);
    final adapter = registration?.adapter;
    if (dependencies == null ||
        features?.isEnabled(Feature.adventureMotivation) != true ||
        !dependencies.hasComposedDependencyFor(Feature.adventureMotivation) ||
        dependencies.learning == null ||
        dependencies.createLessonController == null ||
        dependencies.currentActivityEvidence == null ||
        dependencies.vocabulary == null ||
        registration == null ||
        !_isAdventureMixedReviewRootAdapter(adapter) ||
        features?.isEnabled(registration.feature) != true ||
        mission.content.isEmpty) {
      throw StateError('The canonical Adventure lesson is unavailable.');
    }
    final LessonModeAdapter lessonAdapter = adapter!;

    final initialContext = await _loadSessionConfigurationContext(
      dependencies,
      mode,
    );
    if (!mounted || initialContext.ownerId != mission.ownerId) {
      throw StateError('Adventure mission owner changed before configuration.');
    }
    final maximumItems =
        mission.content.length < initialContext.limits.maximumItemCount
        ? mission.content.length
        : initialContext.limits.maximumItemCount;
    if (maximumItems < initialContext.limits.minimumItemCount) {
      throw StateError('Adventure mission has too little canonical content.');
    }
    final limits = initialContext.limits.copyWith(
      maximumItemCount: maximumItems,
    );
    final initial = initialContext.initialConfiguration;
    final usableInitial =
        initial != null &&
            initial.mode == mode &&
            initial.itemCount <= maximumItems &&
            initial.packIdentity == null
        ? initial
        : null;
    final configuration = await showSessionConfigurationSheet(
      context: context,
      registration: registration,
      policy: const SessionConfigurationPolicy(),
      limits: limits,
      ownerId: initialContext.ownerId,
      packs: const <SessionConfigurationPackOption>[],
      initialConfiguration: usableInitial,
      initialResetRequired: initial == null
          ? initialContext.initialResetRequired
          : null,
      initialResetCanUseDefaults: initialContext.protocolResetRequired == null,
    );
    if (configuration == null || !mounted) return;

    Future<SessionConfiguration> revalidate(
      SessionConfiguration candidate,
    ) async {
      final current = AppDependenciesScope.maybeOf(context);
      final currentRegistration = current?.lessonModes?.resolve(mode);
      final currentFeatures = current == null
          ? null
          : widget.featureRegistry ?? current.features;
      if (current == null ||
          currentRegistration == null ||
          !identical(currentRegistration.adapter, lessonAdapter) ||
          currentFeatures?.isEnabled(registration.feature) != true ||
          currentFeatures?.isEnabled(Feature.adventureMotivation) != true ||
          !current.hasComposedDependencyFor(Feature.adventureMotivation)) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.modeUnavailable,
        );
      }
      final currentContext = await _loadSessionConfigurationContext(
        current,
        mode,
      );
      if (currentContext.ownerId != mission.ownerId) {
        throw const SessionConfigurationResetRequired(
          SessionConfigurationResetReason.ownerDrift,
        );
      }
      final reset = currentContext.protocolResetRequired;
      if (reset != null) throw reset;
      final currentMaximum =
          mission.content.length < currentContext.limits.maximumItemCount
          ? mission.content.length
          : currentContext.limits.maximumItemCount;
      return const SessionConfigurationPolicy().revalidate(
        configuration: candidate,
        registration: currentRegistration,
        limits: currentContext.limits.copyWith(
          maximumItemCount: currentMaximum,
        ),
        ownerId: currentContext.ownerId,
        availablePackIdentities: const <ContentIdentity>[],
      );
    }

    final validated = await revalidate(configuration);
    final plan = await dependencies.adventureSessionComposer!.compose(
      mission: mission,
      today: launch.today,
      requestedConfiguration: validated,
      entry: launch.entryDecision,
    );
    final store = dependencies.sessionConfigurations;
    if (store is! ActiveOwnerSessionConfigurationStore) {
      throw StateError('Session configuration authority is unavailable.');
    }
    if (!mounted || !await _todayOwnerMatches(plan.ownerId)) {
      throw StateError('Adventure mission owner changed before persistence.');
    }
    await store.saveForActiveOwner(
      validated,
      updatedAtUtc: DateTime.now().toUtc(),
    );
    if (!mounted || !await _todayOwnerMatches(plan.ownerId)) {
      throw StateError('Adventure mission owner changed before launch.');
    }
    await _startAdventureMixedReview(
      dependencies: dependencies,
      plan: plan,
      rewardOwnership: launch.rewardOwnership,
    );
  }

  Future<void> _startAdventureMixedReview({
    required AppDependencies dependencies,
    required AdventureSessionPlanV1 plan,
    required RewardAccount rewardOwnership,
  }) async {
    AdventureMixedReviewPromptCatalog? catalog;
    final recovery = AdventureRecoveryUseCases(
      learning: dependencies.learning!,
      evidence: dependencies.currentActivityEvidence!,
      canStartNewMission: _canStartAdventureMission,
      isRepairModeEligible: (identity, mode, promptVariant) {
        final current = AppDependenciesScope.maybeOf(context);
        final currentCatalog = catalog;
        final registration = current?.lessonModes?.resolve(mode);
        final features = current == null
            ? null
            : widget.featureRegistry ?? current.features;
        return mounted &&
            currentCatalog != null &&
            registration != null &&
            features?.isEnabled(registration.feature) == true &&
            currentCatalog.supports(identity, mode, promptVariant);
      },
    );
    final run = await recovery.startOrResume(
      plan: plan,
      activeOwnerId: plan.ownerId,
      buildPromptCatalogSnapshot: (session) async {
        final registry = dependencies.lessonModes;
        final vocabulary = dependencies.vocabulary;
        final configuration = session.sessionConfiguration;
        if (registry == null || vocabulary == null || configuration == null) {
          throw StateError(
            'Mixed-review reconstruction authority is unavailable.',
          );
        }
        final lexicalWords = await vocabulary.readPinnedByIds(
          plan.content.map((identity) => identity.id),
        );
        final prepared = AdventureMixedReviewPromptCatalog(
          session: session,
          lexicalWords: lexicalWords,
          registry: registry,
          direction: configuration.direction,
        );
        _validateAdventureMixedReviewCatalog(
          catalog: prepared,
          content: plan.content,
          mode: plan.mode,
        );
        catalog = prepared;
        return prepared.snapshot;
      },
    );
    if (!mounted) return;
    final resolvedCatalog =
        catalog ??
        await _buildAdventureMixedReviewCatalog(
          dependencies: dependencies,
          run: run,
        );
    if (!mounted) return;
    _openAdventureMixedReview(
      dependencies: dependencies,
      recovery: recovery,
      catalog: resolvedCatalog,
      rewardOwnership: run.recovered ? null : rewardOwnership,
      catalogVersion: run.recovered ? null : plan.origin.catalogVersion,
    );
  }

  bool _canStartAdventureMission() {
    if (!mounted) return false;
    final current = AppDependenciesScope.maybeOf(context);
    final features = current == null
        ? null
        : widget.featureRegistry ?? current.features;
    return current != null &&
        features?.isEnabled(Feature.adventureMotivation) == true &&
        current.hasComposedDependencyFor(Feature.adventureMotivation);
  }

  Future<AdventureMixedReviewPromptCatalog> _buildAdventureMixedReviewCatalog({
    required AppDependencies dependencies,
    required AdventureLearningRun run,
  }) async {
    final registry = dependencies.lessonModes;
    final configuration = run.session.sessionConfiguration;
    if (registry == null || configuration == null) {
      throw StateError('Mixed-review reconstruction authority is unavailable.');
    }
    final snapshot = run.state.promptCatalogSnapshot;
    final AdventureMixedReviewPromptCatalog catalog;
    if (snapshot != null) {
      catalog = AdventureMixedReviewPromptCatalog.fromSnapshot(
        session: run.session,
        snapshot: snapshot,
        registry: registry,
        direction: configuration.direction,
      );
    } else {
      final vocabulary = dependencies.vocabulary;
      if (vocabulary == null) {
        throw StateError(
          'Legacy mixed-review reconstruction authority is unavailable.',
        );
      }
      final lexicalWords = await vocabulary.readPinnedByIds(
        run.state.content.map((identity) => identity.id),
      );
      catalog = AdventureMixedReviewPromptCatalog(
        session: run.session,
        lexicalWords: lexicalWords,
        registry: registry,
        direction: configuration.direction,
      );
    }
    _validateAdventureMixedReviewCatalog(
      catalog: catalog,
      content: run.state.content,
      mode: run.state.mode,
    );
    return catalog;
  }

  void _validateAdventureMixedReviewCatalog({
    required AdventureMixedReviewPromptCatalog catalog,
    required Iterable<ContentIdentity> content,
    required LessonMode mode,
  }) {
    for (final identity in content) {
      if (!_hasAdventureOriginalPrompt(catalog, identity, mode)) {
        throw StateError(
          'Exact mixed-review prompt is unavailable for ${identity.id}.',
        );
      }
    }
  }

  void _openAdventureMixedReview({
    required AppDependencies dependencies,
    required AdventureRecoveryUseCases recovery,
    required AdventureMixedReviewPromptCatalog catalog,
    required RewardAccount? rewardOwnership,
    required String? catalogVersion,
  }) {
    final run = recovery.currentRun;
    final configuration = run?.session.sessionConfiguration;
    final registration = run == null
        ? null
        : dependencies.lessonModes?.resolve(run.state.mode);
    final adapter = registration?.adapter;
    if (run == null ||
        configuration == null ||
        registration == null ||
        !_isAdventureMixedReviewRootAdapter(adapter) ||
        configuration.ownerId != run.state.ownerId ||
        configuration.mode != run.state.mode ||
        configuration.itemCount != run.state.content.length) {
      throw StateError('Accepted mixed-review session is inconsistent.');
    }
    final LessonModeAdapter lessonAdapter = adapter!;
    final revalidateConfiguration = _acceptedMixedReviewRevalidator(
      ownerId: run.state.ownerId,
      mode: run.state.mode,
      adapter: lessonAdapter,
      itemCount: run.state.content.length,
    );
    _pushDestination(
      'learning/mixed-review',
      (_) => UnifiedLessonModeHost(
        adapter: lessonAdapter,
        createController: dependencies.createLessonController!,
        feature: registration.feature,
        featureRegistry: widget.featureRegistry ?? dependencies.features,
        learning: dependencies.learning,
        configuration: configuration,
        revalidateConfiguration: revalidateConfiguration,
        preservePreacceptedSessionOnAttachmentFailure: true,
        contrastiveFeedback: dependencies.contrastiveFeedback,
        companionBuilder: rewardOwnership == null || catalogVersion == null
            ? null
            : (_, controller) => _AdventureLessonCompanionGate(
                controller: controller,
                rewardOwnership: rewardOwnership,
                catalogVersion: catalogVersion,
                recovery: recovery,
                features: widget.featureRegistry ?? dependencies.features,
              ),
        builder: (_) => AdventureMixedReviewScreen(
          recovery: recovery,
          catalog: catalog,
          registry: dependencies.lessonModes!,
          completionPageBuilder: (resultContext, summary, presentation) =>
              _buildAdventureMixedReviewResult(
                resultContext: resultContext,
                summary: summary,
                presentation: presentation,
                recovery: recovery,
                rewardOwnership: rewardOwnership,
                catalogVersion: catalogVersion,
              ),
        ),
      ),
    );
  }

  SessionConfigurationRevalidator _acceptedMixedReviewRevalidator({
    required String ownerId,
    required LessonMode mode,
    required LessonModeAdapter adapter,
    required int itemCount,
  }) => (candidate) async {
    final current = AppDependenciesScope.maybeOf(context);
    final currentRegistration = current?.lessonModes?.resolve(mode);
    final features = current == null
        ? null
        : widget.featureRegistry ?? current.features;
    if (current == null ||
        currentRegistration == null ||
        !identical(currentRegistration.adapter, adapter) ||
        features?.isEnabled(currentRegistration.feature) != true) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.modeUnavailable,
      );
    }
    final currentContext = await _loadSessionConfigurationContext(
      current,
      mode,
    );
    if (currentContext.ownerId != ownerId) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.ownerDrift,
      );
    }
    final reset = currentContext.protocolResetRequired;
    if (reset != null) throw reset;
    final maximumItems = itemCount < currentContext.limits.maximumItemCount
        ? itemCount
        : currentContext.limits.maximumItemCount;
    if (maximumItems < currentContext.limits.minimumItemCount) {
      throw const SessionConfigurationResetRequired(
        SessionConfigurationResetReason.invalidProtocol,
      );
    }
    return const SessionConfigurationPolicy().revalidate(
      configuration: candidate,
      registration: currentRegistration,
      limits: currentContext.limits.copyWith(maximumItemCount: maximumItems),
      ownerId: currentContext.ownerId,
      availablePackIdentities: const <ContentIdentity>[],
    );
  };

  Widget _buildAdventureMixedReviewResult({
    required BuildContext resultContext,
    required LearningSessionSummary summary,
    required AdventureLearningPresentation presentation,
    required AdventureRecoveryUseCases recovery,
    required RewardAccount? rewardOwnership,
    required String? catalogVersion,
  }) {
    final current = AppDependenciesScope.maybeOf(resultContext);
    final features = current == null
        ? null
        : widget.featureRegistry ?? current.features;
    final canPresentAdventure =
        presentation == AdventureLearningPresentation.adventure &&
        rewardOwnership != null &&
        catalogVersion != null &&
        current != null &&
        identical(current.learning, recovery.learning) &&
        features?.isEnabled(Feature.adventureMotivation) == true &&
        current.hasComposedDependencyFor(Feature.adventureMotivation);
    if (!canPresentAdventure) {
      return ScoreScreen(
        correctAnswers: summary.correctCount,
        wrongAnswers: summary.wrongCount,
        score: summary.score,
      );
    }
    return AdventureResultLifecycleScreen(
      summary: summary,
      motivation: current.adventureMotivation!,
      nextActionReader: current.adventureResultNextAction!,
      receiptBarrier: current.adventureReceiptBarrier!,
      rewardOwnership: rewardOwnership,
      catalogVersion: catalogVersion,
      diagnostics: current.adventureDiagnostics,
      onNextAction: () {
        Navigator.of(resultContext).pop();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            unawaited(_openTodayReview(const <TodayHubReviewWorkItem>[]));
          }
        });
      },
    );
  }

  _MainNavigationTodayHubActions _todayActions() =>
      _MainNavigationTodayHubActions(
        resume: _resumeFromToday,
        startRecommendation: _startTodayRecommendation,
        openReview: _openTodayReview,
        openHistory: _openTodayHistory,
        startAssessment: _openTodayAssessment,
      );

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
      actions: _todayActions(),
      features: widget.featureRegistry ?? dependencies.features,
      assessmentAvailable: dependencies.assessment != null,
    );
  }

  Future<void> _resumeFromToday(LearningSessionSummary session) async {
    if (!await _todayOwnerMatches(session.ownerId) || !mounted) {
      throw StateError('Today resume no longer belongs to the active owner.');
    }
    if (session.activityType == mixedReviewActivityType) {
      final dependencies = AppDependenciesScope.maybeOf(context);
      if (dependencies?.learning == null ||
          dependencies?.currentActivityEvidence == null ||
          dependencies?.createLessonController == null ||
          dependencies?.lessonModes == null) {
        throw StateError(
          'Mixed-review reconstruction authority is unavailable.',
        );
      }
      AdventureMixedReviewPromptCatalog? catalog;
      final recovery = AdventureRecoveryUseCases(
        learning: dependencies!.learning!,
        evidence: dependencies.currentActivityEvidence!,
        canStartNewMission: _canStartAdventureMission,
        isRepairModeEligible: (identity, mode, promptVariant) {
          final current = AppDependenciesScope.maybeOf(context);
          final registration = current?.lessonModes?.resolve(mode);
          final features = current == null
              ? null
              : widget.featureRegistry ?? current.features;
          return mounted &&
              catalog != null &&
              registration != null &&
              features?.isEnabled(registration.feature) == true &&
              catalog.supports(identity, mode, promptVariant);
        },
      );
      final run = await recovery.recoverExact(
        ownerId: session.ownerId,
        sessionId: session.id,
      );
      if (run == null) {
        throw StateError('The accepted mixed-review session is unavailable.');
      }
      catalog = await _buildAdventureMixedReviewCatalog(
        dependencies: dependencies,
        run: run,
      );
      if (!mounted) return;
      _openAdventureMixedReview(
        dependencies: dependencies,
        recovery: recovery,
        catalog: catalog,
        rewardOwnership: null,
        catalogVersion: null,
      );
      return;
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

  void _selectDestination(int index) {
    setState(() {
      _selectedEntryId = _visibleEntries[index].id;
    });
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
                  child: Semantics(
                    button: true,
                    label: NavigationGlossary.require(
                      'home/profile',
                    ).semanticsLabel,
                    onTap: () {
                      setState(() => _selectedEntryId = 'profile');
                    },
                    excludeSemantics: true,
                    child: TextButton.icon(
                      key: const ValueKey<String>(
                        'profile-fallback-destination',
                      ),
                      onPressed: () {
                        setState(() => _selectedEntryId = 'profile');
                      },
                      icon: Icon(
                        NavigationGlossary.require('home/profile').icon,
                      ),
                      label: Text(
                        NavigationGlossary.require(
                          'home/profile',
                        ).fullThaiLabel,
                      ),
                    ),
                  ),
                ),
              ),
            )
          : NavigationBar(
              selectedIndex: selectedDestinationIndex < 0
                  ? 0
                  : selectedDestinationIndex,
              onDestinationSelected: _selectDestination,
              destinations: [
                for (final (index, entry) in _visibleEntries.indexed)
                  Semantics(
                    button: true,
                    role: SemanticsRole.tab,
                    selected:
                        index ==
                        (selectedDestinationIndex < 0
                            ? 0
                            : selectedDestinationIndex),
                    label:
                        '${entry.glossary.semanticsLabel}\n'
                        '${MaterialLocalizations.of(context).tabLabel(tabIndex: index + 1, tabCount: _visibleEntries.length)}',
                    onTap: () => _selectDestination(index),
                    excludeSemantics: true,
                    child: NavigationDestination(
                      key: ValueKey<String>(entry.productionEntryId),
                      icon: Icon(entry.glossary.icon),
                      selectedIcon: Icon(entry.glossary.selectedIcon!),
                      label: entry.glossary.shortThaiLabel,
                      tooltip: entry.glossary.tooltip,
                    ),
                  ),
              ],
            ),
    );
  }
}

DateTime _adventureNowUtc() {
  final now = DateTime.now().toUtc();
  return DateTime.fromMillisecondsSinceEpoch(
    now.millisecondsSinceEpoch,
    isUtc: true,
  );
}

bool _isAdventureMixedReviewRootAdapter(Object? adapter) =>
    adapter is TypedRecallModeAdapter ||
    adapter is MeaningQuizModeAdapter ||
    adapter is ClozeModeAdapter ||
    adapter is DefinitionQuizModeAdapter;

bool _hasAdventureOriginalPrompt(
  AdventureMixedReviewPromptCatalog catalog,
  ContentIdentity identity,
  LessonMode mode,
) => switch (mode) {
  LessonMode.typedRecall => catalog.supports(identity, mode, 'typedRecall'),
  LessonMode.meaningQuiz =>
    catalog.supports(identity, mode, 'meaningChoice') ||
        catalog.supports(identity, mode, 'wordChoice'),
  LessonMode.cloze => catalog.supports(identity, mode, 'clozeSelected'),
  LessonMode.definitionQuiz => catalog.supports(
    identity,
    mode,
    'definitionChoice',
  ),
  _ => false,
};

final class _AdventureLessonCompanionGate extends StatefulWidget {
  const _AdventureLessonCompanionGate({
    required this.controller,
    required this.rewardOwnership,
    required this.catalogVersion,
    required this.recovery,
    required this.features,
  });

  final UnifiedLessonController controller;
  final RewardAccount rewardOwnership;
  final String catalogVersion;
  final AdventureRecoveryUseCases recovery;
  final FeatureRegistry features;

  @override
  State<_AdventureLessonCompanionGate> createState() =>
      _AdventureLessonCompanionGateState();
}

final class _AdventureLessonCompanionGateState
    extends State<_AdventureLessonCompanionGate> {
  Listenable? _featureChanges;

  @override
  void initState() {
    super.initState();
    _observe(widget.features);
  }

  @override
  void didUpdateWidget(_AdventureLessonCompanionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      _observe(widget.features);
    }
  }

  void _observe(FeatureRegistry features) {
    _featureChanges?.removeListener(_onFeatureChanged);
    _featureChanges = features is Listenable ? features as Listenable : null;
    _featureChanges?.addListener(_onFeatureChanged);
  }

  void _onFeatureChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final show =
        widget.features.isEnabled(Feature.adventureMotivation) &&
        widget.recovery.currentRun?.presentation ==
            AdventureLearningPresentation.adventure;
    if (!show) return const SizedBox.shrink();
    return AdventureLessonCompanionPanel(
      controller: widget.controller,
      rewardOwnership: widget.rewardOwnership,
      catalogVersion: widget.catalogVersion,
    );
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    super.dispose();
  }
}

final class _PendingMixedReviewRecoveryCard extends StatefulWidget {
  const _PendingMixedReviewRecoveryCard({
    super.key,
    required this.load,
    required this.onResume,
  });

  final Future<LearningSessionSummary?> Function() load;
  final Future<void> Function(LearningSessionSummary session) onResume;

  @override
  State<_PendingMixedReviewRecoveryCard> createState() =>
      _PendingMixedReviewRecoveryCardState();
}

final class _AdventureTodayRouteGuard extends StatefulWidget {
  const _AdventureTodayRouteGuard({
    required this.features,
    required this.onDisabled,
    required this.child,
  });

  final FeatureRegistry features;
  final VoidCallback onDisabled;
  final Widget child;

  @override
  State<_AdventureTodayRouteGuard> createState() =>
      _AdventureTodayRouteGuardState();
}

final class _AdventureTodayRouteGuardState
    extends State<_AdventureTodayRouteGuard>
    with RouteAware {
  Listenable? _featureChanges;
  PageRoute<dynamic>? _route;
  bool _popScheduled = false;
  bool _returned = false;

  @override
  void initState() {
    super.initState();
    _observeFeatures();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final pageRoute = route is PageRoute<dynamic> ? route : null;
    if (!identical(pageRoute, _route)) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = pageRoute;
      if (pageRoute != null) appRouteObserver.subscribe(this, pageRoute);
    }
    _reconcile();
  }

  @override
  void didUpdateWidget(_AdventureTodayRouteGuard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.features, widget.features)) {
      _observeFeatures();
    }
    _reconcile();
  }

  void _observeFeatures() {
    _featureChanges?.removeListener(_reconcile);
    _featureChanges = widget.features is Listenable
        ? widget.features as Listenable
        : null;
    _featureChanges?.addListener(_reconcile);
  }

  @override
  void didPopNext() => _reconcile();

  void _reconcile() {
    if (!mounted ||
        _returned ||
        _popScheduled ||
        widget.features.isEnabled(Feature.adventureMotivation)) {
      return;
    }
    final route = _route ?? ModalRoute.of(context);
    if (route?.isCurrent != true) return;
    _popScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      _popScheduled = false;
      if (!mounted ||
          _returned ||
          widget.features.isEnabled(Feature.adventureMotivation) ||
          ModalRoute.of(context)?.isCurrent != true) {
        return;
      }
      _returned = true;
      await Navigator.of(context).maybePop();
      widget.onDisabled();
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;

  @override
  void dispose() {
    _featureChanges?.removeListener(_reconcile);
    if (_route != null) appRouteObserver.unsubscribe(this);
    super.dispose();
  }
}

final class _PendingMixedReviewRecoveryCardState
    extends State<_PendingMixedReviewRecoveryCard>
    with RouteAware {
  LearningSessionSummary? _session;
  PageRoute<dynamic>? _route;
  var _loadGeneration = 0;
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    final pageRoute = route is PageRoute<dynamic> ? route : null;
    if (!identical(pageRoute, _route)) {
      if (_route != null) appRouteObserver.unsubscribe(this);
      _route = pageRoute;
      if (pageRoute != null) appRouteObserver.subscribe(this, pageRoute);
    }
  }

  @override
  void didUpdateWidget(_PendingMixedReviewRecoveryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.load, widget.load)) unawaited(_load());
  }

  @override
  void didPopNext() => unawaited(_load());

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    if (mounted && _session != null) setState(() => _session = null);
    try {
      final session = await widget.load();
      if (mounted && generation == _loadGeneration) {
        setState(() => _session = session);
      }
    } on Object {
      // Discovery is an optional read model. Learn remains fully usable when
      // it is temporarily unavailable.
    }
  }

  Future<void> _resume() async {
    final session = _session;
    if (session == null || _opening) return;
    setState(() => _opening = true);
    try {
      await widget.onResume(session);
    } on Object {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('เปิดบทเรียนที่บันทึกไว้ไม่ได้ กรุณาลองอีกครั้ง'),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _opening = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_session == null) return const SizedBox.shrink();
    return Card(
      child: ListTile(
        leading: const Icon(Icons.restore_rounded),
        title: const Text('ทำบทเรียนที่บันทึกไว้ให้เสร็จ'),
        subtitle: const Text(
          'ความคืบหน้ายังอยู่ครบ และจะเปิดต่อในรูปแบบมาตรฐาน',
        ),
        trailing: _opening
            ? const SizedBox.square(
                dimension: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : const Icon(Icons.chevron_right_rounded),
        enabled: !_opening,
        onTap: _opening ? null : _resume,
      ),
    );
  }

  @override
  void dispose() {
    _loadGeneration += 1;
    if (_route != null) appRouteObserver.unsubscribe(this);
    super.dispose();
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
    child: Semantics(
      button: true,
      label: entry.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: ListTile(
        key: key,
        leading: Icon(entry.icon),
        title: Text(entry.fullThaiLabel),
        onTap: onTap,
      ),
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
