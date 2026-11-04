import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/learning_profile/application/learning_profile_use_cases.dart';
import 'package:vocab_learning_app/features/learning_profile/data/drift_learning_profile_repository.dart';
import 'package:vocab_learning_app/features/learning_profile/presentation/learning_profile_editor_screen.dart';

import '../test/screens/achievements_screen_test.dart' as achievements;
import '../test/screens/appearance_settings_screen_test.dart' as appearance;
import '../test/screens/avatar_equipment_screen_test.dart' as avatar;
import '../test/screens/content_report_sheet_test.dart' as reports;
import '../test/screens/definition_quiz_screen_test.dart' as definition;
import '../test/screens/focus_timer_screen_test.dart' as focus;
import '../test/screens/learning_calendar_screen_test.dart' as calendar;
import '../test/screens/learning_history_screen_test.dart' as history;
import '../test/screens/learning_time_entries_test.dart' as learning_time;
import '../test/screens/quiz_srs_learning_time_test.dart' as timed_quiz;
import '../test/screens/review_center_screen_test.dart' as review;
import '../test/features/motivation/avatar_companion_flow_test.dart'
    as companion;
import '../test/features/motivation/quest_screen_test.dart' as quest;

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  group('Achievements', achievements.main);
  group('Appearance', appearance.main);
  group('Avatar', avatar.main);
  group('Reports', reports.main);
  group('Definition', definition.main);
  group('Focus', focus.main);
  group('Calendar', calendar.main);
  group('History', history.main);
  group('Learning time', learning_time.main);
  group('Timed quiz', timed_quiz.main);
  group('Review', review.main);
  group('Companion', companion.main);
  group('Quest', quest.main);

  testWidgets('Android profile goal survives SQLite reopen', (tester) async {
    final directory = (await tester.runAsync(
      () => Directory.systemTemp.createTemp('lexiquest-android-profile-'),
    ))!;
    final file = File('${directory.path}/profile.sqlite');
    var database = AppDatabase(NativeDatabase(file));
    await tester.runAsync(
      () => database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'synthetic-android-profile-owner',
              createdAtUtcMs: 1,
              isActive: const Value(true),
            ),
          ),
    );
    LearningProfileUseCases createProfile() => LearningProfileUseCases(
      repository: DriftLearningProfileRepository(
        database: database,
        ownerWrites: DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => DateTime.utc(2026, 11, 1),
        ),
      ),
      nowUtc: () => DateTime.utc(2026, 11, 1),
    );
    var profile = createProfile();
    try {
      await tester.pumpWidget(
        MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
      );
      final goal = find.byKey(const ValueKey('learning-profile-goal'));
      await _until(tester, goal);
      await tester.ensureVisible(goal);
      await tester.pumpAndSettle();
      expect(goal.hitTestable(), findsOneWidget);
      await tester.tap(goal);
      await tester.pumpAndSettle();
      await tester.enterText(goal, 'Synthetic Android goal');
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();
      final travel = find.widgetWithText(FilterChip, 'การเดินทาง');
      await tester.ensureVisible(travel);
      await tester.pumpAndSettle();
      expect(travel.hitTestable(), findsOneWidget);
      await tester.tap(travel);
      await tester.pumpAndSettle();
      expect(tester.widget<FilterChip>(travel).selected, isTrue);
      final save = find.byKey(const ValueKey('learning-profile-save'));
      await tester.ensureVisible(save);
      await tester.pumpAndSettle();
      expect(save.hitTestable(), findsOneWidget);
      await tester.tap(save);
      await _until(tester, find.text('บันทึกแผนการเรียนแล้ว'));
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await profile.dispose();
        await database.close();
      });
      database = AppDatabase(NativeDatabase(file));
      profile = createProfile();
      await tester.pumpWidget(
        MaterialApp(home: LearningProfileEditorScreen(profile: profile)),
      );
      await _until(tester, find.text('Synthetic Android goal'));
      expect(tester.widget<FilterChip>(travel).selected, isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await profile.dispose();
        await database.close();
        if (await file.exists()) await file.delete();
        await directory.delete();
      });
    }
  });
}

Future<void> _until(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 10)),
    );
    await tester.pump();
    if (finder.evaluate().isNotEmpty) return;
  }
  expect(finder, findsWidgets);
}
