import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class UserService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// บันทึกข้อมูลผู้ใช้ใหม่ลงใน Firestore
  Future<void> saveUserData({
    required String uid,
    required String firstName,
    required String lastName,
    required String email,
  }) async {
    try {
      await _firestore.collection('users').doc(uid).set({
        'first_name': firstName,
        'last_name': lastName,
        'email': email,
        'points': 0,
      });
    } catch (e) {
      throw Exception('Failed to save user data: $e');
    }
  }

  /// ดึงข้อมูลผู้ใช้ทั้งหมดจาก Firestore
  Future<AppUser?> getUserData() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('users').doc(user.uid).get();
        if (doc.exists) {
          return AppUser.fromMap(doc.data()!, doc.id);
        }
      }
    } catch (e) {
      throw Exception('Failed to fetch user data: $e');
    }
    return null;
  }

  Future<int> getTotalPointsFromState() async {
    try {
      final user = _auth.currentUser;
      if (user != null) {
        final doc = await _firestore.collection('state').doc(user.uid).get();
        if (doc.exists) {
          return doc.data()!['totalPoints'] ?? 0;
        }
      }
    } catch (e) {
      throw Exception('Failed to fetch total points: $e');
    }
    return 0;
  }
}
