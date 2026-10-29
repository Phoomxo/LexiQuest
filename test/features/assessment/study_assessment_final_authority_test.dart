import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/measurement_opportunity.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';

import '../../support/assessment_study_harness.dart';

void main() {
  for (final opening in [false, true]) {
    test(
      '${opening ? 'after-insert opening ACK' : 'availability'} rechecks real pre facts after final authority await',
      () async {
        final f = await AssessmentStudyFixture.open();
        addTearDown(f.close);
        final runtime = f.attach();
        final study = f.authorities.study;
        await f.completeAssessment(AssessmentPhase.pre);
        await f.recordMotivation(MotivationTimepoint.baseline);
        final pre = await f.repository.getRun(
          ownerId: study.ownerId,
          runId: f.command(AssessmentPhase.pre).runId,
        );
        final before = await study.researchRows();
        final probe = _FinalParticipantProbe(requireInsert: opening);
        var deleted = false;
        study.participation.states.onRead = (_) async {
          if (deleted || !probe.finalAuthorityCanMutate) return;
          deleted = true;
          await study.database.customStatement(
            'DELETE FROM answer_attempts WHERE owner_id = ? AND session_id = ?',
            [study.ownerId, pre.learningSessionId],
          );
        };
        if (opening) {
          await expectLater(
            study.database.runWithInterceptor(
              () => runtime.openPresentation(
                study.ownerId,
                entryAttemptId: studyEntryId,
                stillCurrent: () => true,
              ),
              interceptor: probe,
            ),
            throwsStateError,
          );
          expect(
            await study.researchRows(),
            before,
            reason:
                'The failed outer opening transaction rolls back both the injected deletion and its opportunity.',
          );
          final id = measurementOpportunityId(
            ownerId: study.ownerId,
            measurementRunId: f.cycleId,
            permitId: pre.participationPermitId,
            entryAttemptId: studyEntryId,
          );
          expect(
            () => runtime.markPresentationMayRender(
              study.ownerId,
              id,
              entryAttemptId: studyEntryId,
            ),
            throwsA(isA<ResearchCaptureDenied>()),
          );
        } else {
          final result = await study.database.runWithInterceptor(
            () => runtime.load(study.ownerId),
            interceptor: probe,
          );
          expect(result.phase, StudyPhase.unavailable);
          expect(
            await study.rows('answer_attempts'),
            isEmpty,
            reason:
                'This availability race injects a committed genuine-data deletion, not a fake phase snapshot.',
          );
        }
        expect(
          deleted,
          isTrue,
          reason:
              'The final real R3 authority callback must execute the SQL fault.',
        );
        expect(probe.runtimeCycleRead, isTrue);
        if (opening) expect(probe.inserted, isTrue);
        expect(await study.rows('measurement_opportunities'), isEmpty);
        expect(await study.rows('events_v2'), before['events_v2']);
        expect(
          await study.rows('outbox_operations'),
          before['outbox_operations'],
        );
      },
    );
  }
}

/// The Runtime's scoped cycle read follows its initial participant check.
/// Requiring the insert additionally targets the *second* Runtime inspection,
/// after repository opening/authority checks, rather than an earlier callback.
final class _FinalParticipantProbe extends QueryInterceptor {
  _FinalParticipantProbe({required this.requireInsert});
  final bool requireInsert;
  bool inserted = false;
  bool runtimeCycleRead = false;
  bool get finalAuthorityCanMutate =>
      runtimeCycleRead && (!requireInsert || inserted);

  @override
  Future<List<Map<String, Object?>>> runSelect(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final rows = await executor.runSelect(statement, args);
    if (statement.contains(
          'SELECT id FROM motivation_measurement_runs WHERE owner_id =',
        ) &&
        statement.contains('AND assignment_id =')) {
      runtimeCycleRead = true;
    }
    return rows;
  }

  void _observeInsert(String statement) {
    final sql = statement.toLowerCase();
    if (sql.contains('insert into measurement_opportunities') ||
        sql.contains('insert into "measurement_opportunities"')) {
      inserted = true;
      runtimeCycleRead = false;
    }
  }

  @override
  Future<void> runCustom(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    await executor.runCustom(statement, args);
    _observeInsert(statement);
  }

  @override
  Future<int> runInsert(
    QueryExecutor executor,
    String statement,
    List<Object?> args,
  ) async {
    final result = await executor.runInsert(statement, args);
    _observeInsert(statement);
    return result;
  }
}
