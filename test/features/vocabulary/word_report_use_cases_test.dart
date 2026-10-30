import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

void main() {
  final target = WordReportTarget.fromWord(
    VocabularyWord(
      id: 'synthetic-word',
      ownerId: 'synthetic-owner',
      categoryId: 'synthetic-category',
      spelling: 'station',
      normalizedSpelling: 'station',
      meaning: 'synthetic gloss',
      normalizedMeaning: 'synthetic gloss',
      partOfSpeech: 'noun',
      source: 'manual',
      isGlobal: false,
      localRevision: 2,
      isDeleted: false,
      createdAtUtc: DateTime.utc(2026, 10, 30),
      updatedAtUtc: DateTime.utc(2026, 10, 30),
    ),
  );

  test(
    'first confirmation captures one original ID/ms time; retries never prepare again',
    () async {
      final repository = _Repository();
      var ids = 0;
      var clocks = 0;
      final now = DateTime.utc(2026, 10, 30, 12, 0, 0, 123, 456);
      final useCases = WordReportUseCases(
        repository: repository,
        generateId: () => 'synthetic-${++ids}',
        nowUtc: () {
          clocks++;
          return now;
        },
      );
      final command = useCases.prepareSubmit(
        expectedOwnerId: 'synthetic-owner',
        target: target,
        reason: ReportReason.other,
        comment: '  synthetic detail  ',
      );
      expect(command.target, same(target));
      expect(command.id, 'word-report:synthetic-1');
      expect(command.comment, 'synthetic detail');
      expect(
        command.queuedAtUtc.millisecondsSinceEpoch,
        now.millisecondsSinceEpoch,
      );
      expect(command.queuedAtUtc.microsecondsSinceEpoch % 1000, 0);
      await useCases.submit(command);
      await useCases.submit(command);
      expect(repository.commands, [same(command), same(command)]);
      expect((ids, clocks), (1, 1));
    },
  );

  test(
    'watch creates no owner ID time or submission and blank optional comment becomes null',
    () async {
      final repository = _Repository();
      final watch = WordReportUseCases(
        repository: repository,
        generateId: () => throw StateError('ID unused'),
        nowUtc: () => throw StateError('clock unused'),
      );
      expect(await watch.watchOwner('synthetic-owner').first, isEmpty);
      expect(repository.owners, ['synthetic-owner']);
      expect(repository.commands, isEmpty);
      final prepare = WordReportUseCases(
        repository: repository,
        generateId: () => 'synthetic',
        nowUtc: () => DateTime.utc(2026, 10, 30),
      );
      expect(
        prepare
            .prepareSubmit(
              expectedOwnerId: 'synthetic-owner',
              target: target,
              reason: ReportReason.spelling,
              comment: ' \n ',
            )
            .comment,
        isNull,
      );
    },
  );

  test(
    'ordinary clock reversal is admitted while non-UTC clock and missing other detail reject',
    () {
      final now = DateTime.utc(2026, 10, 29);
      final useCases = WordReportUseCases(
        repository: _Repository(),
        generateId: () => 'synthetic',
        nowUtc: () => now,
      );
      expect(
        useCases
            .prepareSubmit(
              expectedOwnerId: 'synthetic-owner',
              target: target,
              reason: ReportReason.spelling,
            )
            .queuedAtUtc,
        now,
      );
      expect(
        () => useCases.prepareSubmit(
          expectedOwnerId: 'synthetic-owner',
          target: target,
          reason: ReportReason.other,
        ),
        throwsArgumentError,
      );
      final local = WordReportUseCases(
        repository: _Repository(),
        generateId: () => 'synthetic',
        nowUtc: () => now.toLocal(),
      );
      expect(
        () => local.prepareSubmit(
          expectedOwnerId: 'synthetic-owner',
          target: target,
          reason: ReportReason.spelling,
        ),
        throwsArgumentError,
      );
    },
  );
}

final class _Repository implements WordReportRepository {
  final commands = <WordReportCommand>[];
  final owners = <String>[];
  @override
  Future<SubmitResult> submit(WordReportCommand command) async {
    commands.add(command);
    return SubmitResult(
      status: SubmitStatus.replayed,
      report: StoredWordReport(
        id: command.id,
        ownerId: command.expectedOwnerId,
        target: command.target,
        reason: command.reason,
        comment: command.comment,
        queuedAtUtc: command.queuedAtUtc,
      ),
    );
  }

  @override
  Stream<List<StoredWordReport>> watchOwner(String expectedOwnerId) {
    owners.add(expectedOwnerId);
    return Stream.value(const []);
  }
}
