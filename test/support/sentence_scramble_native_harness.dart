import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/data/local/app_database.dart'
    show AppDatabase;
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class SentenceScrambleNativeHarness {
  SentenceScrambleNativeHarness._(this.storage) {
    repository = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    provider = SyntheticSentenceScrambleProvider(database);
    learning = useCases();
  }

  final ConfiguredQuizHarness storage;
  late final DriftLearningRepository repository;
  late final SyntheticSentenceScrambleProvider provider;
  late final LearningUseCases learning;
  int _nextId = 0;
  int notifications = 0;
  int questEvents = 0;
  int streakEvents = 0;
  bool current = true;

  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;

  static Future<SentenceScrambleNativeHarness> open() async =>
      SentenceScrambleNativeHarness._(await ConfiguredQuizHarness.open());

  LearningUseCases useCases({bool withProvider = true}) => LearningUseCases(
    owners: storage.owners,
    repository: repository,
    generateId: () => 'synthetic-sentence-${++_nextId}',
    nowUtc: () => now,
    buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'sentence-test'),
    contentProvider: withProvider ? provider : null,
    onLocalMutation: () => notifications++,
    questEventSink: (_) async {
      questEvents++;
    },
    streakEventSink: () async {
      streakEvents++;
    },
  );

  Future<SentenceScrambleSession?> prepare({
    String? categoryId = configuredCategoryId,
  }) => learning.prepareSentenceScramble(
    categoryId: categoryId,
    stillCurrent: () => current,
  );

  Future<SentenceScrambleSession> ready() async {
    final prepared = await prepare();
    if (prepared == null) throw StateError('synthetic sentence target missing');
    return learning.startNativeExercise(prepared, stillCurrent: () => current);
  }

  RecordAnswerCommand answer(
    SentenceScrambleSession exercise, {
    bool correct = true,
    String? response,
    Duration responseTime = const Duration(milliseconds: 1234),
  }) => learning.prepareNativeAnswer(
    SentenceScrambleAnswerInput(
      exercise: exercise,
      response: response ?? (correct ? exercise.content.sentence : 'wrong'),
      responseTime: responseTime,
    ),
  );

  Future<void> close() => storage.close();
}

final class SyntheticSentenceScrambleProvider implements ContentProvider {
  SyntheticSentenceScrambleProvider(this.database);
  final AppDatabase database;
  final List<ContentRequest> requests = [];
  final List<bool?> transactionStates = [];
  Future<void> Function(ContentRequest request)? beforeResponse;
  ContentResponse Function(ContentRequest request)? response;

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    requests.add(request);
    final probe = _ActualExecutorProbe();
    await database.runWithInterceptor(
      () => database
          .customSelect('SELECT 1 AS synthetic_sentence_probe')
          .getSingle(),
      interceptor: probe,
    );
    transactionStates.add(probe.insideTransaction);
    await beforeResponse?.call(request);
    return response?.call(request) ??
        ContentResponse(
          text: 'We visit the ${request.text} today.',
          kind: ContentKind.sentence,
          cefr: CefrLevel.unknown,
          language: 'en',
          modelVersion: 'synthetic-sentence-provider-v1',
          cached: false,
        );
  }
}

final class _ActualExecutorProbe extends drift.QueryInterceptor {
  bool? insideTransaction;
  @override
  Future<List<Map<String, Object?>>> runSelect(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) {
    insideTransaction = executor is drift.TransactionExecutor;
    return executor.runSelect(statement, args);
  }
}
