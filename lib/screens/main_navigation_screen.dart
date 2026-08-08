import 'package:flutter/material.dart';

import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../navigation/app_routes.dart';
import 'achievements_screen.dart';
import 'ai_tutor_screen.dart';
import 'categories_page.dart';
import 'choose_mode_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'gemini_settings_screen.dart';
import 'ghost_shadow_duel_screen.dart';
import 'export_center_screen.dart';
import 'object_scanner_screen.dart';
import 'profile_settings_screen.dart';
import 'setting_screen.dart';
import 'shadowing_challenge_screen.dart';
import 'shop_page.dart';
import 'weakness_clinic_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  const MainNavigationScreen({
    super.key,
    this.initialIndex = 0,
    this.featureRegistry,
  });

  final int initialIndex;
  final FieldFeatureRegistry? featureRegistry;

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;
  List<_NavigationEntry> _entries = const [];
  Listenable? _featureChanges;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final features = _fieldFeatures(context);
    _observeFeatureChanges(features);
    _refreshEntries(features);
  }

  @override
  void didUpdateWidget(MainNavigationScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.featureRegistry, widget.featureRegistry)) {
      final features = _fieldFeatures(context);
      _observeFeatureChanges(features);
      _refreshEntries(features);
    }
  }

  void _observeFeatureChanges(FieldFeatureRegistry features) {
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
    setState(() => _refreshEntries(_fieldFeatures(context)));
  }

  void _refreshEntries(FieldFeatureRegistry features) {
    _entries = _buildEntries(features);
    _currentIndex = _currentIndex.clamp(0, _entries.length - 1);
  }

  @override
  void dispose() {
    _featureChanges?.removeListener(_onFeatureChanged);
    super.dispose();
  }

  FieldFeatureRegistry _fieldFeatures(BuildContext context) {
    return widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
  }

  List<_NavigationEntry> _buildEntries(FieldFeatureRegistry features) {
    return [
      if (features.isVisible(FieldFeature.vocabulary))
        _NavigationEntry(
          screen: CategoriesPage(),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book,
          label: 'คลังคำศัพท์',
        ),
      if (features.isVisible(FieldFeature.quiz) ||
          features.isVisible(FieldFeature.srs) ||
          features.isVisible(FieldFeature.reading))
        const _NavigationEntry(
          screen: ChooseModeScreen(),
          icon: Icons.school_outlined,
          selectedIcon: Icons.school,
          label: 'เรียนรู้',
        ),
      if (features.isVisible(FieldFeature.mastery))
        const _NavigationEntry(
          screen: MasteryDashboardScreen(),
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          label: 'สถิติ',
        ),
      if (features.isVisible(FieldFeature.weakness))
        const _NavigationEntry(
          screen: WeaknessClinicScreen(),
          icon: Icons.healing_outlined,
          selectedIcon: Icons.healing,
          label: 'จุดอ่อน',
        ),
      if (features.isVisible(FieldFeature.achievements))
        const _NavigationEntry(
          screen: AchievementsScreen(),
          icon: Icons.emoji_events_outlined,
          selectedIcon: Icons.emoji_events,
          label: 'รางวัล',
        ),
      const _NavigationEntry(
        screen: ProfileSettingsScreen(),
        icon: Icons.person_outlined,
        selectedIcon: Icons.person,
        label: 'โปรไฟล์',
      ),
    ];
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
      if (status.backends != RuntimeAvailability.ready) 'AI/Voice',
    ];
    return '${unavailable.join(' · ')} ยังไม่พร้อม — การเรียนในเครื่องยังใช้ได้';
  }

  String _buildIdentity(BuildContext context) {
    final buildInfo = AppDependenciesScope.maybeOf(context)?.buildInfo;
    if (buildInfo == null) return '';
    return '${buildInfo.version} · ${buildInfo.buildId}';
  }

  void _pushDestination(String name, Widget destination) {
    _scaffoldKey.currentState?.closeDrawer();
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: (_) => destination),
    );
  }

  @override
  Widget build(BuildContext context) {
    final features = _fieldFeatures(context);
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
            child: IndexedStack(
              index: _currentIndex,
              children: [for (final entry in _entries) entry.screen],
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
              if (features.isVisible(FieldFeature.vocabulary))
                ListTile(
                  leading: const Icon(Icons.menu_book),
                  title: const Text('คลังคำศัพท์'),
                  onTap: () {
                    _scaffoldKey.currentState?.closeDrawer();
                    setState(() {
                      _currentIndex = 0;
                    });
                  },
                ),
              if (features.isVisible(FieldFeature.shop))
                ListTile(
                  leading: const Icon(Icons.shopping_bag),
                  title: const Text('ร้านค้า'),
                  onTap: () =>
                      _pushDestination('rewards/shop', const ShopPage()),
                ),
              if (features.isVisible(FieldFeature.objectScanner))
                ListTile(
                  leading: const Icon(Icons.document_scanner_outlined),
                  title: const Text('สแกนวัตถุ'),
                  onTap: () => _pushDestination(
                    'practice/object-scanner',
                    const ObjectScannerScreen(),
                  ),
                ),
              if (features.isVisible(FieldFeature.speechPractice))
                ListTile(
                  leading: const Icon(Icons.mic_none),
                  title: const Text('ฝึกพูดตามเสียง'),
                  onTap: () => _pushDestination(
                    'practice/shadowing',
                    const ShadowingChallengeScreen(),
                  ),
                ),
              if (features.isVisible(FieldFeature.ghostDuel))
                ListTile(
                  leading: const Icon(Icons.sports_esports_outlined),
                  title: const Text('ดวลกับสถิติเดิม'),
                  onTap: () => _pushDestination(
                    'learning/ghost-duel',
                    const GhostShadowDuelScreen(),
                  ),
                ),
              if (features.isVisible(FieldFeature.aiTutor)) ...[
                ListTile(
                  leading: const Icon(Icons.chat_bubble_outline),
                  title: const Text('AI Tutor'),
                  onTap: () =>
                      _pushDestination('gemini/tutor', const AiTutorScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.key_outlined),
                  title: const Text('ตั้งค่า Gemini BYOK'),
                  onTap: () => _pushDestination(
                    'gemini/settings',
                    const GeminiSettingsScreen(),
                  ),
                ),
              ],
              if (features.isVisible(FieldFeature.export))
                ListTile(
                  leading: const Icon(Icons.file_download_outlined),
                  title: const Text('ส่งออกข้อมูล'),
                  onTap: () => _pushDestination(
                    'export/center',
                    const ExportCenterScreen(),
                  ),
                ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('ตั้งค่า'),
                onTap: () =>
                    _pushDestination('settings', const SettingScreen()),
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
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        destinations: [
          for (final entry in _entries)
            NavigationDestination(
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
    required this.screen,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  final Widget screen;
  final IconData icon;
  final IconData selectedIcon;
  final String label;
}
