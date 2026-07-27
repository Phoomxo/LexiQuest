import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'select_wallpaper_screen.dart'; // นำเข้าไฟล์หน้าจอเลือกวอลเปเปอร์

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  Map<String, dynamic>? _profileData;
  IconData _selectedIcon = Icons.account_circle;

  firebase_auth.User? get _currentUser => _auth.currentUser;

  @override
  void initState() {
    super.initState();
    if (_currentUser != null) {
      _fetchUserProfile();
    }
  }

  Future<void> _fetchUserProfile() async {
    try {
      final doc = await _firestore
          .collection('users')
          .doc(_currentUser!.uid)
          .get();
      if (doc.exists) {
        if (!mounted) return;
        setState(() {
          _profileData = doc.data();
        });
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch profile data: $e')),
      );
    }
  }

  void _logout() async {
    await _auth.signOut();
    if (!mounted) return;
    Navigator.pushReplacementNamed(context, '/login');
  }

  void _showIconPicker() {
    showModalBottomSheet(
      context: context,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.0)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(16.0),
          child: GridView.count(
            crossAxisCount: 4,
            padding: const EdgeInsets.all(10),
            children:
                [
                  Icons.emoji_emotions,
                  Icons.emoji_events,
                  Icons.emoji_food_beverage,
                  Icons.emoji_nature,
                  Icons.emoji_objects,
                  Icons.emoji_people,
                  Icons.auto_awesome,
                  Icons.auto_fix_high,
                  Icons.auto_stories,
                  Icons.local_florist,
                  Icons.star,
                  Icons.wb_sunny,
                  Icons.nightlight,
                  Icons.self_improvement,
                  Icons.volunteer_activism,
                  Icons.favorite,
                  Icons.mood,
                  Icons.mood_bad,
                  Icons.cake,
                  Icons.party_mode,
                  Icons.sports_esports,
                  Icons.music_note,
                  Icons.library_music,
                  Icons.piano,
                  Icons.headset,
                  Icons.pets,
                  Icons.toys,
                  Icons.beach_access,
                  Icons.snowboarding,
                  Icons.skateboarding,
                  Icons.airplanemode_active,
                  Icons.directions_boat,
                  Icons.directions_bus,
                  Icons.directions_car,
                  Icons.train,
                  Icons.fireplace,
                  Icons.celebration,
                  Icons.festival,
                  Icons.brightness_5,
                  Icons.auto_awesome_mosaic,
                ].map((iconData) {
                  return IconButton(
                    icon: CircleAvatar(
                      radius: 30,
                      backgroundColor:
                          Colors.primaries[iconData.codePoint %
                              Colors.primaries.length],
                      child: Icon(iconData, size: 40, color: Colors.white),
                    ),
                    onPressed: () {
                      setState(() {
                        _selectedIcon = iconData;
                      });
                      Navigator.pop(context);
                    },
                  );
                }).toList(),
          ),
        );
      },
    );
  }

  Widget _buildProfileItem(String title, String value) {
    return Card(
      elevation: 3,
      margin: EdgeInsets.symmetric(vertical: 8.0, horizontal: 12.0),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ListTile(
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        trailing: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Settings',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 22),
        ),
        backgroundColor: Colors.deepPurpleAccent,
        actions: [
          IconButton(icon: const Icon(Icons.logout), onPressed: _logout),
        ],
      ),
      body: _profileData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _showIconPicker,
                    child: CircleAvatar(
                      radius: 60,
                      backgroundColor:
                          Colors.primaries[_selectedIcon.codePoint %
                              Colors.primaries.length],
                      child: Icon(_selectedIcon, size: 80, color: Colors.white),
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildProfileItem(
                    'First Name',
                    _profileData?['first_name'] ?? '',
                  ),
                  _buildProfileItem(
                    'Last Name',
                    _profileData?['last_name'] ?? '',
                  ),
                  _buildProfileItem(
                    'Age',
                    _profileData?['age']?.toString() ?? '',
                  ),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => SelectWallpaperScreen(),
                        ),
                      );
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.deepPurpleAccent,
                      padding: EdgeInsets.symmetric(
                        horizontal: 32,
                        vertical: 12,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    child: const Text(
                      'เปลี่ยนวอลเปเปอร์',
                      style: TextStyle(color: Colors.white, fontSize: 18),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
