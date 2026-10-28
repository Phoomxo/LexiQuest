import 'package:flutter/material.dart';
import 'RegisterScreen.dart';
import '../services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'OTPScreen.dart'; // เพิ่มไฟล์ OTP Screen

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService();

  bool _isLoading = false;

  bool _isValidEmail(String email) {
    final RegExp regex = RegExp(r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$");
    return regex.hasMatch(email);
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    try {
      String email = _emailController.text.trim();
      String password = _passwordController.text.trim();

      if (!_isValidEmail(email)) {
        throw FirebaseAuthException(code: 'invalid-email', message: 'รูปแบบอีเมลไม่ถูกต้อง');
      }
      if (password.isEmpty) {
        throw FirebaseAuthException(code: 'empty-password', message: 'กรุณากรอกรหัสผ่าน');
      }

      // เข้าสู่ระบบ
      UserCredential userCredential = await _authService.signIn(
        email: email,
        password: password,
      );

      User? user = userCredential.user;
      if (user != null) {
        // ตรวจสอบว่าอีเมลได้รับการยืนยันหรือยัง
        if (!user.emailVerified) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ')),
          );

          // ไปที่หน้ากรอก OTP เพื่อให้ยืนยันอีเมล
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => OTPScreen(email: email),
            ),
          );
          return;
        }

        // อนุญาตให้เข้าสู่ระบบ
        Navigator.pushReplacementNamed(context, '/home');
      }
    } on FirebaseAuthException catch (e) {
      String errorMessage;

      switch (e.code) {
        case 'invalid-email':
          errorMessage = 'รูปแบบอีเมลไม่ถูกต้อง โปรดตรวจสอบอีกครั้ง';
          break;
        case 'empty-password':
          errorMessage = 'กรุณากรอกรหัสผ่าน';
          break;
        case 'user-not-found':
          errorMessage = 'ไม่พบผู้ใช้นี้ กรุณาตรวจสอบอีเมล';
          break;
        case 'wrong-password':
          errorMessage = 'รหัสผ่านไม่ถูกต้อง กรุณาลองใหม่';
          break;
        default:
          errorMessage = 'เกิดข้อผิดพลาด กรุณาลองใหม่อีกครั้ง';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(errorMessage)),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text('เกิดข้อผิดพลาด กรุณาลองใหม่')),
            ],
          ),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
          margin: const EdgeInsets.all(16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: [Colors.deepPurple, Colors.indigo],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Card(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              elevation: 5,
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'Login',
                      style: TextStyle(
                        fontSize: 28,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'Email',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'Password',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.lock),
                      ),
                      obscureText: true,
                    ),
                    const SizedBox(height: 20),
                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton(
                            onPressed: _login,
                            style: ElevatedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                  vertical: 14, horizontal: 50),
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'Login',
                              style: TextStyle(fontSize: 18, color: Colors.white),
                            ),
                          ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(builder: (context) => const RegisterScreen()),
                        );
                      },
                      child: const Text('Don’t have an account? Register here'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}