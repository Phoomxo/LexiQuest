import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/research_authority_cache_harness.dart';

void main() {
  late AuthorityCacheFixture fixture;
  setUp(() async {
    fixture = await AuthorityCacheFixture.open();
    expect(await fixture.cache.refresh(), isTrue);
    fixture.bindRuntime();
  });
  tearDown(() => fixture.close());

  Future<ConfiguredQuizState> startIndex() async {
    await fixture.study.baseline();
    fixture.advance(const Duration(minutes: 1));
    final opened = await fixture.study.runtime.openPresentation(
      fixture.study.ownerId,
      entryAttemptId: '00000000-0000-4000-8000-000000000081',
    );
    await fixture.study.runtime.recordPresented(
      fixture.study.ownerId,
      opened.opportunity!.id,
      stillVisible: () => true,
    );
    fixture.advance(const Duration(minutes: 1));
    return fixture.study.runtime.startIndex(
      fixture.study.ownerId,
      opened.opportunity!.id,
      stillVisible: () => true,
    );
  }

  test(
    'real LocalStudyRuntime collects through five local adapters without gateway IO in TX',
    () async {
      final first = await startIndex();
      expect(fixture.study.runtime.learning, same(fixture.study.learning));
      fixture.advance(const Duration(minutes: 1));
      final finished = await fixture.study.finish(first);
      final post = await fixture.study.runtime.load(fixture.study.ownerId);
      expect(post.phase, StudyPhase.post);
      expect(post.index!.sessionId, first.sessionId);
      expect(post.index!.endedAtUtc, finished.endedAtUtc);
      await fixture.study.runtime
          .measurementsFor(fixture.study.ownerId)
          .record(
            MotivationResponse(
              ownerId: fixture.study.ownerId,
              runId: post.run!.id,
              itemId: 'synthetic-post',
              responseCode: 'high',
            ),
          );
      final complete = await fixture.study.runtime.load(fixture.study.ownerId);
      expect(complete.phase, StudyPhase.completed);
      expect(complete.index!.sessionId, first.sessionId);
      expect(
        complete.index!.plan.stableSerialization,
        first.plan.stableSerialization,
      );
      expect(complete.index!.endedAtUtc, finished.endedAtUtc);
      final stored = await fixture.study.researchRows();
      expect(stored['learning_sessions'], hasLength(1));
      expect(stored['answer_attempts'], hasLength(1));
      expect(stored['motivation_responses'], hasLength(2));
      expect(stored['measurement_opportunities'], hasLength(1));
      expect(
        stored['events_v2']!.map((row) => row['event_type']),
        unorderedEquals([
          measurementPresentedEventType,
          measurementMissionStartedEventType,
          measurementMissionCompletedEventType,
        ]),
      );
      expect(
        stored['outbox_operations']!.map((row) => row['entity_type']),
        unorderedEquals(['attempt', 'srsState', 'achievementUnlock']),
      );
      expect(fixture.gateway.calls, 1);
      expect(fixture.gateway.transactionCalls, [false]);
    },
  );

  test(
    'server revocation refresh denies Research while canonical learning completes',
    () async {
      final first = await startIndex();
      fixture.gateway.snapshotRevision = 2;
      fixture.gateway.stateRevision = 2;
      fixture.gateway.revoked = true;
      expect(await fixture.cache.refresh(), isTrue);
      expect(
        (await fixture.study.runtime.load(fixture.study.ownerId)).phase,
        StudyPhase.unavailable,
      );
      fixture.advance(const Duration(minutes: 1));
      final learning = fixture.study.learning;
      final question = first.plan.questions.single;
      final pending = await learning.prepareQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
        expectedRevision: first.checkpointRevision,
        selectedOptionOrdinal: question.options.indexOf(question.correctAnswer),
        responseTimeMs: 25,
      );
      final answer = await learning.commitQuizAnswer(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
        expectedRevision: pending.checkpointRevision,
      );
      final closing = await learning.prepareQuizFinish(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
        expectedRevision: answer.state.checkpointRevision,
      );
      final completion = await learning.finishConfiguredQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
        expectedRevision: closing.checkpointRevision,
      );
      final finished = completion.state;
      expect(completion.summary.correctCount, 1);
      expect(finished.state, 'completed');
      expect(finished.sessionId, first.sessionId);
      final attempts = await fixture.study.rows('answer_attempts');
      expect(attempts, hasLength(1));
      expect(await fixture.study.rows('srs_states'), hasLength(1));
      final points = await fixture.study.rows('points_ledger_entries');
      expect(points, isNotEmpty);
      expect(points.every((row) => row['owner_id'] == first.ownerId), isTrue);
      final rewards = await fixture.study.rows('reward_transactions');
      expect(rewards, hasLength(1));
      expect(rewards.single['owner_id'], first.ownerId);
      expect(rewards.single['source_event_id'], attempts.single['id']);
      expect(rewards.single['transaction_type'], 'creditQuizCorrectV1');
      expect(rewards.single['amount'], 1);
      final events = await fixture.study.rows('events_v2');
      expect(
        events.map((row) => row['event_type']),
        unorderedEquals([
          measurementPresentedEventType,
          measurementMissionStartedEventType,
        ]),
      );
      expect(await fixture.study.rows('motivation_responses'), hasLength(1));
      expect(fixture.gateway.transactionCalls, [false, false]);
    },
  );

  test(
    'expired cache cannot refresh implicitly or replace the first index',
    () async {
      final first = await startIndex();
      final before = await fixture.study.researchRows();
      fixture.advance(const Duration(minutes: 8, milliseconds: 1));
      expect(
        (await fixture.study.runtime.load(fixture.study.ownerId)).phase,
        StudyPhase.unavailable,
      );
      final ordinary = await fixture.study.learning.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
      );
      expect(ordinary.sessionId, first.sessionId);
      expect(ordinary.plan.stableSerialization, first.plan.stableSerialization);
      expect(await fixture.study.researchRows(), before);
      expect(fixture.gateway.calls, 1);
    },
  );

  test(
    'owner A to B cannot reuse cached A authority or create a research enrollment',
    () async {
      await startIndex();
      await fixture.study.switchOwner();
      fixture.scope = fixture.scopeFor('owner-b', 'uid-b', 2);
      final before = await fixture.study.researchRows();
      expect(
        (await fixture.study.runtime.load('owner-a')).phase,
        StudyPhase.unavailable,
      );
      expect(
        (await fixture.study.runtime.load('owner-b')).phase,
        StudyPhase.unavailable,
      );
      expect(await fixture.cache.refresh(), isFalse);
      expect(await fixture.study.researchRows(), before);
      expect(fixture.gateway.calls, 1);
    },
  );

  test(
    'canonical local withdrawal wins over an unexpired cached server receipt',
    () async {
      final first = await startIndex();
      expect(
        await fixture.study.runtime.consent.withdraw(
          expectedOwnerId: fixture.study.ownerId,
          expectedVersion: fixture.study.runtime.consent.version,
        ),
        isTrue,
      );
      expect(
        (await fixture.study.runtime.load(fixture.study.ownerId)).phase,
        StudyPhase.unavailable,
      );
      expect(await fixture.cache.refresh(), isFalse);
      expect(fixture.gateway.calls, 1);
      final ordinary = await fixture.study.learning.resumeQuiz(
        sessionId: first.sessionId,
        expectedOwnerId: first.ownerId,
      );
      expect(ordinary.sessionId, first.sessionId);
      expect(await fixture.study.rows('motivation_responses'), hasLength(1));
      expect(await fixture.study.rows('learning_sessions'), hasLength(1));
    },
  );
}
