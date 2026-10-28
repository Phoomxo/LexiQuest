import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'RegisterFormScreen.dart';

class OTPScreen extends StatefulWidget {
  final String email;
  const OTPScreen({super.key, required this.email});

  @override
  _OTPScreenState createState() => _OTPScreenState();
}

class _OTPScreenState extends State<OTPScreen> {
  final AuthService _authService = AuthService();
  bool _isLoading = false;

  /// ✅ ตรวจสอบว่าอีเมลได้รับการยืนยันแล้วหรือไม่
  Future<void> _checkEmailVerified() async {
    setState(() => _isLoading = true);

    try {
      bool isVerified = await _authService.isEmailVerified();

      if (isVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('✅ อีเมลได้รับการยืนยันแล้ว!')),
        );

        // 👉 ไปที่หน้ากรอกข้อมูลสมัครสมาชิก
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => RegisterFormScreen(email: widget.email)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('⚠ กรุณายืนยันอีเมลก่อน')),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ตรวจสอบอีเมลล้มเหลว: $e')),
      );
    } finally {
      setState(() => _isLoading = false);
    }
  }

  /// ✅ ให้ Firebase ส่งอีเมลยืนยันใหม่
  Future<void> _resendVerificationEmail() async {
    try {
      await _authService.sendEmailVerification(widget.email, "defaultPassword123");
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('📩 ส่งอีเมลยืนยันใหม่แล้ว!')),
      );
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('❌ ไม่สามารถส่งอีเมลยืนยันใหม่: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              elevation: 5,
              color: Colors.white.withOpacity(0.9),
              child: Padding(
                padding: const EdgeInsets.all(25.0),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.email, size: 80, color: Colors.deepPurple),
                    const SizedBox(height: 15),
                    Text(
                      'ยืนยันอีเมลของคุณ',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.deepPurple.shade700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 15),
                    Text(
                      '📩 เราได้ส่งอีเมลยืนยันไปที่:\n${widget.email}',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontSize: 16),
                    ),
                    const SizedBox(height: 15),
                    const Text(
                      '✉ กรุณาตรวจสอบอีเมลของคุณและกดยืนยัน',
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),

                    _isLoading
                        ? const CircularProgressIndicator()
                        : ElevatedButton.icon(
                            onPressed: _checkEmailVerified,
                            icon: const Icon(Icons.check_circle, color: Colors.white),
                            label: const Text(
                              '✅ ฉันได้ยืนยันแล้ว',
                              style: TextStyle(fontSize: 16, color: Colors.white),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.green,
                              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 50),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                    const SizedBox(height: 10),
                    TextButton.icon(
                      onPressed: _resendVerificationEmail,
                      icon: const Icon(Icons.refresh, color: Colors.deepPurple),
                      label: const Text('🔄 ส่งอีเมลยืนยันใหม่'),
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
