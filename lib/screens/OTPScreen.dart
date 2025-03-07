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

  /// ✅ **ตรวจสอบว่าอีเมลได้รับการยืนยันแล้วหรือไม่**
  Future<void> _checkEmailVerified() async {
    setState(() => _isLoading = true);

    try {
      bool isVerified = await _authService.isEmailVerified();

      if (isVerified) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('✅ อีเมลได้รับการยืนยันแล้ว!')),
        );

        // 👉 ไปที่หน้ากรอกข้อมูลสมัครสมาชิก
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => RegisterFormScreen(email: widget.email)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('⚠ กรุณายืนยันอีเมลก่อน')),
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

  /// ✅ **ให้ Firebase ส่งอีเมลยืนยันใหม่**
  Future<void> _resendVerificationEmail() async {
    try {
      await _authService.sendEmailVerification(widget.email, "defaultPassword123");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('📩 ส่งอีเมลยืนยันใหม่แล้ว!')),
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
      appBar: AppBar(title: Text('ยืนยันอีเมล')),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Text(
              '📩 เราได้ส่งอีเมลยืนยันไปที่: \n${widget.email}',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 15),
            Text(
              '✉ กรุณาตรวจสอบอีเมลของคุณและกดยืนยัน',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            _isLoading
                ? CircularProgressIndicator()
                : ElevatedButton(
                    onPressed: _checkEmailVerified,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 50),
                      backgroundColor: Colors.green,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      '✅ ฉันได้ยืนยันแล้ว',
                      style: TextStyle(fontSize: 16, color: Colors.white),
                    ),
                  ),
            const SizedBox(height: 10),
            TextButton(
              onPressed: _resendVerificationEmail,
              child: const Text('🔄 ส่งอีเมลยืนยันใหม่'),
            ),
          ],
        ),
      ),
    );
  }
}
