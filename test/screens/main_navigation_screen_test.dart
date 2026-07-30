import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';

void main() {
  testWidgets(
    'all-enabled composition renders six destinations and switches tabs',
    (WidgetTester tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pumpAndSettle();

      expect(
        tester
            .widgetList<NavigationDestination>(
              find.byType(NavigationDestination),
            )
            .map((destination) => destination.label),
        <String>[
          'คลังคำศัพท์',
          'เรียนรู้',
          'สถิติ',
          'จุดอ่อน',
          'รางวัล',
          'โปรไฟล์',
        ],
      );

      await tester.tap(find.byType(NavigationDestination).at(2));
      await tester.pumpAndSettle();
      expect(find.text('ภาพรวมการเรียน'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.text('คลินิกจุดอ่อน'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(4));
      await tester.pumpAndSettle();
      expect(find.textContaining('Achievements'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(5));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('field composition hides every unverified destination', (
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

    expect(
      tester
          .widgetList<NavigationDestination>(find.byType(NavigationDestination))
          .map((destination) => destination.label),
      <String>['คลังคำศัพท์', 'โปรไฟล์'],
    );
    expect(find.text('ร้านค้า'), findsNothing);
    expect(find.text('สถิติ'), findsNothing);
    expect(find.text('จุดอ่อน'), findsNothing);
    expect(find.text('รางวัล'), findsNothing);
  });
}
