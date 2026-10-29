import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/application/assessment_comparison.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';

import '../../support/assessment_study_harness.dart';

AssessmentStartCommand? pending(StudyView view) =>
    (view as dynamic).assessmentCommand as AssessmentStartCommand?;
bool completedPair(StudyView view) =>
    (view as dynamic).hasCompletedAssessmentPair as bool;

void main() {
  late AssessmentStudyFixture f;
  setUp(() async => f = await AssessmentStudyFixture.open());
  tearDown(() => f.close());

  test(
    'stable owner cycle phase identities use unambiguous canonical tuples',
    () {
      final a = f.assessment.command(
        ownerId: 'a|b',
        studyCycleId: 'c',
        phase: AssessmentPhase.pre,
      );
      final b = f.assessment.command(
        ownerId: 'a',
        studyCycleId: 'b|c',
        phase: AssessmentPhase.pre,
      );
      final post = f.command(AssessmentPhase.post);
      expect(a.runId, isNot(b.runId));
      expect(a.learningSessionId, isNot(b.learningSessionId));
      expect(f.command(AssessmentPhase.pre).runId, isNot(post.runId));
      expect(
        f.command(AssessmentPhase.pre).learningSessionId,
        isNot(post.learningSessionId),
      );
      expect(
        f.command(AssessmentPhase.pre).runId,
        f.command(AssessmentPhase.pre).runId,
      );
    },
  );

  for (final first in ['Motivation', 'Assessment']) {
    test(
      '$first pre form can complete first; neither alone permits opening',
      () async {
        final runtime = f.attach();
        final owner = f.authorities.study.ownerId;
        var view = await runtime.load(owner);
        expect(view.phase, StudyPhase.baseline);
        expect(pending(view)!.phase, AssessmentPhase.pre);
        if (first == 'Assessment') {
          await f.completeAssessment(AssessmentPhase.pre);
          view = await runtime.load(owner);
          expect(view.phase, StudyPhase.baseline);
          expect(pending(view), isNull);
          await f.recordMotivation(MotivationTimepoint.baseline);
        } else {
          await f.recordMotivation(MotivationTimepoint.baseline);
          view = await runtime.load(owner);
          expect(view.phase, StudyPhase.baseline);
          expect(pending(view)!.phase, AssessmentPhase.pre);
          await f.completeAssessment(AssessmentPhase.pre);
        }
        view = await runtime.load(owner);
        expect(view.phase, StudyPhase.ready);
        expect(pending(view), isNull);
        expect(
          await f.authorities.study.rows('measurement_opportunities'),
          isEmpty,
        );
        expect(
          (await f.authorities.study.rows('assessment_runs')),
          hasLength(1),
        );
      },
    );
  }

  test(
    'Runtime itself denies opening and index mutation while pre is pending',
    () async {
      final runtime = f.attach();
      await f.recordMotivation(MotivationTimepoint.baseline);
      final before = await f.authorities.study.researchRows();
      await expectLater(
        runtime.openPresentation(
          'owner-a',
          entryAttemptId: studyEntryId,
          stillCurrent: () => true,
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      await expectLater(
        runtime.startIndex(
          'owner-a',
          'foreign-opportunity',
          stillVisible: () => true,
        ),
        throwsA(isA<ResearchCaptureDenied>()),
      );
      expect(await f.authorities.study.researchRows(), before);
      expect(await f.authorities.study.rows('assessment_runs'), isEmpty);
      expect(await f.authorities.study.rows('learning_sessions'), isEmpty);
    },
  );

  for (final first in ['Motivation', 'Assessment']) {
    test(
      '$first post form can complete first and pair comparison uses original pre',
      () async {
        final runtime = f.attach();
        await f.completeAssessment(AssessmentPhase.pre);
        await f.recordMotivation(MotivationTimepoint.baseline);
        final originalPre = await f.authorities.study.rows('assessment_runs');
        final index = await f.finishIndex();
        var view = await runtime.load('owner-a');
        expect(view.phase, StudyPhase.post);
        expect(pending(view)!.phase, AssessmentPhase.post);
        expect(view.index!.sessionId, index.sessionId);
        if (first == 'Motivation') {
          await f.recordMotivation(MotivationTimepoint.post);
          view = await runtime.load('owner-a');
          expect(view.phase, StudyPhase.post);
          expect(pending(view)!.phase, AssessmentPhase.post);
          await f.completeAssessment(AssessmentPhase.post);
        } else {
          await f.completeAssessment(AssessmentPhase.post);
          view = await runtime.load('owner-a');
          expect(view.phase, StudyPhase.post);
          expect(pending(view), isNull);
          await f.recordMotivation(MotivationTimepoint.post);
        }
        view = await runtime.load('owner-a');
        expect(view.phase, StudyPhase.completed);
        expect(completedPair(view), isTrue);
        final after = await f.authorities.study.rows('assessment_runs');
        expect(
          after.singleWhere((row) => row['phase'] == 'pre'),
          originalPre.single,
        );
        final result = await f.assessment.comparison.compare(
          ownerId: 'owner-a',
          studyCycleId: f.cycleId,
          stillVisible: () => true,
        );
        expect(result, isA<AssessmentComparisonReady>());
        expect((result as AssessmentComparisonReady).preOutcome.sampleSize, 1);
        expect(result.postOutcome.sampleSize, 1);
        expect(await f.authorities.study.rows('assessment_runs'), hasLength(2));
      },
    );
  }

  test(
    'abandoned pre stops optional Study rather than inventing a replacement',
    () async {
      final runtime = f.attach();
      await f.assessment.useCases.beginPresentation(
        f.command(AssessmentPhase.pre),
        ownerId: 'owner-a',
        stillVisible: () => true,
      );
      await f.assessment.useCases.abandonPresentation(
        ownerId: 'owner-a',
        runId: f.command(AssessmentPhase.pre).runId,
        stillVisible: () => true,
      );
      expect((await runtime.load('owner-a')).phase, StudyPhase.stopped);
      expect(await f.authorities.study.rows('assessment_runs'), hasLength(1));
      expect(
        await f.authorities.study.rows('measurement_opportunities'),
        isEmpty,
      );
    },
  );

  test('tampered numeric Assessment pins cannot authorize opening', () async {
    final runtime = f.attach();
    await f.completeAssessment(AssessmentPhase.pre);
    await f.recordMotivation(MotivationTimepoint.baseline);
    await f.authorities.study.database.customStatement(
      'UPDATE assessment_runs SET instrument_revision = instrument_revision + 1',
    );
    final before = await f.authorities.study.researchRows();
    expect((await runtime.load('owner-a')).phase, StudyPhase.unavailable);
    await expectLater(
      runtime.openPresentation(
        'owner-a',
        entryAttemptId: studyEntryId,
        stillCurrent: () => true,
      ),
      throwsStateError,
    );
    expect(await f.authorities.study.researchRows(), before);
  });

  test(
    'inspection and mutation gates never fetch Assessment form content or gateway IO',
    () async {
      final runtime = f.attach();
      await f.completeAssessment(AssessmentPhase.pre);
      await f.recordMotivation(MotivationTimepoint.baseline);
      final contentCalls = f.content.calls;
      final gatewayCalls = f.authorities.gateway.calls;
      await runtime.load('owner-a');
      await f.openPresentation();
      await runtime.load('owner-a');
      expect(f.content.calls, contentCalls);
      expect(f.authorities.gateway.calls, gatewayCalls);
      expect(f.content.transactionReads, everyElement(isFalse));
      expect(await f.authorities.study.rows('points_ledger_entries'), isEmpty);
      expect(await f.authorities.study.rows('srs_states'), isEmpty);
      expect(await f.authorities.study.rows('outbox_operations'), isEmpty);
    },
  );

  test(
    'foreign database Assessment service cannot be attached to canonical Study',
    () async {
      final foreign = await AssessmentStudyFixture.open();
      addTearDown(foreign.close);
      expect(() => f.attach(supplied: foreign.assessment), throwsArgumentError);
    },
  );

  for (final phase in AssessmentPhase.values) {
    test(
      'completed ${phase.name} with a deleted real response cannot gate or compare',
      () async {
        final runtime = f.attach();
        await f.completeAssessment(AssessmentPhase.pre);
        await f.recordMotivation(MotivationTimepoint.baseline);
        if (phase == AssessmentPhase.post) {
          await f.finishIndex();
          await f.completeAssessment(AssessmentPhase.post);
        }
        await f.authorities.study.database.customStatement(
          'DELETE FROM answer_attempts WHERE owner_id = ? AND session_id = ?',
          ['owner-a', f.command(phase).learningSessionId],
        );
        final before = await f.authorities.study.researchRows();
        final originalRuns = await f.authorities.study.rows('assessment_runs');
        final contentReads = f.content.calls;
        final gatewayReads = f.authorities.gateway.calls;
        final view = await runtime.load('owner-a');
        expect(view.phase, StudyPhase.unavailable);
        expect(completedPair(view), isFalse);
        if (phase == AssessmentPhase.pre) {
          await expectLater(
            runtime.openPresentation(
              'owner-a',
              entryAttemptId: studyEntryId,
              stillCurrent: () => true,
            ),
            throwsStateError,
          );
          expect(
            await f.authorities.study.rows('measurement_opportunities'),
            isEmpty,
          );
        }
        expect(f.content.calls, contentReads);
        expect(f.authorities.gateway.calls, gatewayReads);
        expect(await f.authorities.study.rows('assessment_runs'), originalRuns);
        expect(await f.authorities.study.researchRows(), before);
      },
    );
  }
}
