import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/adventure/application/adventure_presentation_preferences.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';

void main() {
  test(
    'maps the durable owner preference without granting presentation',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final preferences = LearnerPreferencesUseCases(
        repository: DriftLearnerPreferencesRepository(database),
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'owner',
          nowUtc: () => DateTime.utc(2026, 9, 4),
        ),
        nowUtc: () => DateTime.utc(2026, 9, 4, 8),
      );
      final adapter = LearnerAdventurePresentationPreferences(preferences);

      expect(
        await adapter.readForOwner('local:owner'),
        TodayExperiencePresentation.standard,
      );
      await adapter.saveForOwner(
        'local:owner',
        TodayExperiencePresentation.adventure,
      );
      expect(
        await adapter.readForOwner('local:owner'),
        TodayExperiencePresentation.adventure,
      );
      expect(
        (await preferences.read()).homeExperience,
        HomeExperience.adventure,
      );

      expect(
        await adapter.readForOwner('local:different-owner'),
        TodayExperiencePresentation.standard,
      );
      await expectLater(
        adapter.saveForOwner(
          'local:different-owner',
          TodayExperiencePresentation.adventure,
        ),
        throwsA(isA<LearnerPreferencesMutationUnavailable>()),
      );
    },
  );
}
