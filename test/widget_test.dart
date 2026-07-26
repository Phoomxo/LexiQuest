import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    // Build LoginScreen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Verify the Login title appears
    expect(find.textContaining('เข้าสู่ระบบ'), findsWidgets);

    // Verify Email and Password TextFields are present
    expect(find.widgetWithText(TextField, 'อีเมล (Email)'), findsOneWidget);
    expect(
      find.widgetWithText(TextField, 'รหัสผ่าน (Password)'),
      findsOneWidget,
    );

    // Verify the Login button
    expect(
      find.widgetWithText(ElevatedButton, 'เข้าสู่ระบบ (Login)'),
      findsOneWidget,
    );

    // Verify the registration prompt
    expect(find.textContaining('สมัครสมาชิก'), findsOneWidget);
  });
}
