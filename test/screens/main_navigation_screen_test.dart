import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';

void main() {
  testWidgets(
    'MainNavigationScreen renders 4 tab destinations and switches tabs',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pumpAndSettle();

      expect(find.text('เรียนรู้'), findsOneWidget);
      expect(find.text('สถิติ'), findsOneWidget);
      expect(find.text('จุดอ่อน'), findsOneWidget);
      expect(find.text('รางวัล'), findsOneWidget);

      // Tap Analytics tab (index 1)
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();

      expect(find.text('Mastery & Analytics Dashboard'), findsOneWidget);

      // Tap Weakness tab (index 2)
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();

      expect(
        find.text('คลินิกซ่อมแซมจุดอ่อน (Weakness Clinic)'),
        findsOneWidget,
      );

      // Tap Achievements tab (index 3)
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();

      expect(
        find.text('ตราความสำเร็จ & รางวัล (Achievements)'),
        findsOneWidget,
      );
    },
  );
}
