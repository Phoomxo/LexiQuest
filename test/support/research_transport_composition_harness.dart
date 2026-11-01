import 'dart:async';

import 'package:vocab_learning_app/features/adventure/domain/adventure_entry.dart';
import 'package:vocab_learning_app/features/assessment/application/study_assessment.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_authority.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_cycle_reader.dart';
import 'package:vocab_learning_app/features/assessment/data/drift_assessment_repository.dart';
import 'package:vocab_learning_app/features/assessment/domain/assessment_instrument_catalog.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/learning/data/drift_learning_repository.dart';
import 'package:vocab_learning_app/features/research/application/controlled_study_archive_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/controlled_study_upload_use_cases.dart';
import 'package:vocab_learning_app/features/research/application/local_study_runtime.dart';
import 'package:vocab_learning_app/features/research/application/research_authority_lifecycle.dart';
import 'package:vocab_learning_app/features/research/application/research_transport_consent_coordinator.dart';
import 'package:vocab_learning_app/features/research/data/drift_measurement_opportunity_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_repository.dart';
import 'package:vocab_learning_app/features/research/data/drift_motivation_measurement_timing_reader.dart';
import 'package:vocab_learning_app/features/research/data/drift_study_archive_repository.dart';
import 'package:vocab_learning_app/features/research/data/local_research_authority_cache.dart';
import 'package:vocab_learning_app/features/research/domain/research_authority_snapshot.dart';
import 'package:vocab_learning_app/features/research/domain/experiment_assignment_admission.dart';
import 'package:vocab_learning_app/features/research/domain/motivation_study_protocol.dart';
import 'package:vocab_learning_app/features/research/domain/research_transport_contracts.dart';
import 'package:vocab_learning_app/runtime/research_transport_composition.dart';

import 'assessment_authority_harness.dart';
import 'research_authority_cache_harness.dart';

/// Reuses the existing real signed, explicitly synthetic configuration. The
/// caller seeds [source] before bootstrap; this factory never seeds or refreshes.
final class SyntheticResearchCompositionHarness {
  SyntheticResearchCompositionHarness({
    required this.source,
    required this.store,
  }) : binding = source.scope!.binding;

  final AssessmentAuthorityFixture source;
  final ExportArtifactStore store;
  final bindingChanges = StreamController<ResearchAuthorityBinding?>.broadcast(
    sync: true,
  );
  ResearchAuthorityBinding? binding;
  ResearchTransportFactoryContext? capturedContext;
  ResearchTransportComposition? composition;
  int factoryCalls = 0;
  int assessmentFactoryCalls = 0;
  int learningGetterCalls = 0;
  int resourceDisposals = 0;
  Duration elapsed = Duration.zero;
  late SyntheticResearchCompositionGateway gateway;

  void setBinding(ResearchAuthorityBinding? value) {
    binding = value;
    bindingChanges.add(value);
  }

  Future<ResearchTransportComposition> create(
    ResearchTransportFactoryContext context,
  ) async {
    factoryCalls++;
    capturedContext = context;
    final oldStudy = source.study;
    if (!identical(oldStudy.database, context.study.database)) {
      throw ArgumentError('The synthetic seed must use the bootstrap database');
    }
    final template = oldStudy.authorities;
    final motivationFixture = AuthorityCacheFixture(oldStudy);
    final motivationScope = motivationFixture.scopeFor('owner-a', 'uid-a', 1);
    final assessmentScope = source.scope!;
    ResearchAuthorityScope? scope(ResearchAuthorityScope template) {
      final current = binding;
      if (current == null) return null;
      return ResearchAuthorityScope(
        binding: current,
        requirements: template.requirements,
        protocolVersion: template.protocolVersion,
        consentVersion: template.consentVersion,
      );
    }

    final gate = ResearchAuthorityReadGate();
    LocalResearchAuthorityCache cache(
      ResearchAuthorityScope templateScope,
      ResearchAuthorityGateway authorityGateway,
    ) => LocalResearchAuthorityCache(
      ownerWrites: context.study.ownerWrites,
      currentScope: () => scope(templateScope),
      gateway: authorityGateway,
      operationSignatures: template.operationSignatures,
      participationSignatures: template.participationSignatures,
      generateRequestId: context.study.generateId,
      maximumAcceptedAge: const Duration(minutes: 10),
      readGate: gate,
      initiallyForeground: true,
      monotonicElapsed: () => elapsed,
    );
    final motivationCache = cache(
      motivationScope,
      SyntheticAuthorityGateway(motivationFixture),
    );
    final assessmentCache = cache(assessmentScope, source.gateway);
    gateway = SyntheticResearchCompositionGateway(
      currentBinding: () => binding,
      motivation: motivationScope,
      assessment: assessmentScope,
    );
    late final ResearchAuthorityLifecycle lifecycle;
    final consent = ResearchTransportConsentCoordinator(
      repository: context.study.consentRepository,
      gateway: gateway,
      currentBinding: () => binding,
      bindingChanges: bindingChanges.stream,
      invalidateAuthority: () => lifecycle.invalidate(),
      generateRequestId: context.study.generateId,
      version: motivationScope.consentVersion,
    );
    lifecycle = ResearchAuthorityLifecycle(
      caches: [motivationCache, assessmentCache],
      readGate: gate,
      invalidations: [bindingChanges.stream],
      reconcileBeforeRefresh: consent.reconcileBeforeRefresh,
      onUnprovenInterval: consent.retirePending,
      initiallyForeground: true,
    );
    final protocol = template.binding.study;
    final authorities = StudyLocalAuthorities(
      binding: ExperimentAssignmentAdmissionBinding(
        study: MotivationStudyProtocol(
          protocolId: protocol.protocolId,
          protocolVersion: protocol.protocolVersion,
          consentVersion: protocol.consentVersion,
          experimentId: protocol.experimentId,
          experimentVersion: protocol.experimentVersion,
          instrument: protocol.instrument,
          approvedInstrumentChecksum: protocol.instrument.checksumSha256,
          appVersion: context.study.buildInfo.version,
          buildId: context.study.buildInfo.buildId,
          contentRevision: protocol.contentRevision,
          evidencePolicyVersion: protocol.evidencePolicyVersion,
          catalogVersion: protocol.catalogVersion,
        ),
        assignmentRevision: template.binding.assignmentRevision,
        protocolRevision: template.binding.protocolRevision,
        instrumentRevision: template.binding.instrumentRevision,
      ),
      permits: motivationCache,
      states: motivationCache,
      operationSignatures: template.operationSignatures,
      participationDocuments: motivationCache,
      participationSignatures: template.participationSignatures,
      receipts: motivationCache,
      trustedTime: motivationCache,
      supportedFormatVersion: template.supportedFormatVersion,
      trustedIssuerId: template.trustedIssuerId,
      trustedIssuerKeyId: template.trustedIssuerKeyId,
      availability: template.availability,
      supportedPresentations: {TodayExperiencePresentation.standard},
    );
    final assessments = <ResearchAuthorityBinding, StudyAssessment>{};
    late final LocalStudyRuntime runtime;
    runtime = LocalStudyRuntime(
      context: context.study,
      authorities: authorities,
      catalog: oldStudy.catalog,
      remoteConsentDecisions: consent,
      assessmentFactory: () {
        assessmentFactoryCalls++;
        final current = binding;
        if (current == null || current.ownerId != 'owner-a') return null;
        return assessments.putIfAbsent(current, () {
          learningGetterCalls++;
          final learning = context.study.getLearning().repository;
          if (learning is! DriftLearningRepository) {
            throw StateError('The canonical learning writer is required');
          }
          final measurements =
              runtime.measurementsFor(current.ownerId)
                  as DriftMotivationMeasurementRepository;
          final reader = DriftAssessmentCycleReader(
            context.study.database,
            measurements: measurements,
            opportunities: DriftMeasurementOpportunityRepository(
              context.study.database,
              measurements: measurements,
              timing:
                  measurements.timing as DriftMotivationMeasurementTimingReader,
            ),
            learning: learning,
          );
          final content = _SyntheticFormContent(source.definition);
          final repository = DriftAssessmentRepository(
            context.study.database,
            authority: DriftAssessmentAuthority(
              cache: assessmentCache,
              mapping: source.mapping,
            ),
            cycleReader: reader,
            catalog: AssessmentInstrumentCatalog(entries: [source.definition]),
            contentAuthority: content,
            buildInfo: context.study.buildInfo,
            participationPermitId: 'synthetic-participation',
          );
          return StudyAssessment(
            repository: repository,
            definition: source.definition,
            mapping: source.mapping,
            contentAuthority: content,
            cycleReader: reader,
            trustedTime: assessmentCache,
          );
        });
      },
    );
    final archive = DriftStudyArchiveRepository(
      study: runtime,
      motivationAuthority: motivationCache,
    );
    return composition = ResearchTransportComposition(
      studyRuntime: runtime,
      studyArchives: ControlledStudyArchiveUseCases(
        repository: archive,
        store: store,
      ),
      studyUploads: ControlledStudyUploadUseCases(
        repository: archive,
        gateway: gateway,
      ),
      consent: consent,
      lifecycle: lifecycle,
      notice: SuppliedResearchConsentNotice(
        version: motivationScope.consentVersion,
        protocolVersion: motivationScope.protocolVersion,
        title: 'Synthetic consent fixture',
        body: 'Synthetic notice for engineering tests; no production approval.',
      ),
      disposeResources: () async {
        resourceDisposals++;
        assessments.clear();
        await bindingChanges.close();
      },
    );
  }
}

final class _SyntheticFormContent implements AssessmentFormContentAuthority {
  const _SyntheticFormContent(this.definition);
  final AssessmentInstrumentDefinition definition;

  @override
  Future<AssessmentVerifiedFormContent> requireVerified(
    AssessmentFormContentIdentity identity,
  ) async => AssessmentVerifiedFormContent(
    identity: identity,
    checksumSha256: definition.formChecksumSha256,
    bytes: definition.formBytes,
  );
}

final class SyntheticResearchCompositionGateway
    implements ResearchEnrollmentGateway, StudyUploadGateway {
  SyntheticResearchCompositionGateway({
    required this.currentBinding,
    required this.motivation,
    required this.assessment,
  });
  final ResearchAuthorityBinding? Function() currentBinding;
  final ResearchAuthorityScope motivation;
  final ResearchAuthorityScope assessment;
  int enrollmentReads = 0;
  int consentDecisions = 0;
  int uploadWrites = 0;
  bool _withdrawn = false;

  void _requireCurrent(
    ResearchAuthorityBinding binding,
    bool Function() current,
  ) {
    if (currentBinding() != binding || !current()) {
      throw const ResearchTransportException(
        ResearchTransportFailureCode.ownerChanged,
      );
    }
  }

  @override
  Future<ResearchEnrollmentContext> loadEnrollment(
    ResearchAuthorityBinding binding, {
    required bool Function() stillCurrent,
  }) async {
    _requireCurrent(binding, stillCurrent);
    enrollmentReads++;
    return ResearchEnrollmentContext(
      enrollmentId: 'synthetic-composition-enrollment',
      ownerId: binding.ownerId,
      authSubjectId: binding.authSubjectId,
      consentVersion: motivation.consentVersion,
      protocolVersion: motivation.protocolVersion,
      motivationRequirements: motivation.requirements,
      assessmentRequirements: assessment.requirements,
    );
  }

  @override
  Future<ResearchConsentAcknowledgement> decideConsent({
    required ResearchAuthorityBinding binding,
    required ResearchEnrollmentContext enrollment,
    required bool accepted,
    required String requestId,
    required bool Function() stillCurrent,
  }) async {
    _requireCurrent(binding, stillCurrent);
    consentDecisions++;
    if (!accepted) _withdrawn = true;
    return ResearchConsentAcknowledgement(
      enrollmentId: enrollment.enrollmentId,
      ownerId: binding.ownerId,
      version: enrollment.consentVersion,
      requestId: requestId,
      accepted: !_withdrawn,
      receiptId: 'synthetic-consent-receipt',
      revision: _withdrawn ? 2 : 1,
      decidedAtUtc: participationStart.subtract(const Duration(hours: 1)),
      withdrawnAtUtc: _withdrawn ? participationStart : null,
    );
  }

  @override
  Future<StudyUploadReceipt> upload(
    StudyUploadRequest request, {
    required bool Function() stillCurrent,
    required Future<void> Function() revalidateBeforeSubmit,
  }) async {
    _requireCurrent(request.motivationScope.binding, stillCurrent);
    await revalidateBeforeSubmit();
    _requireCurrent(request.motivationScope.binding, stillCurrent);
    uploadWrites++;
    return StudyUploadReceipt(
      uploadId: 'a' * 64,
      receiptId: 'research-upload:${'a' * 64}',
      payloadSha256: request.payloadSha256,
      acceptedAtUtc: participationStart,
    );
  }
}
