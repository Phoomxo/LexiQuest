import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  testWidgets('AchievementsScreen renders coin balance and badge cards', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: AchievementsScreen(coins: 300)),
    );
    await tester.pumpAndSettle();

    expect(find.text('ตราความสำเร็จ & รางวัล (Achievements)'), findsOneWidget);
    expect(find.text('300 เหรียญสะสม'), findsOneWidget);
    expect(find.text('นักเรียนต่อเนื่อง 3 วัน'), findsOneWidget);
    expect(find.byIcon(Icons.shopping_bag), findsNothing);
  });
}
