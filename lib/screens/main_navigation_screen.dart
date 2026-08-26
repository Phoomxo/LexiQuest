import 'package:flutter/material.dart';

import '../features/learning/application/native_mode_adapters.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning/presentation/unified_lesson_shell.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import '../runtime/production_feature_gate.dart';
import '../runtime/registries/feature_registry.dart';
import '../navigation/app_routes.dart';
import 'achievements_screen.dart';
import 'ai_tutor_screen.dart';
import 'ai_tutor_settings_screen.dart';
import 'categories_page.dart';
import 'choose_mode_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'ghost_shadow_duel_screen.dart';
import 'export_center_screen.dart';
import 'object_scanner_screen.dart';
import 'profile_settings_screen.dart';
import 'quest_status_screen.dart';
import 'setting_screen.dart';
import 'shadowing_challenge_screen.dart';
import 'shop_page.dart';
import 'study_planning_hub_screen.dart';
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
        icon: Icons.menu_book_outlined,
        selectedIcon: Icons.menu_book,
        label: 'คลังคำศัพท์',
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
        icon: Icons.school_outlined,
        selectedIcon: Icons.school,
        label: 'เรียนรู้',
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
        icon: Icons.event_note_outlined,
        selectedIcon: Icons.event_note,
        label: 'แผนการเรียน',
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
        icon: Icons.analytics_outlined,
        selectedIcon: Icons.analytics,
        label: 'สถิติ',
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
        icon: Icons.healing_outlined,
        selectedIcon: Icons.healing,
        label: 'จุดอ่อน',
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
        icon: Icons.emoji_events_outlined,
        selectedIcon: Icons.emoji_events,
        label: 'รางวัล',
      ),
      const _NavigationEntry(
        id: 'profile',
        productionEntryId: 'home/profile',
        alwaysVisible: true,
        screen: ProfileSettingsScreen(),
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        label: 'โปรไฟล์',
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

  void _pushRegisteredShadowing() {
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
    _pushDestination(
      registration.routeName,
      (_) => ProductionFeatureGate(
        feature: registration.feature,
        registry: widget.featureRegistry ?? dependencies?.features,
        builder: (context) => _buildRegisteredShadowing(
          context,
          adapter: adapter,
          feature: registration.feature,
        ),
      ),
    );
  }

  Widget _buildRegisteredShadowing(
    BuildContext context, {
    required ShadowingModeAdapter adapter,
    required Feature feature,
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
      builder: (_) => ShadowingChallengeScreen(modeAdapter: adapter),
    );
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
                ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: const Text('คลังคำศัพท์'),
                  onTap: () {
                    _scaffoldKey.currentState?.closeDrawer();
                    setState(() {
                      _selectedEntryId = 'vocabulary';
                    });
                  },
                ),
              if (features?.isVisible(Feature.shop) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/rewards/shop'),
                  leading: const Icon(Icons.shopping_bag),
                  title: const Text('ร้านค้า'),
                  onTap: () => _pushFeatureDestination(
                    'rewards/shop',
                    Feature.shop,
                    (_) => const ShopPage(),
                  ),
                ),
              if (features?.isVisible(Feature.objectScanner) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/practice/object-scanner'),
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('สแกนวัตถุ'),
                  onTap: () => _pushFeatureDestination(
                    'practice/object-scanner',
                    Feature.objectScanner,
                    (_) => const ObjectScannerScreen(),
                  ),
                ),
              if (shadowingFeature != null &&
                  features?.isVisible(shadowingFeature) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/practice/shadowing'),
                  leading: const Icon(Icons.mic_none),
                  title: const Text('ฝึกพูดตามเสียง'),
                  onTap: _pushRegisteredShadowing,
                ),
              if (features?.isVisible(Feature.ghostDuel) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/learning/ghost-duel'),
                  leading: const Icon(Icons.sports_esports_outlined),
                  title: const Text('ดวลกับสถิติเดิม'),
                  onTap: () => _pushFeatureDestination(
                    'learning/ghost-duel',
                    Feature.ghostDuel,
                    (_) => const GhostShadowDuelScreen(),
                  ),
                ),
              if (features?.isVisible(Feature.aiTutor) == true) ...[
                ListTile(
                  key: const ValueKey<String>('drawer/ai-tutor/chat'),
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('AI Tutor'),
                  onTap: () => _pushFeatureDestination(
                    'ai-tutor/chat',
                    Feature.aiTutor,
                    (_) => const AiTutorScreen(),
                  ),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('AI Provider BYOK'),
                  onTap: () => _pushFeatureDestination(
                    'ai-tutor/settings',
                    Feature.aiTutor,
                    (_) => const AiTutorSettingsScreen(),
                  ),
                ),
              ],
              if (features?.isVisible(Feature.export) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/export/center'),
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('ส่งออกข้อมูล'),
                  onTap: () => _pushFeatureDestination(
                    'export/center',
                    Feature.export,
                    (_) => const ExportCenterScreen(),
                  ),
                ),
              if (features?.isVisible(Feature.questV2) == true)
                ListTile(
                  key: const ValueKey<String>('drawer/rewards/quests'),
                  leading: const Icon(Icons.flag_outlined),
                  title: const Text('Quests'),
                  onTap: () => _pushFeatureDestination(
                    'rewards/quests',
                    Feature.questV2,
                    (_) => const QuestStatusScreen(),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('ตั้งค่า'),
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
                child: TextButton.icon(
                  key: const ValueKey<String>('profile-fallback-destination'),
                  onPressed: () {
                    setState(() => _selectedEntryId = 'profile');
                  },
                  icon: const Icon(Icons.person_outlined),
                  label: const Text('โปรไฟล์'),
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
                    icon: Icon(entry.icon),
                    selectedIcon: Icon(entry.selectedIcon),
                    label: entry.label,
                  ),
              ],
            ),
    );
  }
}

final class _NavigationEntry {
  const _NavigationEntry({
    required this.id,
    required this.productionEntryId,
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    this.visibilityFeatures = const [],
    this.alwaysVisible = false,
    this.showUnavailableWhenHidden = false,
    this.requiresComposedDependency = false,
  });

  final String id;
  final String productionEntryId;
  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
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
