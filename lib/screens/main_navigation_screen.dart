import 'package:flutter/material.dart';
import '../runtime/app_dependencies.dart';
import '../runtime/app_runtime_status.dart';
import 'achievements_screen.dart';
import 'categories_page.dart';
import 'choose_mode_screen.dart';
import 'mastery_dashboard_screen.dart';
import 'profile_settings_screen.dart';
import 'setting_screen.dart';
import 'shop_page.dart';
import 'weakness_clinic_screen.dart';

class MainNavigationScreen extends StatefulWidget {
  final int initialIndex;

  const MainNavigationScreen({super.key, this.initialIndex = 0});

  @override
  State<MainNavigationScreen> createState() => _MainNavigationScreenState();
}

class _MainNavigationScreenState extends State<MainNavigationScreen> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  late int _currentIndex;

  final List<Widget> _screens = const [
    ChooseModeScreen(),
    MasteryDashboardScreen(),
    WeaknessClinicScreen(),
    AchievementsScreen(),
    ProfileSettingsScreen(),
  ];

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex.clamp(0, _screens.length - 1);
  }

  String _runtimeStatusSummary(BuildContext context) {
    final status = AppDependenciesScope.maybeOf(context)?.runtimeStatus;
    if (status == null) {
      return 'โหมดทดสอบ · ระบบอาจไม่พร้อมใช้งาน';
    }
    if (status.isFullyReady) {
      return 'ระบบพร้อมใช้งาน';
    }

    final unavailable = <String>[
      if (status.firebase != RuntimeAvailability.ready) 'Firebase',
      if (status.supabase != RuntimeAvailability.ready) 'Supabase',
      if (status.backends != RuntimeAvailability.ready) 'AI/Voice',
    ];
    return '${unavailable.join(' · ')} ยังไม่พร้อมใช้งาน';
  }

  String _buildIdentity(BuildContext context) {
    final buildInfo = AppDependenciesScope.maybeOf(context)?.buildInfo;
    if (buildInfo == null) return '';
    return '${buildInfo.version} · ${buildInfo.buildId}';
  }

  void _pushLegacyDestination(Widget destination) {
    _scaffoldKey.currentState?.closeDrawer();
    Navigator.of(
      context,
    ).push(MaterialPageRoute<void>(builder: (_) => destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      body: IndexedStack(index: _currentIndex, children: _screens),
      floatingActionButton: FloatingActionButton.small(
        key: const ValueKey<String>('legacy-drawer-button'),
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
              const DrawerHeader(
                decoration: BoxDecoration(color: Colors.deepPurple),
                child: Text(
                  'LexiQuest',
                  style: TextStyle(color: Colors.white, fontSize: 22),
                ),
              ),
              ListTile(
                leading: const Icon(Icons.menu_book),
                title: const Text('คลังหมวดหมู่'),
                onTap: () => _pushLegacyDestination(CategoriesPage()),
              ),
              if (AppDependenciesScope.maybeOf(
                    context,
                  )?.remoteEconomyPolicy.shopAndPurchasesEnabled ??
                  false)
                ListTile(
                  leading: const Icon(Icons.shopping_bag),
                  title: const Text('ร้านค้า'),
                  onTap: () => _pushLegacyDestination(const ShopPage()),
                ),
              ListTile(
                leading: const Icon(Icons.settings),
                title: const Text('ตั้งค่าเดิม'),
                onTap: () => _pushLegacyDestination(const SettingScreen()),
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
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.school_outlined),
            selectedIcon: Icon(Icons.school),
            label: 'เรียนรู้',
          ),
          NavigationDestination(
            icon: Icon(Icons.analytics_outlined),
            selectedIcon: Icon(Icons.analytics),
            label: 'สถิติ',
          ),
          NavigationDestination(
            icon: Icon(Icons.healing_outlined),
            selectedIcon: Icon(Icons.healing),
            label: 'จุดอ่อน',
          ),
          NavigationDestination(
            icon: Icon(Icons.emoji_events_outlined),
            selectedIcon: Icon(Icons.emoji_events),
            label: 'รางวัล',
          ),
          NavigationDestination(
            icon: Icon(Icons.person_outlined),
            selectedIcon: Icon(Icons.person),
            label: 'โปรไฟล์',
          ),
        ],
      ),
    );
  }
}
