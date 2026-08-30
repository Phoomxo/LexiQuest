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
    required LearnerPreferenceGoal goal,
    required int availableMinutesPerDay,
    required LearnerActivityPreference activityPreference,
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    final owner = await owners.getOrCreateActiveOwner();
    final candidate = LearnerPreferences(
      ownerId: owner.id,
      preferenceVersion: 1,
      goal: goal,
      availableMinutesPerDay: availableMinutesPerDay,
      activityPreference: activityPreference,
      updatedAtUtc: nowUtc(),
    );
    await repository.save(candidate, mutationAllowed: mutationAllowed);
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
