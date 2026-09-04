import '../../preferences/application/learner_preferences_use_cases.dart';
import '../../preferences/domain/learner_preferences.dart';
import '../domain/adventure_entry.dart';
import 'adventure_entry_use_cases.dart';

final class LearnerAdventurePresentationPreferences
    implements AdventurePresentationPreferenceReader {
  const LearnerAdventurePresentationPreferences(this.preferences);

  final LearnerPreferencesUseCases preferences;

  @override
  Future<TodayExperiencePresentation?> readForOwner(String ownerId) async {
    final saved = await preferences.read();
    if (saved.ownerId != ownerId) return TodayExperiencePresentation.standard;
    return switch (saved.homeExperience) {
      HomeExperience.standard => TodayExperiencePresentation.standard,
      HomeExperience.adventure => TodayExperiencePresentation.adventure,
    };
  }

  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) async {
    await preferences.saveHomeExperience(
      expectedOwnerId: ownerId,
      homeExperience: switch (presentation) {
        TodayExperiencePresentation.standard => HomeExperience.standard,
        TodayExperiencePresentation.adventure => HomeExperience.adventure,
      },
    );
  }
}
