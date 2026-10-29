import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  test(
    'backed pre container at exact first Presented millisecond preserves canonical quiz then post',
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
        responseTimeMs: 17,
        stillVisible: () => true,
      );
      final completedPre = await fixture.repository.complete(
        ownerId: 'owner-a',
        runId: pre.id,
        stillVisible: () => true,
      );
      final presented = await fixture.authorities.study.ready();
      expect(presented.phase, StudyPhase.ready);
      expect(
        completedPre.completedAtUtc,
        presented.opportunity!.presentation!.occurredAtUtc,
      );
      expect(
        pre.startedAtUtc,
        presented.opportunity!.presentation!.occurredAtUtc,
      );
      fixture.authorities.advance(const Duration(minutes: 1));
      final index = await fixture.authorities.study.runtime.startIndex(
        'owner-a',
        presented.opportunity!.id,
        stillVisible: () => true,
      );
      final completedIndex = await fixture.authorities.study.finish(index);
      // Refresh observes the actual R3 completion time; no artificial delay is added.
      expect(await fixture.authorities.cache.refresh(), isTrue);
      final ordinaryBeforePost = await fixture.ordinaryRows();
      final post = await fixture.start(phase: AssessmentPhase.post);
      expect(post.startedAtUtc, completedIndex.endedAtUtc);
      await fixture.repository.recordResponse(
        ownerId: 'owner-a',
        runId: post.id,
        itemId: fixture.definition.items.single.itemId,
        option: 'synthetic yes',
        responseTimeMs: 13,
        stillVisible: () => true,
      );
      await fixture.repository.complete(
        ownerId: 'owner-a',
        runId: post.id,
        stillVisible: () => true,
      );
      expect(await fixture.ordinaryRows(), ordinaryBeforePost);
      final proof = await fixture.authorities.cycleReader().requirePhase(
        run: post,
      );
      expect(proof.interventionSessionId, index.sessionId);
      expect(proof.interventionCompletedAtUtc, completedIndex.endedAtUtc);
    },
  );

  test(
    'unbacked activity assessment cannot hide an earlier ordinary index candidate',
    () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      final database = fixture.authorities.study.database;
      await database.customStatement(
        'INSERT INTO learning_sessions (id,owner_id,activity_type,state,started_at_utc_ms,app_version,build_id) '
        "VALUES ('synthetic-unbacked-assessment','owner-a','assessment','completed',?,?,?)",
        [
          participationStart
              .add(const Duration(minutes: 1))
              .millisecondsSinceEpoch,
          fixture.authorities.study.runtime.context.buildInfo.version,
          fixture.authorities.study.runtime.context.buildInfo.buildId,
        ],
      );
      await expectLater(
        () => fixture.authorities.study.ready(),
        throwsA(
          isA<ResearchCaptureDenied>().having(
            (error) => error.reason,
            'reason',
            ResearchCaptureReason.timingUnavailable,
          ),
        ),
      );
      expect(await fixture.authorities.study.rows('assessment_runs'), isEmpty);
      expect(
        (await fixture.authorities.study.rows(
          'learning_sessions',
        )).single['id'],
        'synthetic-unbacked-assessment',
      );
    },
  );
}
