final class LearningFeatureFlags {
  const LearningFeatureFlags({
    this.associativeReadingEnabled = false,
    this.generatedContentEnabled = false,
    this.voiceEnrichmentEnabled = false,
  });

  const LearningFeatureFlags.fromEnvironment()
    : associativeReadingEnabled = const bool.fromEnvironment(
        'LEXIQUEST_ASSOCIATIVE_READING_ENABLED',
        defaultValue: false,
      ),
      generatedContentEnabled = const bool.fromEnvironment(
        'LEXIQUEST_GENERATED_READING_ENABLED',
        defaultValue: false,
      ),
      voiceEnrichmentEnabled = const bool.fromEnvironment(
        'LEXIQUEST_READING_VOICE_ENABLED',
        defaultValue: false,
      );

  final bool associativeReadingEnabled;
  final bool generatedContentEnabled;
  final bool voiceEnrichmentEnabled;

  bool get researchModeEnabled => false;

  @override
  String toString() => 'LearningFeatureFlags';
}
