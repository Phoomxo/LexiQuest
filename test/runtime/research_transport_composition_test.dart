import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/consent/data/drift_research_consent_repository.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/research/data/drift_study_archive_repository.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import '../support/assessment_authority_harness.dart';
import '../support/research_transport_composition_harness.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'synthetic composition shares exact context and defers canonical learning',
    () async {
      final source = await AssessmentAuthorityFixture.open();
      addTearDown(source.close);
      final old = source.study.runtime.context;
      late LearningUseCases learning;
      var getterCalls = 0;
      final context = StudyRuntimeContext(
        database: old.database,
        owners: old.owners,
        ownerWrites: old.ownerWrites,
        consentRepository: DriftResearchConsentRepository(
          old.database,
          ownerWrites: old.ownerWrites,
        ),
        generateId: old.generateId,
        nowUtc: old.nowUtc,
        buildInfo: old.buildInfo,
        getLearning: () {
          getterCalls++;
          return learning;
        },
      );
      final before = await _rows(source);
      final harness = SyntheticResearchCompositionHarness(
        source: source,
        store: _NoWriteStore(),
      );
      final factoryContext = ResearchTransportFactoryContext(
        study: context,
        baseUri: Uri.https('synthetic-research.invalid'),
      );
      final composition = await harness.create(factoryContext);
      addTearDown(composition.dispose);
      composition.validate(factoryContext);
      expect(harness.capturedContext, same(factoryContext));
      expect(composition.studyRuntime.context, same(context));
      expect(composition.consent.repository, same(context.consentRepository));
      expect(
        composition.studyRuntime.consent.remoteDecisions,
        same(composition.consent),
      );
      expect(
        composition.studyUploads.repository,
        same(composition.studyArchives.repository),
      );
      final archive =
          composition.studyArchives.repository as DriftStudyArchiveRepository;
      expect(archive.study, same(composition.studyRuntime));
      expect(
        composition.lifecycle.caches,
        contains(same(archive.motivationAuthority)),
      );
      expect(harness.assessmentFactoryCalls, 0);
      expect(harness.learningGetterCalls, 0);
      expect(getterCalls, 0);
      expect(harness.gateway.enrollmentReads, 0);
      expect(harness.gateway.consentDecisions, 0);
      expect(harness.gateway.uploadWrites, 0);
      expect(composition.lifecycle.readGate.isOpen, isFalse);
      expect(await _rows(source), before);

      final writer = DriftLearningRepository(
        context.database,
        ownerWrites: context.ownerWrites,
        lifecycleObserver: composition.studyRuntime.lifecycleObserver,
      );
      learning = LearningUseCases(
        owners: context.owners,
        repository: writer,
        generateId: context.generateId,
        nowUtc: context.nowUtc,
        buildInfo: context.buildInfo,
      );
      final assessment = composition.studyRuntime.assessment!;
      expect(composition.studyRuntime.assessment, same(assessment));
      final assessmentWriter =
          assessment.repository as DriftAssessmentRepository;
      final cycleReader = assessmentWriter.cycleReader;
      expect(cycleReader.learning, same(writer));
      expect(cycleReader.database, same(context.database));
      expect(
        assessmentWriter.authority.cache.ownerWrites,
        same(context.ownerWrites),
      );
      expect(getterCalls, 1);
      expect(harness.learningGetterCalls, 1);
      expect(composition.studyRuntime.learning, same(learning));
      expect(
        await composition.lifecycle.refresh(stillCurrent: () => true),
        isTrue,
      );
      expect(composition.lifecycle.readGate.isOpen, isTrue);
      expect(harness.gateway.consentDecisions, 0);
      expect(harness.gateway.uploadWrites, 0);
      expect(await _rows(source), before);

      harness.setBinding(null);
      expect(composition.lifecycle.readGate.isOpen, isFalse);
      expect(composition.studyRuntime.assessment, isNull);
      final firstDisposal = composition.dispose();
      expect(composition.dispose(), same(firstDisposal));
      await firstDisposal;
      expect(harness.resourceDisposals, 1);
      expect(await _rows(source), before);
    },
  );
}

Future<Map<String, List<Map<String, Object?>>>> _rows(
  AssessmentAuthorityFixture source,
) async => {
  for (final table in source.study.database.allTables)
    table.actualTableName:
        (await source.study.database
                .customSelect('SELECT * FROM "${table.actualTableName}"')
                .get())
            .map((row) => row.data)
            .toList(),
};

final class _NoWriteStore implements ExportArtifactStore {
  @override
  Future<ExportSaveResult> save(
    ExportArtifact artifact, {
    required ExportCancellation cancellation,
    required Future<void> Function() revalidateBeforeWrite,
  }) => throw StateError('Composition must not write an archive');
}
