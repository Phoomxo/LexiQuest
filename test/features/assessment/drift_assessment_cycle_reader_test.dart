import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/accepted_quiz_plan.dart';

import '../../support/assessment_authority_harness.dart';

void main() {
  late AssessmentAuthorityFixture fixture;
  setUp(() async => fixture = await AssessmentAuthorityFixture.open());
  tearDown(() => fixture.close());

  test(
    'pre reads exact existing R3 cycle with no opening and no intervention facts',
    () async {
      final view = await fixture.study.baseline();
      final before = await fixture.study.researchRows();
      final receipt = await fixture.cycleReader().requirePhase(
        run: fixture.run(cycleId: view.run!.id),
      );
      expect(receipt.ownerId, 'owner-a');
      expect(receipt.studyCycleId, view.run!.id);
      expect(receipt.phase, AssessmentPhase.pre);
      expect(receipt.opportunityId, isNull);
      expect(receipt.firstExposureAtUtc, isNull);
      expect(receipt.interventionSessionId, isNull);
      expect(receipt.interventionStartedAtUtc, isNull);
      expect(receipt.interventionCompletedAtUtc, isNull);
      expect(await fixture.study.researchRows(), before);
      expect(fixture.gateway.calls, 0);
    },
  );

  test(
    'pre rejects even an unpresented opening and does not backfill facts',
    () async {
      final view = await fixture.study.baseline();
      final opening = await fixture.study.runtime.openPresentation(
        'owner-a',
        entryAttemptId: studyEntryId,
        stillCurrent: () => true,
      );
      expect(opening.opportunity!.presentation, isNull);
      final before = await fixture.study.researchRows();
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(cycleId: view.run!.id),
        ),
        throwsStateError,
      );
      expect(await fixture.study.researchRows(), before);
    },
  );

  test(
    'post uses original completed canonical first index and remains read-only',
    () async {
      final started = await fixture.study.start();
      final completed = await fixture.study.finish(started);
      final view = await fixture.study.runtime.load('owner-a');
      final before = await fixture.study.researchRows();
      final receipt = await fixture.cycleReader().requirePhase(
        run: fixture.run(cycleId: view.run!.id, phase: AssessmentPhase.post),
      );
      expect(receipt.opportunityId, view.opportunity!.id);
      expect(
        receipt.firstExposureAtUtc,
        participationStart.add(const Duration(minutes: 1)),
      );
      expect(receipt.interventionSessionId, started.sessionId);
      expect(receipt.interventionStartedAtUtc, started.startedAtUtc);
      expect(receipt.interventionCompletedAtUtc, completed.endedAtUtc);
      expect(await fixture.study.researchRows(), before);
      expect(fixture.gateway.calls, 0);
    },
  );

  test(
    'post requires actual completion and a start no earlier than original completion',
    () async {
      final index = await fixture.study.start();
      final view = await fixture.study.runtime.load('owner-a');
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(cycleId: view.run!.id, phase: AssessmentPhase.post),
        ),
        throwsStateError,
      );
      await fixture.study.finish(index);
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(
            cycleId: view.run!.id,
            phase: AssessmentPhase.post,
            startedAtUtc: index.startedAtUtc,
          ),
        ),
        throwsStateError,
      );
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(cycleId: view.run!.id),
        ),
        throwsStateError,
      );
    },
  );

  for (final eventType in [
    'TodayExperiencePresented',
    'TodayExperienceMissionStarted',
    'TodayExperienceMissionCompleted',
  ]) {
    test(
      'post rejects missing $eventType envelope without repairing it',
      () async {
        final index = await fixture.study.start();
        await fixture.study.finish(index);
        final view = await fixture.study.runtime.load('owner-a');
        // Simulate corrupt historical rows; production FK enforcement stays on.
        await fixture.study.database.customStatement(
          'PRAGMA foreign_keys = OFF',
        );
        try {
          await fixture.study.database.customStatement(
            "DELETE FROM events_v2 WHERE event_type = '$eventType'",
          );
        } finally {
          await fixture.study.database.customStatement(
            'PRAGMA foreign_keys = ON',
          );
        }
        expect(
          (await fixture.study.database
                  .customSelect('PRAGMA foreign_keys')
                  .getSingle())
              .read<int>('foreign_keys'),
          1,
        );
        final before = await fixture.study.researchRows();
        expect(
          before['events_v2']!.where((row) => row['event_type'] == eventType),
          isEmpty,
        );
        await expectLater(
          () => fixture.cycleReader().requirePhase(
            run: fixture.run(
              cycleId: view.run!.id,
              phase: AssessmentPhase.post,
            ),
          ),
          throwsA(anything),
        );
        expect(await fixture.study.researchRows(), before);
      },
    );
  }

  test(
    'post rejects absent completion projections instead of repairing both',
    () async {
      final index = await fixture.study.start();
      await fixture.study.finish(index);
      final view = await fixture.study.runtime.load('owner-a');
      await fixture.study.database.customStatement(
        "DELETE FROM events_v2 WHERE event_type = 'TodayExperienceMissionCompleted'",
      );
      await fixture.study.database.customStatement(
        'UPDATE measurement_opportunities SET closed_at_utc_ms = NULL',
      );
      final before = await fixture.study.researchRows();
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(cycleId: view.run!.id, phase: AssessmentPhase.post),
        ),
        throwsStateError,
      );
      expect(await fixture.study.researchRows(), before);
    },
  );

  test(
    'abandoned original index is never replaced by a later completed ordinary session',
    () async {
      final original = await fixture.study.start();
      final view = await fixture.study.runtime.load('owner-a');
      await fixture.study.learning.abandonQuiz(
        sessionId: original.sessionId,
        expectedOwnerId: 'owner-a',
        expectedRevision: original.checkpointRevision,
      );
      fixture.study.participation.clock.now = participationStart.add(
        const Duration(minutes: 2, seconds: 10),
      );
      final launch = await fixture.study.learning.prepareConfiguredQuiz(
        configuration: QuizConfiguration.sourcePractice(
          wordIds: ['synthetic-study-word'],
          limit: 1,
        ),
        expectedOwnerId: 'owner-a',
      );
      final later = await fixture.study.learning.startConfiguredQuiz(launch);
      await fixture.study.finish(later);
      final before = await fixture.study.researchRows();
      await expectLater(
        () => fixture.cycleReader().requirePhase(
          run: fixture.run(cycleId: view.run!.id, phase: AssessmentPhase.post),
        ),
        throwsStateError,
      );
      expect(await fixture.study.researchRows(), before);
      expect(original.sessionId, isNot(later.sessionId));
    },
  );

  test(
    'exact cycle owner assignment revisions and original permit identity must all match',
    () async {
      final view = await fixture.study.baseline();
      for (final run in <AssessmentRun>[
        fixture.run(cycleId: 'synthetic-missing-cycle'),
        fixture.run(cycleId: view.run!.id, ownerId: 'owner-b'),
        fixture.run(
          cycleId: view.run!.id,
          assignmentId: 'synthetic-other-assignment',
        ),
        fixture.run(cycleId: view.run!.id, assignmentRevision: 12),
        fixture.run(cycleId: view.run!.id, protocolRevision: 6),
        fixture.run(cycleId: view.run!.id, permitRevision: 2),
        fixture.run(cycleId: view.run!.id, permitHash: 'b' * 64),
      ]) {
        await expectLater(
          () => fixture.cycleReader().requirePhase(run: run),
          throwsA(anything),
        );
      }
    },
  );
}
