import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  test('writer rejects an actual cycle reader from another database', () async {
    final first = await AssessmentWriterFixture.open();
    addTearDown(first.close);
    final other = await AssessmentWriterFixture.open();
    addTearDown(other.close);
    final writer = first.repository;
    expect(
      () => DriftAssessmentRepository(
        writer.database,
        authority: writer.authority,
        cycleReader: other.repository.cycleReader,
        catalog: writer.catalog,
        contentAuthority: writer.contentAuthority,
        buildInfo: writer.buildInfo,
        participationPermitId: writer.participationPermitId,
      ),
      throwsArgumentError,
    );
    expect(await first.authorities.study.rows('assessment_runs'), isEmpty);
    expect(await other.authorities.study.rows('assessment_runs'), isEmpty);
  });
}
