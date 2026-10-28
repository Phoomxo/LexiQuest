import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/achievements_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets(
    'all-enabled composition renders six destinations and switches tabs',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pumpAndSettle();

      expect(find.byType(NavigationDestination), findsNWidgets(6));

      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('Mastery & Analytics Dashboard'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.byType(AchievementsScreen), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(5));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('field composition hides unverified destinations', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry.fieldDefaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(2));
    expect(find.byIcon(Icons.analytics_outlined), findsNothing);
    expect(find.byIcon(Icons.healing_outlined), findsNothing);
    expect(find.byIcon(Icons.emoji_events_outlined), findsNothing);
  });
}
