import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../domain/learner_preferences.dart';
import '../domain/learner_preferences_repository.dart';

typedef LearnerPreferenceMutationNotifier = Future<void> Function();

final class DriftLearnerPreferencesRepository
    implements LearnerPreferencesRepository {
  const DriftLearnerPreferencesRepository(
    this.database, {
    this.onLocalMutation,
  });

  final db.AppDatabase database;
  final LearnerPreferenceMutationNotifier? onLocalMutation;

  @override
  Future<LearnerPreferences> read(String ownerId) async {
    final row =
        await (database.select(database.learnerPreferences)
              ..where((candidate) => candidate.ownerId.equals(ownerId)))
            .getSingleOrNull();
    if (row == null || row.isDeleted) {
      return LearnerPreferences.defaults(
        ownerId: ownerId,
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
      );
    }
    return _toDomain(row);
  }

  @override
  Future<void> save(
    LearnerPreferences preferences, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    final changed = await database.transaction(() async {
      final owner = await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(preferences.ownerId))).getSingleOrNull();
      if (owner == null || !owner.isActive) {
        throw StateError('learner preference owner must be the active owner');
      }
      final existing =
          await (database.select(database.learnerPreferences)
                ..where((row) => row.ownerId.equals(preferences.ownerId)))
              .getSingleOrNull();
      if (existing != null &&
          !existing.isDeleted &&
          _sameValues(existing, preferences)) {
        return false;
      }
      if (!(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final baseRevision = existing?.cloudRevision ?? 0;
      final revision = baseRevision + 1;
      final requestedUpdatedAt =
          preferences.updatedAtUtc.millisecondsSinceEpoch;
      final updatedAtUtcMs =
          existing == null || requestedUpdatedAt > existing.updatedAtUtcMs
          ? requestedUpdatedAt
          : existing.updatedAtUtcMs + 1;
      await database.customUpdate(
        '''
        UPDATE outbox_operations
        SET state = 'superseded',
            next_attempt_at_utc_ms = NULL,
            lease_token = NULL,
            lease_expires_at_utc_ms = NULL,
            failure_code = 'replacedByNewerPreference'
        WHERE owner_id = ?
          AND entity_type = 'learnerPreference'
          AND entity_id = ?
          AND state IN (
            'pending',
            'retryWaiting',
            'inFlight',
            'blockedAuth',
            'permanentFailure'
          )
        ''',
        variables: [
          Variable<String>(preferences.ownerId),
          Variable<String>(preferences.ownerId),
        ],
        updates: {database.outboxOperations},
      );
      await database
          .into(database.learnerPreferences)
          .insertOnConflictUpdate(
            db.LearnerPreferencesCompanion.insert(
              ownerId: preferences.ownerId,
              preferenceVersion: preferences.preferenceVersion,
              goal: preferences.goal.name,
              availableMinutesPerDay: preferences.availableMinutesPerDay,
              activityPreference: preferences.activityPreference.name,
              updatedAtUtcMs: updatedAtUtcMs,
              localRevision: Value(revision),
              cloudRevision: Value(existing?.cloudRevision ?? 0),
              lastAcknowledgedAtUtcMs: Value(existing?.lastAcknowledgedAtUtcMs),
              serverUpdatedAtUtcMs: Value(existing?.serverUpdatedAtUtcMs),
              isDeleted: const Value(false),
            ),
          );
      await database
          .into(database.outboxOperations)
          .insert(
            db.OutboxOperationsCompanion.insert(
              operationId:
                  'learnerPreference:${preferences.ownerId}:$updatedAtUtcMs',
              ownerId: preferences.ownerId,
              entityType: 'learnerPreference',
              entityId: preferences.ownerId,
              operationKind: 'upsert',
              payloadVersion: const Value(1),
              baseRevision: Value(baseRevision),
              createdAtUtcMs: updatedAtUtcMs,
            ),
          );
      return true;
    });
    if (changed) await onLocalMutation?.call();
  }

  bool _sameValues(
    db.LearnerPreferenceRow row,
    LearnerPreferences preferences,
  ) =>
      row.preferenceVersion == preferences.preferenceVersion &&
      row.goal == preferences.goal.name &&
      row.availableMinutesPerDay == preferences.availableMinutesPerDay &&
      row.activityPreference == preferences.activityPreference.name;

  LearnerPreferences _toDomain(db.LearnerPreferenceRow row) =>
      LearnerPreferences(
        ownerId: row.ownerId,
        preferenceVersion: row.preferenceVersion,
        goal: LearnerPreferenceGoalCodec.parse(row.goal),
        availableMinutesPerDay: row.availableMinutesPerDay,
        activityPreference: LearnerActivityPreferenceCodec.parse(
          row.activityPreference,
        ),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.updatedAtUtcMs,
          isUtc: true,
        ),
      );
}
