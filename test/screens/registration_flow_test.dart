import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/register_screen.dart';

void main() {
  testWidgets('registration requires consent and a real account provider', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));

    expect(find.text('สร้างบัญชี'), findsOneWidget);
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('สมัครและส่งอีเมลยืนยัน'), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'student@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await tester.pump();

    expect(find.text('กรุณายอมรับประกาศความเป็นส่วนตัวก่อน'), findsOneWidget);
  });

  testWidgets('registration never reports success without a provider', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: RegisterScreen()));
    await tester.tap(find.byType(Checkbox));
    await tester.enterText(find.byType(TextField).first, 'student@example.com');
    await tester.enterText(find.byType(TextField).last, 'password123');
    await tester.tap(find.text('สมัครและส่งอีเมลยืนยัน'));
    await tester.pump();

    expect(find.text('ระบบบัญชีออนไลน์ไม่พร้อม'), findsOneWidget);
    expect(find.byType(RegisterScreen), findsOneWidget);
  });
}
