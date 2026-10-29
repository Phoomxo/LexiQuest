import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/assessment_writer_harness.dart';
import '../../support/experiment_assignment_fixture.dart';
import '../../support/motivation_measurement_fixture.dart';
import '../../support/research_participation_fixture.dart';

void main() {
  for (final corruption in [
    'active-pre',
    'other-cycle',
    'foreign-owner',
    'participation-hash',
    'session-terminal',
    'malformed-shape',
  ]) {
    test('$corruption Assessment container cannot conceal a first-index gap', () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      fixture.authorities.advance(const Duration(minutes: 1));
      final pre = await fixture.start();
      if (corruption != 'active-pre') await _completePre(fixture, pre);
      final database = fixture.authorities.study.database;
      switch (corruption) {
        case 'active-pre':
          break;
        case 'other-cycle':
          // A real historical signed second-owner bundle provides a distinct
          // existing FK target. Moving this run to it is deliberate corruption,
          // not authority to collect or a fabricated valid cycle history.
          final assignment = await seedOwnerAssignment(database, 'owner-b');
          final permit = await insertOwnerParticipation(
            database,
            'owner-b',
            assignmentId: assignment,
          );
          final other = await insertOwnerMotivationMeasurement(
            database,
            permit,
          );
          await database.customStatement(
            'UPDATE assessment_runs SET study_cycle_id = ? WHERE id = ?',
            [other.runId, pre.id],
          );
        case 'foreign-owner':
          await database.customStatement(
            "UPDATE assessment_runs SET owner_id = 'owner-b' WHERE id = ?",
            [pre.id],
          );
        case 'participation-hash':
          await database.customStatement(
            'UPDATE assessment_runs SET participation_permit_payload_sha256 = ? WHERE id = ?',
            ['f' * 64, pre.id],
          );
        case 'session-terminal':
          await database.customStatement(
            "UPDATE learning_sessions SET state = 'active', ended_at_utc_ms = NULL WHERE id = ?",
            [pre.learningSessionId],
          );
        case 'malformed-shape':
          // Exercise recovery of damaged stored data without weakening the
          // shipped CHECK or the model's strict constructor.
          await database.customStatement(
            'PRAGMA ignore_check_constraints = ON',
          );
          try {
            await database.customStatement(
              "UPDATE assessment_runs SET instrument_checksum_sha256 = 'invalid' WHERE id = ?",
              [pre.id],
            );
          } finally {
            await database.customStatement(
              'PRAGMA ignore_check_constraints = OFF',
            );
          }
      }
      final assessmentBefore = await fixture.authorities.study.rows(
        'assessment_runs',
      );
      final sessionsBefore = await fixture.authorities.study.rows(
        'learning_sessions',
      );
      final answersBefore = await fixture.authorities.study.rows(
        'answer_attempts',
      );

      await expectLater(
        fixture.authorities.study.ready(),
        throwsA(
          isA<ResearchCaptureDenied>().having(
            (error) => error.reason,
            'reason',
            ResearchCaptureReason.timingUnavailable,
          ),
        ),
      );

      expect(
        await fixture.authorities.study.rows('assessment_runs'),
        assessmentBefore,
      );
      expect(
        await fixture.authorities.study.rows('learning_sessions'),
        sessionsBefore,
      );
      expect(
        await fixture.authorities.study.rows('answer_attempts'),
        answersBefore,
      );
      expect(await fixture.authorities.study.rows('events_v2'), isEmpty);
      expect(
        await fixture.authorities.study.rows('outbox_operations'),
        isEmpty,
      );
      expect(await fixture.authorities.study.rows('srs_states'), isEmpty);
      expect(
        await fixture.authorities.study.rows('points_ledger_entries'),
        isEmpty,
      );
      expect(
        await fixture.authorities.study.rows('reward_transactions'),
        isEmpty,
      );
    });
  }

  for (final terminal in ['completed', 'abandoned']) {
    test(
      'backed active then $terminal post at exact zero-duration index end preserves the first index',
      () async {
        final fixture = await AssessmentWriterFixture.open();
        addTearDown(fixture.close);
        fixture.authorities.advance(const Duration(minutes: 1));
        final pre = await fixture.start();
        final completedPre = await _completePre(fixture, pre);
        final presented = await fixture.authorities.study.ready();
        expect(completedPre.completedAtUtc, presented.opportunity!.openedAtUtc);
        expect(
          completedPre.completedAtUtc,
          presented.opportunity!.presentation!.occurredAtUtc,
        );
        final index = await fixture.authorities.study.runtime.startIndex(
          'owner-a',
          presented.opportunity!.id,
          stillVisible: () => true,
        );
        // No clock advance or artificial scheduling delay. The canonical APIs
        // persist the original same-millisecond answer and terminal receipt.
        final completedIndex = await _finishAtCurrentTime(fixture, index);
        expect(completedIndex.endedAtUtc, index.startedAtUtc);
        expect(await fixture.authorities.cache.refresh(), isTrue);
        final ordinaryBeforePost = await fixture.ordinaryRows();
        final post = await fixture.start(phase: AssessmentPhase.post);
        expect(post.startedAtUtc, completedIndex.endedAtUtc);
        expect(post.state, AssessmentRunState.active);
        final activeProof = await fixture.authorities
            .cycleReader()
            .requirePhase(run: post);
        expect(activeProof.interventionSessionId, index.sessionId);
        expect(
          activeProof.interventionCompletedAtUtc,
          completedIndex.endedAtUtc,
        );

        late AssessmentRun closed;
        if (terminal == 'completed') {
          await fixture.repository.recordResponse(
            ownerId: 'owner-a',
            runId: post.id,
            itemId: fixture.definition.items.single.itemId,
            option: 'synthetic yes',
            responseTimeMs: 0,
            stillVisible: () => true,
          );
          closed = await fixture.repository.complete(
            ownerId: 'owner-a',
            runId: post.id,
            stillVisible: () => true,
          );
        } else {
          closed = await fixture.repository.abandon(
            ownerId: 'owner-a',
            runId: post.id,
            stillVisible: () => true,
          );
        }

        final proof = await fixture.authorities.cycleReader().requirePhase(
          run: closed,
        );
        expect(proof.interventionSessionId, index.sessionId);
        expect(proof.interventionStartedAtUtc, index.startedAtUtc);
        expect(proof.interventionCompletedAtUtc, completedIndex.endedAtUtc);
        expect(closed.state.name, terminal);
        expect(
          closed.completedAtUtc ?? closed.abandonedAtUtc,
          completedIndex.endedAtUtc,
        );
        expect(await fixture.ordinaryRows(), ordinaryBeforePost);
        final view = await fixture.authorities.study.runtime.load('owner-a');
        expect(view.phase, StudyPhase.post);
        expect(view.index!.sessionId, index.sessionId);
        expect(view.index!.startedAtUtc, index.startedAtUtc);
        expect(view.index!.endedAtUtc, completedIndex.endedAtUtc);
        final sessions = await fixture.authorities.study.rows(
          'learning_sessions',
        );
        expect(sessions, hasLength(3));
        expect(
          sessions.where((row) => row['activity_type'] != 'assessment'),
          hasLength(1),
        );
      },
    );
  }
}

Future<AssessmentRun> _completePre(
  AssessmentWriterFixture fixture,
  AssessmentRun pre,
) async {
  await fixture.repository.recordResponse(
    ownerId: 'owner-a',
    runId: pre.id,
    itemId: fixture.definition.items.single.itemId,
    option: 'synthetic yes',
    responseTimeMs: 0,
    stillVisible: () => true,
  );
  return fixture.repository.complete(
    ownerId: 'owner-a',
    runId: pre.id,
    stillVisible: () => true,
  );
}

Future<ConfiguredQuizState> _finishAtCurrentTime(
  AssessmentWriterFixture fixture,
  ConfiguredQuizState index,
) async {
  final learning = fixture.authorities.study.learning;
  final question = index.plan.questions.single;
  var saved = await learning.prepareQuizAnswer(
    sessionId: index.sessionId,
    expectedOwnerId: 'owner-a',
    expectedRevision: index.checkpointRevision,
    selectedOptionOrdinal: question.options.indexWhere(
      (option) => option != question.correctAnswer,
    ),
    responseTimeMs: 0,
  );
  saved = (await learning.commitQuizAnswer(
    sessionId: saved.sessionId,
    expectedOwnerId: 'owner-a',
    expectedRevision: saved.checkpointRevision,
  )).state;
  saved = await learning.prepareQuizFinish(
    sessionId: saved.sessionId,
    expectedOwnerId: 'owner-a',
    expectedRevision: saved.checkpointRevision,
  );
  return (await learning.finishConfiguredQuiz(
    sessionId: saved.sessionId,
    expectedOwnerId: 'owner-a',
    expectedRevision: saved.checkpointRevision,
  )).state;
}
