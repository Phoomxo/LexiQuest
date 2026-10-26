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

    // A bare screen has no online account provider, so local learning is primary.
    expect(
      find.widgetWithText(FilledButton, 'เริ่มเรียนในเครื่อง'),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('local-mode-notice')),
      findsOneWidget,
    );

    expect(find.textContaining('สร้างบัญชีใหม่'), findsNothing);
  });
}
