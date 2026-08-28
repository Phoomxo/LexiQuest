import 'study_reminder.dart';

const String studyReminderPlatformOutboxEntityType = 'studyReminderPlatform';
const String studyReminderPlatformPendingState = 'platformPending';

typedef StudyReminderMutationGuard = bool Function();

final class StudyReminderMutationUnavailable implements Exception {
  const StudyReminderMutationUnavailable();

  @override
  String toString() => 'StudyReminderMutationUnavailable';
}

enum StudyReminderPlatformIntentKind { schedule, cancel }

final class StudyReminderPlatformIntent {
  const StudyReminderPlatformIntent({
    required this.operationId,
    required this.ownerId,
    required this.reminderId,
    required this.kind,
    required this.localRevision,
    required this.attemptCount,
  });

  final String operationId;
  final String ownerId;
  final String reminderId;
  final StudyReminderPlatformIntentKind kind;
  final int localRevision;
  final int attemptCount;
}

final class StudyReminderDesiredState {
  const StudyReminderDesiredState({
    required this.reminder,
    required this.localRevision,
  });

  final StudyReminder reminder;
  final int localRevision;
}

abstract interface class StudyReminderRepository {
  Future<String> activeOwnerId();

  Future<void> beginOwnerOperationFence({
    required String ownerId,
    required String operationToken,
    required DateTime nowUtc,
  });

  Future<bool> isOwnerOperationFenced({
    required String ownerId,
    required DateTime nowUtc,
  });

  Future<void> endOwnerOperationFence({
    required String ownerId,
    required String operationToken,
  });

  Future<void> save(
    StudyReminder reminder, {
    StudyReminderMutationGuard? mutationAllowed,
  });

  Future<void> cancel(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  });

  Future<void> delete(
    String reminderId, {
    required DateTime updatedAtUtc,
    StudyReminderMutationGuard? mutationAllowed,
  });

  Future<List<StudyReminder>> list({bool includeDeleted = false});

  Future<List<StudyReminderDesiredState>> listForOwner(
    String ownerId, {
    bool includeDeleted = false,
  });

  Future<List<String>> reminderIdsForOwner(String ownerId);

  Future<StudyReminderDesiredState?> desiredState(
    String ownerId,
    String reminderId,
  );

  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntents();

  Future<List<StudyReminderPlatformIntent>> pendingPlatformIntentsForOwner(
    String ownerId,
  );

  Future<StudyReminderDesiredState?> resolvePlatformIntent(
    StudyReminderPlatformIntent intent,
  );

  Future<bool> acknowledgePlatformIntent(
    StudyReminderPlatformIntent intent, {
    required DateTime acknowledgedAtUtc,
  });

  Future<void> recordPlatformFailure(
    StudyReminderPlatformIntent intent, {
    required DateTime attemptedAtUtc,
    required String failureCode,
  });
}
