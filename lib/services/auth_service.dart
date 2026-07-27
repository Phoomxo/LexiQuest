import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../models/user_model.dart';
import 'category_service.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// **🔹 1. ส่งอีเมลยืนยันผ่าน Firebase Authentication**
  Future<void> sendEmailVerification(String email, String password) async {
    try {
      // สมัครสมาชิกชั่วคราวเพื่อให้ Firebase ส่งอีเมลยืนยัน
      UserCredential userCredential = await _auth.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );

      User? user = userCredential.user;
      if (user != null && !user.emailVerified) {
        await user.sendEmailVerification();
      }
    } catch (e) {
      throw Exception('Failed to send verification email: $e');
    }
  }

  /// **🔹 2. ตรวจสอบว่าอีเมลได้รับการยืนยันหรือยัง**
  Future<bool> isEmailVerified() async {
    User? user = _auth.currentUser;
    await user?.reload(); // รีเฟรชข้อมูลบัญชี
    return user?.emailVerified ?? false;
  }

  /// **🔹 3. สมัครสมาชิก (ต้องยืนยัน OTP ก่อน)**
  Future<void> registerUser({
    required String email,
    required String password,
    required String firstName,
    required String lastName,
    required int age,
  }) async {
    try {
      User? user = _auth.currentUser;
      if (user != null && user.emailVerified) {
        // บันทึกข้อมูลผู้ใช้ลง Firestore หลังจากยืนยันอีเมล
        await _firestore.collection('users').doc(user.uid).set({
          'first_name': firstName,
          'last_name': lastName,
          'email': email,
          'age': age,
          'createdAt': FieldValue.serverTimestamp(),
        });

        // ✅ เพิ่มหมวดหมู่เริ่มต้นให้ผู้ใช้ใหม่
await CategoryService().addDefaultCategoriesForNewUser(user.uid);

      } else {
        throw Exception('กรุณายืนยันอีเมลก่อนสมัครสมาชิก');
      }
    } catch (e) {
      throw Exception('Failed to register user: $e');
    }
  }

  /// **🔹 4. เข้าสู่ระบบ**
  Future<UserCredential> signIn({required String email, required String password}) async {
    try {
      UserCredential userCredential = await _auth.signInWithEmailAndPassword(
        email: email,
        password: password,
      );

      // ตรวจสอบว่าอีเมลได้รับการยืนยันหรือยัง
      if (!userCredential.user!.emailVerified) {
        throw Exception('กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ');
      }

      return userCredential;
    } catch (e) {
      throw Exception('Failed to sign in: $e');
    }
  }

  /// **🔹 5. ออกจากระบบ**
  Future<void> signOut() async {
    try {
      await _auth.signOut();
    } catch (e) {
      throw Exception('Failed to sign out: $e');
    }
  }

  /// **🔹 6. ดึงข้อมูลผู้ใช้ปัจจุบัน**
  User? get currentUser => _auth.currentUser;
}