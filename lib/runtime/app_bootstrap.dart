import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../firebase_options.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/account/data/firebase_account_gateway.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/ai_tutor/application/ai_tutor_use_cases.dart';
import '../features/ai_tutor/data/ai_tutor_settings_store.dart';
import '../features/ai_tutor/data/drift_ai_usage_repository.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/consent/data/drift_research_consent_repository.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/device_model/application/model_download_manager.dart';
import '../features/device_model/data/drift_model_download_repository.dart';
import '../features/device_model/data/http_model_byte_source.dart';
import '../features/device_model/data/litert_image_classifier.dart';
import '../features/device_model/domain/model_manifest.dart';
import '../features/export/application/export_use_cases.dart';
import '../features/export/data/drift_export_reader.dart';
import '../features/export/data/file_selector_export_store.dart';
import '../features/identity/data/drift_local_owner_repository.dart';
import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/identity/data/drift_owner_upgrade_repository.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/learning_side_effect_reconciler.dart';
import '../features/learning/data/drift_associative_learning_adapter.dart';
import '../features/learning/data/drift_learning_repository.dart';
import '../features/media_practice/application/image_preprocessor.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/data/plugin_camera_gateway.dart';
import '../features/media_practice/data/plugin_speech_recognition_gateway.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/motivation/data/drift_streak_repository.dart';
import '../features/quest/application/quest_catalog_provider.dart';
import '../features/quest/application/quest_use_cases.dart';
import '../features/quest/data/drift_quest_repository.dart';
import '../features/rewards/application/shadow_reward_orchestrator.dart';
import '../features/events/application/event_v1_to_v2_adapter.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/data/drift_progress_queries.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/data/drift_reward_repository.dart';
import '../features/session/data/shared_preferences_app_entry_state_store.dart';
import '../features/session/domain/app_entry_state.dart';
import '../features/sync/application/sync_backoff.dart';
import '../features/sync/application/sync_engine.dart';
import '../features/sync/application/sync_mutex.dart';
import '../features/sync/application/sync_trigger.dart';
import '../features/sync/data/drift_cloud_policy_cache.dart';
import '../features/sync/data/drift_owner_operation_gate.dart';
import '../features/sync/data/drift_sync_store.dart';
import '../features/sync/data/firestore_sync_gateway.dart';
import '../features/sync/domain/sync_gateway.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/drift_vocabulary_import_repository.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_dependencies.dart';
import 'download_counter.dart';
import 'field_feature_registry.dart';
import 'app_runtime_status.dart';
import 'app_start_route_resolver.dart';
import 'registries/feature_registry.dart';
import 'runtime_feature_override_store.dart';
import 'resource_disposer_stack.dart';
import 'supabase_client_config.dart';

typedef RuntimeInitializer = Future<void> Function();
typedef AppConfigLoader = AppConfig Function();
typedef AppDatabaseFactory = AppDatabase Function();
typedef SyncGatewayFactory = SyncGateway Function();
typedef AccountGatewayFactory = AccountGateway Function();
typedef AppEntryStateStoreFactory = Future<AppEntryStateStore> Function();

// Public client identifiers, not server credentials. The Supabase URL keeps a
// public default, but the publishable key must be supplied per build.
const _productionSupabaseUrl = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_URL',
  defaultValue: 'https://anyiuoqnuimtjlbjhwuf.supabase.co',
);
const _productionSupabasePublishableKey = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_PUBLISHABLE_KEY',
);
const _productionCloudSyncEnabled = bool.fromEnvironment(
  'LEXIQUEST_CLOUD_SYNC_ENABLED',
  defaultValue: true,
);
const _productionAppCheckDebug = bool.fromEnvironment(
  'LEXIQUEST_APP_CHECK_DEBUG',
  defaultValue: !kReleaseMode,
);

/// Selects the Android App Check provider based on the `debugMode` flag.
///
/// Kept as a pure top-level function (no Firebase state) so the provider
/// selection can be unit-tested without initializing Firebase. In production
/// the flag comes from the `LEXIQUEST_APP_CHECK_DEBUG` dart-define (default
/// `!kReleaseMode`): debug builds use [AndroidDebugProvider], release builds
/// use [AndroidPlayIntegrityProvider].
AndroidAppCheckProvider resolveAndroidAppCheckProvider({
  required bool debugMode,
}) {
  return debugMode
      ? const AndroidDebugProvider()
      : const AndroidPlayIntegrityProvider();
}

bool _productionSupabaseInitialized = false;

Future<void> _initializeFirebaseProduction() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  await FirebaseAppCheck.instance.activate(
    providerAndroid: resolveAndroidAppCheckProvider(
      debugMode: _productionAppCheckDebug,
    ),
  );
}

// ignore: unused_element
Future<void> _initializeSupabaseProduction() async {
  if (_productionSupabaseInitialized) return;
  final publishableKey = requireSupabasePublishableKey(
    _productionSupabasePublishableKey,
  );
  await Supabase.initialize(
    url: _productionSupabaseUrl,
    publishableKey: publishableKey,
  );
  _productionSupabaseInitialized = true;
}

/// P1.4: Supabase is off the critical path. This no-op initializer
/// replaces [_initializeSupabaseProduction] so the app starts without
/// requiring a Supabase project to be active.
Future<void> _initializeSupabaseOptional() async {
  // Intentionally empty — Supabase is plumbed but unused.
  // If shop/wallpaper images need to return to Supabase Storage,
  // swap this back to _initializeSupabaseProduction.
}

Future<AppEntryStateStore> createProductionEntryStateStore() async {
  final preferences = await SharedPreferences.getInstance();
  return SharedPreferencesAppEntryStateStore(preferences);
}

final class AppBootstrap {
  AppBootstrap({
    required this.initializeFirebase,
    required this.initializeSupabase,
    required this.loadConfig,
    required this.guestSessionService,
    required this.createDatabase,
    required this.createEntryStateStore,
    this.bindGuestOwnership = false,
    this.syncGatewayFactory,
    this.accountGatewayFactory,
    this.cloudSyncEnabled = true,
  });

  factory AppBootstrap.production() {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      initializeSupabase: _initializeSupabaseOptional,
      loadConfig: AppConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
      createDatabase: AppDatabase.production,
      createEntryStateStore: createProductionEntryStateStore,
      bindGuestOwnership: true,
      syncGatewayFactory: () => FirestoreSyncGateway(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
      ),
      accountGatewayFactory: () =>
          FirebaseAccountGateway(FirebaseAuth.instance),
      cloudSyncEnabled: _productionCloudSyncEnabled,
    );
  }

  final RuntimeInitializer initializeFirebase;
  final RuntimeInitializer initializeSupabase;
  final AppConfigLoader loadConfig;
  final GuestSessionService guestSessionService;
  final AppDatabaseFactory createDatabase;
  final AppEntryStateStoreFactory createEntryStateStore;
  final bool bindGuestOwnership;
  final SyncGatewayFactory? syncGatewayFactory;
  final AccountGatewayFactory? accountGatewayFactory;
  final bool cloudSyncEnabled;
  Future<AppDependencies>? _initialization;

  Future<AppDependencies> initialize() {
    return _initialization ??= _initializeOnce();
  }

  Future<AppDependencies> _initializeOnce() async {
    final resources = ResourceDisposerStack();
    try {
      return await _compose(resources);
    } catch (error, stackTrace) {
      await resources.disposeAfterFailure();
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  Future<AppDependencies> _compose(ResourceDisposerStack resources) async {
    final entryState = await _createEntryState();
    final database = createDatabase();
    resources.own(database.close);
    await database.customSelect('SELECT 1').getSingle();
    final idGenerator = const Uuid();
    final ownerOperationGate = DriftOwnerOperationGate(database);
    final localOwners = DriftLocalOwnerRepository(
      database,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      ownerOperationGate: ownerOperationGate,
      generateOwnerOperationToken: idGenerator.v4,
    );
    await localOwners.getOrCreateActiveOwner();
    Future<String> activeOwnerId() async =>
        (await localOwners.getOrCreateActiveOwner()).id;
    final aiTutorSettings = SecureAiTutorSettingsStore.production(
      activeOwnerId: activeOwnerId,
    );
    final localDataEraser = LocalDataDeletion(
      database,
      deleteOwnerSecrets: aiTutorSettings.deleteCredentialForOwner,
    );
    final ownerUpgrades = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.now().toUtc(),
      generateConflictId: idGenerator.v4,
      generateOwnerId: idGenerator.v4,
      generateOwnerOperationToken: idGenerator.v4,
      deleteOwnerSecrets: aiTutorSettings.deleteCredentialForOwner,
      ownerOperationGate: ownerOperationGate,
    );
    LearningReconciliationScheduler? ownerLearningReconciliation;
    final upgradeGuestOwner = UpgradeGuestOwner(
      ownerUpgrades,
      coordinate: (sourceOwnerId, operation) {
        final scheduler = ownerLearningReconciliation;
        return scheduler == null
            ? operation()
            : scheduler.coordinateOwnerChange(
                sourceOwnerId,
                operation,
                (result) => result.targetOwnerId,
              );
      },
    );
    var firebase = await _availability(initializeFirebase);
    final createAccountGateway = accountGatewayFactory;
    AccountUseCases? account;
    if (firebase == RuntimeAvailability.ready && createAccountGateway != null) {
      final candidate = AccountUseCases(
        gateway: createAccountGateway(),
        owners: localOwners,
        upgradeGuestOwner: upgradeGuestOwner,
        entryState: entryState,
      );
      try {
        await candidate.reconcileLocalOwner();
        account = candidate;
      } catch (_) {
        firebase = RuntimeAvailability.unavailable;
      }
    }
    final supabase = await _availability(initializeSupabase);
    final config = _loadConfig();
    SyncEngine? syncEngine;
    SyncTrigger? syncTrigger;
    final createGateway = syncGatewayFactory;
    if (firebase == RuntimeAvailability.ready && createGateway != null) {
      final gateway = createGateway();
      final policy = CloudSyncPolicyProvider(
        buildEnabled: cloudSyncEnabled,
        cache: DriftCloudPolicyCache(database),
        gateway: gateway,
        nowUtc: () => DateTime.now().toUtc(),
      );
      syncEngine = SyncEngine(
        owners: localOwners,
        store: DriftSyncStore(database),
        gateway: gateway,
        policyProvider: policy.call,
        ownerGate: ownerOperationGate,
        mutex: SyncMutex(),
        backoff: const SyncBackoff(),
        nowUtc: () => DateTime.now().toUtc(),
        generateLeaseToken: idGenerator.v4,
      );
      syncTrigger = SyncTrigger(syncEngine.run);
      resources.own(syncTrigger.dispose);
    }
    void notifyLocalMutation() {
      final trigger = syncTrigger;
      if (trigger != null) {
        trigger.requestDetached(SyncTriggerReason.localMutation);
      }
    }

    GuestSessionService exposedGuestSession = guestSessionService;
    if (bindGuestOwnership) {
      final ownerBindingGuestSession = OwnerBindingGuestSessionService(
        delegate: guestSessionService,
        localOwners: localOwners,
        upgradeGuestOwner: upgradeGuestOwner,
        entryState: entryState,
        onOwnerBound: () {
          final trigger = syncTrigger;
          if (trigger != null) {
            trigger.requestDetached(SyncTriggerReason.accountBinding);
          }
        },
      );
      resources.own(ownerBindingGuestSession.dispose);
      exposedGuestSession = ownerBindingGuestSession;
    }
    final vocabulary = VocabularyUseCases(
      owners: localOwners,
      vocabulary: DriftVocabularyRepository(database),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      onLocalMutation: notifyLocalMutation,
    );
    final vocabularyImporter = ImportVocabulary(
      owners: localOwners,
      repository: DriftVocabularyImportRepository(database),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      onLocalMutation: notifyLocalMutation,
    );
    final progress = ProgressUseCases(
      owners: localOwners,
      queries: DriftProgressQueries(database),
      nowUtc: () => DateTime.now().toUtc(),
    );
    final researchConsent = ResearchConsentUseCases(
      owners: localOwners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.now().toUtc(),
    );
    final rewardRepository = DriftRewardRepository(database);
    final rewards = RewardUseCases(
      owners: localOwners,
      repository: rewardRepository,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      onLocalMutation: notifyLocalMutation,
    );

    // ── V2 Quest pipeline (must precede learning wiring) ─────────────────
    final questRepository = DriftQuestRepository(database);
    final buildInfo = const AppBuildInfo.fromEnvironment();
    final shadowOrchestrator = ShadowRewardOrchestrator(
      logger: _NoopShadowLogger(),
      canGrant: (_, _) async => true,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
    );
    final quest = QuestUseCases(
      repository: questRepository,
      owners: localOwners,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      timezoneId: DateTime.now().timeZoneName,
      shadowOrchestrator: shadowOrchestrator,
      rewardSink:
          ({
            required ownerId,
            required idempotencyKey,
            required xpAmount,
            rewardItemId,
          }) => rewardRepository.grantQuestXp(
            ownerId: ownerId,
            idempotencyKey: idempotencyKey,
            xpAmount: xpAmount,
          ),
    );

    // ── Streak tracking (must precede learning wiring) ───────────────────
    final streak = StreakUseCases(
      repository: DriftStreakRepository(database),
      owners: localOwners,
      nowUtc: () => DateTime.now().toUtc(),
      timezoneId: DateTime.now().timeZoneName,
    );

    // ── Event adapter for V1→V2 event conversion ──────────────────────────
    final eventAdapter = EventV1ToV2Adapter(
      appVersion: buildInfo.version,
      buildId: buildInfo.buildId,
    );

    // Seed before scheduling historical replay so pre-assignment evidence is
    // deterministically skipped instead of racing a newly created quest.
    try {
      await quest.startQuest(QuestCatalogProvider.dailyCorrectAnswers);
    } catch (_) {
      // Best-effort; catalog is also seeded on first quest start.
    }

    final learningReconciler = LearningSideEffectReconciler(
      database,
      questSink: (event) async {
        final projection = await quest.projectEvent(
          event,
          QuestCatalogProvider.allQuests,
        );
        final payload = quest.projectionPayload(
          projection,
          QuestCatalogProvider.allQuests,
        );
        return projection.eligible
            ? LearningProjectionResult.applied(payload: payload)
            : LearningProjectionResult.notApplicable(payload: payload);
      },
      streakSink: (event) async {
        await streak.recordLearningDayForOwner(
          ownerId: event.ownerIdentity,
          occurredAtUtc: event.occurredAtUtc,
        );
        return const LearningProjectionResult.applied();
      },
      rewardSink: (event, questResult) async {
        final applied = await quest.reconcileReward(event, questResult);
        return applied
            ? const LearningProjectionResult.applied()
            : const LearningProjectionResult.notApplicable();
      },
    );
    final learningReconciliation = LearningReconciliationScheduler(
      learningReconciler,
    );
    ownerLearningReconciliation = learningReconciliation;
    resources.own(learningReconciliation.dispose);
    learningReconciliation.request(
      (await localOwners.getOrCreateActiveOwner()).id,
    );

    final learning = LearningUseCases(
      owners: localOwners,
      repository: DriftLearningRepository(database),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      buildInfo: const AppBuildInfo.fromEnvironment(),
      onLocalMutation: notifyLocalMutation,
      shadowOrchestrator: shadowOrchestrator,
      eventAdapter: eventAdapter,
      onSideEffectsPending: learningReconciliation.request,
    );
    final exports = ExportUseCases(
      owners: localOwners,
      reader: DriftExportReader(database),
      store: const FileSelectorExportStore(),
      nowUtc: () => DateTime.now().toUtc(),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: researchConsent,
    );
    final modelRepository = DriftModelDownloadRepository(database);
    final modelByteSource = HttpModelByteSource(http.Client());
    resources.own(modelByteSource.close);
    final downloadCounter = DownloadCounter(
      database,
      generateEventId: idGenerator.v4,
    );
    final modelDownloadManager = ModelDownloadManager(
      repository: modelRepository,
      source: modelByteSource,
      verifier: const LiteRtModelFileVerifier(),
      modelDirectory: () async {
        final support = await getApplicationSupportDirectory();
        return Directory('${support.path}${Platform.pathSeparator}models');
      },
      nowUtc: () => DateTime.now().toUtc(),
      onDownloadCompleted: downloadCounter.increment,
    );
    final deviceModels = DeviceModelUseCases(
      manifest: ModelManifest.fieldImageClassifier,
      repository: modelRepository,
      downloadManager: modelDownloadManager,
      openRuntime: ({required path, required manifest, required delegate}) =>
          LiteRtImageClassifier.open(
            path: path,
            manifest: manifest,
            delegate: delegate,
          ),
    );
    resources.own(deviceModels.dispose);
    final objectScanner = ObjectScannerUseCases(
      camera: PluginCameraGateway(),
      deviceModels: deviceModels,
      vocabulary: vocabulary,
      preprocessor: const DartImagePreprocessor(),
    );
    resources.own(objectScanner.dispose);
    final speechPractice = SpeechPracticeUseCases(
      PluginSpeechRecognitionGateway(),
    );
    resources.own(speechPractice.dispose);
    final aiTutorHttpClient = http.Client();
    resources.own(aiTutorHttpClient.close);
    final aiUsage = DriftAiUsageRepository(
      database,
      activeOwnerId: activeOwnerId,
    );
    final aiTutor = AiTutorUseCases(
      store: aiTutorSettings,
      nowUtc: () => DateTime.now().toUtc(),
      httpClient: aiTutorHttpClient,
      loadProgress: progress.load,
      usageRepository: aiUsage,
      usageEventId: idGenerator.v4,
    );
    resources.own(aiTutor.dispose);

    final associativeLearning = DriftAssociativeLearningAdapter(database);

    // ── Voice (default provider fallback, best-effort) ─────────────────────
    VoiceUseCases? voice;
    try {
      voice = VoiceUseCases.createDefault();
      final ownedVoice = voice;
      resources.own(() => ownedVoice.disposeIfOwned(true));
    } catch (_) {
      // Platform TTS unavailable in this environment (e.g. headless tests).
      // Screens fall back to VoiceUseCases.createDefault() per-screen.
    }

    // ── Wrap feature registry with runtime kill-switch support ────────────
    final featureOverrideStore = RuntimeFeatureOverrideStore(database);
    final runtimeFeatures = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
      overrides: await featureOverrideStore.load(
        nowUtc: DateTime.now().toUtc(),
      ),
    );
    resources.own(runtimeFeatures.dispose);
    final featureControls = RuntimeFeatureControls(
      store: featureOverrideStore,
      registry: runtimeFeatures,
      nowUtc: () => DateTime.now().toUtc(),
    );
    final fieldFeatures = FeatureRegistryFieldAdapter(runtimeFeatures);
    resources.own(fieldFeatures.dispose);

    final initialRoute = await AppStartRouteResolver(
      entryState: entryState,
    ).resolve(hasAuthenticatedSession: account?.currentSession != null);

    return AppDependencies(
      initialRoute: initialRoute,
      runtimeStatus: AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: firebase,
        supabase: supabase,
        backends: config == null
            ? RuntimeAvailability.unavailable
            : RuntimeAvailability.ready,
      ),
      config: config,
      guestSessionService: exposedGuestSession,
      fieldFeatures: fieldFeatures,
      features: runtimeFeatures,
      featureControls: featureControls,
      buildInfo: const AppBuildInfo.fromEnvironment(),
      database: database,
      localOwners: localOwners,
      upgradeGuestOwner: upgradeGuestOwner,
      syncEngine: syncEngine,
      syncTrigger: syncTrigger,
      learning: learning,
      learningReconciliation: learningReconciliation,
      progress: progress,
      rewards: rewards,
      exports: exports,
      vocabulary: vocabulary,
      vocabularyImporter: vocabularyImporter,
      deviceModels: deviceModels,
      account: account,
      localDataEraser: localDataEraser,
      researchConsent: researchConsent,
      aiTutor: aiTutor,
      aiUsage: aiUsage,
      objectScanner: objectScanner,
      speechPractice: speechPractice,
      quest: quest,
      streak: streak,
      voice: voice,
      associativeLearning: associativeLearning,
      disposeResources: resources.dispose,
    );
  }

  Future<AppEntryStateStore> _createEntryState() async {
    try {
      return await createEntryStateStore();
    } catch (_) {
      return _VolatileAppEntryStateStore();
    }
  }

  Future<RuntimeAvailability> _availability(
    RuntimeInitializer initializer,
  ) async {
    try {
      await initializer();
      return RuntimeAvailability.ready;
    } catch (_) {
      return RuntimeAvailability.unavailable;
    }
  }

  AppConfig? _loadConfig() {
    try {
      return loadConfig();
    } catch (_) {
      return null;
    }
  }
}

/// Process-local fail-closed fallback for the non-business app-entry flag.
/// It never stores owner, learning, consent, or research data and intentionally
/// makes no durability claim across process restarts.
final class _VolatileAppEntryStateStore implements AppEntryStateStore {
  AppEntryMode _mode = AppEntryMode.signedOut;

  @override
  Future<AppEntryMode> read() async => _mode;

  @override
  Future<void> markGuest() async {
    _mode = AppEntryMode.guest;
  }

  @override
  Future<void> clear() async {
    _mode = AppEntryMode.signedOut;
  }
}

/// No-op [ShadowLogger] for production; shadow entries are discarded.
final class _NoopShadowLogger implements ShadowLogger {
  @override
  void logEntry(ShadowLogEntry entry) {}

  @override
  void logError(String eventId, Object error, StackTrace stack) {}

  @override
  List<ShadowLogEntry> get entries => const [];
}
