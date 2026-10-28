import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/domain/local_owner_repository.dart';
import '../domain/learning_goal.dart';
import '../domain/learning_goal_repository.dart';

typedef LearningGoalMutationNotifier = Future<void> Function();

final class DriftLearningGoalRepository implements LearningGoalRepository {
  DriftLearningGoalRepository(
    this.database, {
    required this.owners,
    this.onLocalMutation,
  });

  final db.AppDatabase database;
  final LocalOwnerRepository owners;
  final LearningGoalMutationNotifier? onLocalMutation;

  @override
  Future<void> save(
    LearningGoal goal, {
    LearningGoalMutationGuard? mutationAllowed,
  }) async {
    await owners.getOrCreateActiveOwner();
    final changed = await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final existing = await (database.select(
        database.learningGoals,
      )..where((row) => row.id.equals(goal.id))).getSingleOrNull();
      if (existing == null) {
        _requireMutationAllowed(mutationAllowed);
        await database
            .into(database.learningGoals)
            .insert(
              db.LearningGoalsCompanion.insert(
                id: goal.id,
                ownerId: ownerId,
                kind: goal.kind.name,
                title: goal.title,
                deadlineAtUtcMs: goal.deadlineAtUtc.millisecondsSinceEpoch,
                timezoneId: goal.timezone.timezoneId,
                timezoneOffsetMinutes: goal.timezone.utcOffsetMinutes,
                status: goal.status.name,
                createdAtUtcMs: goal.createdAtUtc.millisecondsSinceEpoch,
                updatedAtUtcMs: goal.updatedAtUtc.millisecondsSinceEpoch,
              ),
            );
        await _appendOutbox(ownerId, goal.id, 0, 1, goal.updatedAtUtc);
        return true;
      }
      if (existing.ownerId != ownerId) {
        throw StateError('learning goal is not owned by active owner');
      }
      if (_matches(existing, goal)) return false;
      if (_matchesSemanticCommand(existing, goal)) return false;
      final updatedAtMs = goal.updatedAtUtc.millisecondsSinceEpoch;
      if (updatedAtMs <= existing.updatedAtUtcMs ||
          goal.createdAtUtc.millisecondsSinceEpoch != existing.createdAtUtcMs) {
        throw StateError('learning goal replay conflicts with durable state');
      }
      final revision = existing.localRevision + 1;
      _requireMutationAllowed(mutationAllowed);
      await (database.update(
        database.learningGoals,
      )..where((row) => row.id.equals(goal.id))).write(
        db.LearningGoalsCompanion(
          kind: Value(goal.kind.name),
          title: Value(goal.title),
          deadlineAtUtcMs: Value(goal.deadlineAtUtc.millisecondsSinceEpoch),
          timezoneId: Value(goal.timezone.timezoneId),
          timezoneOffsetMinutes: Value(goal.timezone.utcOffsetMinutes),
          status: Value(goal.status.name),
          updatedAtUtcMs: Value(updatedAtMs),
          localRevision: Value(revision),
        ),
      );
      await _appendOutbox(
        ownerId,
        goal.id,
        existing.cloudRevision,
        revision,
        goal.updatedAtUtc,
      );
      return true;
    });
    if (changed) await onLocalMutation?.call();
  }

  @override
  Future<List<LearningGoal>> list() async {
    await owners.getOrCreateActiveOwner();
    return database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      final rows =
          await (database.select(database.learningGoals)
                ..where(
                  (row) =>
                      row.ownerId.equals(ownerId) & row.isDeleted.equals(false),
                )
                ..orderBy([
                  (row) => OrderingTerm.asc(row.deadlineAtUtcMs),
                  (row) => OrderingTerm.asc(row.id),
                ]))
              .get();
      return List<LearningGoal>.unmodifiable(rows.map(_toDomain));
    });
  }

  Future<void> _appendOutbox(
    String ownerId,
    String goalId,
    int baseRevision,
    int revision,
    DateTime occurredAtUtc,
  ) => database
      .into(database.outboxOperations)
      .insert(
        db.OutboxOperationsCompanion.insert(
          operationId: 'learningGoal:$goalId:$revision',
          ownerId: ownerId,
          entityType: 'learningGoal',
          entityId: goalId,
          operationKind: 'upsert',
          baseRevision: Value(baseRevision),
          createdAtUtcMs: occurredAtUtc.millisecondsSinceEpoch,
        ),
      );

  Future<String> _requireSingleActiveOwnerId() async {
    final rows =
        await (database.select(database.localOwners)
              ..where((row) => row.isActive.equals(true))
              ..limit(2))
            .get();
    if (rows.length != 1) {
      throw StateError('exactly one active local owner is required');
    }
    return rows.single.id;
  }

  bool _matches(db.LearningGoalRow row, LearningGoal goal) =>
      row.kind == goal.kind.name &&
      row.title == goal.title &&
      row.deadlineAtUtcMs == goal.deadlineAtUtc.millisecondsSinceEpoch &&
      row.timezoneId == goal.timezone.timezoneId &&
      row.timezoneOffsetMinutes == goal.timezone.utcOffsetMinutes &&
      row.status == goal.status.name &&
      row.createdAtUtcMs == goal.createdAtUtc.millisecondsSinceEpoch &&
      row.updatedAtUtcMs == goal.updatedAtUtc.millisecondsSinceEpoch &&
      !row.isDeleted;

  bool _matchesSemanticCommand(db.LearningGoalRow row, LearningGoal goal) =>
      row.kind == goal.kind.name &&
      row.title == goal.title &&
      row.deadlineAtUtcMs == goal.deadlineAtUtc.millisecondsSinceEpoch &&
      row.timezoneId == goal.timezone.timezoneId &&
      row.timezoneOffsetMinutes == goal.timezone.utcOffsetMinutes &&
      row.status == goal.status.name &&
      row.createdAtUtcMs == goal.createdAtUtc.millisecondsSinceEpoch &&
      !row.isDeleted;

  void _requireMutationAllowed(LearningGoalMutationGuard? mutationAllowed) {
    if (mutationAllowed != null && !mutationAllowed()) {
      throw const LearningGoalMutationUnavailable();
    }
  }

  LearningGoal _toDomain(db.LearningGoalRow row) => LearningGoal(
    id: row.id,
    kind: LearningGoalKindCodec.parse(row.kind),
    title: row.title,
    deadlineAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.deadlineAtUtcMs,
      isUtc: true,
    ),
    timezone: LearningGoalTimezoneContext(
      timezoneId: row.timezoneId,
      utcOffsetMinutes: row.timezoneOffsetMinutes,
    ),
    status: LearningGoalStatusCodec.parse(row.status),
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.createdAtUtcMs,
      isUtc: true,
    ),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.updatedAtUtcMs,
      isUtc: true,
    ),
  );
}
