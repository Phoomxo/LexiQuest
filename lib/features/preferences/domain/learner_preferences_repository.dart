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

  /// Persists only device-local display fields in the same owner row.
  ///
  /// This deliberately does not create or revise the f35 cloud outbox intent.
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  });
}
