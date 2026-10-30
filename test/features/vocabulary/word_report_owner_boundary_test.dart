import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/word_report_harness.dart';

void main() {
  late WordReportHarness h;
  setUp(() async => h = await WordReportHarness.open());
  tearDown(() => h.close());

  for (final change in [
    'owner',
    'fence',
    'revision',
    'meaning',
    'source',
    'word-delete',
    'category',
    'receipt',
  ]) {
    test(
      'actual report INSERT followed by $change rolls back the whole transaction',
      () async {
        Map<String, Object?>? capturedFence;
        if (change == 'fence') {
          await h.storage.ownerWrites.beginDeletion(
            ownerId: configuredOwnerId,
            firebaseUid: configuredFirebaseUid,
            idempotencyKey: 'synthetic-report-deletion',
          );
          capturedFence =
              (await h.database
                      .customSelect(
                        "SELECT * FROM runtime_flags WHERE key = 'accountDeletion.ownerWriteIntent'",
                      )
                      .getSingle())
                  .data;
          await h.database.customStatement(
            "DELETE FROM runtime_flags WHERE key = 'accountDeletion.ownerWriteIntent'",
          );
        }
        final command = await h.prepare();
        final before = await h.storage.snapshot();
        final interference = WordReportInsertInterference((executor) async {
          switch (change) {
            case 'owner':
              await executor.runUpdate(
                'UPDATE local_owners SET is_active = (id = ?)',
                [configuredOtherOwnerId],
              );
            case 'fence':
              final row = capturedFence!;
              await executor.runInsert(
                'INSERT INTO runtime_flags (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
                row.values.toList(),
              );
            case 'revision':
              await executor.runUpdate(
                'UPDATE vocabulary_words SET local_revision = local_revision + 1 WHERE id = ?',
                [command.target.wordId],
              );
            case 'meaning':
              await executor.runUpdate(
                'UPDATE vocabulary_words SET meaning = ? WHERE id = ?',
                ['changed same revision', command.target.wordId],
              );
            case 'source':
              await executor.runUpdate(
                'UPDATE vocabulary_words SET source = ? WHERE id = ?',
                ['changed source', command.target.wordId],
              );
            case 'word-delete':
              await executor.runUpdate(
                'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
                [command.target.wordId],
              );
            case 'category':
              await executor.runUpdate(
                'UPDATE vocabulary_categories SET owner_id = ? WHERE id = ?',
                [configuredOtherOwnerId, command.target.categoryId],
              );
            case 'receipt':
              await executor.runUpdate(
                'UPDATE word_reports SET comment = ? WHERE id = ?',
                ['altered valid receipt', command.id],
              );
          }
        });
        final expected = change == 'owner' || change == 'fence'
            ? throwsA(isA<AccountDeletionException>())
            : reportFailure(
                change == 'receipt'
                    ? WordReportFailureCode.unavailable
                    : WordReportFailureCode.staleTarget,
              );
        await expectLater(
          h.database.runWithInterceptor(
            () => h.repository.submit(command),
            interceptor: interference,
          ),
          expected,
        );
        expect(interference.fired, isTrue);
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  for (final change in ['owner', 'fence', 'receipt']) {
    test(
      'historical replay still verifies final $change after its original row read',
      () async {
        final command = await h.prepare();
        await h.repository.submit(command);
        Map<String, Object?>? capturedFence;
        if (change == 'fence') {
          await h.storage.ownerWrites.beginDeletion(
            ownerId: configuredOwnerId,
            firebaseUid: configuredFirebaseUid,
            idempotencyKey: 'synthetic-report-replay-deletion',
          );
          capturedFence =
              (await h.database
                      .customSelect(
                        "SELECT * FROM runtime_flags WHERE key = 'accountDeletion.ownerWriteIntent'",
                      )
                      .getSingle())
                  .data;
          await h.database.customStatement(
            "DELETE FROM runtime_flags WHERE key = 'accountDeletion.ownerWriteIntent'",
          );
        }
        final before = await h.storage.snapshot();
        final interference = WordReportReadInterference((executor) async {
          if (change == 'owner') {
            await executor.runUpdate(
              'UPDATE local_owners SET is_active = (id = ?)',
              [configuredOtherOwnerId],
            );
          } else if (change == 'fence') {
            final row = capturedFence!;
            await executor.runInsert(
              'INSERT INTO runtime_flags (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
              row.values.toList(),
            );
          } else {
            await executor.runUpdate(
              'UPDATE word_reports SET comment = ? WHERE id = ?',
              ['changed after original read', command.id],
            );
          }
        });
        await expectLater(
          h.database.runWithInterceptor(
            () => h.repository.submit(command),
            interceptor: interference,
          ),
          change == 'receipt'
              ? reportFailure(WordReportFailureCode.unavailable)
              : throwsA(isA<AccountDeletionException>()),
        );
        expect(interference.fired, isTrue);
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'preexisting actual owner deletion fence denies both fresh and historical submission',
    () async {
      final command = await h.prepare();
      await h.repository.submit(command);
      final fresh = await h.prepare();
      await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-report-preexisting-fence',
      );
      final before = await h.storage.snapshot();
      for (final pending in [command, fresh]) {
        await expectLater(
          h.repository.submit(pending),
          throwsA(isA<AccountDeletionException>()),
        );
      }
      expect(await h.storage.snapshot(), before);
    },
  );
}

Matcher reportFailure(WordReportFailureCode code) => throwsA(
  isA<WordReportException>().having((error) => error.code, 'code', code),
);
