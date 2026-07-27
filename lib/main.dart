import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'screens/CategoriesPage.dart';
import 'screens/Home.dart';
import 'screens/Shop_Page.dart';
import 'screens/SettingScreen.dart';
import 'screens/LoginScreen.dart';
import 'screens/RegisterScreen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase
  await Firebase.initializeApp();

  // Initialize Supabase
  await Supabase.initialize(
    url: 'https://anyiuoqnuimtjlbjhwuf.supabase.co',
    anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFueWl1b3FudWltdGpsYmpod3VmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzY1ODMyMzIsImV4cCI6MjA1MjE1OTIzMn0.sHp532XD1L_Xr5X9eiRMCZqpgV2LA5RwQoOw3df6gDg',
  );

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'แอพฝึกคำศัพท์',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        brightness: Brightness.light,
      ),
      initialRoute: '/login',
      routes: {
        '/login': (context) => const LoginScreen(),
        '/register': (context) => const RegisterScreen(),
        '/home': (context) => const MainNavigation(),
      },
    );
  }
}

class MainNavigation extends StatefulWidget {
  const MainNavigation({super.key});

  @override
  _MainNavigationState createState() => _MainNavigationState();
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
