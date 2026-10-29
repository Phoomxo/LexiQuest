import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_repository.dart';
import 'package:vocab_learning_app/runtime/app_build_info.dart';

import '../../support/assessment_writer_harness.dart';

DriftAssessmentRepository upgradedReader(AssessmentWriterFixture fixture) =>
    DriftAssessmentRepository(
      fixture.authorities.study.database,
      authority: fixture.repository.authority,
      cycleReader: fixture.repository.cycleReader,
      catalog: fixture.repository.catalog,
      contentAuthority: fixture.content,
      buildInfo: const AppBuildInfo(
        version: 'synthetic-upgraded-app',
        buildId: 'synthetic-upgraded-build',
      ),
      participationPermitId: 'synthetic-participation',
    );

void main() {
  test(
    'compatible completed outcome remains historically readable after app build upgrade',
    () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      final run = await fixture.start();
      await fixture.repository.recordResponse(
        ownerId: 'owner-a',
        runId: run.id,
        itemId: fixture.definition.items.single.itemId,
        option: 'synthetic yes',
        responseTimeMs: 31,
        stillVisible: () => true,
      );
      await fixture.repository.complete(
        ownerId: 'owner-a',
        runId: run.id,
        stillVisible: () => true,
      );
      final original = await fixture.repository.listOutcomeEvidence(
        ownerId: 'owner-a',
        learningSessionId: run.learningSessionId,
      );
      final before = await fixture.authorities.study.rows('answer_attempts');
      final historical = await upgradedReader(fixture).listOutcomeEvidence(
        ownerId: 'owner-a',
        learningSessionId: run.learningSessionId,
      );
      expect(
        historical.single.sourceEvidenceId,
        original.single.sourceEvidenceId,
      );
      expect(historical.single.occurredAtUtc, original.single.occurredAtUtc);
      expect(historical.single.responseTimeMs, original.single.responseTimeMs);
      expect(
        historical.single.evidenceContext.toJson(),
        original.single.evidenceContext.toJson(),
      );
      expect(await fixture.authorities.study.rows('answer_attempts'), before);
    },
  );

  test(
    'upgraded reader does not reopen current capture or presentation under old run pins',
    () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      final run = await fixture.start();
      final reader = upgradedReader(fixture);
      await expectLater(
        () => reader.recordResponse(
          ownerId: 'owner-a',
          runId: run.id,
          itemId: fixture.definition.items.single.itemId,
          option: 'synthetic yes',
          responseTimeMs: 31,
          stillVisible: () => true,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      await expectLater(
        () => reader.requireActivePresentation(
          ownerId: 'owner-a',
          runId: run.id,
          stillVisible: () => true,
        ),
        throwsA(isA<AssessmentRunConflict>()),
      );
      expect(await fixture.authorities.study.rows('answer_attempts'), isEmpty);
    },
  );
}
