import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/ai/ai_models.dart';
import 'package:vocab_learning_app/ai/content_provider.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import 'configured_quiz_harness.dart';

export 'configured_quiz_harness.dart';

final class ClozeSessionHarness {
  ClozeSessionHarness._(this.storage) {
    repository = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    provider = SyntheticClozeProvider(database);
    learning = useCases();
  }

  final ConfiguredQuizHarness storage;
  late final DriftLearningRepository repository;
  late final SyntheticClozeProvider provider;
  late final LearningUseCases learning;
  int _nextId = 0;
  int notifications = 0;
  int questEvents = 0;
  int streakEvents = 0;
  bool current = true;

  AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;

  static Future<ClozeSessionHarness> open() async =>
      ClozeSessionHarness._(await ConfiguredQuizHarness.open());

  LearningUseCases useCases({bool withProvider = true}) => LearningUseCases(
    owners: storage.owners,
    repository: repository,
    generateId: () => 'synthetic-cloze-${++_nextId}',
    nowUtc: () => now,
    buildInfo: const AppBuildInfo(version: '1.0.0', buildId: 'cloze-test'),
    contentProvider: withProvider ? provider : null,
    onLocalMutation: () => notifications++,
    questEventSink: (_) async {
      questEvents++;
    },
    streakEventSink: () async {
      streakEvents++;
    },
  );

  Future<ClozeSession?> prepare(
    ClozeVariant variant, {
    String? categoryId = configuredCategoryId,
  }) => learning.prepareCloze(
    categoryId: categoryId,
    variant: variant,
    stillCurrent: () => current,
  );

  Future<ClozeSession> ready(ClozeVariant variant) async {
    final prepared = await prepare(variant);
    if (prepared == null) throw StateError('synthetic Cloze target missing');
    return learning.startNativeExercise(prepared, stillCurrent: () => current);
  }

  RecordAnswerCommand answer(ClozeSession exercise, {bool correct = true}) =>
      learning.prepareNativeAnswer(switch (exercise) {
        TypedClozeSession() => TypedClozeAnswerInput(
          exercise: exercise,
          response: correct
              ? ' ${exercise.word.spelling.toUpperCase()} '
              : 'wrong',
          responseTime: const Duration(milliseconds: 1234),
        ),
        ChoiceClozeSession() => ChoiceClozeAnswerInput(
          exercise: exercise,
          optionId: correct
              ? exercise.word.id
              : exercise.choices
                    .firstWhere((word) => word.id != exercise.word.id)
                    .id,
          responseTime: const Duration(milliseconds: 1234),
        ),
      });

  Future<void> close() => storage.close();
}

final class SyntheticClozeProvider implements ContentProvider {
  SyntheticClozeProvider(this.database);
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
          .customSelect('SELECT 1 AS synthetic_provider_probe')
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
          modelVersion: 'synthetic-cloze-provider-v1',
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
