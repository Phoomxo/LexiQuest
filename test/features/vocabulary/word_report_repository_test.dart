import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/word_report_harness.dart';

void main() {
  late WordReportHarness h;
  setUp(() async => h = await WordReportHarness.open());
  tearDown(() => h.close());

  test(
    'queued receipt stores exactly ten original fields with every other table byte-identical',
    () async {
      final command = await h.prepare();
      final before = await h.storage.snapshot();
      final result = await h.repository.submit(command);
      expect(result.status, SubmitStatus.queued);
      expect(result.report.matchesCommand(command), isTrue);
      final row =
          (await h.database
                  .customSelect('SELECT * FROM word_reports')
                  .getSingle())
              .data;
      expect(row, result.report.toStorage());
      expect(row, hasLength(10));
      final after = await h.storage.snapshot();
      for (final table in before.keys.where(
        (table) => table != 'word_reports',
      )) {
        expect(after[table], before[table], reason: table);
      }
      expect(await h.storage.count('word_reports'), 1);
    },
  );

  test(
    'lost ACK reconstruction replays the original ID payload and time without reinsertion',
    () async {
      final command = await h.prepare();
      final first = await h.repository.submit(command);
      final before = await h.storage.snapshot();
      h.now = h.now.add(const Duration(days: 5));
      final restarted = DriftWordReportRepository(
        database: h.database,
        ownerWriteCoordinator: h.storage.ownerWrites,
      );
      final replay = await restarted.submit(command);
      expect(replay.status, SubmitStatus.replayed);
      expect(replay.report.sameFacts(first.report), isTrue);
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'concurrent same-ID submissions yield one queued and one replay with no duplicate',
    () async {
      final command = await h.prepare();
      final before = await h.storage.snapshot();
      final results = await Future.wait([
        h.repository.submit(command),
        h.repository.submit(command),
      ]);
      expect(
        results.where((result) => result.status == SubmitStatus.queued),
        hasLength(1),
      );
      expect(
        results.where((result) => result.status == SubmitStatus.replayed),
        hasLength(1),
      );
      expect(results[0].report.sameFacts(results[1].report), isTrue);
      final after = await h.storage.snapshot();
      for (final table in before.keys.where(
        (table) => table != 'word_reports',
      )) {
        expect(after[table], before[table], reason: table);
      }
      expect(await h.storage.count('word_reports'), 1);
    },
  );

  test(
    'two explicit IDs for the same reviewed payload remain two reports',
    () async {
      final target = WordReportTarget.fromWord(await h.word());
      final first = await h.prepare(target: target);
      final second = await h.prepare(target: target);
      final results = await Future.wait([
        h.repository.submit(first),
        h.repository.submit(second),
      ]);
      expect(
        results.map((result) => result.status),
        everyElement(SubmitStatus.queued),
      );
      expect(results.map((result) => result.report.id).toSet(), hasLength(2));
      expect(await h.storage.count('word_reports'), 2);
    },
  );

  for (final alteration in ['target', 'reason', 'comment', 'time']) {
    test(
      'same owned ID with changed $alteration collides without changing its receipt',
      () async {
        final command = await h.prepare();
        await h.repository.submit(command);
        final altered = WordReportCommand(
          id: command.id,
          expectedOwnerId: command.expectedOwnerId,
          target: alteration == 'target'
              ? WordReportTarget.fromWord(
                  (await h.word()).copyWith(
                    meaning: 'altered synthetic meaning',
                  ),
                )
              : command.target,
          reason: alteration == 'reason'
              ? ReportReason.spelling
              : command.reason,
          comment: alteration == 'comment'
              ? 'different detail'
              : command.comment,
          queuedAtUtc: alteration == 'time'
              ? command.queuedAtUtc.add(const Duration(milliseconds: 1))
              : command.queuedAtUtc,
        );
        final before = await h.storage.snapshot();
        await expectLater(
          h.repository.submit(altered),
          reportFailure(WordReportFailureCode.collision),
        );
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  for (final mutation in [
    'revision',
    'meaning',
    'source',
    'word-delete',
    'category-delete',
  ]) {
    test(
      'fresh report rejects $mutation after displayed target capture, including same-revision hash changes',
      () async {
        final command = await h.prepare();
        if (mutation == 'category-delete') {
          await h.database.customStatement(
            'UPDATE vocabulary_categories SET is_deleted = 1 WHERE id = ?',
            [configuredCategoryId],
          );
        } else {
          final set = switch (mutation) {
            'revision' => 'local_revision = local_revision + 1',
            'meaning' => "meaning = 'changed same revision'",
            'source' => "source = 'changed source'",
            _ => 'is_deleted = 1',
          };
          await h.database.customStatement(
            'UPDATE vocabulary_words SET $set WHERE id = ?',
            [command.target.wordId],
          );
        }
        final before = await h.storage.snapshot();
        await expectLater(
          h.repository.submit(command),
          reportFailure(WordReportFailureCode.staleTarget),
        );
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  for (final change in ['edit', 'soft-delete', 'hard-delete', 'hard-parents']) {
    test(
      'historical receipt survives $change while a new report still requires the original live target',
      () async {
        final command = await h.prepare();
        final original = (await h.repository.submit(command)).report;
        switch (change) {
          case 'edit':
            await h.database.customStatement(
              "UPDATE vocabulary_words SET meaning = 'new meaning',local_revision = local_revision + 1 WHERE id = ?",
              [command.target.wordId],
            );
          case 'soft-delete':
            await h.database.customStatement(
              'UPDATE vocabulary_words SET is_deleted = 1 WHERE id = ?',
              [command.target.wordId],
            );
          case 'hard-delete':
            await h.database.customStatement(
              'DELETE FROM vocabulary_words WHERE id = ?',
              [command.target.wordId],
            );
          case 'hard-parents':
            await h.database.customStatement(
              'DELETE FROM vocabulary_words WHERE category_id = ?',
              [command.target.categoryId],
            );
            await h.database.customStatement(
              'DELETE FROM vocabulary_categories WHERE id = ?',
              [command.target.categoryId],
            );
        }
        final before = await h.storage.snapshot();
        final replay = await h.repository.submit(command);
        expect(replay.status, SubmitStatus.replayed);
        expect(replay.report.sameFacts(original), isTrue);
        final fresh = WordReportCommand(
          id: 'word-report:synthetic-new-$change',
          expectedOwnerId: command.expectedOwnerId,
          target: command.target,
          reason: command.reason,
          comment: command.comment,
          queuedAtUtc: command.queuedAtUtc,
        );
        await expectLater(
          h.repository.submit(fresh),
          reportFailure(WordReportFailureCode.staleTarget),
        );
        expect((await h.reports()).single.sameFacts(original), isTrue);
        expect(await h.storage.snapshot(), before);
      },
    );
  }

  test(
    'same-ID vocabulary recreation leaves original report immutable and needs new explicit target',
    () async {
      final word = await h.word();
      final command = await h.prepare();
      final original = (await h.repository.submit(command)).report;
      final vocabulary = DriftVocabularyRepository(h.database);
      await vocabulary.deleteWord(
        ownerId: configuredOwnerId,
        wordId: word.id,
        nowUtc: h.now,
      );
      final restored = await vocabulary.createWord(word);
      expect(restored.id, word.id);
      expect(restored.localRevision, greaterThan(word.localRevision));
      expect(
        (await h.repository.submit(command)).report.sameFacts(original),
        isTrue,
      );
      final newIntent = await h.prepare(
        target: WordReportTarget.fromWord(restored),
      );
      expect(
        (await h.repository.submit(newIntent)).status,
        SubmitStatus.queued,
      );
      expect(await h.storage.count('word_reports'), 2);
      expect(
        (await h.reports())
            .singleWhere((row) => row.id == original.id)
            .sameFacts(original),
        isTrue,
      );
    },
  );

  test(
    'foreign ID is unavailable without exposing even a corrupt foreign payload',
    () async {
      final command = await h.prepare();
      final other = await h.word(
        ownerId: configuredOtherOwnerId,
        categoryId: configuredOtherCategoryId,
        wordId: 'synthetic-configured-other-word',
      );
      const private = 'SYNTHETIC_PRIVATE_FOREIGN_REPORT';
      final foreign = StoredWordReport(
        id: command.id,
        ownerId: configuredOtherOwnerId,
        target: WordReportTarget.fromWord(other),
        reason: ReportReason.spelling,
        comment: private,
        queuedAtUtc: h.now,
      );
      await h.insertFixture(foreign);
      await h.database.customStatement(
        'UPDATE word_reports SET snapshot_sha256 = ? WHERE id = ?',
        [List.filled(64, '0').join(), command.id],
      );
      final before = await h.storage.snapshot();
      try {
        await h.repository.submit(command);
        fail('foreign report ID was admitted');
      } on WordReportException catch (error) {
        expect(error.code, WordReportFailureCode.unavailable);
        expect(error.toString(), isNot(contains(private)));
      }
      expect(await h.reports(), isEmpty);
      expect(await h.storage.snapshot(), before);
    },
  );

  test('fresh foreign word target never becomes an owned report', () async {
    final foreign = await h.word(
      ownerId: configuredOtherOwnerId,
      categoryId: configuredOtherCategoryId,
      wordId: 'synthetic-configured-other-word',
    );
    final command = await h.prepare(target: WordReportTarget.fromWord(foreign));
    final before = await h.storage.snapshot();
    await expectLater(
      h.repository.submit(command),
      reportFailure(WordReportFailureCode.staleTarget),
    );
    expect(await h.storage.snapshot(), before);
  });

  test(
    'owner remap changes authorization only and old historical pins still replay without parents',
    () async {
      final command = await h.prepare();
      final original = (await h.repository.submit(command)).report;
      await h.database.customStatement(
        'DELETE FROM vocabulary_words WHERE id = ?',
        [command.target.wordId],
      );
      await h.database.customStatement(
        'UPDATE word_reports SET owner_id = ? WHERE id = ?',
        [configuredOtherOwnerId, command.id],
      );
      await h.storage.switchOwner(configuredOtherOwnerId);
      final reauthorized = WordReportCommand(
        id: command.id,
        expectedOwnerId: configuredOtherOwnerId,
        target: command.target,
        reason: command.reason,
        comment: command.comment,
        queuedAtUtc: command.queuedAtUtc,
      );
      final before = await h.storage.snapshot();
      final replay = await h.repository.submit(reauthorized);
      expect(replay.status, SubmitStatus.replayed);
      expect(replay.report.ownerId, configuredOtherOwnerId);
      expect(replay.report.sameHistoricalPayload(original), isTrue);
      await expectLater(
        h.repository.submit(command),
        throwsA(isA<AccountDeletionException>()),
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'ambient transaction and fake/different-database coordinators cannot acknowledge a receipt',
    () async {
      final command = await h.prepare();
      final before = await h.storage.snapshot();
      await h.database.transaction(() async {
        await expectLater(
          h.repository.submit(command),
          reportFailure(WordReportFailureCode.unavailable),
        );
      });
      expect(await h.storage.snapshot(), before);
      expect(
        () => DriftWordReportRepository(
          database: h.database,
          ownerWriteCoordinator: _FakeCoordinator(),
        ),
        throwsArgumentError,
      );
      final other = await WordReportHarness.open();
      try {
        expect(
          () => DriftWordReportRepository(
            database: h.database,
            ownerWriteCoordinator: other.storage.ownerWrites,
          ),
          throwsArgumentError,
        );
      } finally {
        await other.close();
      }
    },
  );

  test(
    'real file restart retains the exact receipt independent of a surviving word',
    () async {
      final tempRoot = await Directory.systemTemp.resolveSymbolicLinks();
      final directory = await Directory(
        tempRoot,
      ).createTemp('lexiquest-word-reports-');
      final file = File(
        '${directory.path}${Platform.pathSeparator}reports.sqlite',
      );
      var stored = await WordReportHarness.open(file: file);
      try {
        final command = await stored.prepare();
        final original = (await stored.repository.submit(command)).report;
        await stored.database.customStatement(
          'DELETE FROM vocabulary_words WHERE id = ?',
          [command.target.wordId],
        );
        await stored.close();
        stored = await WordReportHarness.open(file: file, seed: false);
        expect((await stored.reports()).single.sameFacts(original), isTrue);
        expect(
          (await stored.repository.submit(command)).report.sameFacts(original),
          isTrue,
        );
      } finally {
        await stored.close();
        final resolved = await directory.resolveSymbolicLinks();
        expect(
          resolved,
          startsWith(
            '$tempRoot${Platform.pathSeparator}lexiquest-word-reports-',
          ),
        );
        expect(resolved, directory.absolute.path);
        await Directory(resolved).delete(recursive: true);
      }
    },
  );
}

Matcher reportFailure(WordReportFailureCode code) => throwsA(
  isA<WordReportException>().having((error) => error.code, 'code', code),
);

final class _FakeCoordinator extends Fake implements OwnerWriteCoordinator {}
