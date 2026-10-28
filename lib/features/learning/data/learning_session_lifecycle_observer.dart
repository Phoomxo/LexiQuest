import '../../../data/local/app_database.dart' as db;

final class LearningSessionLifecycleFact {
  const LearningSessionLifecycleFact._({
    required this.id,
    required this.ownerId,
    required this.activityType,
    required this.startedAtUtcMs,
    required this.appVersion,
    required this.buildId,
    required this.state,
    required this.endedAtUtcMs,
  });

  factory LearningSessionLifecycleFact.fromRow(db.LearningSession row) =>
      LearningSessionLifecycleFact._(
        id: row.id,
        ownerId: row.ownerId,
        activityType: row.activityType,
        startedAtUtcMs: row.startedAtUtcMs,
        appVersion: row.appVersion,
        buildId: row.buildId,
        state: row.state,
        endedAtUtcMs: row.endedAtUtcMs,
      );

  final String id;
  final String ownerId;
  final String activityType;
  final int startedAtUtcMs;
  final String appVersion;
  final String buildId;
  final String state;
  final int? endedAtUtcMs;
}

abstract interface class LearningSessionLifecycleObserver {
  db.AppDatabase get database;

  Future<void> accepted(LearningSessionLifecycleFact fact);
  Future<void> completed(LearningSessionLifecycleFact fact);
}
