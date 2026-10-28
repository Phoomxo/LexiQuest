import 'package:drift/drift.dart';
import 'package:vocab_learning_app/data/local/app_database.dart' as db;

import '../../identity/domain/local_owner_repository.dart';
import '../../sync/data/drift_owner_operation_gate.dart';
import '../domain/study_reminder.dart';
import '../domain/study_reminder_repository.dart';

final class DriftStudyReminderRepository implements StudyReminderRepository {
  DriftStudyReminderRepository(this.database, {required this.owners});

  final db.AppDatabase database;
  final LocalOwnerRepository owners;

  @override
  Future<String> activeOwnerId() async {
    await owners.getOrCreateActiveOwner();
    return _requireSingleActiveOwnerId();
  }

  @override
  Future<void> beginOwnerOperationFence({
    required String ownerId,
    required String operationToken,
    required DateTime nowUtc,
  }) {
    return DriftOwnerOperationGate(database).beginOwnerFence(
      ownerId: _canonicalIdentifier(ownerId, 'ownerId'),
      token: operationToken,
      nowUtc: nowUtc,
    );
  }

  @override
  Future<bool> isOwnerOperationFenced({
    required String ownerId,
    required DateTime nowUtc,
  }) {
    return DriftOwnerOperationGate(database).isOwnerFenced(
      ownerId: _canonicalIdentifier(ownerId, 'ownerId'),
      nowUtc: nowUtc,
    );
  }

  @override
  Future<void> endOwnerOperationFence({
    required String ownerId,
    required String operationToken,
  }) {
    return DriftOwnerOperationGate(database).endOwnerFence(
      ownerId: _canonicalIdentifier(ownerId, 'ownerId'),
      token: operationToken,
    );
  }

  @override
  Future<void> save(
    StudyReminder reminder, {
    StudyReminderMutationGuard? mutationAllowed,
  }) async {
    await owners.getOrCreateActiveOwner();
    await database.transaction(() async {
      final ownerId = await _requireSingleActiveOwnerId();
      if (reminder.ownerId != ownerId) {
        throw StateError('study reminder is not owned by active owner');
      }
      await _requireValidSource(reminder, ownerId);
      final existing = await (database.select(
        database.studyReminders,
      )..where((row) => row.id.equals(reminder.id))).getSingleOrNull();
      if (existing == null) {
        _requireMutationAllowed(mutationAllowed);
        await database
            .into(database.studyReminders)
            .insert(_companion(reminder, ownerId: ownerId));
        await _appendPlatformIntent(reminder, revision: 1);
        return;
      }
      if (existing.ownerId != ownerId) {
        throw StateError('study reminder is not owned by active owner');
      }
      if (_matches(existing, reminder) ||
          _matchesSemantic(existing, reminder)) {
        return;
      }
      final updatedAtMs = reminder.updatedAtUtc.millisecondsSinceEpoch;
      if (updatedAtMs <= existing.updatedAtUtcMs ||
          reminder.createdAtUtc.millisecondsSinceEpoch !=
              existing.createdAtUtcMs) {
        throw StateError('study reminder replay conflicts with durable state');
      }
      _requireMutationAllowed(mutationAllowed);
      final revision = existing.localRevision + 1;
      await (database.update(
        database.studyReminders,
      )..where((row) => row.id.equals(reminder.id))).write(
        db.StudyRemindersCompanion(
          goalId: Value(reminder.source.goalId),
          sourceKind: Value(reminder.source.kind.name),
          scheduledAtUtcMs: Value(
            reminder.scheduledAtUtc.millisecondsSinceEpoch,
          ),
          timezoneId: Value(reminder.timezone.timezoneId),
          timezoneOffsetMinutes: Value(reminder.timezone.utcOffsetMinutes),
          quietHoursStartMinutes: Value(reminder.quietHours?.startMinutes),
          quietHoursEndMinutes: Value(reminder.quietHours?.endMinutes),
          isEnabled: Value(reminder.isEnabled),
          updatedAtUtcMs: Value(updatedAtMs),
          localRevision: Value(revision),
          isDeleted: Value(reminder.isDeleted),
        ),
      );
      await _appendPlatformIntent(reminder, revision: revision);
    });
  }

  @override
  Future<void> cancel(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  }) => _mutate(
    reminderId,
    updatedAtUtc: updatedAtUtc,
    mutationAllowed: mutationAllowed,
    update: (reminder, updated) =>
        reminder.copyWith(isEnabled: false, updatedAtUtc: updated),
  );

  @override
  Future<void> delete(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  }) => _mutate(
    reminderId,
    updatedAtUtc: updatedAtUtc,
    mutationAllowed: mutationAllowed,
    update: (reminder, updated) => reminder.copyWith(
      isEnabled: false,
      isDeleted: true,
      updatedAtUtc: updated,
    ),
  );

  @override
  Future<List<StudyReminder>> list({bool includeDeleted = false}) async {
    await owners.getOrCreateActiveOwner();
    final ownerId = await _requireSingleActiveOwnerId();
    final states = await listForOwner(ownerId, includeDeleted: includeDeleted);
    return List<StudyReminder>.unmodifiable(
      states.map((state) => state.reminder),
    );
  }

  @override
  Future<List<StudyReminderDesiredState>> listForOwner(
    String ownerId, {
    bool includeDeleted = false,
  }) => database.transaction(() async {
    final canonicalOwnerId = _canonicalIdentifier(ownerId, 'ownerId');
    final rows =
        await (database.select(database.studyReminders)
              ..where(
                (row) =>
                    row.ownerId.equals(canonicalOwnerId) &
                    (includeDeleted
                        ? const Constant<bool>(true)
                        : row.isDeleted.equals(false)),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.scheduledAtUtcMs),
                (row) => OrderingTerm.asc(row.id),
              ]))
            .get();
    return List<StudyReminderDesiredState>.unmodifiable(
      rows.map(
        (row) => StudyReminderDesiredState(
          reminder: _toDomain(row),
          localRevision: row.localRevision,
        ),
      ),
    );
  });

  @override
  Future<StudyReminderDesiredState?> desiredState(
    String ownerId,
    String reminderId,
  ) => database.transaction(() async {
    final canonicalOwnerId = _canonicalIdentifier(ownerId, 'ownerId');
    final canonicalReminderId = _canonicalIdentifier(reminderId, 'reminderId');
    final row =
        await (database.select(database.studyReminders)..where(
              (candidate) =>
                  candidate.ownerId.equals(canonicalOwnerId) &
                  candidate.id.equals(canonicalReminderId),
            ))
            .getSingleOrNull();
    return row == null
        ? null
        : StudyReminderDesiredState(
            reminder: _toDomain(row),
            localRevision: row.localRevision,
          );
  });

  @override
  Future<List<String>> reminderIdsForOwner(String ownerId) async {
    final canonicalOwnerId = _canonicalIdentifier(ownerId, 'ownerId');
    final rows =
        await (database.selectOnly(database.studyReminders)
              ..addColumns([database.studyReminders.id])
              ..where(database.studyReminders.ownerId.equals(canonicalOwnerId))
              ..orderBy([OrderingTerm.asc(database.studyReminders.id)]))
            .get();
    return List<String>.unmodifiable(
      rows.map((row) => row.read(database.studyReminders.id)!),
    );
  }

  @override
  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntents() async {
    await owners.getOrCreateActiveOwner();
    return pendingPlatformIntentsForOwner(await _requireSingleActiveOwnerId());
  }

  @override
  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntentsForOwner(
    String ownerId,
  ) => database.transaction(() async {
    final canonicalOwnerId = _canonicalIdentifier(ownerId, 'ownerId');
    final rows =
        await (database.select(database.outboxOperations)
              ..where(
                (row) =>
                    row.ownerId.equals(canonicalOwnerId) &
                    row.entityType.equals(
                      studyReminderPlatformOutboxEntityType,
                    ) &
                    row.state.equals(studyReminderPlatformPendingState),
              )
              ..orderBy([
                (row) => OrderingTerm.asc(row.createdAtUtcMs),
                (row) => OrderingTerm.asc(row.operationId),
              ]))
            .get();
    return List<StudyReminderPlatformIntent>.unmodifiable(rows.map(_toIntent));
  });

  @override
  Future<StudyReminderDesiredState?> resolvePlatformIntent(
    StudyReminderPlatformIntent intent,
  ) => database.transaction(() async {
    final row =
        await (database.select(database.outboxOperations)..where(
              (candidate) =>
                  candidate.operationId.equals(intent.operationId) &
                  candidate.ownerId.equals(intent.ownerId) &
                  candidate.entityType.equals(
                    studyReminderPlatformOutboxEntityType,
                  ) &
                  candidate.entityId.equals(intent.reminderId) &
                  candidate.operationKind.equals(_intentKind(intent.kind)) &
                  candidate.baseRevision.equals(intent.localRevision) &
                  candidate.state.equals(studyReminderPlatformPendingState),
            ))
            .getSingleOrNull();
    if (row == null) return null;
    final reminderRow =
        await (database.select(database.studyReminders)..where(
              (candidate) =>
                  candidate.ownerId.equals(intent.ownerId) &
                  candidate.id.equals(intent.reminderId) &
                  candidate.localRevision.equals(intent.localRevision),
            ))
            .getSingleOrNull();
    if (reminderRow == null) return null;
    final expectedKind = reminderRow.isEnabled && !reminderRow.isDeleted
        ? StudyReminderPlatformIntentKind.schedule
        : StudyReminderPlatformIntentKind.cancel;
    if (expectedKind != intent.kind) return null;
    return StudyReminderDesiredState(
      reminder: _toDomain(reminderRow),
      localRevision: reminderRow.localRevision,
    );
  });

  @override
  Future<bool> acknowledgePlatformIntent(
    StudyReminderPlatformIntent intent, {
    required DateTime acknowledgedAtUtc,
  }) async {
    final changed =
        await (database.update(database.outboxOperations)..where(
              (row) =>
                  row.operationId.equals(intent.operationId) &
                  row.ownerId.equals(intent.ownerId) &
                  row.entityType.equals(studyReminderPlatformOutboxEntityType) &
                  row.entityId.equals(intent.reminderId) &
                  row.operationKind.equals(_intentKind(intent.kind)) &
                  row.baseRevision.equals(intent.localRevision) &
                  row.state.equals(studyReminderPlatformPendingState),
            ))
            .write(
              db.OutboxOperationsCompanion(
                state: const Value('acknowledged'),
                acknowledgedAtUtcMs: Value(
                  _utcMs(acknowledgedAtUtc, 'acknowledgedAtUtc'),
                ),
                failureCode: const Value(null),
              ),
            );
    if (changed > 1) throw StateError('platform intent identity is not unique');
    return changed == 1;
  }

  @override
  Future<void> recordPlatformFailure(
    StudyReminderPlatformIntent intent, {
    required DateTime attemptedAtUtc,
    required String failureCode,
  }) async {
    final row =
        await (database.select(database.outboxOperations)..where(
              (candidate) =>
                  candidate.operationId.equals(intent.operationId) &
                  candidate.ownerId.equals(intent.ownerId) &
                  candidate.entityType.equals(
                    studyReminderPlatformOutboxEntityType,
                  ) &
                  candidate.entityId.equals(intent.reminderId) &
                  candidate.operationKind.equals(_intentKind(intent.kind)) &
                  candidate.baseRevision.equals(intent.localRevision) &
                  candidate.state.equals(studyReminderPlatformPendingState),
            ))
            .getSingleOrNull();
    if (row == null) return;
    await (database.update(database.outboxOperations)..where(
          (candidate) => candidate.operationId.equals(intent.operationId),
        ))
        .write(
          db.OutboxOperationsCompanion(
            attemptCount: Value(row.attemptCount + 1),
            lastAttemptAtUtcMs: Value(_utcMs(attemptedAtUtc, 'attemptedAtUtc')),
            failureCode: Value(_failureCode(failureCode)),
          ),
        );
  }

  Future<void> _mutate(
    String reminderId, {
    required DateTime updatedAtUtc,
    required StudyReminderMutationGuard? mutationAllowed,
    required StudyReminder Function(StudyReminder, DateTime) update,
  }) async {
    final updated = DateTime.fromMillisecondsSinceEpoch(
      _utcMs(updatedAtUtc, 'updatedAtUtc'),
      isUtc: true,
    );
    final reminder = (await list(
      includeDeleted: true,
    )).where((candidate) => candidate.id == reminderId).firstOrNull;
    if (reminder == null) throw StateError('study reminder was not found');
    final effectiveUpdated = updated.isAfter(reminder.updatedAtUtc)
        ? updated
        : reminder.updatedAtUtc.add(const Duration(milliseconds: 1));
    await save(
      update(reminder, effectiveUpdated),
      mutationAllowed: mutationAllowed,
    );
  }

  Future<void> _requireValidSource(
    StudyReminder reminder,
    String ownerId,
  ) async {
    final goalId = reminder.source.goalId;
    if (goalId == null) return;
    final goal =
        await (database.select(database.learningGoals)..where(
              (row) =>
                  row.id.equals(goalId) &
                  row.ownerId.equals(ownerId) &
                  row.isDeleted.equals(false),
            ))
            .getSingleOrNull();
    if (goal == null) {
      throw StateError('goal reminder source is unavailable for active owner');
    }
  }

  Future<void> _appendPlatformIntent(
    StudyReminder reminder, {
    required int revision,
  }) async {
    await (database.update(database.outboxOperations)..where(
          (row) =>
              row.ownerId.equals(reminder.ownerId) &
              row.entityType.equals(studyReminderPlatformOutboxEntityType) &
              row.entityId.equals(reminder.id) &
              row.state.equals(studyReminderPlatformPendingState),
        ))
        .write(const db.OutboxOperationsCompanion(state: Value('superseded')));
    final kind = reminder.isEnabled && !reminder.isDeleted
        ? 'schedule'
        : 'cancel';
    await database
        .into(database.outboxOperations)
        .insert(
          db.OutboxOperationsCompanion.insert(
            operationId:
                '$studyReminderPlatformOutboxEntityType:${reminder.id}:$revision:$kind',
            ownerId: reminder.ownerId,
            entityType: studyReminderPlatformOutboxEntityType,
            entityId: reminder.id,
            operationKind: kind,
            baseRevision: Value(revision),
            state: const Value(studyReminderPlatformPendingState),
            createdAtUtcMs: reminder.updatedAtUtc.millisecondsSinceEpoch,
          ),
        );
  }

  db.StudyRemindersCompanion _companion(
    StudyReminder reminder, {
    required String ownerId,
  }) => db.StudyRemindersCompanion.insert(
    id: reminder.id,
    ownerId: ownerId,
    goalId: Value(reminder.source.goalId),
    sourceKind: reminder.source.kind.name,
    scheduledAtUtcMs: reminder.scheduledAtUtc.millisecondsSinceEpoch,
    timezoneId: reminder.timezone.timezoneId,
    timezoneOffsetMinutes: reminder.timezone.utcOffsetMinutes,
    quietHoursStartMinutes: Value(reminder.quietHours?.startMinutes),
    quietHoursEndMinutes: Value(reminder.quietHours?.endMinutes),
    isEnabled: Value(reminder.isEnabled),
    createdAtUtcMs: reminder.createdAtUtc.millisecondsSinceEpoch,
    updatedAtUtcMs: reminder.updatedAtUtc.millisecondsSinceEpoch,
    isDeleted: Value(reminder.isDeleted),
  );

  bool _matches(db.StudyReminderRow row, StudyReminder reminder) =>
      _matchesSemantic(row, reminder) &&
      row.updatedAtUtcMs == reminder.updatedAtUtc.millisecondsSinceEpoch;

  bool _matchesSemantic(db.StudyReminderRow row, StudyReminder reminder) =>
      row.goalId == reminder.source.goalId &&
      row.sourceKind == reminder.source.kind.name &&
      row.scheduledAtUtcMs == reminder.scheduledAtUtc.millisecondsSinceEpoch &&
      row.timezoneId == reminder.timezone.timezoneId &&
      row.timezoneOffsetMinutes == reminder.timezone.utcOffsetMinutes &&
      row.quietHoursStartMinutes == reminder.quietHours?.startMinutes &&
      row.quietHoursEndMinutes == reminder.quietHours?.endMinutes &&
      row.isEnabled == reminder.isEnabled &&
      row.createdAtUtcMs == reminder.createdAtUtc.millisecondsSinceEpoch &&
      row.isDeleted == reminder.isDeleted;

  StudyReminder _toDomain(db.StudyReminderRow row) => StudyReminder(
    id: row.id,
    ownerId: row.ownerId,
    source: switch (row.sourceKind) {
      'dueReview' when row.goalId == null =>
        const StudyReminderSource.dueReview(),
      'goalDeadline' when row.goalId != null =>
        StudyReminderSource.goalDeadline(row.goalId!),
      _ => throw StateError('invalid durable study reminder source'),
    },
    scheduledAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.scheduledAtUtcMs,
      isUtc: true,
    ),
    timezone: StudyReminderTimezoneContext(
      timezoneId: row.timezoneId,
      utcOffsetMinutes: row.timezoneOffsetMinutes,
    ),
    quietHours:
        row.quietHoursStartMinutes == null || row.quietHoursEndMinutes == null
        ? null
        : ReminderQuietHours(
            startMinutes: row.quietHoursStartMinutes!,
            endMinutes: row.quietHoursEndMinutes!,
          ),
    isEnabled: row.isEnabled,
    createdAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.createdAtUtcMs,
      isUtc: true,
    ),
    updatedAtUtc: DateTime.fromMillisecondsSinceEpoch(
      row.updatedAtUtcMs,
      isUtc: true,
    ),
    isDeleted: row.isDeleted,
  );

  StudyReminderPlatformIntent _toIntent(db.OutboxOperation row) =>
      StudyReminderPlatformIntent(
        operationId: row.operationId,
        ownerId: row.ownerId,
        reminderId: row.entityId,
        kind: switch (row.operationKind) {
          'schedule' => StudyReminderPlatformIntentKind.schedule,
          'cancel' => StudyReminderPlatformIntentKind.cancel,
          _ => throw StateError('invalid study reminder platform intent'),
        },
        localRevision: row.baseRevision,
        attemptCount: row.attemptCount,
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

  void _requireMutationAllowed(StudyReminderMutationGuard? mutationAllowed) {
    if (mutationAllowed != null && !mutationAllowed()) {
      throw const StudyReminderMutationUnavailable();
    }
  }
}

int _utcMs(DateTime value, String field) {
  if (!value.isUtc || value.millisecondsSinceEpoch < 0) {
    throw ArgumentError.value(value, field, 'must be nonnegative UTC');
  }
  return value.millisecondsSinceEpoch;
}

String _failureCode(String value) {
  if (value.isEmpty || value != value.trim() || value.length > 80) {
    return 'platformFailure';
  }
  return value;
}

String _canonicalIdentifier(String value, String field) {
  if (value.isEmpty || value != value.trim()) {
    throw ArgumentError.value(value, field, 'must be canonical text');
  }
  return value;
}

String _intentKind(StudyReminderPlatformIntentKind kind) => switch (kind) {
  StudyReminderPlatformIntentKind.schedule => 'schedule',
  StudyReminderPlatformIntentKind.cancel => 'cancel',
};
