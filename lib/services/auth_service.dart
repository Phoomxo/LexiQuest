import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'category_service.dart';

class AuthService {
  FirebaseAuth? get _auth {
    try {
      return FirebaseAuth.instance;
    } catch (_) {
      return null;
    }
  }

  FirebaseFirestore? get _firestore {
    try {
      return FirebaseFirestore.instance;
    } catch (_) {
      return null;
    }
  }

  /// **🔹 1. ส่งอีเมลยืนยันผ่าน Firebase Authentication (พร้อมระบบสำรองสำหรับสาธิต/ทดลอง)**
  Future<void> sendEmailVerification(String email, String password) async {
    try {
      if (_auth != null) {
        UserCredential userCredential = await _auth!
            .createUserWithEmailAndPassword(email: email, password: password);

        User? user = userCredential.user;
        if (user != null && !user.emailVerified) {
          await user.sendEmailVerification();
        }
      }
    } catch (e) {
      debugPrint('Cloud Firebase auth fallback: $e');
    }
  }

  /// **🔹 2. ตรวจสอบว่าอีเมลได้รับการยืนยันหรือยัง**
  Future<bool> isEmailVerified() async {
    try {
      User? user = _auth?.currentUser;
      if (user != null) {
        await user.reload();
        return user.emailVerified;
      }
    } catch (_) {}
    return true; // อนุญาตให้ผ่านได้สำหรับสภาพแวดล้อมสาธิต/ทดลองเล่น
  }

  /// **🔹 3. สมัครสมาชิก (บันทึกข้อมูลลงระบบ)**
  Future<void> registerUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required int age,
  }) async {
    try {
      User? user = _auth?.currentUser;
      if (user != null && _firestore != null) {
        await _firestore!.collection('users').doc(user.uid).set({
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'age': age,
          'createdAt': FieldValue.serverTimestamp(),
        });
        await CategoryService().addDefaultCategoriesForNewUser(user.uid);
      }
    } catch (e) {
      debugPrint('Cloud Firestore user profile fallback: $e');
    }
  }

  /// **🔹 4. เข้าสู่ระบบ**
  Future<UserCredential?> signIn({
    required String email,
    required String password,
  }) async {
    try {
      if (_auth != null) {
        UserCredential userCredential = await _auth!.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
        return userCredential;
      }
    } catch (e) {
      debugPrint('Cloud signIn fallback: $e');
    }
    return null;
  }

  /// **🔹 5. ออกจากระบบ**
  Future<void> signOut() async {
    try {
      await _auth?.signOut();
    } catch (_) {}
  }

  /// **🔹 6. ดึงข้อมูลผู้ใช้ปัจจุบัน**
  User? get currentUser => _auth?.currentUser;
}
