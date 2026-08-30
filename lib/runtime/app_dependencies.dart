import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/assessment/application/assessment_use_cases.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/export/application/export_use_cases.dart';
import '../features/goals/application/learning_goal_use_cases.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/contrastive_feedback_use_cases.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/learning_side_effect_reconciler.dart';
import '../features/learning/application/lesson_mode_registry.dart';
import '../features/learning/application/session_configuration_policy.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/domain/evidence_policy_rollout.dart';
import '../features/learning/domain/session_configuration.dart';
import '../features/learning_packs/application/learning_pack_use_cases.dart';
import '../features/learning_packs/domain/content_manifest.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/preferences/application/learner_preferences_use_cases.dart';
import '../features/quest/application/quest_use_cases.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/research/application/assigned_learning_event_context_provider.dart';
import '../features/research/application/experiment_assignment_use_cases.dart';
import '../features/review/domain/content_quality_report.dart';
import '../features/review/domain/content_quality_report_repository.dart';
import '../features/review/domain/learner_intent.dart';
import '../features/review/domain/learner_intent_repository.dart';
import '../features/reminders/application/study_reminder_use_cases.dart';
import '../features/sync/application/sync_engine.dart';
import '../features/sync/application/sync_trigger.dart';
import '../features/time_tracking/application/active_learning_time_controller.dart';
import '../features/time_tracking/application/focus_timer_rollout.dart';
import '../features/time_tracking/application/learning_time_capture_rollout.dart';
import '../features/time_tracking/domain/learning_time_repository.dart';
import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import '../navigation/app_routes.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_runtime_status.dart';
import 'registries/consent_registry.dart';
import 'registries/entitlement_registry.dart';
import 'registries/experiment_registry.dart';
import 'registries/feature_registry.dart';
import 'runtime_feature_override_store.dart';

final class AppDependencies {
  AppDependencies({
    required this.initialRoute,
    required this.runtimeStatus,
    required this.config,
    required this.guestSessionService,
    required this.quest,
    this.buildInfo = const AppBuildInfo.fromEnvironment(),
    this.features = const BuildFeatureRegistry.fieldDefaults(),
    this.featureControls,
    required this.experiments,
    required this.consents,
    required this.experimentAssignments,
    required this.assignedLearningEventContext,
    required this.evidencePolicyRolloutModeProvider,
    this.entitlements = const NoOpEntitlementRegistry(),
    this.database,
    this.localOwners,
    this.upgradeGuestOwner,
    this.syncEngine,
    this.syncTrigger,
    this.learning,
    this.lessonModes,
    this.createLessonController,
    this.sessionConfigurationProtocols,
    this.sessionConfigurations,
    this.learningTime,
    this.learningTimeCaptureRollout =
        const LearningTimeCaptureRollout.implementedOff(),
    this.focusTimerRollout = const FocusTimerRollout.implementedOff(),
    this.createActiveLearningTimeController,
    this.assessment,
    this.currentActivityEvidence,
    this.contrastiveFeedback,
    this.learningReconciliation,
    this.contentManifests,
    this.studyPlanning,
    this.learningGoals,
    this.learnerPreferences,
    this.studyReminders,
    this.progress,
    this.rewards,
    this.learnerIntents,
    this.bookmarkLearningItem,
    this.contentQualityReports,
    this.reportContent,
    this.vocabulary,
    this.vocabularyImporter,
    this.deviceModels,
    this.account,
    this.localDataEraser,
    this.researchConsent,
    this.exports,
    this.aiTutor,
    this.objectScanner,
    this.speechPractice,
    this.voice,
    this.streak,
    this.associativeLearning,
    this.disposeResources,
  });

  final AppRoute initialRoute;
  final AppRuntimeStatus runtimeStatus;
  final AppConfig? config;
  final GuestSessionService guestSessionService;
  final AppBuildInfo buildInfo;
  // V2 registry is the sole production feature authority.
  final FeatureRegistry features;
  final RuntimeFeatureControls? featureControls;
  final ExperimentRegistry experiments;
  final ConsentRegistry consents;
  final ExperimentAssignmentUseCases experimentAssignments;
  final AssignedLearningEventContextProvider assignedLearningEventContext;
  final EvidencePolicyRolloutModeProvider evidencePolicyRolloutModeProvider;
  final EntitlementRegistry entitlements;
  final AppDatabase? database;
  final LocalOwnerRepository? localOwners;
  final UpgradeGuestOwner? upgradeGuestOwner;
  final SyncEngine? syncEngine;
  final SyncTrigger? syncTrigger;
  final LearningUseCases? learning;
  final LessonModeRegistry? lessonModes;
  final UnifiedLessonControllerFactory? createLessonController;
  final SessionConfigurationProtocolProvider? sessionConfigurationProtocols;
  final SessionConfigurationStore? sessionConfigurations;
  final LearningTimeRepository? learningTime;
  final LearningTimeCaptureRollout learningTimeCaptureRollout;
  final FocusTimerRollout focusTimerRollout;
  final ActiveLearningTimeControllerFactory? createActiveLearningTimeController;
  final AssessmentUseCases? assessment;
  final CurrentActivityEvidenceAdapter? currentActivityEvidence;
  final ContrastiveFeedbackUseCases? contrastiveFeedback;
  final LearningReconciliationScheduler? learningReconciliation;
  final ContentManifestRepository? contentManifests;
  final StudyPlanningUseCases? studyPlanning;
  final LearningGoalUseCases? learningGoals;
  final LearnerPreferencesUseCases? learnerPreferences;
  final StudyReminderUseCases? studyReminders;
  final ProgressUseCases? progress;
  final RewardUseCases? rewards;
  final LearnerIntentRepository? learnerIntents;
  final BookmarkLearningItemAction? bookmarkLearningItem;
  final ContentQualityReportRepository? contentQualityReports;
  final ReportContentAction? reportContent;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? vocabularyImporter;
  final DeviceModelUseCases? deviceModels;
  final AccountUseCases? account;
  final LocalDataEraser? localDataEraser;
  final ResearchConsentUseCases? researchConsent;
  final ExportUseCases? exports;
  final AiTutorController? aiTutor;
  final ObjectScannerController? objectScanner;
  final SpeechPracticeUseCases? speechPractice;
  final VoiceUseCases? voice;

  /// Durable V2 Quest projection. [Feature.questV2] gates UI invocation only.
  final QuestUseCases quest;

  /// Streak tracking — wired at composition root.
  final StreakUseCases? streak;

  /// Associative learning persistence port. Null means unavailable.
  final AssociativeLearningPort? associativeLearning;

  final Future<void> Function()? disposeResources;
  Future<void>? _disposeFuture;

  /// Reports whether the canonical composition root can satisfy one runtime
  /// delivery. Unknown and not-yet-composed broad parents remain unavailable
  /// even if a registry override makes their flag visible.
  bool hasComposedDependencyFor(Feature feature) => switch (feature) {
    Feature.vocabulary => vocabulary != null,
    Feature.quiz =>
      learning != null &&
          identical(currentActivityEvidence?.learning, learning),
    Feature.srs || Feature.ghostDuel => learning != null,
    Feature.reading =>
      vocabulary != null && learning != null && associativeLearning != null,
    Feature.mastery ||
    Feature.weakness ||
    Feature.achievements => progress != null,
    Feature.shop => rewards != null,
    Feature.objectScanner => objectScanner != null,
    Feature.speechPractice => speechPractice != null,
    Feature.aiTutor => aiTutor != null,
    Feature.export => exports != null,
    Feature.shadowRewardV2 => false,
    Feature.questV2 => true,
    Feature.studyPlanning => studyPlanning != null,
    Feature.researchAssessment => assessment != null,
    Feature.dailyContinuity => false,
    Feature.offlineContent => false,
  };

  Future<void> dispose() {
    return _disposeFuture ??= disposeResources?.call() ?? Future<void>.value();
  }

  @override
  String toString() => 'AppDependencies';
}

final class AppDependenciesScope extends InheritedWidget {
  const AppDependenciesScope({
    super.key,
    required this.dependencies,
    required super.child,
  });

  final AppDependencies dependencies;

  static AppDependencies? maybeOf(BuildContext context) {
    return context
        .dependOnInheritedWidgetOfExactType<AppDependenciesScope>()
        ?.dependencies;
  }

  static AppDependencies of(BuildContext context) {
    final dependencies = maybeOf(context);
    assert(
      dependencies != null,
      'AppDependenciesScope was not found in the widget tree.',
    );
    return dependencies!;
  }

  @override
  bool updateShouldNotify(AppDependenciesScope oldWidget) {
    return !identical(dependencies, oldWidget.dependencies);
  }
}
