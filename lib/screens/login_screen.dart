import 'package:flutter/material.dart';
import 'register_screen.dart';
import '../services/auth_service.dart';
import '../services/guest_session_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'otp_screen.dart'; // เพิ่มไฟล์ OTP Screen

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, this.guestSessionService});

  final GuestSessionService? guestSessionService;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();
  AuthService? _authServiceInstance;

  AuthService get _authService {
    _authServiceInstance ??= AuthService();
    return _authServiceInstance!;
  }

  GuestSessionService? _guestSessionServiceInstance;

  GuestSessionService get _guestSessionService {
    final injected = widget.guestSessionService;
    if (injected != null) return injected;
    _guestSessionServiceInstance ??= FirebaseGuestSessionService.production();
    return _guestSessionServiceInstance!;
  }

  bool _isLoading = false;
  bool _isGuestLoading = false;

  bool _isValidEmail(String email) {
    final RegExp regex = RegExp(
      r"^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$",
    );
    return regex.hasMatch(email);
  }

  Future<void> _login() async {
    setState(() => _isLoading = true);

    try {
      String email = _emailController.text.trim();
      String password = _passwordController.text.trim();

      if (!_isValidEmail(email)) {
        throw FirebaseAuthException(
          code: 'invalid-email',
          message: 'รูปแบบอีเมลไม่ถูกต้อง',
        );
      }
      if (password.isEmpty) {
        throw FirebaseAuthException(
          code: 'empty-password',
          message: 'กรุณากรอกรหัสผ่าน',
        );
      }

      // เข้าสู่ระบบ
      UserCredential? userCredential = await _authService.signIn(
        email: email,
        password: password,
      );

      User? user = userCredential?.user;
      if (user != null && !user.emailVerified) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('กรุณายืนยันอีเมลก่อนเข้าสู่ระบบ')),
        );
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => OTPScreen(email: email)),
        );
        return;
      }

      // อนุญาตให้เข้าสู่ระบบ
      if (!mounted) return;
      Navigator.pushReplacementNamed(context, '/home');
    } on FirebaseAuthException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(AuthService.getErrorMessage(e))),
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
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 10),
              Expanded(child: Text(AuthService.getErrorMessage(e))),
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
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _startGuestSession() async {
    if (_isGuestLoading) return;
    setState(() => _isGuestLoading = true);

    final GuestSessionResult result;
    try {
      result = await _guestSessionService.start();
    } catch (_) {
      if (!mounted) return;
      _showGuestFailureSnackBar(GuestSessionFailure.unknown);
      setState(() => _isGuestLoading = false);
      return;
    }

    if (!mounted) return;
    switch (result) {
      case GuestSessionStarted():
        Navigator.pushReplacementNamed(context, '/home');
      case GuestSessionFailed(:final reason):
        _showGuestFailureSnackBar(reason);
        setState(() => _isGuestLoading = false);
    }
  }

  void _showGuestFailureSnackBar(GuestSessionFailure reason) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(_guestFailureMessage(reason)),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _guestFailureMessage(GuestSessionFailure reason) {
    return switch (reason) {
      GuestSessionFailure.firebaseUnavailable =>
        'ระบบยืนยันตัวตนยังไม่พร้อม กรุณาลองใหม่ภายหลัง',
      GuestSessionFailure.providerDisabled =>
        'โหมดผู้เยี่ยมชมยังไม่เปิดใช้งาน กรุณาเข้าสู่ระบบด้วยอีเมล',
      GuestSessionFailure.network =>
        'เชื่อมต่อเครือข่ายไม่ได้ กรุณาตรวจสอบอินเทอร์เน็ตแล้วลองใหม่',
      GuestSessionFailure.unknown =>
        'เริ่มโหมดผู้เยี่ยมชมไม่ได้ กรุณาลองใหม่หรือเข้าสู่ระบบด้วยอีเมล',
    };
  }

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
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
                      '🔑 เข้าสู่ระบบ (Login)',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      'LexiQuest: แอปพลิเคชันเรียนรู้คำศัพท์ภาษาอังกฤษ',
                      style: TextStyle(fontSize: 13, color: Colors.grey),
                    ),
                    const SizedBox(height: 20),
                    TextField(
                      controller: _emailController,
                      decoration: const InputDecoration(
                        labelText: 'อีเมล (Email)',
                        hintText: 'กรอกอีเมลของคุณ',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.email),
                      ),
                    ),
                    const SizedBox(height: 15),
                    TextField(
                      controller: _passwordController,
                      decoration: const InputDecoration(
                        labelText: 'รหัสผ่าน (Password)',
                        hintText: 'กรอกรหัสผ่าน',
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
                                vertical: 14,
                                horizontal: 50,
                              ),
                              backgroundColor: Colors.deepPurple,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            child: const Text(
                              'เข้าสู่ระบบ (Login)',
                              style: TextStyle(
                                fontSize: 18,
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                    const SizedBox(height: 10),
                    OutlinedButton.icon(
                      key: const ValueKey<String>('guest-mode-button'),
                      onPressed: _isGuestLoading ? null : _startGuestSession,
                      icon: _isGuestLoading
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.play_arrow, color: Colors.green),
                      label: const Text(
                        '🚀 ทดลองใช้งานทันที (Guest Mode)',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: Colors.green,
                        ),
                      ),
                    ),
                    TextButton(
                      onPressed: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const RegisterScreen(),
                          ),
                        );
                      },
                      child: const Text(
                        "ยังไม่มีบัญชีใช่ไหม? สมัครสมาชิกที่นี่ (Register)",
                      ),
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
