import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart' as firebase_auth;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:image_picker/image_picker.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:io';
import 'SelectWallpaperScreen.dart'; // นำเข้าไฟล์หน้าจอเลือกวอลเปเปอร์

class SettingScreen extends StatefulWidget {
  const SettingScreen({super.key});

  @override
  _SettingScreenState createState() => _SettingScreenState();
}

class _SettingScreenState extends State<SettingScreen> {
  final firebase_auth.FirebaseAuth _auth = firebase_auth.FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final SupabaseClient _supabase = Supabase.instance.client;
  Map<String, dynamic>? _profileData;
  File? _profileImage;
  bool isPickingImage = false;

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
      final doc = await _firestore.collection('users').doc(_currentUser!.uid).get();
      if (doc.exists) {
        setState(() {
          _profileData = doc.data();
        });
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to fetch profile data: $e')),
      );
    }
  }

  Future<void> _pickImage() async {
    if (isPickingImage) return;
    isPickingImage = true;

    try {
      final pickedFile = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (pickedFile != null) {
        setState(() {
          _profileImage = File(pickedFile.path);
        });
        _uploadProfileImage();
      }
    } catch (e) {
      if (!mounted) return;

      Future.delayed(Duration.zero, () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('เกิดข้อผิดพลาดในการเลือกภาพ')),
        );
      });
    } finally {
      isPickingImage = false;
    }
  }

  Future<void> _uploadProfileImage() async {
    if (_profileImage == null) return;

    try {
      final String fileName = '${_currentUser!.uid}.jpg';
      await _supabase.storage.from('Pic_User').upload(fileName, _profileImage!);
      final imageUrl = _supabase.storage.from('Pic_User').getPublicUrl(fileName);

      await _firestore.collection('users').doc(_currentUser!.uid).update({'profile_image': imageUrl});

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('อัปโหลดรูปภาพสำเร็จ!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('เกิดข้อผิดพลาดในการอัปโหลดรูปภาพ: $e')),
      );
    }
  }

  void _logout() async {
    await _auth.signOut();
    Navigator.pushReplacementNamed(context, '/login');
  }

  Widget _buildProfileItem(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
          Text(value),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: _profileData == null
          ? const Center(child: CircularProgressIndicator())
          : Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                children: [
                  GestureDetector(
                    onTap: _pickImage,
                    child: CircleAvatar(
                      radius: 50,
                      backgroundImage: _profileImage != null
                          ? FileImage(_profileImage!)
                          : (_profileData?['profile_image'] != null
                              ? NetworkImage(_profileData!['profile_image'])
                              : const AssetImage('assets/profile_placeholder.png'))
                                  as ImageProvider,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildProfileItem('First Name', _profileData?['first_name'] ?? ''),
                  _buildProfileItem('Last Name', _profileData?['last_name'] ?? ''),
                  _buildProfileItem('Age', _profileData?['age']?.toString() ?? ''),
                  const SizedBox(height: 20),
                  ElevatedButton(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(builder: (context) => SelectWallpaperScreen()),
                      );
                    },
                    child: const Text('เปลี่ยนวอลเปเปอร์'),
                  ),
                ],
              ),
            ),
    );
  }
}