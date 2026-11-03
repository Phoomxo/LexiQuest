import 'dart:async';
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

  testWidgets('native reminders wait for background writers and recheck authority', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final root = await getApplicationSupportDirectory();
      final directory = await root.createTemp('synthetic-reminder-contention-');
      final file = File('${directory.path}/authority.sqlite');
      final database = AppDatabase(
        NativeDatabase.createInBackground(
          file,
          setup: (database) {
            database.execute('PRAGMA journal_mode=WAL');
            database.execute('PRAGMA busy_timeout=5000');
            database.execute('PRAGMA foreign_keys=ON');
          },
        ),
      );
      final platform = MethodChannelStudyReminderPlatform(
        ownerWrites: DriftOwnerWriteCoordinator(
          database,
          nowUtc: () => DateTime.utc(2026, 11, 3),
        ),
        isAndroid: true,
      );
      String? token;
      Object? testFailure;
      try {
        await database.customStatement(
          "INSERT INTO local_owners (id, created_at_utc_ms, is_active) "
          "VALUES ('synthetic-contention-owner', 1, 1), "
          "('synthetic-next-owner', 1, 0)",
        );
        await database.customStatement(
          "INSERT INTO study_reminder_preferences "
          "(owner_id, enabled, minute_of_day, timezone_id, revision, updated_at_utc_ms) "
          "VALUES ('synthetic-contention-owner', 0, 60, 'UTC', 1, 1)",
        );
        await database.customStatement(
          "INSERT INTO runtime_flags (key, bool_value, source, updated_at_utc_ms) "
          "VALUES ('synthetic.contention', 1, 'synthetic', 1)",
        );
        await _whileWriterHeld(
          database,
          hold: const Duration(seconds: 3),
          write: () => database.customStatement(
            "UPDATE runtime_flags SET bool_value=0 WHERE key='synthetic.contention'",
          ),
          request: () async {
            token = await platform.bindScope(
              databasePath: file.path,
              ownerId: 'synthetic-contention-owner',
            );
          },
        );
        expect(token, isNotEmpty);
        expect(
          (await platform.cancel(scopeToken: token!, revision: 1)).revision,
          1,
        );
        expect(
          (await database
                  .customSelect(
                    "SELECT bool_value FROM runtime_flags WHERE key='synthetic.contention'",
                  )
                  .getSingle())
              .read<int>('bool_value'),
          0,
        );

        final changedAuthority = throwsA(
          isA<StudyReminderException>().having(
            (error) => error.code,
            'code',
            StudyReminderFailureCode.ownerChanged,
          ),
        );
        await _whileWriterHeld(
          database,
          write: () => database.customStatement(
            'UPDATE study_reminder_preferences SET revision=2',
          ),
          request: () => expectLater(
            platform.cancel(scopeToken: token!, revision: 1),
            changedAuthority,
          ),
        );
        expect(
          (await platform.cancel(scopeToken: token!, revision: 2)).revision,
          2,
        );
        await _whileWriterHeld(
          database,
          write: () async {
            await database.customStatement(
              'UPDATE local_owners SET is_active=0 WHERE is_active=1',
            );
            await database.customStatement(
              "UPDATE local_owners SET is_active=1 WHERE id='synthetic-next-owner'",
            );
          },
          request: () => expectLater(
            platform.bindScope(
              databasePath: file.path,
              ownerId: 'synthetic-contention-owner',
            ),
            changedAuthority,
          ),
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

Future<void> _whileWriterHeld(
  AppDatabase database, {
  required Future<void> Function() write,
  required Future<void> Function() request,
  Duration hold = Duration.zero,
}) async {
  final writerHeld = Completer<void>();
  final releaseWriter = Completer<void>();
  final writer = database.transaction(() async {
    await write();
    writerHeld.complete();
    await releaseWriter.future;
  });
  Future<void>? pending;
  Object? requestFailure;
  StackTrace? requestStack;
  var completedBeforeCommit = false;
  try {
    await Future.any<void>([writerHeld.future, writer]);
    pending = Future<void>.sync(request).then<void>(
      (_) => completedBeforeCommit = !releaseWriter.isCompleted,
      onError: (Object error, StackTrace stack) {
        requestFailure = error;
        requestStack = stack;
      },
    );
    await Future<void>.delayed(hold);
  } finally {
    releaseWriter.complete();
    await writer;
    await pending;
  }
  if (requestFailure != null) {
    Error.throwWithStackTrace(requestFailure!, requestStack!);
  }
  expect(completedBeforeCommit, isFalse);
}
