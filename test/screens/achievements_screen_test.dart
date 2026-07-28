import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  testWidgets('disabled economy shows only device-local practice messaging', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AchievementsScreen(coins: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ความสำเร็จการฝึก (เฉพาะอุปกรณ์นี้)'), findsOneWidget);
    expect(
      find.text('ความคืบหน้าการฝึกเฉพาะอุปกรณ์นี้ • ใช้จ่ายไม่ได้'),
      findsOneWidget,
    );
    expect(find.textContaining('250'), findsNothing);
    expect(find.textContaining('300'), findsNothing);
    expect(find.textContaining('เหรียญ'), findsNothing);
    expect(find.textContaining('รางวัล'), findsNothing);
    expect(find.textContaining('ร้านค้า'), findsNothing);
    expect(find.text('นักเรียนต่อเนื่อง 3 วัน'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag), findsNothing);
  });
}
