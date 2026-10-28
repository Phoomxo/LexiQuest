import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    // Build LoginScreen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    // Verify the AppBar title appears.
    expect(find.text('เข้าสู่ระบบ LexiQuest'), findsOneWidget);

    // Verify Email and Password TextFields are present.
    expect(find.widgetWithText(TextField, 'อีเมล'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'รหัสผ่าน'), findsOneWidget);

    // Verify the Login FilledButton.
    expect(find.widgetWithText(FilledButton, 'เข้าสู่ระบบ'), findsOneWidget);

    // Verify the Guest OutlinedButton.
    expect(
      find.widgetWithText(OutlinedButton, 'เรียนแบบ Guest'),
      findsOneWidget,
    );

    // Verify the registration prompt TextButton.
    expect(find.widgetWithText(TextButton, 'สร้างบัญชีใหม่'), findsOneWidget);
  });
}
