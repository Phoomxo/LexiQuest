import 'package:flutter_test/flutter_test.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:vocab_learning_app/services/auth_service.dart';

void main() {
  group('AuthService getErrorMessage Tests', () {
    test('returns Thai translation for email-already-in-use', () {
      final exception = FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'The email address is already in use by another account.',
      );
      final msg = AuthService.getErrorMessage(exception);
      expect(msg, contains('อีเมลนี้ถูกใช้งานในระบบแล้ว'));
    });

    test('returns Thai translation for invalid-email', () {
      final exception = FirebaseAuthException(
        code: 'invalid-email',
        message: 'The email address is badly formatted.',
      );
      final msg = AuthService.getErrorMessage(exception);
      expect(msg, contains('รูปแบบอีเมลไม่ถูกต้อง'));
    });

    test('returns Thai translation for weak-password', () {
      final exception = FirebaseAuthException(
        code: 'weak-password',
        message: 'The password must be 6 characters long or more.',
      );
      final msg = AuthService.getErrorMessage(exception);
      expect(msg, contains('รหัสผ่านไม่ปลอดภัย'));
    });

    test('strips Exception prefix for standard Exception', () {
      final exception = Exception('ข้อความทดสอบ');
      final msg = AuthService.getErrorMessage(exception);
      expect(msg, equals('ข้อความทดสอบ'));
    });
  });
}
