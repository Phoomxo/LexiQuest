import 'package:drift/drift.dart' show QueryExecutor, QueryInterceptor;
import 'package:flutter_test/flutter_test.dart';

import '../../support/assessment_writer_harness.dart';

void main() {
  for (final change in <String, String>{
    'original P2 signed bytes':
        "UPDATE research_participation_permits SET age_band_code = 'post-authority-tamper' WHERE id = 'synthetic-participation'",
    'original assignment bytes':
        "UPDATE experiment_assignments SET assigned_at_utc_ms = assigned_at_utc_ms + 1 WHERE owner_id = 'owner-a'",
  }.entries) {
    test(
      '${change.key} changed after authority awaits rolls response and tamper back',
      () async {
        final fixture = await AssessmentWriterFixture.open();
        addTearDown(fixture.close);
        final run = await fixture.start();
        final before = await fixture.ordinaryRows();
        final probe = _FinalBindingTamper(
          () =>
              fixture.authorities.study.database.customStatement(change.value),
        );
        await expectLater(
          () => fixture.authorities.study.database.runWithInterceptor(
            () => fixture.repository.recordResponse(
              ownerId: 'owner-a',
              runId: run.id,
              itemId: fixture.definition.items.single.itemId,
              option: 'synthetic yes',
              responseTimeMs: 29,
              stillVisible: () => true,
            ),
            interceptor: probe,
          ),
          throwsStateError,
        );
        expect(probe.answerInserts, 1);
        expect(probe.tampered, isTrue);
        expect(
          await fixture.authorities.study.rows('answer_attempts'),
          isEmpty,
        );
        expect(await fixture.ordinaryRows(), before);
      },
    );
  }
}

final class _FinalBindingTamper extends QueryInterceptor {
  _FinalBindingTamper(this.mutate);
  final Future<void> Function() mutate;
  int answerInserts = 0;
  bool tampered = false;
  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    if (statement.startsWith('INSERT INTO answer_attempts')) answerInserts++;
  }

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runSelect(statement, args);
    if (answerInserts > 0 &&
        !tampered &&
        statement.startsWith('SELECT id FROM vocabulary_words')) {
      tampered = true;
      await mutate();
    }
    return result;
  }
}
