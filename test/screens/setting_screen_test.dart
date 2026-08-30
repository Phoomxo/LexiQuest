import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/display_preferences_controller.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/screens/setting_screen.dart';

void main() {
  testWidgets('f39 settings persist theme and reduced motion controls', (
    tester,
  ) async {
    final database = AppDatabase(NativeDatabase.memory());
    addTearDown(database.close);
    final controller = DisplayPreferencesController(
      LearnerPreferencesUseCases(
        repository: DriftLearnerPreferencesRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'settings-owner',
          nowUtc: () => DateTime.utc(2026, 8, 30),
        ),
        nowUtc: () => DateTime.utc(2026, 8, 30, 12),
      ),
    );
    addTearDown(controller.dispose);
    await controller.initialize();

    await tester.pumpWidget(
      MaterialApp(home: SettingScreen(displayPreferences: controller)),
    );

    expect(find.byKey(const ValueKey<String>('theme-system')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('theme-light')), findsOneWidget);
    expect(find.byKey(const ValueKey<String>('theme-dark')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('reduced-motion-switch')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('theme-dark')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('reduced-motion-switch')),
    );
    await tester.pumpAndSettle();

    expect(controller.themeMode, ThemeMode.dark);
    expect(controller.reducedMotionEnabled, isTrue);
    final row = await database
        .customSelect('SELECT theme_mode, motion_mode FROM learner_preferences')
        .getSingle();
    expect(row.read<String>('theme_mode'), 'dark');
    expect(row.read<String>('motion_mode'), 'reduced');
  });

  testWidgets('f39 unavailable display authority fails closed', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: SettingScreen()));

    expect(find.byKey(const ValueKey<String>('theme-system')), findsNothing);
    expect(
      find.byKey(const ValueKey<String>('reduced-motion-switch')),
      findsNothing,
    );
  });
}
