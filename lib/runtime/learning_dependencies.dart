import '../config/app_config.dart';
import '../learning/associative_memory.dart';
import '../learning/associative_reading_coordinator.dart';
import '../learning/learning_repository.dart';
import '../voice/reading_voice_enrichment.dart';
import 'learning_feature_flags.dart';

typedef LearningDependenciesLoader =
    Future<LearningDependencies> Function(
      AppConfig? config,
      LearningFeatureFlags flags,
    );
typedef LearningDependenciesCloser = Future<void> Function();

final class LearningDependencies {
  LearningDependencies({
    required this.repository,
    required this.reader,
    required this.associativeMemory,
    required this.readingCoordinator,
    required this.readingVoice,
    required this.close,
  });

  final LearningRepository repository;
  final LearningReader reader;
  final AssociativeMemory associativeMemory;
  final AssociativeReadingCoordinator readingCoordinator;
  final ReadingVoiceEnrichment readingVoice;
  final LearningDependenciesCloser close;

  @override
  String toString() => 'LearningDependencies';
}
