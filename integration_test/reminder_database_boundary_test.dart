import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path_provider/path_provider.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/study_reminders/data/method_channel_study_reminder_platform.dart';
import 'package:vocab_learning_app/features/study_reminders/domain/study_reminder.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('native reminder reads current WAL revision without losing writes', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await getApplicationSupportDirectory();
      final directory = await root.createTemp('synthetic-reminder-boundary-');
      final file = File('${directory.path}/authority.sqlite');
      AppDatabase open() => AppDatabase(
        NativeDatabase(
          file,
          setup: (database) {
            database.execute('PRAGMA journal_mode=WAL');
            database.execute('PRAGMA busy_timeout=5000');
            database.execute('PRAGMA foreign_keys=ON');
          },
        ),
      );
      var database = open();
      var platform = MethodChannelStudyReminderPlatform(
        ownerWrites: DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => DateTime.now().toUtc(),
        ),
        isAndroid: true,
      );
      String? token;
      Object? testFailure;
      try {
        await database.customStatement(
          "INSERT INTO local_owners (id, created_at_utc_ms, is_active) "
          "VALUES ('synthetic-boundary-owner', 1, 1)",
        );
        await database.customStatement(
          "INSERT INTO study_reminder_preferences "
          "(owner_id, enabled, minute_of_day, timezone_id, revision, updated_at_utc_ms) "
          "VALUES ('synthetic-boundary-owner', 0, 60, 'UTC', 1, 1)",
        );
        await database.customStatement(
          "INSERT INTO runtime_flags (key, bool_value, source, updated_at_utc_ms) "
          "VALUES ('synthetic.durability', 1, 'synthetic', 1)",
        );
        token = await platform.bindScope(
          databasePath: file.path,
          ownerId: 'synthetic-boundary-owner',
        );
        expect(
          (await platform.cancel(scopeToken: token, revision: 1)).revision,
          1,
        );
        await database.transaction(() async {
          await database.customStatement(
            'UPDATE study_reminder_preferences SET revision=2, minute_of_day=120',
          );
          await database.customStatement(
            "UPDATE runtime_flags SET bool_value=0 WHERE key='synthetic.durability'",
          );
        });
        expect(
          (await platform.cancel(scopeToken: token, revision: 2)).revision,
          2,
        );
        await expectLater(
          platform.cancel(scopeToken: token, revision: 1),
          throwsA(
            isA<StudyReminderException>().having(
              (error) => error.code,
              'code',
              StudyReminderFailureCode.ownerChanged,
            ),
          ),
        );
        await database.close();
        database = open();
        platform = MethodChannelStudyReminderPlatform(
          ownerWrites: DriftOwnerWriteCoordinator(
            database,
            nowUtc: () => DateTime.now().toUtc(),
          ),
          isAndroid: true,
        );
        expect(
          (await database
                  .customSelect(
                    'SELECT revision FROM study_reminder_preferences',
                  )
                  .getSingle())
              .read<int>('revision'),
          2,
        );
        expect(
          (await database
                  .customSelect(
                    "SELECT bool_value FROM runtime_flags WHERE key='synthetic.durability'",
                  )
                  .getSingle())
              .read<int>('bool_value'),
          0,
        );
        expect(
          (await database.customSelect('PRAGMA quick_check').getSingle())
              .data
              .values
              .single,
          'ok',
        );
        expect(
          (await database.customSelect('PRAGMA journal_mode').getSingle())
              .data
              .values
              .single,
          'wal',
        );
      } catch (error) {
        testFailure = error;
        rethrow;
      } finally {
        try {
          if (token != null) await platform.retire(scopeToken: token);
        } catch (_) {
          if (testFailure == null) rethrow;
        } finally {
          try {
            await database.close();
          } finally {
            await directory.delete(recursive: true);
          }
        }
      }
    });
  });
}
