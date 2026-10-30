import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart'
    show configuredOwnerId, configuredOtherOwnerId, configuredCategoryId;

final class DictationSessionHarness {
  DictationSessionHarness._(this.storage) {
    repository = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    learning = LearningUseCases(
      owners: storage.owners,
      repository: repository,
      generateId: () => 'dictation-${++_nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(
        version: '1.0.0',
        buildId: 'dictation-test',
      ),
      onLocalMutation: () => notifications++,
      questEventSink: (_) async {
        questEvents++;
      },
      streakEventSink: () async {
        streakEvents++;
      },
    );
  }

  final ConfiguredQuizHarness storage;
  late final DriftLearningRepository repository;
  late final LearningUseCases learning;
  int _nextId = 0;
  int notifications = 0;
  int questEvents = 0;
  int streakEvents = 0;
  bool current = true;

  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;
  bool get isCurrent => current;

  static Future<DictationSessionHarness> open() async =>
      DictationSessionHarness._(await ConfiguredQuizHarness.open());

  Future<DictationSession> ready() async {
    final prepared = await learning.prepareDictation(
      categoryId: configuredCategoryId,
      stillCurrent: () => current,
    );
    if (prepared == null) {
      throw StateError('synthetic Dictation target missing');
    }
    return learning.startNativeExercise(prepared, stillCurrent: () => current);
  }

  RecordAnswerCommand answer(
    DictationSession session, {
    bool assisted = false,
    bool correct = true,
  }) => learning.prepareNativeAnswer(
    DictationAnswerInput(
      exercise: session,
      response: correct ? ' ${session.word.spelling.toUpperCase()} ' : 'wrong',
      assisted: assisted,
      responseTime: const Duration(milliseconds: 1234),
    ),
  );

  Future<void> close() => storage.close();
}

final class DictationWriteInterference extends drift.QueryInterceptor {
  DictationWriteInterference(
    this.table,
    this.afterInsert, {
    this.onUpdate = false,
  });
  final String table;
  final Future<void> Function(drift.QueryExecutor executor) afterInsert;
  final bool onUpdate;
  bool fired = false;

  @override
  Future<int> runInsert(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    if (!fired && statement.toLowerCase().contains('into "$table"')) {
      fired = true;
      await afterInsert(executor);
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
    if (onUpdate &&
        !fired &&
        statement.toLowerCase().contains('update "$table"')) {
      fired = true;
      await afterInsert(executor);
    }
    return result;
  }
}
