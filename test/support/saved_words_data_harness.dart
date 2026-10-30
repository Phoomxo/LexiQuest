import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/vocabulary/application/saved_words_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/features/vocabulary/domain/saved_words.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class SavedWordsDataHarness {
  SavedWordsDataHarness._(this.storage) {
    repository = DriftSavedWordsRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    useCases = SavedWordsUseCases(
      repository: repository,
      generateId: () => 'synthetic-saved-${++_id}',
      nowUtc: () => now,
    );
  }

  final ConfiguredQuizHarness storage;
  late final DriftSavedWordsRepository repository;
  late final SavedWordsUseCases useCases;
  int _id = 0;
  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;

  static Future<SavedWordsDataHarness> open({
    File? file,
    bool seed = true,
  }) async => SavedWordsDataHarness._(
    await ConfiguredQuizHarness.open(file: file, seed: seed),
  );

  Future<SavedWordsSnapshot> snapshot([String ownerId = configuredOwnerId]) =>
      repository.watchOwner(ownerId).first;

  Future<SavedWordState> state({
    String? wordId,
    String ownerId = configuredOwnerId,
  }) async =>
      (await snapshot(ownerId)).stateFor(wordId ?? configuredWordIds.first);

  Future<SavedWordMutation> command({
    bool saved = true,
    String? wordId,
  }) async => useCases.prepareSet(
    state: await state(wordId: wordId),
    desiredIsSaved: saved,
  );

  Future<SavedWordApplyResult> set(bool saved, {String? wordId}) async =>
      repository.apply(await command(saved: saved, wordId: wordId));

  Future<void> close() => storage.close();
}

final class SavedWordsSqlInterference extends drift.QueryInterceptor {
  SavedWordsSqlInterference(this.afterWrite, {required this.insert});
  final Future<void> Function(drift.QueryExecutor) afterWrite;
  final bool insert;
  bool fired = false;

  bool _matches(String statement) => RegExp(
    insert ? r'insert\s+into\s+"?saved_words' : r'update\s+"?saved_words',
    caseSensitive: false,
  ).hasMatch(statement);

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (insert && !fired && _matches(statement)) {
      fired = true;
      await afterWrite(executor);
    }
    return result;
  }

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runUpdate(statement, args);
    if (!insert && !fired && _matches(statement)) {
      fired = true;
      await afterWrite(executor);
    }
    return result;
  }
}
