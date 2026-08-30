import 'learner_preferences.dart';

typedef LearnerPreferencesMutationGuard = bool Function();

final class LearnerPreferencesMutationUnavailable implements Exception {
  const LearnerPreferencesMutationUnavailable();
}

abstract interface class LearnerPreferencesRepository {
  Future<LearnerPreferences> read(String ownerId);

  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  });
}
