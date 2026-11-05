import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';

void main() {
  testWidgets('LoginScreen smoke test', (WidgetTester tester) async {
    // Build LoginScreen and trigger a frame.
    await tester.pumpWidget(const MaterialApp(home: LoginScreen()));

    expect(find.text('เริ่มเรียนกับ LexiQuest'), findsOneWidget);
    expect(find.textContaining('เข้าสู่ระบบ'), findsNothing);
    expect(find.byType(TextField), findsNothing);

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
