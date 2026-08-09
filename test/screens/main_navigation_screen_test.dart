import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/field_feature_registry.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
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
      expect(find.text('ความสำเร็จ'), findsOneWidget);

      await tester.tap(find.byType(NavigationDestination).at(5));
      await tester.pumpAndSettle();
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    },
  );

  testWidgets('field composition exposes completed field destinations', (
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
      <String>[
        'คลังคำศัพท์',
        'เรียนรู้',
        'สถิติ',
        'จุดอ่อน',
        'รางวัล',
        'โปรไฟล์',
      ],
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    expect(find.text('ร้านค้า'), findsOneWidget);
    expect(find.text('สแกนวัตถุ'), findsOneWidget);
    expect(find.text('ฝึกพูดตามเสียง'), findsOneWidget);
    expect(find.text('AI Tutor'), findsOneWidget);
  });

  testWidgets('live emergency-off rebuilds mounted navigation', (
    WidgetTester tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    final legacy = FeatureRegistryFieldAdapter(registry);
    addTearDown(legacy.dispose);
    await tester.pumpWidget(
      MaterialApp(home: MainNavigationScreen(featureRegistry: legacy)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(6));

    registry.emergencyOff(Feature.weakness);
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets('AI settings drawer route uses provider-neutral screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFieldFeatureRegistry.fieldDefaults(),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('legacy-drawer-button')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.key_outlined));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    expect(find.byType(AiTutorSettingsScreen), findsOneWidget);
  });
}
