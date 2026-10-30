import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class WordScrambleSessionHarness {
  WordScrambleSessionHarness._(this.storage) {
    repository = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    learning = LearningUseCases(
      owners: storage.owners,
      repository: repository,
      generateId: () => 'synthetic-scramble-${++_nextId}',
      nowUtc: () => now,
      buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'scramble-test'),
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

  static Future<WordScrambleSessionHarness> open() async =>
      WordScrambleSessionHarness._(await ConfiguredQuizHarness.open());

  Future<WordScrambleSession?> prepare({
    String? categoryId = configuredCategoryId,
  }) => learning.prepareWordScramble(
    categoryId: categoryId,
    stillCurrent: () => current,
  );

  Future<WordScrambleSession> ready() async {
    final prepared = await prepare();
    if (prepared == null) throw StateError('synthetic Scramble target missing');
    return learning.startNativeExercise(prepared, stillCurrent: () => current);
  }

  RecordAnswerCommand answer(
    WordScrambleSession exercise, {
    bool correct = true,
    String? response,
    Duration responseTime = const Duration(milliseconds: 1234),
  }) => learning.prepareNativeAnswer(
    WordScrambleAnswerInput(
      exercise: exercise,
      response:
          response ??
          (correct ? ' ${exercise.word.spelling.toUpperCase()} ' : 'wrong'),
      responseTime: responseTime,
    ),
  );

  Future<void> close() => storage.close();
}
