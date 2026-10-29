import 'package:vocab_learning_app/features/assessment/application/study_assessment.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_models.dart';
import 'package:vocab_learning_app/features/learning/domain/learning_models.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_measurement.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_instrument.dart';

import 'assessment_writer_harness.dart';

export 'assessment_writer_harness.dart' show participationStart, studyEntryId;

final class AssessmentStudyFixture {
  AssessmentStudyFixture(this.authorities);
  final AssessmentAuthorityFixture authorities;
  late final WriterContentAuthority content;
  late final DriftAssessmentRepository repository;
  late final StudyAssessment assessment;
  late final String cycleId;

  static Future<AssessmentStudyFixture> open() async {
    final f = AssessmentStudyFixture(await AssessmentAuthorityFixture.open());
    final study = f.authorities.study;
    f.cycleId = (await study.runtime.begin(study.ownerId)).run!.id;
    f.content = WriterContentAuthority(f.authorities, f.authorities.definition);
    final cycleReader = f.authorities.cycleReader();
    f.repository = DriftAssessmentRepository(
      study.database,
      authority: f.authorities.authority,
      cycleReader: cycleReader,
      catalog: AssessmentInstrumentCatalog(entries: [f.authorities.definition]),
      contentAuthority: f.content,
      buildInfo: study.runtime.context.buildInfo,
      participationPermitId: 'synthetic-participation',
    );
    f.assessment = StudyAssessment(
      repository: f.repository,
      definition: f.authorities.definition,
      mapping: f.repository.authority.mapping,
      contentAuthority: f.content,
      cycleReader: cycleReader,
      trustedTime: f.authorities.cache,
    );
    if (!await f.authorities.cache.refresh()) {
      throw StateError('Synthetic Assessment refresh failed.');
    }
    return f;
  }

  LocalStudyRuntime attach({StudyAssessment? supplied}) {
    final study = authorities.study;
    final runtime =
        Function.apply(LocalStudyRuntime.new, [], {
              #context: study.runtime.context,
              #authorities: study.authorities,
              #catalog: study.catalog,
              #assessment: supplied ?? assessment,
            })
            as LocalStudyRuntime;
    study.runtime = runtime;
    study.bindLearning();
    return runtime;
  }

  AssessmentStartCommand command(AssessmentPhase phase) => assessment.command(
    ownerId: authorities.study.ownerId,
    studyCycleId: cycleId,
    phase: phase,
  );

  Future<void> completeAssessment(AssessmentPhase phase) async {
    final cmd = command(phase);
    final shown = await assessment.useCases.beginPresentation(
      cmd,
      ownerId: authorities.study.ownerId,
      stillVisible: () => true,
    );
    for (final item in shown.items) {
      final option = authorities.definition
          .item(item.itemId)
          .responses
          .entries
          .firstWhere((entry) => entry.value.isCorrect)
          .key;
      await assessment.useCases.submitPresentedResponse(
        ownerId: authorities.study.ownerId,
        runId: cmd.runId,
        itemId: item.itemId,
        option: option,
        responseTimeMs: 25,
        stillVisible: () => true,
      );
    }
    await assessment.useCases.completePresentation(
      ownerId: authorities.study.ownerId,
      runId: cmd.runId,
      stillVisible: () => true,
    );
  }

  Future<void> recordMotivation(MotivationTimepoint point) => authorities
      .study
      .runtime
      .measurementsFor(authorities.study.ownerId)
      .record(
        MotivationResponse(
          ownerId: authorities.study.ownerId,
          runId: cycleId,
          itemId: 'synthetic-${point.name}',
          responseCode: 'high',
        ),
      )
      .then((_) {});

  Future<StudyView> openPresentation() async {
    final study = authorities.study;
    authorities.advance(const Duration(minutes: 1));
    final opened = await study.runtime.openPresentation(
      study.ownerId,
      entryAttemptId: studyEntryId,
      stillCurrent: () => true,
    );
    study.runtime.markPresentationMayRender(
      study.ownerId,
      opened.opportunity!.id,
      entryAttemptId: studyEntryId,
    );
    return study.runtime.recordPresented(
      study.ownerId,
      opened.opportunity!.id,
      entryAttemptId: studyEntryId,
      stillVisible: () => true,
    );
  }

  Future<ConfiguredQuizState> finishIndex() async {
    final study = authorities.study;
    final ready = await openPresentation();
    authorities.advance(const Duration(minutes: 1));
    final index = await study.runtime.startIndex(
      study.ownerId,
      ready.opportunity!.id,
      stillVisible: () => true,
    );
    authorities.advance(const Duration(minutes: 1));
    return study.finish(index);
  }

  Future<void> close() => authorities.close();
}
