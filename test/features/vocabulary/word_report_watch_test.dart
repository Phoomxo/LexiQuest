import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import '../../support/word_report_harness.dart';

void main() {
  late WordReportHarness h;
  setUp(() async => h = await WordReportHarness.open());
  tearDown(() => h.close());

  test(
    'watch is pure, owner-only, immutable and sorted by original time then ID',
    () async {
      final target = WordReportTarget.fromWord(await h.word());
      final at = h.now;
      final reports = [
        StoredWordReport(
          id: 'word-report:z',
          ownerId: configuredOwnerId,
          target: target,
          reason: ReportReason.spelling,
          comment: null,
          queuedAtUtc: at,
        ),
        StoredWordReport(
          id: 'word-report:a',
          ownerId: configuredOwnerId,
          target: target,
          reason: ReportReason.spelling,
          comment: null,
          queuedAtUtc: at,
        ),
        StoredWordReport(
          id: 'word-report:earlier',
          ownerId: configuredOwnerId,
          target: target,
          reason: ReportReason.spelling,
          comment: null,
          queuedAtUtc: at.subtract(const Duration(days: 1)),
        ),
        StoredWordReport(
          id: 'word-report:foreign',
          ownerId: configuredOtherOwnerId,
          target: target,
          reason: ReportReason.other,
          comment: 'synthetic foreign detail',
          queuedAtUtc: at,
        ),
      ];
      for (final report in reports) {
        await h.insertFixture(report);
      }
      final before = await h.storage.snapshot();
      final own = await h.reports();
      expect(own.map((row) => row.id), [
        'word-report:earlier',
        'word-report:a',
        'word-report:z',
      ]);
      expect(() => own.clear(), throwsUnsupportedError);
      expect(await h.reports('synthetic-unknown-owner'), isEmpty);
      expect(
        (await h.reports(configuredOtherOwnerId)).single.id,
        'word-report:foreign',
      );
      expect(await h.storage.snapshot(), before);
    },
  );

  test(
    'live watch sees committed insert then retains historical content after word deletion',
    () async {
      final iterator = StreamIterator<List<StoredWordReport>>(
        h.repository.watchOwner(configuredOwnerId),
      );
      try {
        expect(await iterator.moveNext(), isTrue);
        expect(iterator.current, isEmpty);
        final inserted = iterator.moveNext();
        final command = await h.prepare();
        await h.repository.submit(command);
        expect(await inserted, isTrue);
        expect(iterator.current.single.matchesCommand(command), isTrue);
        await h.database.customStatement(
          'DELETE FROM vocabulary_words WHERE id = ?',
          [command.target.wordId],
        );
        expect((await h.reports()).single.matchesCommand(command), isTrue);
      } finally {
        await iterator.cancel();
      }
    },
  );

  test(
    'corrupt owned snapshot is unavailable to watch or replay and never repaired',
    () async {
      final command = await h.prepare();
      await h.repository.submit(command);
      await h.database.customStatement(
        'UPDATE word_reports SET snapshot_sha256 = ?',
        [List.filled(64, '0').join()],
      );
      final before = await h.storage.snapshot();
      await expectLater(
        h.reports(),
        reportFailure(WordReportFailureCode.unavailable),
      );
      await expectLater(
        h.repository.submit(command),
        reportFailure(WordReportFailureCode.unavailable),
      );
      expect(await h.storage.snapshot(), before);
    },
  );
}

Matcher reportFailure(WordReportFailureCode code) => throwsA(
  isA<WordReportException>().having((error) => error.code, 'code', code),
);
