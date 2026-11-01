import 'dart:async';

import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:http/http.dart' as http;

import '../features/adventure/domain/adventure_entry.dart';
import '../features/assessment/application/study_assessment.dart';
import '../features/assessment/data/drift_assessment_authority.dart';
import '../features/assessment/data/drift_assessment_cycle_reader.dart';
import '../features/assessment/data/drift_assessment_repository.dart';
import '../features/assessment/domain/assessment_authority.dart';
import '../features/assessment/domain/assessment_instrument_catalog.dart';
import '../features/export/domain/export_contracts.dart';
import '../features/learning/data/drift_learning_repository.dart';
import '../features/research/application/controlled_study_archive_use_cases.dart';
import '../features/research/application/controlled_study_upload_use_cases.dart';
import '../features/research/application/local_research_participation_activation.dart';
import '../features/research/application/local_study_runtime.dart';
import '../features/research/application/research_authority_lifecycle.dart';
import '../features/research/application/research_transport_consent_coordinator.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/data/drift_measurement_opportunity_repository.dart';
import '../features/research/data/drift_motivation_measurement_repository.dart';
import '../features/research/data/drift_motivation_measurement_timing_reader.dart';
import '../features/research/data/drift_study_archive_repository.dart';
import '../features/research/data/http_research_authority_gateway.dart';
import '../features/research/data/local_research_authority_cache.dart';
import '../features/research/data/research_p256_signature_verifier.dart';
import '../features/research/domain/ed25519_research_permit_signature_verifier.dart';
import '../features/research/domain/experiment_assignment.dart';
import '../features/research/domain/experiment_assignment_admission.dart';
import '../features/research/domain/motivation_study_protocol.dart';
import '../features/research/domain/research_authority_snapshot.dart';
import '../features/research/domain/research_operation_authorizer.dart';
import '../features/research/domain/research_runtime_availability.dart';
import '../features/research/domain/research_transport_contracts.dart';
import 'research_transport_composition.dart';

/// Supplied release inputs only. This type does not establish research approval.
final class ResearchTransportConfiguration {
  ResearchTransportConfiguration({
    required this.binding,
    required this.catalog,
    required this.assessmentDefinition,
    required this.assessmentMapping,
    required this.assessmentContent,
    required this.operationSignatures,
    required this.participationSignatures,
    required this.trustedIssuerId,
    required this.trustedIssuerKeyId,
    required this.notice,
    required Set<TodayExperiencePresentation> supportedPresentations,
    required this.participationPermitId,
    this.supportedFormatVersion = 1,
    this.availability = ResearchRuntimeAvailability.disabled,
    this.maximumAcceptedAge = const Duration(minutes: 10),
  }) : supportedPresentations = Set.unmodifiable(supportedPresentations);

  final ExperimentAssignmentAdmissionBinding binding;
  final StudyPresentationCatalog catalog;
  final AssessmentInstrumentDefinition assessmentDefinition;
  final AssessmentAuthorityMapping assessmentMapping;
  final AssessmentFormContentAuthority assessmentContent;
  final Ed25519ResearchPermitSignatureVerifier operationSignatures;
  final ResearchP256SignatureVerifier participationSignatures;
  final String trustedIssuerId;
  final String trustedIssuerKeyId;
  final int supportedFormatVersion;
  final SuppliedResearchConsentNotice notice;
  final Set<TodayExperiencePresentation> supportedPresentations;
  final String? Function(ResearchAuthorityBinding binding)
  participationPermitId;
  final ResearchRuntimeAvailability availability;
  final Duration maximumAcceptedAge;

  void _validate(StudyRuntimeContext context) {
    if (!availability.isEnabled) {
      throw StateError('Research transport is disabled');
    }
    requireResearchCode(trustedIssuerId);
    requireResearchCode(trustedIssuerKeyId);
    final protocol = binding.study;
    final mapping = assessmentMapping;
    final definition = assessmentDefinition;
    AssessmentInstrumentCatalog(entries: [definition]).lookup(
      instrumentId: definition.instrumentId,
      instrumentVersion: definition.instrumentVersion,
      formId: definition.formId,
      formVersion: definition.formVersion,
    );
    if (supportedFormatVersion < 1 ||
        maximumAcceptedAge <= Duration.zero ||
        supportedPresentations.isEmpty ||
        context.buildInfo.version != protocol.appVersion ||
        context.buildInfo.buildId != protocol.buildId ||
        catalog.version != protocol.catalogVersion ||
        notice.version != protocol.consentVersion ||
        notice.protocolVersion != protocol.protocolVersion ||
        mapping.protocolId != protocol.protocolId ||
        mapping.protocolVersion != protocol.protocolVersion ||
        mapping.protocolRevision != binding.protocolRevision ||
        mapping.experimentId != protocol.experimentId ||
        mapping.experimentVersion != protocol.experimentVersion ||
        mapping.instrumentId == protocol.instrument.instrumentId ||
        definition.protocolId != mapping.protocolId ||
        definition.instrumentId != mapping.instrumentId ||
        definition.instrumentVersion != mapping.instrumentVersion ||
        definition.formId != mapping.formId ||
        definition.formVersion != mapping.formVersion ||
        definition.formContentRevision != mapping.formContentRevision ||
        definition.instrumentChecksumSha256 !=
            mapping.instrumentChecksumSha256 ||
        definition.formChecksumSha256 != mapping.formChecksumSha256 ||
        definition.experimentId != mapping.experimentId ||
        definition.experimentVersion != mapping.experimentVersion ||
        definition.contentRevision != mapping.contentRevision) {
      throw ArgumentError('Research transport configuration does not match');
    }
  }
}

/// An owned adapter to the existing registered-account and owner generation.
final class ResearchTransportIdentityPorts {
  const ResearchTransportIdentityPorts({
    required this.currentBinding,
    required this.bindingChanges,
    required this.loadIdToken,
    required this.dispose,
  });
  final ResearchAuthorityBinding? Function() currentBinding;
  final Stream<ResearchAuthorityBinding?> bindingChanges;
  final Future<String?> Function(ResearchAuthorityBinding binding) loadIdToken;
  final Future<void> Function() dispose;
}

final class ConfiguredResearchTransportFactory {
  ConfiguredResearchTransportFactory({
    required this.configuration,
    required this.createIdentity,
    required this.store,
    http.Client Function()? createHttpClient,
    this.initiallyForeground,
    this.monotonicElapsed,
  }) : _createHttpClient = createHttpClient ?? http.Client.new;

  final ResearchTransportConfiguration configuration;
  final Future<ResearchTransportIdentityPorts> Function(
    StudyRuntimeContext context,
  )
  createIdentity;
  final ExportArtifactStore store;
  final http.Client Function() _createHttpClient;
  final bool? initiallyForeground;
  final Duration Function()? monotonicElapsed;

  Future<ResearchTransportComposition> create(
    ResearchTransportFactoryContext context,
  ) async {
    configuration._validate(context.study);
    ResearchTransportIdentityPorts? identity;
    http.Client? client;
    ResearchTransportConsentCoordinator? consent;
    ResearchAuthorityLifecycle? lifecycle;
    ResearchTransportComposition? composition;
    final caches = <LocalResearchAuthorityCache>[];
    Future<void> closeResources() async {
      try {
        client?.close();
      } finally {
        await identity?.dispose();
      }
    }

    try {
      final account = await createIdentity(context.study);
      identity = account;
      if (!account.bindingChanges.isBroadcast) {
        throw ArgumentError(
          'Research identity changes must support both observers',
        );
      }
      final httpClient = _createHttpClient();
      client = httpClient;
      final transport = HttpResearchTransport(
        client: httpClient,
        baseUri: context.baseUri,
        currentBinding: account.currentBinding,
        loadIdToken: account.loadIdToken,
      );
      final config = configuration;
      final protocol = config.binding.study;
      final readGate = ResearchAuthorityReadGate();
      ResearchAuthorityScope? scope({required bool assessment}) {
        final binding = account.currentBinding();
        if (binding == null) return null;
        return ResearchAuthorityScope(
          binding: binding,
          protocolVersion: protocol.protocolVersion,
          consentVersion: protocol.consentVersion,
          requirements: ResearchPermitRequirements(
            supportedFormatVersion: config.supportedFormatVersion,
            trustedIssuerId: config.trustedIssuerId,
            trustedIssuerKeyId: config.trustedIssuerKeyId,
            signatureAlgorithm:
                Ed25519ResearchPermitSignatureVerifier.algorithm,
            assignmentId: experimentAssignmentId(
              ownerId: binding.ownerId,
              experimentId: protocol.experimentId,
              experimentVersion: protocol.experimentVersion,
            ),
            assignmentRevision: config.binding.assignmentRevision,
            protocolId: protocol.protocolId,
            protocolRevision: config.binding.protocolRevision,
            instrumentId: assessment
                ? config.assessmentMapping.instrumentId
                : protocol.instrument.instrumentId,
            instrumentRevision: assessment
                ? config.assessmentMapping.instrumentRevision
                : config.binding.instrumentRevision,
          ),
        );
      }

      LocalResearchAuthorityCache cache({required bool assessment}) {
        final value = LocalResearchAuthorityCache(
          ownerWrites: context.study.ownerWrites,
          currentScope: () => scope(assessment: assessment),
          gateway: transport,
          operationSignatures: config.operationSignatures,
          participationSignatures: config.participationSignatures,
          generateRequestId: context.study.generateId,
          maximumAcceptedAge: config.maximumAcceptedAge,
          readGate: readGate,
          initiallyForeground: initiallyForeground ?? true,
          monotonicElapsed: monotonicElapsed,
        );
        caches.add(value);
        return value;
      }

      final motivationCache = cache(assessment: false);
      final assessmentCache = cache(assessment: true);
      late final ResearchAuthorityLifecycle actualLifecycle;
      final decisions = ResearchTransportConsentCoordinator(
        repository: context.study.consentRepository,
        gateway: transport,
        currentBinding: account.currentBinding,
        bindingChanges: account.bindingChanges,
        invalidateAuthority: () => lifecycle?.invalidate(),
        generateRequestId: context.study.generateId,
        version: protocol.consentVersion,
      );
      consent = decisions;
      actualLifecycle = ResearchAuthorityLifecycle(
        caches: caches,
        readGate: readGate,
        initiallyForeground: initiallyForeground,
        reconcileBeforeRefresh: decisions.reconcileBeforeRefresh,
        onUnprovenInterval: decisions.retirePending,
        invalidations: [
          account.bindingChanges,
          context.study.database.tableUpdates(
            TableUpdateQuery.onTable(context.study.database.localOwners),
          ),
          context.study.database.tableUpdates(
            TableUpdateQuery.onTable(context.study.database.runtimeFlags),
          ),
          context.study.database.tableUpdates(
            TableUpdateQuery.onTable(context.study.database.researchConsents),
          ),
        ],
      );
      lifecycle = actualLifecycle;
      final authorities = StudyLocalAuthorities(
        binding: config.binding,
        permits: motivationCache,
        states: motivationCache,
        operationSignatures: config.operationSignatures,
        participationDocuments: motivationCache,
        participationSignatures: config.participationSignatures,
        receipts: motivationCache,
        trustedTime: motivationCache,
        supportedFormatVersion: config.supportedFormatVersion,
        trustedIssuerId: config.trustedIssuerId,
        trustedIssuerKeyId: config.trustedIssuerKeyId,
        availability: config.availability,
        supportedPresentations: config.supportedPresentations,
      );
      ({
        ResearchAuthorityBinding binding,
        String permitId,
        StudyAssessment assessment,
      })?
      previous;
      late final LocalStudyRuntime runtime;
      runtime = LocalStudyRuntime(
        context: context.study,
        authorities: authorities,
        catalog: config.catalog,
        remoteConsentDecisions: decisions,
        assessmentFactory: () {
          final binding = account.currentBinding();
          if (binding == null) return null;
          final permitId = config.participationPermitId(binding);
          if (permitId == null) return null;
          requireResearchCode(permitId);
          if (previous?.binding == binding && previous?.permitId == permitId) {
            return previous!.assessment;
          }
          final learning = context.study.getLearning().repository;
          if (learning is! DriftLearningRepository) return null;
          final measurements =
              runtime.measurementsFor(binding.ownerId)
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
          final writer = DriftAssessmentRepository(
            context.study.database,
            authority: DriftAssessmentAuthority(
              cache: assessmentCache,
              mapping: config.assessmentMapping,
            ),
            cycleReader: reader,
            catalog: AssessmentInstrumentCatalog(
              entries: [config.assessmentDefinition],
            ),
            contentAuthority: config.assessmentContent,
            buildInfo: context.study.buildInfo,
            participationPermitId: permitId,
          );
          final value = StudyAssessment(
            repository: writer,
            definition: config.assessmentDefinition,
            mapping: config.assessmentMapping,
            contentAuthority: config.assessmentContent,
            cycleReader: reader,
            trustedTime: assessmentCache,
          );
          previous = (binding: binding, permitId: permitId, assessment: value);
          return value;
        },
      );
      final archive = DriftStudyArchiveRepository(
        study: runtime,
        motivationAuthority: motivationCache,
      );
      composition = ResearchTransportComposition(
        studyRuntime: runtime,
        studyArchives: ControlledStudyArchiveUseCases(
          repository: archive,
          store: store,
        ),
        studyUploads: ControlledStudyUploadUseCases(
          repository: archive,
          gateway: transport,
        ),
        consent: decisions,
        lifecycle: actualLifecycle,
        notice: config.notice,
        participationActivation: LocalResearchParticipationActivation(
          study: runtime,
          lifecycle: actualLifecycle,
          participationPermitId: config.participationPermitId,
        ),
        disposeResources: closeResources,
      );
      composition.validate(context);
      return composition;
    } on Object {
      if (composition != null) {
        await composition.dispose();
      } else {
        try {
          consent?.dispose();
        } finally {
          try {
            if (lifecycle != null) {
              await lifecycle.dispose();
            } else {
              for (final cache in caches) {
                cache.dispose();
              }
            }
          } finally {
            await closeResources();
          }
        }
      }
      rethrow;
    }
  }
}
