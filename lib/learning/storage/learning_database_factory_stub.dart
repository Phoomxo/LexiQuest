import 'learning_database.dart';
import 'learning_database_open_exception.dart';

final class LearningDatabaseFactory {
  const LearningDatabaseFactory();

  Future<LearningDatabase> open() {
    throw const LearningDatabaseOpenException(
      LearningDatabaseOpenErrorCode.unsupportedPlatform,
      'Durable learning storage is available on Android only.',
    );
  }
}
