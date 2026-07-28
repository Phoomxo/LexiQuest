import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import '../services/local_user_progress_store.dart';
import '../config/remote_economy_policy.dart';
import '../runtime/app_dependencies.dart';
import 'achievements_screen.dart';
import 'avatar_equipment_screen.dart';
import 'select_wallpaper_screen.dart';

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key, this.profileData, this.remoteEconomyPolicy});

  final Map<String, dynamic>? profileData;
  final RemoteEconomyPolicy? remoteEconomyPolicy;

  @override
  State<SettingScreen> createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  firebase_auth.FirebaseAuth? _auth;
  FirebaseFirestore? _firestore;
  Map<String, dynamic>? _profileData;
  IconData _selectedIcon = Icons.account_circle;

  firebase_auth.User? get _currentUser => _auth?.currentUser;

  @override
  void initState() {
    super.initState();
    _auth = _resolveAuth();
    _firestore = _resolveFirestore();
    _profileData = widget.profileData;
    if (_profileData == null && _currentUser != null) {
      _fetchUserProfile();
    }
  }

  firebase_auth.FirebaseAuth? _resolveAuth() {
    try {
      return firebase_auth.FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? _resolveFirestore() {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  Future<void> _fetchUserProfile() async {
    final firestore = _firestore;
    final user = _currentUser;
    if (firestore == null || user == null) return;

    try {
      final doc = await firestore.collection('users').doc(user.uid).get();
      if (doc.exists) {
        if (!mounted) return;
        setState(() {
          _profileData = doc.data();
        });
      }
    } catch (_) {
      // Profile remains unavailable without surfacing provider diagnostics.
    }
  }

  void _logout() async {
    final auth = _auth;
    if (auth == null) return;
    await auth.signOut();
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
    final remoteEconomyEnabled =
        widget.remoteEconomyPolicy ??
        AppDependenciesScope.maybeOf(context)?.remoteEconomyPolicy ??
        const RemoteEconomyPolicy();
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
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    alignment: WrapAlignment.center,
                    children: [
                      if (remoteEconomyEnabled.shopAndPurchasesEnabled)
                        ElevatedButton.icon(
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(
                                builder: (context) => SelectWallpaperScreen(),
                              ),
                            );
                          },
                          icon: const Icon(Icons.wallpaper, size: 18),
                          label: const Text('เปลี่ยนวอลเปเปอร์'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.deepPurpleAccent,
                            foregroundColor: Colors.white,
                          ),
                        ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) =>
                                  const AvatarEquipmentScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.shield, size: 18),
                        label: const Text('อุปกรณ์ Avatar'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.deepPurple.shade700,
                          foregroundColor: Colors.white,
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => const AchievementsScreen(),
                            ),
                          );
                        },
                        icon: const Icon(Icons.emoji_events, size: 18),
                        label: const Text('เหรียญรางวัล'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.amber.shade800,
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  OutlinedButton.icon(
                    onPressed: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await LocalUserProgressStore().clearAll();
                      if (!mounted) return;
                      messenger.showSnackBar(
                        const SnackBar(
                          content: Text(
                            '🧹 เคลียร์ข้อมูลสถิติและฐานข้อมูลเริ่มต้นใหม่ทั้งหมดเรียบร้อยแล้ว!',
                          ),
                          backgroundColor: Colors.green,
                        ),
                      );
                    },
                    icon: const Icon(
                      Icons.cleaning_services,
                      color: Colors.redAccent,
                    ),
                    label: const Text(
                      '🧹 เคลียร์ข้อมูลสถิติเริ่มต้นใหม่ (Reset DB)',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
