import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// ฟังก์ชันสำหรับสมัครสมาชิกใหม่
  Future<void> registerUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required int age,
  }) async {
    try {
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      final String uid = userCredential.user!.uid;

      final newUser = AppUser(
        uid: uid,
        firstName: firstName,
        lastName: lastName,
        age: age,
        email: email,
      );

      // บันทึกข้อมูลผู้ใช้ใหม่ใน Firestore พร้อมแต้มเริ่มต้น
      await _firestore.collection('users').doc(uid).set({
        ...newUser.toMap(),
        'points': 0, // เพิ่มแต้มเริ่มต้นเป็น 0
      });
    } catch (e) {
      throw Exception('Failed to register user: $e');
    }
  }

  /// ฟังก์ชันสำหรับเข้าสู่ระบบ
  Future<void> signIn({required String email, required String password}) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  /// ฟังก์ชันสำหรับออกจากระบบ
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  /// ฟังก์ชันสำหรับดึงผู้ใช้ปัจจุบัน
  User? get currentUser => _auth.currentUser;
}
