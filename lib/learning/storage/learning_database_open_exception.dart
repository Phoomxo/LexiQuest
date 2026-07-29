enum LearningDatabaseOpenErrorCode {
  unsupportedPlatform,
  incompatibleSchema,
  corruptOrUnreadable,
}

final class LearningDatabaseOpenException implements Exception {
  const LearningDatabaseOpenException(this.code, this.message);

  final LearningDatabaseOpenErrorCode code;
  final String message;

  @override
  String toString() => 'LearningDatabaseOpenException($code, $message)';
}

final class LearningDatabaseMigrationException implements Exception {
  const LearningDatabaseMigrationException({
    required this.fromVersion,
    required this.toVersion,
  });

  final int fromVersion;
  final int toVersion;

  @override
  String toString() {
    return 'Unsupported learning database migration '
        'from $fromVersion to $toVersion';
  }
}

final class LearningDatabaseIntegrityException implements Exception {
  const LearningDatabaseIntegrityException();

  @override
  String toString() => 'Learning database integrity check failed';
}
