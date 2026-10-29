import 'package:flutter_test/flutter_test.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  test(
    'real signed writer persists one exact Assessment run and bare container',
    () async {
      final fixture = await AssessmentWriterFixture.open();
      addTearDown(fixture.close);
      final run = await fixture.start();
      expect(run.startedAtUtc, participationStart);
      expect(run.instrumentRevision, 41);
      final rows = await fixture.authorities.study.rows('assessment_runs');
      expect(rows, hasLength(1));
      final session = (await fixture.authorities.study.rows(
        'learning_sessions',
      )).single;
      expect(session['id'], run.learningSessionId);
      expect(session['activity_type'], 'assessment');
      expect(session['accepted_plan_json'], isNull);
      expect(session['checkpoint_json'], isNull);
      expect(fixture.content.transactionReads, everyElement(isFalse));
    },
  );
}
