import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';

void main() {
  group('OTPScreen Widget Tests', () {
    testWidgets('renders OTP screen elements cleanly', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(home: OTPScreen(email: 'test@example.com')),
      );

      expect(find.text('ยืนยันอีเมลของคุณ'), findsOneWidget);
      expect(find.textContaining('test@example.com'), findsOneWidget);
      expect(find.text('✅ ฉันได้ยืนยันแล้ว'), findsOneWidget);
      expect(find.text('🔄 ส่งอีเมลยืนยันใหม่'), findsOneWidget);
    });

    testWidgets(
      'tapping check verification when unverified shows snackbar warning',
      (WidgetTester tester) async {
        await tester.pumpWidget(
          const MaterialApp(home: OTPScreen(email: 'test@example.com')),
        );

        final checkButton = find.text('✅ ฉันได้ยืนยันแล้ว');
        await tester.tap(checkButton);
        await tester.pumpAndSettle();

        expect(find.text('⚠ กรุณายืนยันอีเมลก่อน'), findsOneWidget);
      },
    );
  });
}
