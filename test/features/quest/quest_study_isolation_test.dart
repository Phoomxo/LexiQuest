import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/events/application/event_v1_to_v2_adapter.dart';
import 'package:vocab_learning_app/features/events/domain/event_envelope_v2.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_evidence_contract.dart';
import 'package:vocab_learning_app/features/quest/data/drift_quest_repository.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';

import '../../support/measurement_opportunity_harness.dart';
import '../../support/populated_owner_migration_fixture.dart';

void main() {
  late OpportunityFixture fixture;
  late DriftQuestRepository quests;
  late QuestDefinition definition;
  setUp(() async {
    fixture = await OpportunityFixture.open(longLived: true);
    quests = DriftQuestRepository(
      fixture.database,
      ownerWrites: fixture.participation.ownerWrites,
      nowUtc: () => fixture.participation.clock.now,
    );
    definition = QuestDefinition(
      questId: 'synthetic-study-isolation-quest',
      catalogVersion: 1,
      title: 'Synthetic ordinary practice',
      description: 'Synthetic',
      type: QuestType.daily,
      objectives: [
        QuestObjective(
          objectiveId: 'correct',
          description: 'Correct ordinary answer',
          targetCount: 1,
          criteria: ObjectiveCriteria(
            eventType: 'QuizCompleted',
            filters: {'correct': true},
          ),
        ),
      ],
      reward: const RewardSpec(xpAmount: 50),
    );
    await quests.assignCurrentPeriod(
      ownerId: 'owner-a',
      definition: definition,
      instanceId: 'synthetic-study-isolation-instance',
      assignedAtUtc: fixture.participation.clock.now,
      timezoneId: 'UTC',
      stillCurrent: () => true,
    );
  });
  tearDown(() => fixture.database.close());

  test(
    'actual controlled Study quiz remains excluded from live Quest',
    () async {
      final event = await _canonicalMeaningAnswer(fixture, controlled: true);
      final linked = await fixture.storedOpportunity();
      expect(linked['learning_session_id'], event.aggregateId);
      final before = await ownerMigrationRows(fixture.database);
      await expectLater(
        quests.applyCanonicalAnswer(
          ownerId: 'owner-a',
          event: event,
          catalog: [definition],
        ),
        throwsStateError,
      );
      expect(await ownerMigrationRows(fixture.database), before);
      expect(
        await quests.readValidatedCompletions(
          expectedOwnerId: 'owner-a',
          stillCurrent: () => true,
        ),
        isEmpty,
      );
    },
  );

  test(
    'actual controlled Study quiz is skipped by missed-callback recovery',
    () async {
      final event = await _canonicalMeaningAnswer(fixture, controlled: true);
      expect(
        (await fixture.storedOpportunity())['learning_session_id'],
        event.aggregateId,
      );
      final before = await ownerMigrationRows(fixture.database);
      expect(
        await quests.reconcile(
          expectedOwnerId: 'owner-a',
          catalog: [definition],
          stillCurrent: () => true,
        ),
        isEmpty,
      );
      expect(await ownerMigrationRows(fixture.database), before);
      expect(
        (await quests.getActiveInstances(
          'owner-a',
        )).single.progress.single.currentCount,
        0,
      );
      expect(
        await quests.readValidatedCompletions(
          expectedOwnerId: 'owner-a',
          stillCurrent: () => true,
        ),
        isEmpty,
      );
    },
  );

  test(
    'the same canonical Meaning quiz without a Study link still completes Quest',
    () async {
      final event = await _canonicalMeaningAnswer(fixture, controlled: false);
      expect(
        await fixture.database
            .customSelect('SELECT * FROM measurement_opportunities')
            .get(),
        isEmpty,
      );
      final before = await ownerMigrationRows(fixture.database);
      final completed = await quests.applyCanonicalAnswer(
        ownerId: 'owner-a',
        event: event,
        catalog: [definition],
      );
      expect(completed.single.objectiveEventIds, [event.eventId]);
      final after = await ownerMigrationRows(fixture.database);
      for (final table in before.keys) {
        if (!{'quest_instances', 'quest_objective_progress'}.contains(table)) {
          expect(after[table], before[table], reason: table);
        }
      }
      expect(
        (await quests.readValidatedCompletions(
          expectedOwnerId: 'owner-a',
          stillCurrent: () => true,
        )).single.completion.objectiveEventIds,
        [event.eventId],
      );
    },
  );
}

Future<EventEnvelopeV2> _canonicalMeaningAnswer(
  OpportunityFixture fixture, {
  required bool controlled,
}) async {
  if (controlled) await fixture.ready();
  final learning = controlled
      ? fixture.learning
      : DriftLearningRepository(
          fixture.database,
          ownerWrites: fixture.participation.ownerWrites,
        );
  final start = participationStart.add(const Duration(minutes: 2));
  fixture.participation.clock.now = start;
  final session = fixture.session(
    id: 'synthetic-study-quest-session',
    at: start,
  );
  var state = await learning.startConfiguredQuiz(
    session: session,
    plan: await fixture.quizPlan(),
  );
  fixture.participation.clock.now = start.add(const Duration(seconds: 1));
  final question = state.plan.questions.single;
  final answer = QuizAnswerReceipt.capture(
    plan: state.plan,
    ownerId: 'owner-a',
    attemptId: 'synthetic-study-quest-answer',
    questionOrdinal: 0,
    selectedOptionOrdinal: question.options.indexOf(question.word.meaning),
    revealed: false,
    assistance: state.checkpoint.assistance,
    occurredAtUtcMs: fixture.participation.clock.now.millisecondsSinceEpoch,
    responseTimeMs: 500,
  );
  expect(answer.isCorrect, isTrue);
  expect(
    LearningEvidenceContract.isOrdinaryEvidence(answer.evidenceContext),
    isTrue,
  );
  state = await learning.saveQuizCheckpoint(
    sessionId: session.id,
    expectedOwnerId: 'owner-a',
    expectedRevision: state.checkpointRevision,
    checkpoint: state.bindCheckpointWrite(
      PendingQuizAnswer(
        planId: state.plan.id,
        questionOrdinal: 0,
        assistance: state.checkpoint.assistance,
        answer: answer,
      ),
    ),
  );
  state = (await learning.commitQuizAnswer(
    sessionId: session.id,
    expectedOwnerId: 'owner-a',
    expectedRevision: state.checkpointRevision,
  )).state;
  fixture.participation.clock.now = start.add(const Duration(seconds: 2));
  state = await learning.saveQuizCheckpoint(
    sessionId: session.id,
    expectedOwnerId: 'owner-a',
    expectedRevision: state.checkpointRevision,
    checkpoint: state.bindCheckpointWrite(
      ClosingQuizSession(
        planId: state.plan.id,
        questionOrdinal: 0,
        assistance: state.checkpoint.assistance,
        close: QuizCloseReceipt(
          capturedOwnerId: 'owner-a',
          endedAtUtcMs: fixture.participation.clock.now.millisecondsSinceEpoch,
        ),
      ),
    ),
  );
  await learning.finishConfiguredQuiz(
    sessionId: session.id,
    expectedOwnerId: 'owner-a',
    expectedRevision: state.checkpointRevision,
  );
  final command = answer.toCommand(sessionId: session.id);
  return EventV1ToV2Adapter(
    appVersion: session.appVersion,
    buildId: session.buildId,
  ).adaptFromCommand(
    attemptId: command.id,
    ownerId: command.ownerId,
    sessionId: command.sessionId,
    wordId: command.wordId,
    promptMode: command.promptMode,
    isCorrect: command.isCorrect,
    responseTimeMs: command.responseTimeMs,
    attemptNumber: command.attemptNumber,
    occurredAtUtc: command.occurredAtUtc,
    appVersion: session.appVersion,
    buildId: session.buildId,
  );
}
