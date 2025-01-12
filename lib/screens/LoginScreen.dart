import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/auth_service.dart';
import 'RegisterScreen.dart';
import '../main.dart'; // หรือหน้าหลักของคุณ เช่น Home.dart

class LoginScreen extends StatefulWidget {
  const LoginScreen({Key? key}) : super(key: key);

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  final AuthService _authService = AuthService(); // ประกาศใช้งาน AuthService

  bool _isLoading = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _login() async {
    setState(() {
      _isLoading = true;
    });

    try {
      await _authService.signIn(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      // หลังจากล็อกอินเสร็จ พาไปหน้า Home หรือ Main
      Navigator.pushReplacement(
        context,
         MaterialPageRoute(builder: (context) => MainNavigation()),
        // เปลี่ยนเป็นหน้า Home หรือ MainScreen ตามที่คุณใช้งานจริง
      );
    } on FirebaseAuthException catch (e) {
      // ดัก error จาก FirebaseAuth โดยตรง
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Login Failed: ${e.message}')),
      );
    } catch (e) {
      // ดัก error ทั่วไป
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      setState(() {
        _isLoading = false;
      });
    }
  }

  void _navigateToRegister() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Login'),
      ),

      body: Padding(
        padding: const EdgeInsets.all(16.0),

        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Input Email
            TextField(
              controller: _emailController,
              decoration: const InputDecoration(labelText: 'Email'),
            ),

            // Input Password
            TextField(
              controller: _passwordController,
              decoration: const InputDecoration(labelText: 'Password'),
              obscureText: true,
            ),

            const SizedBox(height: 20),

            // ปุ่ม Login
            _isLoading
                ? const CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _login,
                    child: const Text('Login'),
                  ),

            const SizedBox(height: 20),

            // ปุ่มไป Register
            TextButton(
              onPressed: _navigateToRegister,
              child: const Text(
                "Don't have an account? Register",
                style: TextStyle(color: Colors.blue),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
