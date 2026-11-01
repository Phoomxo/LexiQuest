import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/study_reminders/data/drift_study_reminder_repository.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';

import '../quest/support/quest_repository_harness.dart';

void main() {
  test(
    'absent reminder is disabled and reading every stored fact is pure',
    () async {
      final h = await QuestHarness.open();
      try {
        final before = await h.storage.snapshot();
        final repository = DriftStudyReminderRepository(
          h.database,
          h.storage.ownerWrites,
        );
        final setting = await repository.readForOwner(
          ownerId: configuredOwnerId,
          stillCurrent: () => true,
        );
        expect(setting.enabled, isFalse);
        expect(setting.revision, 0);
        expect(setting.minuteOfDay, isNull);
        expect(setting.timezoneId, isNull);
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );

  test(
    'explicit local reminder change has one revision and lost acknowledgement replays it',
    () async {
      final h = await QuestHarness.open();
      try {
        final repository = DriftStudyReminderRepository(
          h.database,
          h.storage.ownerWrites,
        );
        final before = (await h.storage.snapshot())
          ..remove('study_reminder_preferences');
        const choice = StudyReminderChoice(
          enabled: true,
          minuteOfDay: 19 * 60,
          timezoneId: 'Asia/Bangkok',
        );
        final first = await repository.writeForOwner(
          ownerId: configuredOwnerId,
          baseRevision: 0,
          choice: choice,
          updatedAtUtc: h.now,
          stillCurrent: () => true,
        );
        final committed = await h.storage.snapshot();
        final replay = await repository.writeForOwner(
          ownerId: configuredOwnerId,
          baseRevision: 0,
          choice: choice,
          updatedAtUtc: h.now,
          stillCurrent: () => true,
        );
        expect(first.revision, 1);
        expect(replay.revision, 1);
        expect(await h.storage.snapshot(), committed);
        final unaffected = (await h.storage.snapshot())
          ..remove('study_reminder_preferences');
        expect(unaffected, before);
        final rows = await h.database
            .select(h.database.studyReminderPreferences)
            .get();
        expect(rows, hasLength(1));
        expect(rows.single.ownerId, configuredOwnerId);
      } finally {
        await h.close();
      }
    },
  );

  test('invalid time or timezone fails before changing any row', () async {
    final h = await QuestHarness.open();
    try {
      final repository = DriftStudyReminderRepository(
        h.database,
        h.storage.ownerWrites,
      );
      final before = await h.storage.snapshot();
      for (final choice in [
        const StudyReminderChoice(
          enabled: true,
          minuteOfDay: -1,
          timezoneId: 'UTC',
        ),
        const StudyReminderChoice(
          enabled: true,
          minuteOfDay: 1440,
          timezoneId: 'UTC',
        ),
        const StudyReminderChoice(
          enabled: true,
          minuteOfDay: 100,
          timezoneId: 'Not/AZone',
        ),
      ]) {
        await expectLater(
          repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: choice,
            updatedAtUtc: h.now,
            stillCurrent: () => true,
          ),
          throwsA(isA<StudyReminderException>()),
        );
      }
      expect(await h.storage.snapshot(), before);
    } finally {
      await h.close();
    }
  });

  for (final kind in ['cancelled', 'deletion', 'ambient']) {
    test(
      'actual $kind reminder change cannot mutate preference or other facts',
      () async {
        final h = await QuestHarness.open();
        try {
          final repository = DriftStudyReminderRepository(
            h.database,
            h.storage.ownerWrites,
          );
          if (kind == 'deletion') {
            await h.storage.ownerWrites.beginDeletion(
              ownerId: configuredOwnerId,
              firebaseUid: 'synthetic-configured-uid-a',
              idempotencyKey: 'synthetic-reminder-delete',
            );
          }
          final before = await h.storage.snapshot();
          Future<void> change() async {
            await repository.writeForOwner(
              ownerId: configuredOwnerId,
              baseRevision: 0,
              choice: const StudyReminderChoice(
                enabled: true,
                minuteOfDay: 10,
                timezoneId: 'UTC',
              ),
              updatedAtUtc: h.now,
              stillCurrent: () => kind != 'cancelled',
            );
          }

          await expectLater(
            kind == 'ambient' ? h.database.transaction(change) : change(),
            throwsA(isA<StudyReminderException>()),
          );
          expect(await h.storage.snapshot(), before);
        } finally {
          await h.close();
        }
      },
    );
  }

  test(
    'stale preference edit cannot replace a newer explicit choice',
    () async {
      final h = await QuestHarness.open();
      try {
        final repository = DriftStudyReminderRepository(
          h.database,
          h.storage.ownerWrites,
        );
        await repository.writeForOwner(
          ownerId: configuredOwnerId,
          baseRevision: 0,
          choice: const StudyReminderChoice(
            enabled: false,
            minuteOfDay: 60,
            timezoneId: 'UTC',
          ),
          updatedAtUtc: h.now,
          stillCurrent: () => true,
        );
        final before = await h.storage.snapshot();
        await expectLater(
          repository.writeForOwner(
            ownerId: configuredOwnerId,
            baseRevision: 0,
            choice: const StudyReminderChoice(
              enabled: true,
              minuteOfDay: 120,
              timezoneId: 'UTC',
            ),
            updatedAtUtc: h.now.add(const Duration(milliseconds: 1)),
            stillCurrent: () => true,
          ),
          throwsA(
            isA<StudyReminderException>().having(
              (e) => e.code,
              'code',
              StudyReminderFailureCode.staleRevision,
            ),
          ),
        );
        expect(await h.storage.snapshot(), before);
      } finally {
        await h.close();
      }
    },
  );
}
