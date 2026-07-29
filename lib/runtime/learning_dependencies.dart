import '../learning/associative_memory.dart';
import '../learning/learning_repository.dart';

typedef LearningDependenciesLoader = Future<LearningDependencies> Function();
typedef LearningDependenciesCloser = Future<void> Function();

final class LearningDependencies {
  LearningDependencies({
    required this.repository,
    required this.reader,
    required this.associativeMemory,
    required this.close,
  });

  final LearningRepository repository;
  final LearningReader reader;
  final AssociativeMemory associativeMemory;
  final LearningDependenciesCloser close;

  @override
  String toString() => 'LearningDependencies';
}
