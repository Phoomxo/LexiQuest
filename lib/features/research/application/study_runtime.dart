import '../../../data/local/app_database.dart' show AppDatabase;
import '../../../runtime/app_build_info.dart';
import '../../assessment/application/study_assessment.dart';
import '../../assessment/domain/assessment_models.dart';
import '../../adventure/domain/adventure_entry.dart';
import '../../consent/application/research_consent_use_cases.dart';
import '../../consent/data/drift_research_consent_repository.dart';
import '../../identity/data/drift_owner_write_coordinator.dart';
import '../../identity/domain/local_owner_repository.dart';
import '../../learning/application/learning_use_cases.dart';
import '../../learning/data/learning_session_lifecycle_observer.dart';
import '../../learning/domain/accepted_quiz_plan.dart';
import '../../learning/domain/learning_models.dart';
import '../domain/measurement_opportunity.dart';
import '../domain/motivation_measurement.dart';
import '../domain/motivation_measurement_repository.dart';
import '../domain/motivation_study_protocol.dart';

typedef StudyRuntimeFactory =
    StudyRuntime Function(StudyRuntimeContext context);

/// The learning getter is used only after the composition factory returns.
final class StudyRuntimeContext {
  const StudyRuntimeContext({
    required this.database,
    required this.owners,
    required this.ownerWrites,
    required this.consentRepository,
    required this.generateId,
    required this.nowUtc,
    required this.buildInfo,
    required this.getLearning,
  });

  final AppDatabase database;
  final LocalOwnerRepository owners;
  final DriftOwnerWriteCoordinator ownerWrites;
  final DriftResearchConsentRepository consentRepository;
  final LearningIdGenerator generateId;
  final LearningUtcNow nowUtc;
  final AppBuildInfo buildInfo;
  final LearningUseCases Function() getLearning;
}

/// Supplied treatment copy and selection, never generated study authority.
final class StudyPresentationCatalog {
  StudyPresentationCatalog({
    required this.version,
    required this.missionId,
    required Map<String, String> titles,
    required Map<String, String> descriptions,
    required this.configuration,
  }) : titles = Map.unmodifiable(titles),
       descriptions = Map.unmodifiable(descriptions) {
    requireResearchCode(version);
    requireResearchCode(missionId);
    for (final translations in [this.titles, this.descriptions]) {
      if (!translations.keys.toSet().containsAll({'th', 'en'}) ||
          translations.values.any(
            (text) => text.trim().isEmpty || text.length > 2000,
          )) {
        throw const FormatException(
          'Study copy requires bounded Thai and English text',
        );
      }
    }
  }

  final String version;
  final String missionId;
  final Map<String, String> titles;
  final Map<String, String> descriptions;
  final QuizConfiguration configuration;

  String title(String languageCode) => titles[languageCode] ?? titles['en']!;
  String description(String languageCode) =>
      descriptions[languageCode] ?? descriptions['en']!;
}

enum StudyPhase {
  unavailable,
  baseline,
  ready,
  activeIndex,
  post,
  completed,
  stopped,
}

/// A display snapshot. Every command rechecks current authority and owner.
final class StudyView {
  const StudyView({
    required this.ownerId,
    required this.catalog,
    required this.phase,
    this.reason,
    this.run,
    this.opportunity,
    this.index,
    this.evaluatedAtUtc,
    this.promptExpiresAtUtc,
    this.assessment,
    this.assessmentCommand,
    this.hasCompletedAssessmentPair = false,
  });

  final String ownerId;
  final StudyPresentationCatalog catalog;
  final StudyPhase phase;
  final ResearchCaptureReason? reason;
  final MotivationMeasurementRun? run;
  final MeasurementOpportunity? opportunity;
  final ConfiguredQuizState? index;
  final DateTime? evaluatedAtUtc;
  final DateTime? promptExpiresAtUtc;
  final StudyAssessment? assessment;
  final AssessmentStartCommand? assessmentCommand;
  final bool hasCompletedAssessmentPair;

  bool get canStart =>
      phase == StudyPhase.ready &&
      opportunity?.presentation != null &&
      opportunity?.pendingPresentationChange == null &&
      index == null;
}

abstract interface class StudyRuntime {
  StudyPresentationCatalog get catalog;
  LearningSessionLifecycleObserver get lifecycleObserver;
  LearningUseCases get learning;
  ResearchConsentUseCases get consent;
  MotivationMeasurementRepository measurementsFor(String ownerId);

  /// Does not create an owner, consent, assignment, permit, run or opportunity.
  Future<StudyView> load(String ownerId);
  Future<StudyView> begin(String ownerId);
  Future<StudyView> openPresentation(
    String ownerId, {
    required String entryAttemptId,
    required bool Function() stillCurrent,
  });
  void markPresentationMayRender(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
  });
  void invalidatePresentationOpening(
    String ownerId, {
    required String entryAttemptId,
  });
  Future<StudyView> recordPresented(
    String ownerId,
    String opportunityId, {
    required String entryAttemptId,
    required bool Function() stillVisible,
  });
  Future<StudyView> preparePresentationChange(
    String ownerId,
    String opportunityId, {
    required String attemptId,
    required int expectedRevision,
    required TodayExperiencePresentation target,
    required bool Function() stillCurrent,
  });
  void markPresentationChangeMayRender(
    String ownerId,
    String opportunityId, {
    required String attemptId,
  });
  void invalidatePresentationChange(
    String ownerId,
    String opportunityId, {
    required String attemptId,
  });
  Future<StudyView> recordPresentationChanged(
    String ownerId,
    String opportunityId, {
    required String attemptId,
    required bool Function() stillVisible,
  });
  Future<ConfiguredQuizState> startIndex(
    String ownerId,
    String opportunityId, {
    required bool Function() stillVisible,
  });
  Future<ConfiguredQuizState> resumeIndex(String ownerId);
}
