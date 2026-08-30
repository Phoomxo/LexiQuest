import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';
import 'package:vocab_learning_app/screens/learning_preference_quiz_screen.dart';

void main() {
  testWidgets('f35 quiz edits goal time and activity without style labels', (
    tester,
  ) async {
    final repository = _Preferences();
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('learning style'), findsNothing);
    expect(find.textContaining('personality'), findsNothing);
    final goal = tester.widget<DropdownButtonFormField<LearnerPreferenceGoal>>(
      find.byKey(const ValueKey<String>('learning-preferences/goal')),
    );
    goal.onChanged!(LearnerPreferenceGoal.examPreparation);
    final activity = tester
        .widget<DropdownButtonFormField<LearnerActivityPreference>>(
          find.byKey(
            const ValueKey<String>('learning-preferences/activity-preference'),
          ),
        );
    activity.onChanged!(LearnerActivityPreference.quiz);
    await tester.enterText(
      find.byKey(
        const ValueKey<String>('learning-preferences/available-minutes'),
      ),
      '45',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
    );
    await tester.pumpAndSettle();

    expect(repository.saveCount, 1);
    expect(repository.current.goal, LearnerPreferenceGoal.examPreparation);
    expect(repository.current.availableMinutesPerDay, 45);
    expect(
      repository.current.activityPreference,
      LearnerActivityPreference.quiz,
    );
    expect(find.text('Preferences saved.'), findsOneWidget);
  });

  testWidgets('f35 quiz rejects invalid time without mutating authority', (
    tester,
  ) async {
    final repository = _Preferences();
    final useCases = LearnerPreferencesUseCases(
      repository: repository,
      owners: _Owner(),
      nowUtc: () => DateTime.utc(2026, 8, 30, 12),
    );
    await tester.pumpWidget(
      MaterialApp(home: LearningPreferenceQuizScreen(useCases: useCases)),
    );
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(
        const ValueKey<String>('learning-preferences/available-minutes'),
      ),
      '0',
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
    );
    await tester.pump();

    expect(repository.saveCount, 0);
    expect(find.text('Enter between 1 and 240 minutes.'), findsOneWidget);
  });

  testWidgets('f35 general constructor fails closed without dependency', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: LearningPreferenceQuizScreen()),
    );
    await tester.pumpAndSettle();

    expect(find.text('Learning preferences are unavailable.'), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('learning-preferences/save')),
      findsNothing,
    );
  });
}

final class _Preferences implements LearnerPreferencesRepository {
  LearnerPreferences current = LearnerPreferences.defaults(
    ownerId: 'local:preferences-screen',
    updatedAtUtc: DateTime.utc(2026, 8, 30),
  );
  int saveCount = 0;

  @override
  Future<LearnerPreferences> read(String ownerId) async => current;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = preferences;
    saveCount += 1;
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    if (!(mutationAllowed?.call() ?? true)) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    current = LearnerPreferences(
      ownerId: current.ownerId,
      preferenceVersion: current.preferenceVersion,
      goal: current.goal,
      availableMinutesPerDay: current.availableMinutesPerDay,
      activityPreference: current.activityPreference,
      updatedAtUtc: current.updatedAtUtc,
      display: display,
    );
  }
}

final class _Owner implements LocalOwnerRepository {
  @override
  Future<LocalOwner> getOrCreateActiveOwner() async => LocalOwner(
    id: 'local:preferences-screen',
    createdAtUtc: DateTime.utc(2026, 8, 30),
  );

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      getOrCreateActiveOwner();
}
