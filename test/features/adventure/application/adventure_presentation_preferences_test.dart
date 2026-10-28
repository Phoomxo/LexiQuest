import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    hide LocalOwner;
import 'package:vocab_learning_app/features/adventure/application/adventure_presentation_preferences.dart';
import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
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

  test(
    'serializes the same owner across Host lifecycles last-write-wins',
    () async {
      final firstWrite = Completer<void>();
      final repository = _BlockingPreferencesRepository(firstWrite.future);
      final useCases = LearnerPreferencesUseCases(
        repository: repository,
        owners: const _OwnerRepository(),
        nowUtc: () => DateTime.utc(2026, 9, 4, 8),
      );
      final sharedWriter = LearnerAdventurePresentationPreferences(useCases);

      final oldHostWrite = sharedWriter.saveForOwner(
        'owner:one',
        TodayExperiencePresentation.adventure,
      );
      await Future<void>.delayed(Duration.zero);
      final newHostWrite = sharedWriter.saveForOwner(
        'owner:one',
        TodayExperiencePresentation.standard,
      );
      await Future<void>.delayed(Duration.zero);

      expect(repository.started, <HomeExperience>[HomeExperience.adventure]);
      firstWrite.complete();
      await Future.wait(<Future<void>>[oldHostWrite, newHostWrite]);

      expect(repository.started, <HomeExperience>[
        HomeExperience.adventure,
        HomeExperience.standard,
      ]);
      expect(repository.current.homeExperience, HomeExperience.standard);
    },
  );
}

final class _OwnerRepository implements LocalOwnerRepository {
  const _OwnerRepository();

  @override
  Future<LocalOwner> getOrCreateActiveOwner() async =>
      LocalOwner(id: 'owner:one', createdAtUtc: DateTime.utc(2026, 9, 1));

  @override
  Future<LocalOwner> bindFirebaseUid(String ownerId, String firebaseUid) =>
      throw UnimplementedError();
}

final class _BlockingPreferencesRepository
    implements LearnerPreferencesRepository {
  _BlockingPreferencesRepository(this.firstWrite)
    : current = LearnerPreferences.defaults(
        ownerId: 'owner:one',
        updatedAtUtc: DateTime.utc(2026, 9, 1),
      );

  final Future<void> firstWrite;
  LearnerPreferences current;
  final List<HomeExperience> started = <HomeExperience>[];

  @override
  Future<LearnerPreferences> read(String ownerId) async => current;

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    started.add(preferences.homeExperience);
    if (started.length == 1) await firstWrite;
    current = preferences;
  }

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) => throw UnimplementedError();
}
