final class LearningFeatureFlags {
  const LearningFeatureFlags({this.associativeReadingEnabled = false});

  const LearningFeatureFlags.fromEnvironment()
    : associativeReadingEnabled = const bool.fromEnvironment(
        'LEXIQUEST_ASSOCIATIVE_READING_ENABLED',
        defaultValue: false,
      );

  final bool associativeReadingEnabled;

  bool get researchModeEnabled => false;

  @override
  String toString() => 'LearningFeatureFlags';
}
