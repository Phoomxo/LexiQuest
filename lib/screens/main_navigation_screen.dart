import 'package:flutter/material.dart';

import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import '../runtime/field_feature.dart';
import '../runtime/field_feature_registry.dart';
import '../navigation/app_routes.dart';
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

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _entries = _buildEntries(_fieldFeatures(context));
    _currentIndex = _currentIndex.clamp(0, _entries.length - 1);
  }

  FieldFeatureRegistry _fieldFeatures(BuildContext context) {
    return widget.featureRegistry ??
        AppDependenciesScope.maybeOf(context)?.fieldFeatures ??
        const BuildFieldFeatureRegistry.allEnabled();
  }

  List<_NavigationEntry> _buildEntries(FieldFeatureRegistry features) {
    return [
      if (features.isVisible(FieldFeature.quiz) ||
          features.isVisible(FieldFeature.srs) ||
          features.isVisible(FieldFeature.reading))
        _NavigationEntry(
          screen: ChooseModeScreen(
            featureRegistry: features,
            onOpenMenu: _openDrawer,
          ),
          icon: Icons.school_outlined,
          selectedIcon: Icons.school,
          label: 'เรียน',
        ),
      if (features.isVisible(FieldFeature.vocabulary))
        _NavigationEntry(
          screen: CategoriesPage(onOpenMenu: _openDrawer),
          icon: Icons.menu_book_outlined,
          selectedIcon: Icons.menu_book,
          label: 'คำศัพท์',
        ),
      if (features.isVisible(FieldFeature.mastery))
        _NavigationEntry(
          screen: MasteryDashboardScreen(
            featureRegistry: features,
            onOpenMenu: _openDrawer,
          ),
          icon: Icons.analytics_outlined,
          selectedIcon: Icons.analytics,
          label: 'ก้าวหน้า',
        ),
      _NavigationEntry(
        screen: ProfileSettingsScreen(onOpenMenu: _openDrawer),
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
      if (status.firebase != RuntimeAvailability.ready) 'ระบบบัญชี',
      if (status.supabase != RuntimeAvailability.ready) 'ระบบข้อมูลออนไลน์',
      if (status.backends != RuntimeAvailability.ready)
        'ผู้ช่วย AI และระบบเสียง',
    ];
    return '${unavailable.join(' · ')} ยังไม่พร้อม — การเรียนในเครื่องยังใช้ได้';
  }

  String _buildIdentity(BuildContext context) {
    final buildInfo = AppDependenciesScope.maybeOf(context)?.buildInfo;
    if (buildInfo == null) return '';
    return 'เวอร์ชัน ${buildInfo.version}';
  }

  void _pushDestination(String name, Widget destination) {
    _scaffoldKey.currentState?.closeDrawer();
    AppNavigator.pushPage<void>(
      context,
      AppPage<void>(name: name, builder: (_) => destination),
    );
  }

  void _openDrawer() => _scaffoldKey.currentState?.openDrawer();

  @override
  Widget build(BuildContext context) {
    final features = _fieldFeatures(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showNavigation = _entries.length >= 2;
        final useRail =
            showNavigation &&
            constraints.maxWidth >= 600 &&
            constraints.maxHeight >= 480;
        final content = IndexedStack(
          index: _currentIndex,
          children: [for (final entry in _entries) entry.screen],
        );

        return Scaffold(
          key: _scaffoldKey,
          body: Stack(
            children: [
              Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: 1200,
                    minHeight: constraints.maxHeight,
                  ),
                  child: Row(
                    children: [
                      if (useRail) ...[
                        SafeArea(
                          child: NavigationRail(
                            selectedIndex: _currentIndex,
                            onDestinationSelected: _selectDestination,
                            labelType: NavigationRailLabelType.all,
                            destinations: [
                              for (final entry in _entries)
                                NavigationRailDestination(
                                  icon: Icon(entry.icon),
                                  selectedIcon: Icon(entry.selectedIcon),
                                  label: Text(entry.label),
                                ),
                            ],
                          ),
                        ),
                        const VerticalDivider(width: 1),
                      ],
                      Expanded(child: content),
                    ],
                  ),
                ),
              ),
            ],
          ),
          drawer: Drawer(
            child: SafeArea(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
                  DrawerHeader(
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                    ),
                    child: Semantics(
                      header: true,
                      child: Text(
                        'LexiQuest',
                        style: TextStyle(
                          color: Theme.of(
                            context,
                          ).colorScheme.onPrimaryContainer,
                          fontSize: 22,
                        ),
                      ),
                    ),
                  ),
                  if (features.isVisible(FieldFeature.vocabulary))
                    ListTile(
                      leading: const Icon(Icons.menu_book),
                      title: const Text('คำศัพท์'),
                      onTap: () {
                        _scaffoldKey.currentState?.closeDrawer();
                        setState(() {
                          _currentIndex = _entries.indexWhere(
                            (entry) => entry.screen is CategoriesPage,
                          );
                        });
                      },
                    ),
                  if (features.isVisible(FieldFeature.shop))
                    ListTile(
                      leading: const Icon(Icons.shopping_bag),
                      title: const Text('ร้านค้ารางวัล'),
                      onTap: () =>
                          _pushDestination('rewards/shop', const ShopPage()),
                    ),
                  if (features.isVisible(FieldFeature.objectScanner))
                    _featureTile(
                      features: features,
                      feature: FieldFeature.objectScanner,
                      icon: Icons.document_scanner_outlined,
                      title: 'สแกนวัตถุ',
                      limitedReason:
                          'ต้องอนุญาตกล้อง และอาจต้องดาวน์โหลดโมเดลก่อนใช้งาน',
                      onTap: () => _pushDestination(
                        'practice/object-scanner',
                        const ObjectScannerScreen(),
                      ),
                      onSetup: () => _pushDestination(
                        'practice/object-scanner',
                        const ObjectScannerScreen(),
                      ),
                    ),
                  if (features.isVisible(FieldFeature.speechPractice))
                    _featureTile(
                      features: features,
                      feature: FieldFeature.speechPractice,
                      icon: Icons.mic_none,
                      title: 'ฝึกพูดตามเสียง',
                      limitedReason:
                          'ต้องอนุญาตไมโครโฟน และใช้ระบบรู้จำเสียงของอุปกรณ์',
                      onTap: () => _pushDestination(
                        'practice/shadowing',
                        const ShadowingChallengeScreen(),
                      ),
                      onSetup: () => _pushDestination(
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
                    _featureTile(
                      features: features,
                      feature: FieldFeature.aiTutor,
                      icon: Icons.chat_bubble_outline,
                      title: 'ผู้ช่วยฝึกภาษาอังกฤษ',
                      limitedReason:
                          'ต้องเชื่อมต่อผู้ช่วย AI และยินยอมก่อนใช้งาน',
                      onTap: () => _pushDestination(
                        'gemini/tutor',
                        const AiTutorScreen(),
                      ),
                      onSetup: () => _pushDestination(
                        'gemini/settings',
                        const GeminiSettingsScreen(),
                      ),
                      setupLabel: 'เชื่อมต่อผู้ช่วย AI',
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
          bottomNavigationBar: useRail || !showNavigation
              ? null
              : NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: _selectDestination,
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
      },
    );
  }

  void _selectDestination(int index) {
    setState(() {
      _currentIndex = index;
    });
  }

  Widget _featureTile({
    required FieldFeatureRegistry features,
    required FieldFeature feature,
    required IconData icon,
    required String title,
    required String limitedReason,
    required VoidCallback onTap,
    required VoidCallback onSetup,
    String setupLabel = 'เตรียมใช้',
  }) {
    final limited = features.stateOf(feature) == FieldFeatureState.limited;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ListTile(
          minVerticalPadding: limited ? 12 : null,
          leading: Icon(icon),
          title: Text(title),
          subtitle: limited ? Text('ทดลองใช้ · $limitedReason') : null,
          isThreeLine: limited,
          onTap: onTap,
        ),
        if (limited)
          Padding(
            padding: const EdgeInsetsDirectional.only(
              start: 72,
              end: 16,
              bottom: 4,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(onPressed: onSetup, child: Text(setupLabel)),
            ),
          ),
      ],
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
