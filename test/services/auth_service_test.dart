import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/services/auth_service.dart';
import 'package:firebase_auth/firebase_auth.dart';

void main() {
  group('AuthService Security & Fail-Closed Tests', () {
    final authService = AuthService();

    test(
      'isEmailVerified returns false when Firebase is uninitialized or user is null (Fail-Closed)',
      () async {
        final isVerified = await authService.isEmailVerified();
        expect(isVerified, isFalse);
      },
    );

    test(
      'resendVerificationEmail throws Exception when no user is logged in',
      () async {
        expect(
          () async => await authService.resendVerificationEmail(),
          throwsA(isA<Exception>()),
        );
      },
    );

    test('getErrorMessage correctly formats FirebaseAuthExceptions', () {
      final ex = FirebaseAuthException(
        code: 'email-already-in-use',
        message: 'Email used',
      );
      expect(
        AuthService.getErrorMessage(ex),
        contains('อีเมลนี้ถูกใช้งานในระบบแล้ว'),
      );

      final invalidEx = FirebaseAuthException(code: 'invalid-email');
      expect(
        AuthService.getErrorMessage(invalidEx),
        contains('รูปแบบอีเมลไม่ถูกต้อง'),
      );
    });
  });
}
