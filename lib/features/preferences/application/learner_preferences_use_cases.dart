import '../../identity/domain/local_owner_repository.dart';
import '../domain/learner_preferences.dart';
import '../domain/learner_preferences_repository.dart';

typedef LearnerPreferencesUtcNow = DateTime Function();

final class LearnerPreferencesUseCases {
  const LearnerPreferencesUseCases({
    required this.repository,
    required this.owners,
    required this.nowUtc,
  });

  final LearnerPreferencesRepository repository;
  final LocalOwnerRepository owners;
  final LearnerPreferencesUtcNow nowUtc;

  Future<LearnerPreferences> read() async {
    final owner = await owners.getOrCreateActiveOwner();
    return repository.read(owner.id);
  }

  Future<LearnerPreferences> save({
    String? expectedOwnerId,
    required LearnerPreferenceGoal goal,
    required int availableMinutesPerDay,
    required LearnerActivityPreference activityPreference,
    HomeExperience? homeExperience,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (expectedOwnerId != null && owner.id != expectedOwnerId) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    final current = await repository.read(owner.id);
    final candidate = LearnerPreferences(
      ownerId: owner.id,
      preferenceVersion: 2,
      goal: goal,
      availableMinutesPerDay: availableMinutesPerDay,
      activityPreference: activityPreference,
      homeExperience: homeExperience ?? current.homeExperience,
      updatedAtUtc: nowUtc(),
    );
    await repository.save(candidate, mutationAllowed: mutationAllowed);
    return repository.read(owner.id);
  }

  Future<LearnerPreferences> saveHomeExperience({
    required String expectedOwnerId,
    required HomeExperience homeExperience,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (owner.id != expectedOwnerId) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    final current = await repository.read(owner.id);
    if (current.homeExperience == homeExperience &&
        current.preferenceVersion == 2) {
      return current;
    }
    await repository.save(
      LearnerPreferences(
        ownerId: owner.id,
        preferenceVersion: 2,
        goal: current.goal,
        availableMinutesPerDay: current.availableMinutesPerDay,
        activityPreference: current.activityPreference,
        homeExperience: homeExperience,
        updatedAtUtc: nowUtc(),
        display: current.display,
      ),
      mutationAllowed: mutationAllowed,
    );
    return repository.read(owner.id);
  }

  Future<LearnerPreferences> saveDisplayPreferences({
    required String expectedOwnerId,
    required LearnerThemePreference themeMode,
    required LearnerMotionPreference motionMode,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    if (owner.id != expectedOwnerId) {
      throw const LearnerPreferencesMutationUnavailable();
    }
    final current = await repository.read(owner.id);
    if (current.display.themeMode == themeMode &&
        current.display.motionMode == motionMode) {
      return current;
    }
    await repository.saveDisplayPreferences(
      owner.id,
      LearnerDisplayPreferences(
        themeMode: themeMode,
        motionMode: motionMode,
        updatedAtUtc: nowUtc(),
      ),
      mutationAllowed: mutationAllowed,
    );
    return repository.read(owner.id);
  }

  Future<EffectiveLearnerPreferences> readEffective({
    LearnerPreferenceProtocolClamp? protocolClamp,
  }) async {
    final saved = await read();
    if (protocolClamp == null) {
      return EffectiveLearnerPreferences(
        saved: saved,
        availableMinutesPerDay: saved.availableMinutesPerDay,
        activityPreference: saved.activityPreference,
        wasClamped: false,
      );
    }
    if (protocolClamp.maximumAvailableMinutesPerDay < 1 ||
        protocolClamp.maximumAvailableMinutesPerDay > 240) {
      throw ArgumentError.value(
        protocolClamp.maximumAvailableMinutesPerDay,
        'maximumAvailableMinutesPerDay',
      );
    }
    final effectiveMinutes =
        saved.availableMinutesPerDay >
            protocolClamp.maximumAvailableMinutesPerDay
        ? protocolClamp.maximumAvailableMinutesPerDay
        : saved.availableMinutesPerDay;
    return EffectiveLearnerPreferences(
      saved: saved,
      availableMinutesPerDay: effectiveMinutes,
      activityPreference: protocolClamp.activityPreference,
      wasClamped:
          effectiveMinutes != saved.availableMinutesPerDay ||
          protocolClamp.activityPreference != saved.activityPreference,
    );
  }
}
