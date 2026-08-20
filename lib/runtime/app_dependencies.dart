import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/export/application/export_use_cases.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/learning_side_effect_reconciler.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/quest/application/quest_use_cases.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/sync/application/sync_engine.dart';
import '../features/sync/application/sync_trigger.dart';
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
    this.experiments = const NoOpExperimentRegistry(),
    this.consents = const NoOpConsentRegistry(),
    this.entitlements = const NoOpEntitlementRegistry(),
    this.database,
    this.localOwners,
    this.upgradeGuestOwner,
    this.syncEngine,
    this.syncTrigger,
    this.learning,
    this.currentActivityEvidence,
    this.learningReconciliation,
    this.progress,
    this.rewards,
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
  final EntitlementRegistry entitlements;
  final AppDatabase? database;
  final LocalOwnerRepository? localOwners;
  final UpgradeGuestOwner? upgradeGuestOwner;
  final SyncEngine? syncEngine;
  final SyncTrigger? syncTrigger;
  final LearningUseCases? learning;
  final CurrentActivityEvidenceAdapter? currentActivityEvidence;
  final LearningReconciliationScheduler? learningReconciliation;
  final ProgressUseCases? progress;
  final RewardUseCases? rewards;
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
