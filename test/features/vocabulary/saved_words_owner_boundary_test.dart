import 'package:drift/drift.dart' as drift;
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

import '../../support/saved_words_data_harness.dart';

void main() {
  late SavedWordsDataHarness h;
  setUp(() async => h = await SavedWordsDataHarness.open());
  tearDown(() => h.close());

  for (final insert in [true, false]) {
    for (final change in ['owner', 'fence', 'word', 'category', 'receipt']) {
      test(
        '${insert ? 'INSERT' : 'UPDATE'} followed by actual $change change rolls back every row',
        () async {
          if (!insert) {
            await h.set(true);
            await h.set(false);
          }
          Map<String, Object?>? capturedFence;
          if (change == 'fence') {
            await h.storage.ownerWrites.beginDeletion(
              ownerId: configuredOwnerId,
              firebaseUid: configuredFirebaseUid,
              idempotencyKey: 'synthetic-saved-deletion',
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
          final command = await h.command();
          final before = await h.storage.snapshot();
          final interference = SavedWordsSqlInterference((executor) async {
            switch (change) {
              case 'owner':
                await executor.runUpdate(
                  'UPDATE local_owners SET is_active = (id = ?)',
                  [configuredOtherOwnerId],
                );
              case 'fence':
                final fence = capturedFence!;
                await executor.runInsert(
                  'INSERT INTO runtime_flags (${fence.keys.join(',')}) VALUES (${List.filled(fence.length, '?').join(',')})',
                  fence.values.toList(),
                );
              case 'word':
                await executor.runUpdate(
                  'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
                  [command.wordId],
                );
              case 'category':
                await executor.runUpdate(
                  'UPDATE vocabulary_categories SET owner_id = ? WHERE id = ?',
                  [configuredOtherOwnerId, configuredCategoryId],
                );
              case 'receipt':
                await executor.runUpdate(
                  'UPDATE saved_words SET last_mutation_id = ? WHERE owner_id = ? AND word_id = ?',
                  [
                    'synthetic-replaced-receipt',
                    configuredOwnerId,
                    command.wordId,
                  ],
                );
            }
          }, insert: insert);
          await expectLater(
            h.database.runWithInterceptor(
              () => h.repository.apply(command),
              interceptor: interference,
            ),
            change == 'owner' || change == 'fence'
                ? throwsA(isA<AccountDeletionException>())
                : _unavailable(),
          );
          expect(interference.fired, isTrue);
          expect(await h.storage.snapshot(), before);
        },
      );
    }
  }

  for (final path in ['replay', 'conflict', 'unchanged']) {
    test(
      '$path still performs final owner verification after its row read',
      () async {
        SavedWordMutation command;
        if (path == 'unchanged') {
          command = await h.command(saved: false);
        } else {
          command = await h.command();
          await h.repository.apply(command);
          if (path == 'conflict') {
            await h.set(false);
          }
        }
        final before = await h.storage.snapshot();
        final interference = _AfterSavedRead(
          (executor) => executor.runUpdate(
            'UPDATE local_owners SET is_active = (id = ?)',
            [configuredOtherOwnerId],
          ),
        );
        await expectLater(
          h.database.runWithInterceptor(
            () => h.repository.apply(command),
            interceptor: interference,
          ),
          throwsA(isA<AccountDeletionException>()),
        );
        expect(interference.fired, isTrue);
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'foreign owner and a real preexisting deletion fence deny save',
    () async {
      final command = await h.command();
      await h.storage.switchOwner(configuredOtherOwnerId);
      await expectLater(
        h.repository.apply(command),
        throwsA(isA<AccountDeletionException>()),
      );
      await h.storage.switchOwner(configuredOwnerId);
      await h.storage.ownerWrites.beginDeletion(
        ownerId: configuredOwnerId,
        firebaseUid: configuredFirebaseUid,
        idempotencyKey: 'synthetic-saved-fence',
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.repository.apply(command),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'foreign word or category cannot be saved through valid individual FKs',
    () async {
      final foreign = SavedWordMutation(
        mutationId: 'synthetic-foreign-save',
        expectedOwnerId: configuredOwnerId,
        wordId: 'synthetic-configured-other-word',
        desiredIsSaved: true,
        expectedRevision: 0,
        occurredAtUtc: h.now,
      );
      final before = await h.storage.snapshot();
      await expectLater(h.repository.apply(foreign), _unavailable());
      expect(await h.storage.snapshot(), before);
      await h.database.customStatement(
        'UPDATE vocabulary_words SET category_id = ? WHERE id = ?',
        [configuredOtherCategoryId, configuredWordIds.first],
      );
      final changed = await h.storage.snapshot();
      await expectLater(h.repository.apply(await h.command()), _unavailable());
      expect(await h.storage.snapshot(), changed);
    },
  );

  test(
    'malformed stored state fails closed and is never repaired by a new command',
    () async {
      await h.set(true);
      final command = await h.command(saved: false);
      await h.database.customStatement('PRAGMA ignore_check_constraints = ON');
      await h.database.customStatement(
        'UPDATE saved_words SET local_revision = 0',
      );
      await h.database.customStatement('PRAGMA ignore_check_constraints = OFF');
      expect(
        (await h.database
                .customSelect('PRAGMA ignore_check_constraints')
                .getSingle())
            .data
            .values
            .single,
        0,
      );
      final before = await h.storage.snapshot();
      await expectLater(h.repository.apply(command), _unavailable());
      expect(await h.storage.snapshot(), before);
    },
  );
}

Matcher _unavailable() => throwsA(
  isA<SavedWordsException>().having(
    (error) => error.code,
    'code',
    SavedWordsFailureCode.unavailable,
  ),
);

final class _AfterSavedRead extends drift.QueryInterceptor {
  _AfterSavedRead(this.afterRead);
  final Future<int> Function(drift.QueryExecutor) afterRead;
  bool fired = false;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!fired && statement.toLowerCase().contains('from saved_words')) {
      fired = true;
      await afterRead(executor);
    }
    return result;
  }
}
