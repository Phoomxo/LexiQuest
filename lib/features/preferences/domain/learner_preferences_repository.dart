import 'learner_preferences.dart';

/// Independent fields merge at the repository transaction boundary.
/// Conflicting writes to the same scope use commit order (last commit wins).
enum LearnerPreferencesWriteScope { all, learning, home }

typedef LearnerPreferencesMutationGuard = bool Function();

final class LearnerPreferencesMutationUnavailable implements Exception {
  const LearnerPreferencesMutationUnavailable();
}

abstract interface class LearnerPreferencesRepository {
  Future<LearnerPreferences> read(String ownerId);

  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesWriteScope scope = LearnerPreferencesWriteScope.all,
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
