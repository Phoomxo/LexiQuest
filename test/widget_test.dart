import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    // Build LoginScreen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Verify the Login title appears
    expect(find.textContaining('เข้าสู่ระบบ'), findsWidgets);

    // Verify Email and Password TextFields are present (Thai-only labels since localization update)
    expect(find.widgetWithText(TextField, 'อีเมล'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'รหัสผ่าน'), findsOneWidget);

    // Verify the Login button (FilledButton since UI refresh)
    expect(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'), findsOneWidget);

    // Verify the registration prompt
    expect(find.textContaining('สร้างบัญชีใหม่'), findsOneWidget);
  });
}
