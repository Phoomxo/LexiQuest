import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/vocab_list_screen.dart';
import 'screens/add_vocab_screen.dart';
import 'screens/Home.dart';
import 'screens/SettingScreen.dart'; // เพิ่มการ import SettingScreen

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      theme: ThemeData(primarySwatch: Colors.deepPurple),
      home: MainNavigation(),
    );
  }
}

class MainNavigation extends StatefulWidget {
  @override
  _MainNavigationState createState() => _MainNavigationState();
}

class _MainNavigationState extends State<MainNavigation> {
  int _selectedIndex = 0;

  final List<Widget> _pages = [
    VocabListScreen(), // หน้ารายการคำศัพท์    
    Home(),            // หน้าหลัก
    AddVocabScreen(),  // หน้าสำหรับเพิ่มคำศัพท์ใหม่
    SettingScreen(),     // หน้า Settings (โปรไฟล์)
    

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
    bottomNavigationBar: BottomNavigationBar(
  items: const <BottomNavigationBarItem>[
    BottomNavigationBarItem(
      icon: Icon(Icons.list),
      label: 'Vocabulary',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.home),
      label: 'Home',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.add),
      label: 'Add Vocab',
    ),
    BottomNavigationBarItem(
      icon: Icon(Icons.settings),
      label: 'Settings',
    ),
  ],
  currentIndex: _selectedIndex,
  selectedItemColor: Colors.deepPurple,
  unselectedItemColor: Colors.grey,
  iconSize: 30, // เพิ่มขนาดไอคอน (ค่าเริ่มต้นคือ 24)
  onTap: _onItemTapped,
),
  );
}
}
