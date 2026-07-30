import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/otp_screen.dart';

void main() {
  testWidgets('verification screen fails closed without an account provider', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: OTPScreen(email: 'test@example.com')),
    );

    expect(find.text('ยืนยันอีเมล'), findsOneWidget);
    expect(find.textContaining('test@example.com'), findsOneWidget);
    await tester.tap(find.text('ฉันยืนยันอีเมลแล้ว'));
    await tester.pump();
    expect(find.text('ระบบยืนยันอีเมลไม่พร้อมใช้งาน'), findsOneWidget);
  });
}
