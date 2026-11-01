import '../features/research/application/controlled_study_archive_use_cases.dart';
import '../features/research/application/controlled_study_upload_use_cases.dart';
import '../features/research/application/local_study_runtime.dart';
import '../features/research/application/local_research_participation_activation.dart';
import '../features/research/application/research_authority_lifecycle.dart';
import '../features/research/application/research_transport_consent_coordinator.dart';
import '../features/research/application/study_runtime.dart';
import '../features/research/data/drift_study_archive_repository.dart';
import '../features/research/domain/research_transport_contracts.dart';

typedef ResearchTransportFactory =
    Future<ResearchTransportComposition> Function(
      ResearchTransportFactoryContext context,
    );

final class ResearchTransportFactoryContext {
  const ResearchTransportFactoryContext({
    required this.study,
    required this.baseUri,
  });
  final StudyRuntimeContext study;
  final Uri baseUri;
}

final class ResearchTransportComposition {
  ResearchTransportComposition({
    required this.studyRuntime,
    required this.studyArchives,
    required this.studyUploads,
    required this.consent,
    required this.lifecycle,
    required this._disposeResources,
    this.notice,
    this.participationActivation,
  });

  final LocalStudyRuntime studyRuntime;
  final ControlledStudyArchiveUseCases studyArchives;
  final ControlledStudyUploadUseCases studyUploads;
  final ResearchTransportConsentCoordinator consent;
  final ResearchAuthorityLifecycle lifecycle;
  final SuppliedResearchConsentNotice? notice;
  final LocalResearchParticipationActivation? participationActivation;
  final Future<void> Function() _disposeResources;
  Future<void>? _disposal;

  void validate(ResearchTransportFactoryContext context) {
    final archive = studyArchives.repository;
    if (!identical(studyRuntime.context, context.study) ||
        !identical(consent.repository, context.study.consentRepository) ||
        !identical(studyRuntime.consent.repository, consent.repository) ||
        !identical(studyRuntime.consent.remoteDecisions, consent) ||
        studyRuntime.consent.version != consent.version ||
        archive is! DriftStudyArchiveRepository ||
        !identical(archive.study, studyRuntime) ||
        !identical(studyUploads.repository, archive) ||
        !lifecycle.caches.any(
          (cache) => identical(cache, archive.motivationAuthority),
        ) ||
        (participationActivation != null &&
            (!identical(participationActivation!.study, studyRuntime) ||
                !identical(participationActivation!.lifecycle, lifecycle))) ||
        lifecycle.caches.any(
          (cache) =>
              !identical(cache.ownerWrites, context.study.ownerWrites) ||
              !identical(cache.readGate, lifecycle.readGate),
        )) {
      throw ArgumentError(
        'Research transport must share its actual Study authorities',
      );
    }
  }

  Future<void> dispose() => _disposal ??= _close();

  Future<void> _close() async {
    lifecycle.readGate.close();
    try {
      consent.dispose();
    } finally {
      try {
        await lifecycle.dispose();
      } finally {
        await _disposeResources();
      }
    }
  }
}
