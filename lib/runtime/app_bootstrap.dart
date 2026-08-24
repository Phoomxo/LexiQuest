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
import 'package:timezone/data/latest_all.dart' as timezone_data;
import 'package:timezone/timezone.dart' as timezone;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../config/research_runtime_config.dart';
import '../data/local/app_database.dart';
import '../firebase_options.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/application/local_data_deletion.dart';
import '../features/account/data/firebase_account_gateway.dart';
import '../features/account/domain/account_contracts.dart';
import '../features/ai_tutor/application/ai_tutor_use_cases.dart';
import '../features/ai_tutor/application/owner_operation_coordinator.dart';
import '../features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import '../features/ai_tutor/data/ai_credential_version_index.dart';
import '../features/ai_tutor/data/ai_tutor_settings_store.dart';
import '../features/ai_tutor/data/drift_ai_usage_repository.dart';
import '../features/ai_tutor/domain/ai_tutor_contracts.dart';
import '../features/assessment/application/assessment_use_cases.dart';
import '../features/consent/application/research_consent_use_cases.dart';
import '../features/consent/data/drift_research_consent_repository.dart';
import '../features/device_model/application/device_model_use_cases.dart';
import '../features/device_model/application/model_download_manager.dart';
import '../features/device_model/data/drift_model_download_repository.dart';
import '../features/device_model/data/http_model_byte_source.dart';
import '../features/device_model/data/litert_image_classifier.dart';
import '../features/device_model/domain/model_manifest.dart';
import '../features/export/application/export_use_cases.dart';
import '../features/export/application/owner_lifecycle_archive.dart';
import '../features/export/data/drift_export_reader.dart';
import '../features/export/data/file_selector_export_store.dart';
import '../features/export/domain/export_contracts.dart';
import '../features/goals/application/learning_goal_use_cases.dart';
import '../features/goals/data/drift_learning_goal_repository.dart';
import '../features/identity/data/drift_local_owner_repository.dart';
import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/identity/data/drift_owner_upgrade_repository.dart';
import '../features/learning/application/current_activity_evidence.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/application/learning_side_effect_reconciler.dart';
import '../features/learning/application/legacy_lesson_mode_adapters.dart';
import '../features/learning/application/unified_lesson_controller.dart';
import '../features/learning/data/drift_associative_learning_adapter.dart';
import '../features/learning/data/drift_learning_repository.dart';
import '../features/learning/domain/evidence_context.dart';
import '../features/learning/domain/evidence_eligibility_policy.dart';
import '../features/learning/domain/lesson_mode.dart';
import '../features/learning_packs/data/drift_content_manifest_repository.dart';
import '../features/learning_packs/data/drift_learning_pack_repository.dart';
import '../features/learning_packs/application/learning_pack_use_cases.dart';
import '../features/learning_packs/domain/content_manifest.dart';
import '../features/media_practice/application/image_preprocessor.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/data/plugin_camera_gateway.dart';
import '../features/media_practice/data/plugin_speech_recognition_gateway.dart';
import '../features/media_practice/domain/media_practice_contracts.dart';
import '../features/motivation/application/streak_use_cases.dart';
import '../features/motivation/data/drift_streak_repository.dart';
import '../features/quest/application/quest_catalog_provider.dart';
import '../features/quest/application/quest_use_cases.dart';
import '../features/quest/data/drift_quest_repository.dart';
import '../features/events/application/event_v1_to_v2_adapter.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/data/drift_progress_queries.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/data/drift_reward_repository.dart';
import '../features/review/application/learner_intent_use_cases.dart';
import '../features/review/application/content_report_use_cases.dart';
import '../features/review/data/drift_content_quality_report_repository.dart';
import '../features/review/data/drift_learner_intent_repository.dart';
import '../features/rewards/domain/economy_transaction_policy.dart';
import '../features/rewards/domain/reward_models.dart';
import '../features/research/application/assigned_learning_event_context_provider.dart';
import '../features/research/application/experiment_assignment_use_cases.dart';
import '../features/research/data/drift_experiment_assignment_repository.dart';
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
import '../features/time_tracking/application/active_learning_time_controller.dart';
import '../features/time_tracking/application/focus_timer_controller.dart';
import '../features/time_tracking/application/focus_timer_rollout.dart';
import '../features/time_tracking/application/learning_time_capture_rollout.dart';
import '../features/time_tracking/data/drift_learning_time_repository.dart';
import '../features/time_tracking/domain/learning_time_segment.dart';
import '../features/sync/domain/sync_gateway.dart';
import '../features/sync/domain/sync_entity.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/drift_vocabulary_import_repository.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../features/voice/application/voice_use_cases.dart';
import '../voice/voice_provider.dart';
import '../voice/voice_service_factory.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_dependencies.dart';
import 'central_cost_policy.dart';
import 'download_counter.dart';
import 'app_runtime_status.dart';
import 'app_start_route_resolver.dart';
import 'registries/drift_consent_registry.dart';
import 'registries/experiment_registry.dart';
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
typedef ExportArtifactStoreFactory = ExportArtifactStore Function();
typedef CameraGatewayFactory = CameraGateway Function();
typedef SpeechRecognitionGatewayFactory = SpeechRecognitionGateway Function();
typedef ManagedAiTutorBuilder =
    FutureOr<ManagedAiTutor> Function(AiTutorBuildContext context);
typedef ManagedVoiceBuilder =
    FutureOr<ManagedVoiceProvider> Function(AppConfig? config);

DateTime _runtimeFeatureSystemNowUtc() => DateTime.now().toUtc();
DateTime _aiSystemNowUtc() => DateTime.now().toUtc();
String _systemLearningTimezoneId() => 'Asia/Bangkok';
final Stopwatch _learningTimeMonotonicClock = Stopwatch()..start();
int _systemLearningTimeMonotonicMicros() =>
    _learningTimeMonotonicClock.elapsedMicroseconds;
bool _learningTimezonesInitialized = false;
void _initializeLearningTimezonesOnce() {
  if (_learningTimezonesInitialized) return;
  timezone_data.initializeTimeZones();
  _learningTimezonesInitialized = true;
}

ExportArtifactStore _productionExportStore() => const FileSelectorExportStore();
CameraGateway _productionCameraGateway() => PluginCameraGateway();
SpeechRecognitionGateway _productionSpeechRecognitionGateway() =>
    PluginSpeechRecognitionGateway();
ResearchRuntimeConfig _legacyResearchRuntimeConfig() =>
    ResearchRuntimeConfig.legacySafe();

const int _maxBundledLexicalMetadataBytes = 8 * 1024;
final RegExp _bundledLexicalWordId = RegExp(r'^word:[a-z0-9][a-z0-9_-]{0,95}$');

/// Loads only bounded, packaged lexical artifacts from their canonical path.
/// Missing, malformed, or non-lexical identities deliberately resolve to null
/// so the content-manifest repository fails closed before presentation.
Future<Uint8List?> _productionContentArtifactBytes(
  ContentIdentity identity,
) async {
  final path = _bundledLexicalMetadataAssetPath(identity);
  if (path == null) return null;
  try {
    final bytes = await rootBundle.load(path);
    if (bytes.lengthInBytes > _maxBundledLexicalMetadataBytes) return null;
    return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
  } on Object {
    return null;
  }
}

String? _bundledLexicalMetadataAssetPath(ContentIdentity identity) {
  if (identity.type != ContentType.lexicalMetadata ||
      identity.revision <= 0 ||
      !_bundledLexicalWordId.hasMatch(identity.id)) {
    return null;
  }
  final wordKey = identity.id.substring('word:'.length);
  return 'assets/content/lexical_metadata/$wordKey/r${identity.revision}.json';
}

Future<void> Function() _retainAsyncDisposer(Future<void> Function() value) =>
    value;

final class AiTutorBuildContext {
  const AiTutorBuildContext({
    required this.settings,
    required this.usage,
    required this.ownerCoordinator,
    required this.loadProgress,
    required this.nowUtc,
    required this.usageEventId,
  });

  final AiTutorSettingsStore settings;
  final AiUsageRepository usage;
  final OwnerOperationCoordinator ownerCoordinator;
  final LoadAiTutorProgress loadProgress;
  final DateTime Function() nowUtc;
  final String Function() usageEventId;
}

final class ManagedAiTutor {
  ManagedAiTutor({
    required this.controller,
    required Future<void> Function() disposeController,
  }) : _disposeController = _retainAsyncDisposer(disposeController);

  final AiTutorController controller;
  final Future<void> Function() _disposeController;
  Future<void>? _disposeFuture;

  Future<void> dispose() => _disposeFuture ??= _disposeController();
}

// Public client identifiers, not server credentials. The Supabase URL keeps a
// public default, but the publishable key must be supplied per build.
const _productionSupabaseUrl = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_URL',
  defaultValue: 'https://anyiuoqnuimtjlbjhwuf.supabase.co',
);
const _productionSupabasePublishableKey = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_PUBLISHABLE_KEY',
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
    DateTime Function()? runtimeFeatureNowUtc,
    DateTime Function()? aiNowUtc,
    String Function()? learningTimezoneId,
    this.scheduleRuntimeFeatureExpiry,
    ExportArtifactStoreFactory? exportStoreFactory,
    CameraGatewayFactory? cameraGatewayFactory,
    SpeechRecognitionGatewayFactory? speechRecognitionGatewayFactory,
    ManagedAiTutorBuilder? buildAiTutor,
    ManagedVoiceBuilder? buildVoice,
    ResearchRuntimeConfigLoader? loadResearchRuntimeConfig,
    this.researchStateProvider,
    ResearchProtocolModeCatalog? researchProtocolModeCatalog,
    this.assessmentOverride,
    ContentArtifactBytesLoader? loadContentArtifactBytes,
    LearningTimeMonotonicMicros? learningTimeMonotonicMicros,
    this.activeLearningIdleTimeout = const Duration(minutes: 5),
    this.learningTimeCaptureRollout =
        const LearningTimeCaptureRollout.implementedOff(),
    this.focusTimerRollout = const FocusTimerRollout.implementedOff(),
    this.learningTimeSegmentSyncRollout =
        const LearningTimeSegmentSyncRollout.off(),
    this.learningGoalSyncRollout = const LearningGoalSyncRollout.off(),
  }) : exportStoreFactory = exportStoreFactory ?? _productionExportStore,
       cameraGatewayFactory = cameraGatewayFactory ?? _productionCameraGateway,
       speechRecognitionGatewayFactory =
           speechRecognitionGatewayFactory ??
           _productionSpeechRecognitionGateway,
       buildAiTutor = buildAiTutor ?? _buildManagedAiTutor,
       buildVoice = buildVoice ?? _buildManagedVoice,
       loadResearchRuntimeConfig =
           loadResearchRuntimeConfig ?? _legacyResearchRuntimeConfig,
       researchProtocolModeCatalog =
           researchProtocolModeCatalog ??
           const ResearchProtocolModeCatalog(
             mappings: <ResearchProtocolModeMapping>[],
           ),
       runtimeFeatureNowUtc =
           runtimeFeatureNowUtc ?? _runtimeFeatureSystemNowUtc,
       aiNowUtc = aiNowUtc ?? _aiSystemNowUtc,
       learningTimezoneId = learningTimezoneId ?? _systemLearningTimezoneId,
       learningTimeMonotonicMicros =
           learningTimeMonotonicMicros ?? _systemLearningTimeMonotonicMicros,
       loadContentArtifactBytes =
           loadContentArtifactBytes ?? _productionContentArtifactBytes;

  factory AppBootstrap.production({
    LearningTimeSegmentSyncRollout learningTimeSegmentSyncRollout =
        const LearningTimeSegmentSyncRollout.off(),
    LearningGoalSyncRollout learningGoalSyncRollout =
        const LearningGoalSyncRollout.off(),
  }) {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      initializeSupabase: _initializeSupabaseOptional,
      loadConfig: AppConfig.fromEnvironment,
      loadResearchRuntimeConfig: ResearchRuntimeConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
      createDatabase: AppDatabase.production,
      createEntryStateStore: createProductionEntryStateStore,
      bindGuestOwnership: true,
      syncGatewayFactory: () => FirestoreSyncGateway(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
        learningTimeSegmentRollout: learningTimeSegmentSyncRollout,
        learningGoalRollout: learningGoalSyncRollout,
      ),
      accountGatewayFactory: () =>
          FirebaseAccountGateway(FirebaseAuth.instance),
      cloudSyncEnabled: productionCloudSyncEnabledByDefault,
      learningTimeSegmentSyncRollout: learningTimeSegmentSyncRollout,
      learningGoalSyncRollout: learningGoalSyncRollout,
    );
  }

  final RuntimeInitializer initializeFirebase;
  final RuntimeInitializer initializeSupabase;
  final AppConfigLoader loadConfig;
  final ResearchRuntimeConfigLoader loadResearchRuntimeConfig;
  final CurrentActivityResearchStateProvider? researchStateProvider;
  final ResearchProtocolModeCatalog researchProtocolModeCatalog;
  final AssessmentUseCases? assessmentOverride;
  final GuestSessionService guestSessionService;
  final AppDatabaseFactory createDatabase;
  final AppEntryStateStoreFactory createEntryStateStore;
  final bool bindGuestOwnership;
  final SyncGatewayFactory? syncGatewayFactory;
  final AccountGatewayFactory? accountGatewayFactory;
  final bool cloudSyncEnabled;
  final DateTime Function() runtimeFeatureNowUtc;
  final DateTime Function() aiNowUtc;
  final String Function() learningTimezoneId;
  final LearningTimeMonotonicMicros learningTimeMonotonicMicros;
  final Duration activeLearningIdleTimeout;
  final LearningTimeCaptureRollout learningTimeCaptureRollout;
  final FocusTimerRollout focusTimerRollout;
  final LearningTimeSegmentSyncRollout learningTimeSegmentSyncRollout;
  final LearningGoalSyncRollout learningGoalSyncRollout;
  final RuntimeFeatureExpiryScheduler? scheduleRuntimeFeatureExpiry;
  final ExportArtifactStoreFactory exportStoreFactory;
  final CameraGatewayFactory cameraGatewayFactory;
  final SpeechRecognitionGatewayFactory speechRecognitionGatewayFactory;
  final ManagedAiTutorBuilder buildAiTutor;
  final ManagedVoiceBuilder buildVoice;
  final ContentArtifactBytesLoader loadContentArtifactBytes;
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
    _initializeLearningTimezonesOnce();
    final researchRuntimeConfig = loadResearchRuntimeConfig();
    final entryState = await _createEntryState();
    final database = createDatabase();
    resources.own(database.close);
    await database.customSelect('SELECT 1').getSingle();
    final idGenerator = const Uuid();
    final ownerOperationGate = DriftOwnerOperationGate(database);
    const evidencePolicy = EvidenceEligibilityPolicySet();
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
    final experimentAssignmentRepository = DriftExperimentAssignmentRepository(
      database,
    );
    final experimentRegistry = DriftExperimentRegistry(
      experimentAssignmentRepository,
    );
    final consentRegistry = DriftConsentRegistry(database);
    final experimentAssignments = ExperimentAssignmentUseCases(
      repository: experimentAssignmentRepository,
      consentRegistry: consentRegistry,
    );
    final assignedLearningEventContext = AssignedLearningEventContextProvider(
      experimentRegistry: experimentRegistry,
      consentRegistry: consentRegistry,
      protocolModeCatalog: researchProtocolModeCatalog,
    );
    final currentResearchStateProvider =
        researchStateProvider ??
        (researchProtocolModeCatalog.isEmpty
            ? const BaselineCurrentActivityResearchStateProvider()
            : assignedLearningEventContext);
    final evidenceRolloutModeProvider =
        PersistedEvidencePolicyRolloutModeProvider(
          experimentRegistry: experimentRegistry,
          consentRegistry: consentRegistry,
          protocolModeCatalog: researchProtocolModeCatalog,
          currentActivityResearchStateProvider: assignedLearningEventContext,
        );
    final aiCredentialVersionIndex = DriftAiCredentialVersionIndex(database);
    final aiTutorSettings = SecureAiTutorSettingsStore.production(
      activeOwnerId: activeOwnerId,
      versionIndex: aiCredentialVersionIndex,
    );
    Future<void> eraseOwnerCredentialsWithLease(
      String ownerId,
      String operationToken,
    ) {
      return aiTutorSettings.eraseOwnerCredentialsFenced(
        ownerId,
        leaseToken: operationToken,
        leaseIsOwned: () => ownerOperationGate.isOwned(
          token: operationToken,
          nowUtc: DateTime.now().toUtc(),
        ),
        nowUtc: () => DateTime.now().toUtc(),
      );
    }

    final localErasureCoordinator = OwnerOperationCoordinator(
      gate: ownerOperationGate,
      activeOwnerId: activeOwnerId,
      nowUtc: () => DateTime.now().toUtc(),
      generateToken: idGenerator.v4,
      leaseDuration: const Duration(minutes: 1),
      heartbeatInterval: const Duration(seconds: 20),
      waitTimeout: const Duration(seconds: 5),
    );
    final localDataEraser = LocalDataDeletion(
      database,
      deleteOwnerSecrets: aiTutorSettings.deleteCredentialForOwner,
      deleteOwnerSecretsFenced: eraseOwnerCredentialsWithLease,
      fenceOwnerOperation: (operationToken) => ownerOperationGate.requireOwned(
        token: operationToken,
        nowUtc: DateTime.now().toUtc(),
      ),
      coordinate: (ownerId, operation) async {
        final cancellation = AiCancellation();
        return localErasureCoordinator.run(cancellation, (activeOwner) {
          if (activeOwner != ownerId) {
            throw StateError('Only the active owner can be erased.');
          }
          final operationToken = OwnerOperationCoordinator.currentLeaseToken;
          if (operationToken == null) {
            throw StateError('Local erasure requires the owner lease.');
          }
          return operation(operationToken).then((deleted) {
            localErasureCoordinator.markCurrentOperationResultCommitted();
            return deleted;
          });
        });
      },
    );
    final ownerUpgrades = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.now().toUtc(),
      generateConflictId: idGenerator.v4,
      generateOwnerId: idGenerator.v4,
      generateOwnerOperationToken: idGenerator.v4,
      deleteOwnerSecrets: aiTutorSettings.deleteCredentialForOwner,
      deleteOwnerSecretsFenced: eraseOwnerCredentialsWithLease,
      ownerOperationGate: ownerOperationGate,
      evidencePolicy: evidencePolicy,
      rolloutModeProvider: evidenceRolloutModeProvider,
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
      if (learningTimeSegmentSyncRollout.enabled) {
        if (gateway is! LearningTimeSegmentSyncRolloutGateway) {
          throw StateError(
            'Learning-time sync rollout must be shared by store and gateway.',
          );
        }
        final rolloutGateway = gateway as LearningTimeSegmentSyncRolloutGateway;
        if (!identical(
          rolloutGateway.learningTimeSegmentSyncRollout,
          learningTimeSegmentSyncRollout,
        )) {
          throw StateError(
            'Learning-time sync rollout must be shared by store and gateway.',
          );
        }
      }
      if (learningGoalSyncRollout.enabled) {
        if (gateway is! LearningGoalSyncRolloutGateway) {
          throw StateError(
            'Learning-goal sync rollout must be shared by store and gateway.',
          );
        }
        final rolloutGateway = gateway as LearningGoalSyncRolloutGateway;
        if (!identical(
          rolloutGateway.learningGoalSyncRollout,
          learningGoalSyncRollout,
        )) {
          throw StateError(
            'Learning-goal sync rollout must be shared by store and gateway.',
          );
        }
      }
      final policy = CloudSyncPolicyProvider(
        buildEnabled: cloudSyncEnabled,
        cache: DriftCloudPolicyCache(database),
        gateway: gateway,
        nowUtc: () => DateTime.now().toUtc(),
      );
      syncEngine = SyncEngine(
        owners: localOwners,
        store: DriftSyncStore(
          database,
          evidencePolicy: evidencePolicy,
          rolloutModeProvider: evidenceRolloutModeProvider,
          payloadRollout: researchRuntimeConfig.syncPayloadRollout,
          consentRegistry: consentRegistry,
          learningTimeSegmentSyncRollout: learningTimeSegmentSyncRollout,
          learningGoalSyncRollout: learningGoalSyncRollout,
        ),
        gateway: gateway,
        policyProvider: policy.call,
        ownerGate: ownerOperationGate,
        mutex: SyncMutex(),
        backoff: const SyncBackoff(),
        nowUtc: () => DateTime.now().toUtc(),
        generateLeaseToken: idGenerator.v4,
        optionalPullCollections: <SyncCollection>{
          if (learningTimeSegmentSyncRollout.allowsClaims)
            SyncCollection.learningTimeSegments,
          if (learningGoalSyncRollout.allowsClaims)
            SyncCollection.learningGoals,
        },
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

    final learnerIntents = DriftLearnerIntentRepository(
      database,
      owners: localOwners,
      nowUtc: () => DateTime.now().toUtc(),
      onLocalMutation: () async => notifyLocalMutation(),
    );
    final bookmarkLearningItem = LearnerIntentUseCases(
      repository: learnerIntents,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
    ).bookmark;
    final contentQualityReports = DriftContentQualityReportRepository(
      database,
      owners: localOwners,
      consentRegistry: consentRegistry,
      onLocalMutation: () async => notifyLocalMutation(),
    );
    final reportContent = ContentReportUseCases(
      repository: contentQualityReports,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
    ).report;

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
    final contentManifests = DriftContentManifestRepository(
      database,
      loadArtifactBytes: loadContentArtifactBytes,
    );
    final vocabulary = VocabularyUseCases(
      owners: localOwners,
      vocabulary: DriftVocabularyRepository(
        database,
        contentManifests: contentManifests,
      ),
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
    final studyPlanning = StudyPlanningUseCases(
      packs: DriftLearningPackRepository(
        database,
        contentManifests: contentManifests,
      ),
      progress: progress,
    );
    final learningGoals = LearningGoalUseCases(
      repository: DriftLearningGoalRepository(
        database,
        owners: localOwners,
        onLocalMutation: () async => notifyLocalMutation(),
      ),
      nowUtc: () => DateTime.now().toUtc(),
      generateId: () => 'goal:${idGenerator.v4()}',
    );
    final researchConsent = ResearchConsentUseCases(
      owners: localOwners,
      repository: DriftResearchConsentRepository(database),
      nowUtc: () => DateTime.now().toUtc(),
    );
    final rewardRepository = DriftRewardRepository(database);
    const economyAwardPolicy = EconomyAwardPolicyV1();
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
    final resolvedLearningTimezoneId = learningTimezoneId();
    final quest = QuestUseCases(
      repository: questRepository,
      owners: localOwners,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      timezoneId: resolvedLearningTimezoneId,
      rewardSink:
          ({
            required ownerId,
            required idempotencyKey,
            required xpAmount,
            required sourceEventId,
            required occurredAtUtc,
            rewardItemId,
          }) async {
            final award = economyAwardPolicy.evaluate(
              sourceEventId: sourceEventId,
              amount: xpAmount,
              eligible: true,
            );
            final result = await rewardRepository.grantQuestXpAndCoins(
              ownerId: ownerId,
              sourceEventId: award.sourceEventId,
              xpAmount: award.xpAmount,
              occurredAtUtc: occurredAtUtc,
            );
            if (result == QuestEconomyGrantResult.inserted) {
              notifyLocalMutation();
            }
          },
    );

    // ── Streak tracking (must precede learning wiring) ───────────────────
    final streak = StreakUseCases(
      repository: DriftStreakRepository(database),
      owners: localOwners,
      nowUtc: () => DateTime.now().toUtc(),
      timezoneId: resolvedLearningTimezoneId,
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
      coinsSink: (_, evidence) async {
        final isCorrect = evidence.attempt.isCorrect;
        final eligibleClass =
            evidence.context.evidenceClass != EvidenceClass.assessment &&
            evidence.context.evidenceClass != EvidenceClass.recreational;
        final award = economyAwardPolicy.evaluate(
          sourceEventId: evidence.attempt.id,
          amount: 1,
          eligible: isCorrect && eligibleClass,
        );
        if (award.coinAmount == 0) {
          return LearningProjectionResult.notApplicable(
            payload: <String, dynamic>{
              'reasonCode': isCorrect
                  ? 'evidenceIneligible'
                  : 'incorrectAnswer',
            },
          );
        }
        final result = await rewardRepository.grantCoins(
          ownerId: evidence.attempt.ownerId,
          idempotencyKey: award.coinIdempotencyKey,
          amount: award.coinAmount,
          sourceEventId: award.sourceEventId,
          occurredAtUtc: DateTime.fromMillisecondsSinceEpoch(
            evidence.attempt.occurredAtUtcMs,
            isUtc: true,
          ),
        );
        if (result == CoinGrantResult.inserted) {
          notifyLocalMutation();
        }
        return switch (result) {
          CoinGrantResult.inserted => const LearningProjectionResult.applied(
            payload: <String, dynamic>{'status': 'inserted'},
          ),
          CoinGrantResult.replayed => const LearningProjectionResult.applied(
            payload: <String, dynamic>{'status': 'replayed'},
          ),
          CoinGrantResult.capturedByLegacyBackfill =>
            const LearningProjectionResult.notApplicable(
              payload: <String, dynamic>{
                'reasonCode': 'capturedByLegacyBackfill',
              },
            ),
        };
      },
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
      evidencePolicy: evidencePolicy,
      rolloutModeProvider: evidenceRolloutModeProvider,
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
      repository: DriftLearningRepository(
        database,
        evidencePolicy: evidencePolicy,
        rolloutModeProvider: evidenceRolloutModeProvider,
      ),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      buildInfo: const AppBuildInfo.fromEnvironment(),
      onLocalMutation: notifyLocalMutation,
      eventAdapter: eventAdapter,
      eventContextProvider: currentResearchStateProvider,
      onSideEffectsPending: learningReconciliation.request,
    );
    final currentActivityEvidence = CurrentActivityEvidenceAdapter(
      learning: learning,
      rolloutModeProvider: evidenceRolloutModeProvider,
      researchStateProvider: currentResearchStateProvider,
    );
    final lessonModes = buildLegacyLessonModeRegistry();
    final learningTime = DriftLearningTimeRepository(
      database,
      owners: localOwners,
      onLocalMutation: () async => notifyLocalMutation(),
    );
    ActiveLearningTimeController createActiveLearningTimeController() {
      final timezoneId = resolvedLearningTimezoneId;
      final location = timezone.getLocation(timezoneId);
      return ActiveLearningTimeController(
        repository: learningTime,
        monotonicMicros: learningTimeMonotonicMicros,
        nowUtc: () => DateTime.now().toUtc(),
        timezoneContext: (occurredAtUtc) {
          final local = timezone.TZDateTime.from(occurredAtUtc, location);
          return LearningTimeZoneContext(
            timezoneId: timezoneId,
            utcOffsetMinutes: local.timeZoneOffset.inMinutes,
          );
        },
        idleTimeout: activeLearningIdleTimeout,
      );
    }

    final exports = ExportUseCases(
      reader: DriftExportReader(database),
      store: exportStoreFactory(),
      nowUtc: () => DateTime.now().toUtc(),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      lifecycleArchive: OwnerLifecycleArchiveExporter(
        database: database,
        nowUtc: aiNowUtc,
      ),
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
      onVerifiedActivation: ({required modelVersion, required completionId}) =>
          downloadCounter.recordCompletion(modelVersion, completionId),
      onCachedArtifactVerified:
          ({required modelVersion, required completionId}) =>
              downloadCounter.reconcileCompletion(modelVersion, completionId),
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
      camera: cameraGatewayFactory(),
      deviceModels: deviceModels,
      vocabulary: vocabulary,
      preprocessor: const DartImagePreprocessor(),
    );
    resources.own(objectScanner.dispose);
    final speechPractice = SpeechPracticeUseCases(
      speechRecognitionGatewayFactory(),
    );
    resources.own(speechPractice.dispose);
    final aiUsage = DriftAiUsageRepository(
      database,
      activeOwnerId: activeOwnerId,
      activeOwnerLeaseToken: () => OwnerOperationCoordinator.currentLeaseToken,
      nowUtc: aiNowUtc,
    );
    final aiOwnerCoordinator = OwnerOperationCoordinator(
      gate: ownerOperationGate,
      activeOwnerId: activeOwnerId,
      nowUtc: aiNowUtc,
      generateToken: idGenerator.v4,
      recoverPending: (cutoffUtc, {required recoveredAtUtc}) async {
        final recoveredUsage = await aiUsage.recoverPendingStartedBefore(
          cutoffUtc,
          recoveredAtUtc: recoveredAtUtc,
        );
        await aiUsage.purgeExpired(recoveredAtUtc);
        final leaseToken = OwnerOperationCoordinator.currentLeaseToken;
        if (leaseToken == null) {
          throw StateError('Credential recovery requires the owner lease.');
        }
        final recoveredCredentials = await aiTutorSettings
            .recoverCredentialMutations(
              leaseToken: leaseToken,
              nowUtc: aiNowUtc,
            );
        return recoveredUsage + recoveredCredentials;
      },
    );
    AiTutorController? aiTutor;
    try {
      final managedAi = await buildAiTutor(
        AiTutorBuildContext(
          settings: aiTutorSettings,
          usage: aiUsage,
          ownerCoordinator: aiOwnerCoordinator,
          loadProgress: progress.load,
          nowUtc: aiNowUtc,
          usageEventId: idGenerator.v4,
        ),
      );
      resources.own(managedAi.dispose);
      aiTutor = managedAi.controller;
    } on Object {
      // AI is optional. Local learning and voice composition continue.
    }

    final associativeLearning = DriftAssociativeLearningAdapter(database);

    // ── Voice (default provider fallback, best-effort) ─────────────────────
    VoiceUseCases? voice;
    try {
      final managedVoice = await buildVoice(config);
      voice = VoiceUseCases(
        provider: managedVoice,
        disposeProvider: managedVoice.dispose,
      );
      final ownedVoice = voice;
      resources.own(ownedVoice.dispose);
    } on Object {
      // Platform TTS unavailable in this environment (e.g. headless tests).
      // Scoped media consumers render typed unavailable; they do not create a
      // screen-owned provider fallback.
    }

    // ── Wrap feature registry with runtime kill-switch support ────────────
    final featureOverrideStore = RuntimeFeatureOverrideStore(database);
    final runtimeFeatures = RuntimeFeatureRegistry(
      const BuildFeatureRegistry.fieldDefaults(),
    );
    resources.own(runtimeFeatures.dispose);
    final featureControls = RuntimeFeatureControls(
      store: featureOverrideStore,
      registry: runtimeFeatures,
      nowUtc: runtimeFeatureNowUtc,
      scheduleExpiry: scheduleRuntimeFeatureExpiry,
    );
    resources.own(featureControls.dispose);
    await featureControls.initialize();
    final initialRoute = await AppStartRouteResolver(
      entryState: entryState,
    ).resolve(hasAuthenticatedSession: account?.currentSession != null);

    return AppDependencies(
      initialRoute: initialRoute,
      runtimeStatus: AppRuntimeStatus(
        localData: RuntimeAvailability.ready,
        firebase: firebase,
        supabase: supabase,
        backends: config != null && firebase == RuntimeAvailability.ready
            ? RuntimeAvailability.ready
            : RuntimeAvailability.unavailable,
        aiTutor: aiTutor == null
            ? RuntimeAvailability.unavailable
            : RuntimeAvailability.ready,
        voice: voice == null
            ? RuntimeAvailability.unavailable
            : RuntimeAvailability.ready,
      ),
      config: config,
      guestSessionService: exposedGuestSession,
      features: runtimeFeatures,
      featureControls: featureControls,
      experiments: experimentRegistry,
      consents: consentRegistry,
      experimentAssignments: experimentAssignments,
      assignedLearningEventContext: assignedLearningEventContext,
      evidencePolicyRolloutModeProvider: evidenceRolloutModeProvider,
      buildInfo: const AppBuildInfo.fromEnvironment(),
      database: database,
      localOwners: localOwners,
      upgradeGuestOwner: upgradeGuestOwner,
      syncEngine: syncEngine,
      syncTrigger: syncTrigger,
      learning: learning,
      lessonModes: lessonModes,
      createLessonController: (adapter) {
        final registration = lessonModes.find(adapter.mode);
        final registeredFeature =
            registration != null && identical(registration.adapter, adapter)
            ? registration.feature
            : null;
        final activeTime =
            learningTimeCaptureRollout.allowsCapture &&
                adapter is TrustworthyActiveEffortLessonModeAdapter
            ? createActiveLearningTimeController()
            : null;
        final focusTimer =
            activeTime != null &&
                focusTimerRollout.allowsFocusTimer &&
                registeredFeature != null &&
                adapter is FocusTimerSupportingLessonModeAdapter
            ? FocusTimerController(timeAuthority: activeTime)
            : null;
        return UnifiedLessonController(
          learning: learning,
          adapter: adapter,
          activeLearningTime: activeTime,
          focusTimer: focusTimer,
          focusTimerFeature: focusTimer == null ? null : registeredFeature,
        );
      },
      learningTime: learningTime,
      learningTimeCaptureRollout: learningTimeCaptureRollout,
      focusTimerRollout: focusTimerRollout,
      createActiveLearningTimeController:
          learningTimeCaptureRollout.allowsCapture
          ? createActiveLearningTimeController
          : null,
      assessment: assessmentOverride,
      currentActivityEvidence: currentActivityEvidence,
      learningReconciliation: learningReconciliation,
      contentManifests: contentManifests,
      studyPlanning: studyPlanning,
      learningGoals: learningGoals,
      progress: progress,
      rewards: rewards,
      learnerIntents: learnerIntents,
      bookmarkLearningItem: bookmarkLearningItem,
      contentQualityReports: contentQualityReports,
      reportContent: reportContent,
      exports: exports,
      vocabulary: vocabulary,
      vocabularyImporter: vocabularyImporter,
      deviceModels: deviceModels,
      account: account,
      localDataEraser: localDataEraser,
      researchConsent: researchConsent,
      aiTutor: aiTutor,
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

FutureOr<ManagedAiTutor> _buildManagedAiTutor(AiTutorBuildContext context) {
  final client = http.Client();
  try {
    final gatewayFactory = AiTutorGatewayFactory(
      client: client,
      requestTimeout: const Duration(seconds: 20),
    );
    final controller = AiTutorUseCases(
      store: context.settings,
      nowUtc: context.nowUtc,
      gatewayResolver: ({required providerId, required model, customBaseUrl}) =>
          gatewayFactory.create(
            providerId: providerId,
            model: model,
            customBaseUrl: customBaseUrl,
          ),
      loadProgress: context.loadProgress,
      usageRepository: context.usage,
      ownerCoordinator: context.ownerCoordinator,
      usageEventId: context.usageEventId,
    );
    return ManagedAiTutor(
      controller: controller,
      disposeController: () async {
        Object? firstError;
        StackTrace? firstStackTrace;
        try {
          await controller.dispose();
        } on Object catch (error, stackTrace) {
          firstError = error;
          firstStackTrace = stackTrace;
        }
        try {
          client.close();
        } on Object catch (error, stackTrace) {
          firstError ??= error;
          firstStackTrace ??= stackTrace;
        }
        if (firstError case final error?) {
          Error.throwWithStackTrace(error, firstStackTrace!);
        }
      },
    );
  } on Object {
    client.close();
    rethrow;
  }
}

FutureOr<ManagedVoiceProvider> _buildManagedVoice(AppConfig? config) {
  final client = config == null ? null : http.Client();
  try {
    return VoiceServiceFactory.create(config: config, client: client);
  } on Object {
    client?.close();
    rethrow;
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
