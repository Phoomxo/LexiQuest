import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart' show AppDatabase;
import 'package:vocab_learning_app/features/vocabulary/application/word_report_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_vocabulary_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_word_report_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/vocabulary_word.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/word_report.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class WordReportHarness {
  WordReportHarness._(this.storage) {
    repository = DriftWordReportRepository(
      database: database,
      ownerWriteCoordinator: storage.ownerWrites,
    );
    useCases = WordReportUseCases(
      repository: repository,
      generateId: () => 'synthetic-report-${++_id}',
      nowUtc: () => now,
    );
  }

  final ConfiguredQuizHarness storage;
  late final DriftWordReportRepository repository;
  late final WordReportUseCases useCases;
  int _id = 0;
  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;

  static Future<WordReportHarness> open({File? file, bool seed = true}) async =>
      WordReportHarness._(
        await ConfiguredQuizHarness.open(file: file, seed: seed),
      );

  Future<VocabularyWord> word({
    String? wordId,
    String ownerId = configuredOwnerId,
    String categoryId = configuredCategoryId,
  }) async =>
      (await DriftVocabularyRepository(
        database,
      ).watchWords(ownerId, categoryId).first).singleWhere(
        (word) => word.id == (wordId ?? configuredWordIds.first),
      );

  Future<WordReportCommand> prepare({
    WordReportTarget? target,
    ReportReason reason = ReportReason.incorrectMeaning,
    String? comment = 'synthetic detail',
  }) async => useCases.prepareSubmit(
    expectedOwnerId: configuredOwnerId,
    target: target ?? WordReportTarget.fromWord(await word()),
    reason: reason,
    comment: comment,
  );

  Future<List<StoredWordReport>> reports([
    String ownerId = configuredOwnerId,
  ]) => repository.watchOwner(ownerId).first;

  Future<void> insertFixture(StoredWordReport report) async {
    final row = report.toStorage();
    await database.customStatement(
      'INSERT INTO word_reports (${row.keys.join(',')}) VALUES (${List.filled(row.length, '?').join(',')})',
      row.values.toList(),
    );
  }

  Future<void> close() => storage.close();
}

final class WordReportInsertInterference extends drift.QueryInterceptor {
  WordReportInsertInterference(this.afterInsert);
  final Future<void> Function(drift.QueryExecutor) afterInsert;
  bool fired = false;

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!fired &&
        RegExp(
          r'insert\s+into\s+"?word_reports',
          caseSensitive: false,
        ).hasMatch(statement)) {
      fired = true;
      await afterInsert(executor);
    }
    return result;
  }
}

final class WordReportReadInterference extends drift.QueryInterceptor {
  WordReportReadInterference(this.afterRead);
  final Future<void> Function(drift.QueryExecutor) afterRead;
  bool fired = false;

  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (!fired && statement.toLowerCase().contains('from word_reports')) {
      fired = true;
      await afterRead(executor);
    }
    return result;
  }
}
