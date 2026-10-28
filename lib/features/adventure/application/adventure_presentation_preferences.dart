import '../../preferences/application/learner_preferences_use_cases.dart';
import '../../preferences/domain/learner_preferences.dart';
import '../domain/adventure_entry.dart';
import 'adventure_entry_use_cases.dart';

abstract interface class AdventurePresentationPreferenceWriter {
  /// Implementations must serialize writes per owner across Host lifecycles.
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  );
}

final class LearnerAdventurePresentationPreferences
    implements
        AdventurePresentationPreferenceReader,
        AdventurePresentationPreferenceWriter {
  LearnerAdventurePresentationPreferences(this.preferences);

  final LearnerPreferencesUseCases preferences;
  final Map<String, Future<void>> _saveTails = <String, Future<void>>{};

  @override
  Future<TodayExperiencePresentation?> readForOwner(String ownerId) async {
    final saved = await preferences.read();
    if (saved.ownerId != ownerId) return TodayExperiencePresentation.standard;
    return switch (saved.homeExperience) {
      HomeExperience.standard => TodayExperiencePresentation.standard,
      HomeExperience.adventure => TodayExperiencePresentation.adventure,
    };
  }

  @override
  Future<void> saveForOwner(
    String ownerId,
    TodayExperiencePresentation presentation,
  ) {
    final predecessor = _saveTails[ownerId] ?? Future<void>.value();
    late final Future<void> operation;
    operation = predecessor
        .catchError((Object _) {})
        .then<void>(
          (_) => preferences.saveHomeExperience(
            expectedOwnerId: ownerId,
            homeExperience: switch (presentation) {
              TodayExperiencePresentation.standard => HomeExperience.standard,
              TodayExperiencePresentation.adventure => HomeExperience.adventure,
            },
          ),
        )
        .whenComplete(() {
          if (identical(_saveTails[ownerId], operation)) {
            _saveTails.remove(ownerId);
          }
        });
    _saveTails[ownerId] = operation;
    return operation;
  }
}
