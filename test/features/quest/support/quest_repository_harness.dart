import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' as drift;
import 'package:vocab_learning_app/data/local/app_database.dart' as db;
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/quest/application/quest_use_cases.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import '../../../support/configured_quiz_harness.dart';

export '../../../support/configured_quiz_harness.dart'
    show configuredOwnerId, configuredOtherOwnerId, configuredWordIds;

final class QuestHarness {
  QuestHarness._(this.storage) {
    learning = DriftLearningRepository(
      database,
      ownerWrites: storage.ownerWrites,
    );
    repository = DriftQuestRepository(
      database,
      ownerWrites: storage.ownerWrites,
      nowUtc: () => now,
    );
    useCases = QuestUseCases(
      repository: repository,
      owners: storage.owners,
      generateId: () => 'synthetic-quest-${++_ids}',
      nowUtc: () => now,
      timezoneId: 'Asia/Bangkok',
    );
  }

  static Future<QuestHarness> open({File? file, bool seed = true}) async =>
      QuestHarness._(await ConfiguredQuizHarness.open(file: file, seed: seed));

  final ConfiguredQuizHarness storage;
  db.AppDatabase get database => storage.database;
  DateTime get now => storage.now;
  set now(DateTime value) => storage.now = value;
  late final DriftLearningRepository learning;
  late final DriftQuestRepository repository;
  late final QuestUseCases useCases;
  int _ids = 0;

  Future<EventEnvelopeV2> answer({
    String id = 'synthetic-answer-1',
    String sessionId = 'synthetic-learning-1',
    bool correct = true,
    DateTime? at,
  }) async {
    final saved = await (database.select(
      database.learningSessions,
    )..where((row) => row.id.equals(sessionId))).getSingleOrNull();
    if (saved == null) {
      await learning.startSession(
        LearningSessionDraft(
          id: sessionId,
          ownerId: configuredOwnerId,
          activityType: 'quiz',
          startedAtUtc: now,
          appVersion: 'synthetic-1',
          buildId: 'synthetic-build',
        ),
      );
    }
    final command = RecordAnswerCommand(
      id: id,
      ownerId: configuredOwnerId,
      sessionId: sessionId,
      wordId: configuredWordIds.first,
      promptMode: 'multipleChoice',
      isCorrect: correct,
      responseTimeMs: 500,
      attemptNumber: 1,
      occurredAtUtc: at ?? now,
    );
    await learning.recordAnswer(command);
    return EventEnvelopeV2(
      eventId: command.id,
      eventType: correct ? 'QuizCompleted' : 'QuizAttempted',
      eventVersion: 1,
      occurredAtUtc: command.occurredAtUtc,
      recordedAtUtc: command.occurredAtUtc,
      actorIdentity: command.ownerId,
      ownerIdentity: command.ownerId,
      aggregateType: 'LearningSession',
      aggregateId: command.sessionId,
      idempotencyKey: 'answer-attempt:${command.id}',
      consentContext: const ConsentContext.none(),
      appVersion: 'synthetic-1',
      buildId: 'synthetic-build',
      privacyClassification: PrivacyClassification.anonymized,
      payload: {
        'wordId': command.wordId,
        'promptMode': command.promptMode,
        'correct': command.isCorrect,
        'score': command.isCorrect ? 100 : 0,
        'responseTimeMs': command.responseTimeMs,
        'attemptNumber': command.attemptNumber,
      },
    );
  }

  Future<List<QuestCompletedEvent>> apply(
    EventEnvelopeV2 event,
    QuestDefinition definition,
  ) => repository.applyCanonicalAnswer(
    ownerId: configuredOwnerId,
    event: event,
    catalog: [definition],
  );

  Future<Map<String, List<String>>> protectedSnapshot() async {
    final all = await storage.snapshot();
    all.remove('quest_definitions');
    all.remove('quest_instances');
    all.remove('quest_objective_progress');
    return all;
  }

  Future<void> sql(String statement, [List<Object?> arguments = const []]) =>
      database.customStatement(statement, arguments);

  Future<void> close() => storage.close();
}

QuestDefinition questDefinition({
  String id = 'synthetic-quest-definition',
  int version = 1,
  int target = 3,
  Duration? expiry,
  String eventType = 'QuizCompleted',
  List<QuestObjective>? objectives,
}) => QuestDefinition(
  questId: id,
  catalogVersion: version,
  title: 'Synthetic Quest',
  description: 'Canonical answer test',
  type: QuestType.daily,
  objectives:
      objectives ??
      [
        QuestObjective(
          objectiveId: 'synthetic-objective',
          description: 'Correct answers',
          targetCount: target,
          criteria: ObjectiveCriteria(
            eventType: eventType,
            filters: const {'correct': true},
          ),
        ),
      ],
  reward: const RewardSpec(xpAmount: 50),
  expiresIn: expiry,
);

EventEnvelopeV2 changedEvent(
  EventEnvelopeV2 event,
  Map<String, Object?> changes,
) => EventEnvelopeV2.fromJson({
  ...jsonDecode(jsonEncode(event.toJson())) as Map<String, dynamic>,
  ...changes,
});

final class QuestWriteProbe extends drift.QueryInterceptor {
  Future<void> Function()? afterProgress;
  bool failCompletion = false;
  int progressWrites = 0;
  bool completionAttempted = false;

  @override
  Future<int> runUpdate(
    drift.QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final sql = statement.toLowerCase();
    if (sql.contains('quest_instances') && args.contains('completed')) {
      completionAttempted = true;
      if (failCompletion) {
        throw StateError('synthetic completion failure');
      }
    }
    final result = await executor.runUpdate(statement, args);
    if (sql.contains('quest_objective_progress')) {
      progressWrites++;
      final callback = afterProgress;
      afterProgress = null;
      await callback?.call();
    }
    return result;
  }
}
