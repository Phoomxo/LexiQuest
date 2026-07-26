import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'runtime/app_bootstrap.dart';
import 'runtime/app_dependencies.dart';
import 'screens/categories_page.dart';
import 'screens/home.dart';
import 'screens/shop_page.dart';
import 'screens/setting_screen.dart';
import 'screens/login_screen.dart';
import 'screens/register_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dependencies = await AppBootstrap.production().initialize();
  runApp(MyApp(dependencies: dependencies));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key, required this.dependencies});

  final AppDependencies dependencies;

  @override
  Widget build(BuildContext context) {
    return AppDependenciesScope(
      dependencies: dependencies,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        title: 'LexiQuest - AI Vocab Learning',
        theme: ThemeData(
          useMaterial3: true,
          colorScheme: ColorScheme.fromSeed(
            seedColor: Colors.deepPurple,
            primary: Colors.deepPurple,
            secondary: Colors.indigo,
            tertiary: Colors.teal,
          ),
          textTheme: GoogleFonts.outfitTextTheme(ThemeData.light().textTheme),
          cardTheme: CardThemeData(
            elevation: 4,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
          appBarTheme: const AppBarTheme(
            centerTitle: true,
            elevation: 0,
            backgroundColor: Colors.transparent,
          ),
        ),
        initialRoute: '/login',
        routes: {
          '/login': (context) => LoginScreen(
            guestSessionService: AppDependenciesScope.of(
              context,
            ).guestSessionService,
          ),
          '/register': (context) => const RegisterScreen(),
          '/home': (context) => const MainNavigation(),
        },
      ),
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  State<MainNavigation> createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 1;

  final List<Widget> _pages = [
    CategoriesPage(),
    Home(),
    ShopPage(),
    SettingScreen(),
  ];

  void _onItemTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: _pages[_selectedIndex],
      bottomNavigationBar: NavigationBar(
        backgroundColor: Colors.white,
        indicatorColor: Colors.blueAccent.shade100,
        selectedIndex: _selectedIndex,
        onDestinationSelected: _onItemTapped,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.menu_book),
            selectedIcon: Icon(Icons.menu_book, color: Colors.blueAccent),
            label: 'หมวดหมู่',
          ),
          NavigationDestination(
            icon: Icon(Icons.school),
            selectedIcon: Icon(Icons.school, color: Colors.blueAccent),
            label: 'เรียนรู้',
          ),
          NavigationDestination(
            icon: Icon(Icons.shopping_bag),
            selectedIcon: Icon(Icons.shopping_bag, color: Colors.blueAccent),
            label: 'ร้านค้า',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings),
            selectedIcon: Icon(Icons.settings, color: Colors.blueAccent),
            label: 'ตั้งค่า',
          ),
        ],
      ),
    );
  }
}
