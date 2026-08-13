import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/runtime/production_feature_gate.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/screens/mastery_dashboard_screen.dart';
import 'package:vocab_learning_app/screens/main_navigation_screen.dart';
import 'package:vocab_learning_app/screens/ai_tutor_settings_screen.dart';
import 'package:vocab_learning_app/screens/choose_mode_screen.dart';
import 'package:vocab_learning_app/screens/profile_settings_screen.dart';
import 'package:vocab_learning_app/screens/weakness_clinic_screen.dart';

void main() {
  testWidgets(
    'all-enabled composition renders six destinations and switches tabs',
    (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationScreen(
            featureRegistry: BuildFeatureRegistry.allEnabled(),
          ),
        ),
      );
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
          featureRegistry: BuildFeatureRegistry.fieldDefaults(),
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

  testWidgets('only the selected indexed destination keeps tickers active', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFeatureRegistry.allEnabled(),
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.byKey(const ValueKey<String>('home/mastery')));
    await tester.pump();

    final masteryContext = tester.element(find.byType(MasteryDashboardScreen));
    expect(TickerMode.valuesOf(masteryContext).enabled, isTrue);
    await tester.tap(find.byKey(const ValueKey<String>('home/vocabulary')));
    await tester.pump();
    expect(TickerMode.valuesOf(masteryContext).enabled, isFalse);
  });

  testWidgets('live emergency-off rebuilds mounted navigation', (
    WidgetTester tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(
      MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NavigationDestination), findsNWidgets(6));

    registry.emergencyOff(Feature.weakness);
    await tester.pump();

    expect(find.byType(NavigationDestination), findsNWidgets(5));
  });

  testWidgets(
    'removing an earlier entry preserves the selected feature and State',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      final selectedState = tester.state(find.byType(WeaknessClinicScreen));

      registry.emergencyOff(Feature.vocabulary);
      await tester.pump();

      expect(find.byType(WeaknessClinicScreen), findsOneWidget);
      expect(
        tester.state(find.byType(WeaknessClinicScreen)),
        same(selectedState),
      );
    },
  );

  testWidgets(
    'disabling the selected entry removes its destination but gates its view',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(3));
      await tester.pumpAndSettle();
      expect(find.byType(WeaknessClinicScreen), findsOneWidget);

      registry.emergencyOff(Feature.weakness);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.byType(WeaknessClinicScreen), findsNothing);
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    },
  );

  testWidgets(
    'disabling every selected Learning capability shows unavailable only',
    (tester) async {
      final registry = RuntimeFeatureRegistry(
        const BuildFeatureRegistry.allEnabled(),
      );
      await tester.pumpWidget(
        MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byType(NavigationDestination).at(1));
      await tester.pumpAndSettle();
      expect(find.byType(ChooseModeScreen), findsOneWidget);

      registry.emergencyOff(Feature.quiz);
      registry.emergencyOff(Feature.srs);
      registry.emergencyOff(Feature.reading);
      await tester.pump();

      expect(find.byType(NavigationDestination), findsNWidgets(5));
      expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
      expect(find.text('Associative Reading'), findsNothing);
      expect(find.text('Word Scramble'), findsNothing);
    },
  );

  testWidgets(
    'missing or all-hidden registries keep a one-entry Profile shell',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: MainNavigationScreen()));
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);

      await tester.pumpWidget(
        const MaterialApp(
          home: MainNavigationScreen(
            featureRegistry: BuildFeatureRegistry(<Feature, FeatureState>{}),
          ),
        ),
      );
      await tester.pump();

      expect(tester.takeException(), isNull);
      expect(find.byType(NavigationBar), findsNothing);
      expect(find.byType(ProfileSettingsScreen), findsOneWidget);
      expect(find.byType(ChooseModeScreen), findsNothing);
    },
  );

  testWidgets('one-entry fallback can leave a retained unavailable view', (
    tester,
  ) async {
    final registry = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.allEnabled(),
    );
    await tester.pumpWidget(
      MaterialApp(home: MainNavigationScreen(featureRegistry: registry)),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byType(NavigationDestination).at(3));
    await tester.pumpAndSettle();
    for (final feature in <Feature>[
      Feature.vocabulary,
      Feature.quiz,
      Feature.srs,
      Feature.reading,
      Feature.mastery,
      Feature.weakness,
      Feature.achievements,
    ]) {
      registry.emergencyOff(feature);
    }
    await tester.pump();

    expect(find.byType(ProductionFeatureUnavailable), findsOneWidget);
    final profileFallback = find.byKey(
      const ValueKey<String>('profile-fallback-destination'),
    );
    expect(profileFallback, findsOneWidget);

    await tester.tap(profileFallback);
    await tester.pump();
    expect(find.byType(ProfileSettingsScreen), findsOneWidget);
    expect(find.byType(ProductionFeatureUnavailable), findsNothing);
  });

  testWidgets('AI settings drawer route uses provider-neutral screen', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: MainNavigationScreen(
          featureRegistry: BuildFeatureRegistry.fieldDefaults(),
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
