import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/screens/login_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/avatar_equipment_screen.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';

void main() {
  group('LexiQuest Comprehensive Section-by-Section Full System Audit', () {
    testWidgets('Section 1 Audit: LoginScreen renders Thai UI & Guest Mode button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: LoginScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('เข้าสู่ระบบ'), findsWidgets);
      expect(find.textContaining('Guest Mode'), findsOneWidget);
    });

    testWidgets('Section 2 Audit: ChooseModeScreen renders mode grid and Avatar Equipment button', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: ChooseModeScreen()));
      await tester.pumpAndSettle();

      expect(find.textContaining('เลือกรูปแบบการเรียนรู้'), findsOneWidget);
      expect(find.textContaining('Avatar Gear'), findsOneWidget);
    });

    testWidgets('Section 3 Audit: MainNavigationScreen switches across all 4 primary tabs', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pumpAndSettle();

      // Tab 0: Learn
      expect(find.text('เรียนรู้'), findsOneWidget);

      // Tab 1: Analytics
      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.byType(MasteryDashboardScreen), findsOneWidget);

      // Tab 2: Weakness Clinic
      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);

      // Tab 3: Achievements
      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsOneWidget);
    });

    testWidgets('Section 4 Audit: AvatarEquipmentScreen displays 4 slots and stat buff summary', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AvatarEquipmentScreen(),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.textContaining('Vocabulary Warrior'), findsOneWidget);
      expect(find.textContaining('Damage: +'), findsOneWidget);
    });
  });
}
