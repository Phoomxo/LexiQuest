import 'package:flutter/widgets.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/export/application/export_use_cases.dart';
import '../features/gemini/domain/gemini_contracts.dart';
import '../features/identity/domain/local_owner_repository.dart';
import '../features/learning/application/learning_layer_adapter.dart';
import '../features/learning/application/learning_use_cases.dart';
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
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_runtime_status.dart';
import 'field_feature_registry.dart';
import 'registries/consent_registry.dart';
import 'registries/entitlement_registry.dart';
import 'registries/experiment_registry.dart';
import 'registries/feature_registry.dart';

final class AppDependencies {
  AppDependencies({
    required this.runtimeStatus,
    required this.config,
    required this.guestSessionService,
    this.buildInfo = const AppBuildInfo.fromEnvironment(),
    this.fieldFeatures = const BuildFieldFeatureRegistry.fieldDefaults(),
    this.features = const BuildFeatureRegistry.fieldDefaults(),
    this.experiments = const NoOpExperimentRegistry(),
    this.consents = const NoOpConsentRegistry(),
    this.entitlements = const NoOpEntitlementRegistry(),
    this.database,
    this.localOwners,
    this.upgradeGuestOwner,
    this.syncEngine,
    this.syncTrigger,
    this.learning,
    this.progress,
    this.rewards,
    this.vocabulary,
    this.vocabularyImporter,
    this.deviceModels,
    this.account,
    this.researchConsent,
    this.exports,
    this.geminiTutor,
    this.objectScanner,
    this.speechPractice,
    this.voice,
    this.quest,
    this.streak,
    this.associativeLearning,
    this.disposeResources,
  });

  final AppRuntimeStatus runtimeStatus;
  final AppConfig? config;
  final GuestSessionService guestSessionService;
  final AppBuildInfo buildInfo;
  final FieldFeatureRegistry fieldFeatures;
  // V2 registries — use these for new code; FieldFeatureRegistry is legacy.
  final FeatureRegistry features;
  final ExperimentRegistry experiments;
  final ConsentRegistry consents;
  final EntitlementRegistry entitlements;
  final AppDatabase? database;
  final LocalOwnerRepository? localOwners;
  final UpgradeGuestOwner? upgradeGuestOwner;
  final SyncEngine? syncEngine;
  final SyncTrigger? syncTrigger;
  final LearningUseCases? learning;
  final ProgressUseCases? progress;
  final RewardUseCases? rewards;
  final VocabularyUseCases? vocabulary;
  final ImportVocabulary? vocabularyImporter;
  final DeviceModelUseCases? deviceModels;
  final AccountUseCases? account;
  final ResearchConsentUseCases? researchConsent;
  final ExportUseCases? exports;
  final GeminiTutorController? geminiTutor;
  final ObjectScannerController? objectScanner;
  final SpeechPracticeUseCases? speechPractice;
  final VoiceUseCases? voice;

  /// V2 Quest pipeline — wired when [Feature.questV2] is enabled.
  /// Null when the feature flag is off (hidden state).
  final QuestUseCases? quest;

  /// Streak tracking — wired at composition root.
  final StreakUseCases? streak;

  /// Associative learning persistence port.
  /// Falls back to [InMemoryAssociativeLearningAdapter] when null.
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
