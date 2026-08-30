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
          existing.localRevision > 0 &&
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
      if (existing == null) {
        await database
            .into(database.learnerPreferences)
            .insert(
              db.LearnerPreferencesCompanion.insert(
                ownerId: preferences.ownerId,
                preferenceVersion: preferences.preferenceVersion,
                goal: preferences.goal.name,
                availableMinutesPerDay: preferences.availableMinutesPerDay,
                activityPreference: preferences.activityPreference.name,
                updatedAtUtcMs: updatedAtUtcMs,
                localRevision: Value(revision),
                isDeleted: const Value(false),
              ),
            );
      } else {
        await (database.update(
          database.learnerPreferences,
        )..where((row) => row.ownerId.equals(preferences.ownerId))).write(
          db.LearnerPreferencesCompanion(
            preferenceVersion: Value(preferences.preferenceVersion),
            goal: Value(preferences.goal.name),
            availableMinutesPerDay: Value(preferences.availableMinutesPerDay),
            activityPreference: Value(preferences.activityPreference.name),
            updatedAtUtcMs: Value(updatedAtUtcMs),
            localRevision: Value(revision),
            cloudRevision: Value(existing.cloudRevision),
            lastAcknowledgedAtUtcMs: Value(existing.lastAcknowledgedAtUtcMs),
            serverUpdatedAtUtcMs: Value(existing.serverUpdatedAtUtcMs),
            isDeleted: const Value(false),
          ),
        );
      }
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

  @override
  Future<void> saveDisplayPreferences(
    String ownerId,
    LearnerDisplayPreferences display, {
    LearnerPreferencesMutationGuard? mutationAllowed,
  }) async {
    await database.transaction(() async {
      final owner = await (database.select(
        database.localOwners,
      )..where((row) => row.id.equals(ownerId))).getSingleOrNull();
      if (owner == null || !owner.isActive) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final existing = await (database.select(
        database.learnerPreferences,
      )..where((row) => row.ownerId.equals(ownerId))).getSingleOrNull();
      if (existing != null &&
          existing.themeMode == display.themeMode.name &&
          existing.motionMode == display.motionMode.name) {
        return;
      }
      if (!(mutationAllowed?.call() ?? true)) {
        throw const LearnerPreferencesMutationUnavailable();
      }
      final requestedUpdatedAt = display.updatedAtUtc.millisecondsSinceEpoch;
      final updatedAtUtcMs =
          existing == null ||
              requestedUpdatedAt > existing.displayUpdatedAtUtcMs
          ? requestedUpdatedAt
          : existing.displayUpdatedAtUtcMs + 1;
      if (existing == null) {
        await database
            .into(database.learnerPreferences)
            .insert(
              db.LearnerPreferencesCompanion.insert(
                ownerId: ownerId,
                preferenceVersion: 1,
                goal: LearnerPreferenceGoal.balancedGrowth.name,
                availableMinutesPerDay: 20,
                activityPreference:
                    LearnerActivityPreference.mixedPractice.name,
                updatedAtUtcMs: 0,
                themeMode: Value(display.themeMode.name),
                motionMode: Value(display.motionMode.name),
                displayUpdatedAtUtcMs: Value(updatedAtUtcMs),
                localRevision: const Value(0),
              ),
            );
        return;
      }
      await (database.update(
        database.learnerPreferences,
      )..where((row) => row.ownerId.equals(ownerId))).write(
        db.LearnerPreferencesCompanion(
          themeMode: Value(display.themeMode.name),
          motionMode: Value(display.motionMode.name),
          displayUpdatedAtUtcMs: Value(updatedAtUtcMs),
        ),
      );
    });
  }

  bool _sameValues(
    db.LearnerPreferenceRow row,
    LearnerPreferences preferences,
  ) =>
      row.preferenceVersion == preferences.preferenceVersion &&
      row.goal == preferences.goal.name &&
      row.availableMinutesPerDay == preferences.availableMinutesPerDay &&
      row.activityPreference == preferences.activityPreference.name;

  LearnerPreferences _toDomain(db.LearnerPreferenceRow row) {
    LearnerDisplayPreferences display;
    try {
      display = LearnerDisplayPreferences(
        themeMode: LearnerThemePreferenceCodec.parse(row.themeMode),
        motionMode: LearnerMotionPreferenceCodec.parse(row.motionMode),
        updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
          row.displayUpdatedAtUtcMs,
          isUtc: true,
        ),
      );
    } on Object {
      display = LearnerDisplayPreferences.defaults();
    }
    return LearnerPreferences(
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
      display: display,
    );
  }
}
