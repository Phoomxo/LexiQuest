import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  test(
    'historical backed pre at exact exposure survives public pending switch and keeps the canonical first index',
    () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      fixture.authorities.advance(const Duration(minutes: 1));
      final pre = await fixture.start();
      await fixture.repository.recordResponse(
        ownerId: 'owner-a',
        runId: pre.id,
        itemId: fixture.definition.items.single.itemId,
        option: 'synthetic yes',
        responseTimeMs: 0,
        stillVisible: () => true,
      );
      final completedPre = await fixture.repository.complete(
        ownerId: 'owner-a',
        runId: pre.id,
        stillVisible: () => true,
      );
      final study = fixture.authorities.study;
      final runtime = study.runtime;
      final exposed = await study.ready();
      final opportunity = exposed.opportunity!;
      expect(completedPre.completedAtUtc, opportunity.openedAtUtc);
      expect(
        completedPre.completedAtUtc,
        opportunity.presentation!.occurredAtUtc,
      );
      final originalAssessment = await study.rows('assessment_runs');
      final originalPresented = (await study.rows('events_v2')).singleWhere(
        (row) => row['event_type'] == measurementPresentedEventType,
      );
      final target = oppositePresentation(opportunity.currentPresentation);
      const attempt = '50000000-0000-4000-8000-000000000001';

      final prepared = await runtime.preparePresentationChange(
        'owner-a',
        opportunity.id,
        attemptId: attempt,
        expectedRevision: opportunity.localRevision,
        target: target,
        stillCurrent: () => true,
      );
      expect(prepared.opportunity!.pendingPresentationChange, isNotNull);
      expect(
        (await runtime.load('owner-a')).phase,
        StudyPhase.unavailable,
        reason:
            'Historical pre proof does not grant collection during pending exposure',
      );
      runtime.markPresentationChangeMayRender(
        'owner-a',
        opportunity.id,
        attemptId: attempt,
      );
      final switched = await runtime.recordPresentationChanged(
        'owner-a',
        opportunity.id,
        attemptId: attempt,
        stillVisible: () => true,
      );

      expect(switched.opportunity!.pendingPresentationChange, isNull);
      expect(switched.opportunity!.currentPresentation, target);
      expect(switched.opportunity!.lastSwitchOrdinal, 1);
      final index = await runtime.startIndex(
        'owner-a',
        opportunity.id,
        stillVisible: () => true,
      );
      final current = await runtime.load('owner-a');
      expect(current.phase, StudyPhase.activeIndex);
      expect(current.index!.sessionId, index.sessionId);
      expect(current.index!.startedAtUtc, index.startedAtUtc);
      expect(current.opportunity!.id, opportunity.id);
      expect(current.opportunity!.indexLink!.sessionId, index.sessionId);
      expect(await study.rows('assessment_runs'), originalAssessment);
      final events = await study.rows('events_v2');
      expect(
        events.singleWhere(
          (row) => row['event_type'] == measurementPresentedEventType,
        ),
        originalPresented,
      );
      expect(
        events.where(
          (row) => row['event_type'] == measurementPresentationChangedEventType,
        ),
        hasLength(1),
      );
      expect(
        events.where(
          (row) => row['event_type'] == measurementMissionStartedEventType,
        ),
        hasLength(1),
      );
      final sessions = await study.rows('learning_sessions');
      expect(sessions, hasLength(2));
      expect(
        sessions
            .where((row) => row['activity_type'] != 'assessment')
            .single['id'],
        index.sessionId,
      );
      expect(await study.rows('outbox_operations'), isEmpty);
      expect(await study.rows('srs_states'), isEmpty);
      expect(await study.rows('points_ledger_entries'), isEmpty);
      expect(await study.rows('reward_transactions'), isEmpty);
    },
  );
}
