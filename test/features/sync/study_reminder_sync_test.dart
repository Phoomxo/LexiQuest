import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder.dart';
import 'package:vocab_learning_app/features/reminders/domain/study_reminder_repository.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/sync/data/drift_sync_store.dart';

void main() {
  test(
    'platform desired-state outbox is isolated from cloud sync claims',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final repository = DriftStudyReminderRepository(
        database,
        owners: DriftLocalOwnerRepository(
          database,
          generateId: () => 'owner-a',
          nowUtc: () => DateTime.utc(2026, 8, 28),
        ),
      );
      await repository.save(
        StudyReminder(
          id: 'reminder:due-review',
          ownerId: 'local:owner-a',
          source: const StudyReminderSource.dueReview(),
          scheduledAtUtc: DateTime.utc(2026, 8, 29, 2),
          timezone: const StudyReminderTimezoneContext(
            timezoneId: 'Asia/Bangkok',
            utcOffsetMinutes: 420,
          ),
          isEnabled: true,
          createdAtUtc: DateTime.utc(2026, 8, 28),
          updatedAtUtc: DateTime.utc(2026, 8, 28),
        ),
      );
      final outbox = await database
          .select(database.outboxOperations)
          .getSingle();
      expect(outbox.entityType, studyReminderPlatformOutboxEntityType);
      expect(outbox.state, studyReminderPlatformPendingState);

      final now = DateTime.utc(2026, 8, 28, 1);
      expect(
        await DriftOwnerOperationGate(database).tryAcquire(
          token: 'owner-gate',
          nowUtc: now,
          leaseDuration: const Duration(minutes: 10),
        ),
        isTrue,
      );
      final claims = await DriftSyncStore(database).claimPending(
        ownerId: 'local:owner-a',
        firebaseUid: 'firebase-a',
        limit: 10,
        leaseToken: 'cloud-lease',
        ownerGateToken: 'owner-gate',
        leaseDuration: const Duration(minutes: 5),
        nowUtc: now,
      );

      expect(claims, isEmpty);
      expect(
        (await database.select(database.outboxOperations).getSingle()).state,
        studyReminderPlatformPendingState,
      );
    },
  );
}
