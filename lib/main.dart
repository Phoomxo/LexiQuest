import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'screens/vocab_list_screen.dart';
import 'screens/Home.dart';
import 'screens/SettingScreen.dart'; 
import 'screens/Shop_Page.dart'; // เพิ่มการ import ShopPage

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
    ShopPage(),        // เปลี่ยนจาก AddVocabScreen เป็น ShopPage
    SettingScreen(),   // หน้า Settings (โปรไฟล์)
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
            label: 'Vocabulary', // แสดงหน้ารายการคำศัพท์
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.home),
            label: 'Home', // แสดงหน้าหลัก
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.shopping_cart), // ใช้ไอคอนตะกร้าร้านค้า
            label: 'Shop', // เปลี่ยนจาก Add Vocab เป็น Shop
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings),
            label: 'Settings', // แสดงหน้าโปรไฟล์/การตั้งค่า
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
