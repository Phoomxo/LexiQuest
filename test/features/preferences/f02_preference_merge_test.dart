import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/preferences/application/learner_preferences_use_cases.dart';
import 'package:vocab_learning_app/features/preferences/data/drift_learner_preferences_repository.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences.dart';
import 'package:vocab_learning_app/features/preferences/domain/learner_preferences_repository.dart';

void main() {
  for (final holdHome in [true, false]) {
    test(
      'F02 concurrent independent preferences merge, holdHome=$holdHome',
      () async {
        final db = AppDatabase(NativeDatabase.memory());
        addTearDown(db.close);
        final owners = DriftLocalOwnerRepository(
          db,
          generateId: () => 'a',
          nowUtc: () => DateTime.utc(2026),
        );
        final repo = DriftLearnerPreferencesRepository(db);
        final held = _HeldRead(repo);
        LearnerPreferencesUseCases use(LearnerPreferencesRepository r) =>
            LearnerPreferencesUseCases(
              repository: r,
              owners: owners,
              nowUtc: () => DateTime.utc(2026),
            );
        final ordinary = use(repo);
        final delayed = use(held);
        final baseline = await ordinary.read();
        await ordinary.saveDisplayPreferences(
          expectedOwnerId: baseline.ownerId,
          themeMode: LearnerThemePreference.dark,
          motionMode: LearnerMotionPreference.reduced,
        );
        final display = (await ordinary.read()).display;
        Future<LearnerPreferences> home(LearnerPreferencesUseCases u) =>
            u.saveHomeExperience(
              expectedOwnerId: baseline.ownerId,
              homeExperience: HomeExperience.adventure,
            );
        Future<LearnerPreferences> semantic(LearnerPreferencesUseCases u) =>
            u.save(
              goal: LearnerPreferenceGoal.examPreparation,
              availableMinutesPerDay: 45,
              activityPreference: LearnerActivityPreference.quiz,
            );
        final pending = holdHome ? home(delayed) : semantic(delayed);
        await held.entered.future;
        final first = await (holdHome ? semantic(ordinary) : home(ordinary));
        held.release.complete();
        final last = await pending;
        expect(last.homeExperience, HomeExperience.adventure);
        expect(last.goal, LearnerPreferenceGoal.examPreparation);
        expect(last.availableMinutesPerDay, 45);
        expect(last.activityPreference, LearnerActivityPreference.quiz);
        expect(last.updatedAtUtc.isAfter(first.updatedAtUtc), isTrue);
        expect(last.display, display);
        final intents = await db.select(db.outboxOperations).get();
        expect(intents.where((r) => r.state == 'pending'), hasLength(1));
        expect(intents.where((r) => r.state == 'superseded'), hasLength(1));
        expect(await db.select(db.experimentAssignments).get(), isEmpty);
      },
    );
  }
}

class _HeldRead implements LearnerPreferencesRepository {
  _HeldRead(this.delegate);
  final LearnerPreferencesRepository delegate;
  final entered = Completer<void>();
  final release = Completer<void>();
  @override
  Future<LearnerPreferences> read(String ownerId) async {
    final value = await delegate.read(ownerId);
    if (!entered.isCompleted) {
      entered.complete();
      await release.future;
    }
    return value;
  }

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) => delegate.save(
    preferences,
    scope: scope,
    mutationAllowed: mutationAllowed,
  );
  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) => delegate.saveDisplayPreferences(
    ownerId,
    display,
    mutationAllowed: mutationAllowed,
  );
}
