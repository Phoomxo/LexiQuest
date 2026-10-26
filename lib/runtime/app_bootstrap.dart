import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:drift/drift.dart' show TableUpdateQuery;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart' hide User;
import 'package:uuid/uuid.dart';

import '../config/app_config.dart';
import '../data/local/app_database.dart';
import '../firebase_options.dart';
import '../features/account/application/account_use_cases.dart';
import '../features/account/data/firebase_account_gateway.dart';
import '../features/account/data/google_sign_in_credential_source.dart';
import '../features/account/domain/account_contracts.dart';
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
import '../features/gemini/application/gemini_tutor_use_cases.dart';
import '../features/gemini/data/gemini_rest_gateway.dart';
import '../features/gemini/data/secure_gemini_settings_store.dart';
import '../features/gemini/domain/gemini_contracts.dart';
import '../features/identity/data/drift_local_owner_repository.dart';
import '../features/identity/application/upgrade_guest_owner.dart';
import '../features/identity/data/drift_owner_upgrade_repository.dart';
import '../features/learning/application/learning_use_cases.dart';
import '../features/learning/data/drift_learning_repository.dart';
import '../features/learning/data/drift_associative_learning_adapter.dart';
import '../features/media_practice/application/image_preprocessor.dart';
import '../features/media_practice/data/plugin_device_permission_access.dart';
import '../features/media_practice/application/object_scanner_use_cases.dart';
import '../features/media_practice/application/speech_practice_use_cases.dart';
import '../features/media_practice/data/plugin_camera_gateway.dart';
import '../features/media_practice/data/plugin_speech_recognition_gateway.dart';
import '../features/progress/application/progress_use_cases.dart';
import '../features/progress/data/drift_progress_queries.dart';
import '../features/research/domain/research_operation_authorizer.dart';
import '../features/rewards/application/reward_use_cases.dart';
import '../features/rewards/data/drift_reward_repository.dart';
import '../features/sync/application/sync_backoff.dart';
import '../features/sync/application/sync_engine.dart';
import '../features/sync/application/sync_mutex.dart';
import '../features/sync/application/sync_trigger.dart';
import '../features/sync/data/drift_cloud_policy_cache.dart';
import '../features/sync/data/drift_sync_store.dart';
import '../features/sync/data/firestore_sync_gateway.dart';
import '../features/sync/domain/sync_gateway.dart';
import '../features/vocabulary/application/import_vocabulary.dart';
import '../features/vocabulary/application/vocabulary_use_cases.dart';
import '../features/vocabulary/data/file_selector_vocabulary_import_file_picker.dart';
import '../features/vocabulary/data/file_selector_source_practice_file_picker.dart';
import '../features/vocabulary/data/drift_vocabulary_import_repository.dart';
import '../features/vocabulary/data/drift_vocabulary_repository.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_dependencies.dart';
import 'app_runtime_status.dart';
import 'supabase_client_config.dart';

typedef RuntimeInitializer = Future<void> Function();
typedef AppConfigLoader = AppConfig Function();
typedef AppDatabaseFactory = AppDatabase Function();
typedef SyncGatewayFactory = SyncGateway Function();
typedef AccountGatewayFactory = AccountGateway Function();

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
const _productionGoogleSignInEnabled = bool.fromEnvironment(
  'LEXIQUEST_GOOGLE_SIGN_IN_ENABLED',
  defaultValue: true,
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

final class AppBootstrap {
  const AppBootstrap({
    required this.initializeFirebase,
    required this.initializeSupabase,
    required this.loadConfig,
    required this.guestSessionService,
    required this.createDatabase,
    this.bindGuestOwnership = false,
    this.syncGatewayFactory,
    this.accountGatewayFactory,
    this.cloudSyncEnabled = true,
    this.readGeminiSession,
    this.watchGeminiSessions,
    this.geminiSettingsStoreFactory,
    this.geminiGatewayFactory,
    this.researchAuthorizer = const DenyAllResearchOperationAuthorizer(),
  });

  factory AppBootstrap.production({
    ResearchOperationAuthorizer researchAuthorizer =
        const DenyAllResearchOperationAuthorizer(),
  }) {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      initializeSupabase: _initializeSupabaseProduction,
      loadConfig: AppConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
      createDatabase: AppDatabase.production,
      bindGuestOwnership: true,
      syncGatewayFactory: () => FirestoreSyncGateway(
        firestore: FirebaseFirestore.instance,
        auth: FirebaseAuth.instance,
      ),
      accountGatewayFactory: () => FirebaseAccountGateway(
        FirebaseAuth.instance,
        google: _productionGoogleSignInEnabled
            ? GoogleSignInCredentialSource.production()
            : null,
      ),
      cloudSyncEnabled: _productionCloudSyncEnabled,
      readGeminiSession: () =>
          _geminiAuthSession(FirebaseAuth.instance.currentUser),
      watchGeminiSessions: () =>
          FirebaseAuth.instance.userChanges().map(_geminiAuthSession),
      researchAuthorizer: researchAuthorizer,
    );
  }

  final RuntimeInitializer initializeFirebase;
  final RuntimeInitializer initializeSupabase;
  final AppConfigLoader loadConfig;
  final GuestSessionService guestSessionService;
  final AppDatabaseFactory createDatabase;
  final bool bindGuestOwnership;
  final SyncGatewayFactory? syncGatewayFactory;
  final AccountGatewayFactory? accountGatewayFactory;
  final bool cloudSyncEnabled;
  final AccountSession? Function()? readGeminiSession;
  final Stream<AccountSession?> Function()? watchGeminiSessions;
  final GeminiSettingsStore Function()? geminiSettingsStoreFactory;
  final GeminiGateway Function()? geminiGatewayFactory;
  final ResearchOperationAuthorizer researchAuthorizer;

  Future<AppDependencies> initialize() async {
    final database = createDatabase();
    await database.customSelect('SELECT 1').getSingle();
    final idGenerator = const Uuid();
    final localOwners = DriftLocalOwnerRepository(
      database,
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
    );
    await localOwners.getOrCreateActiveOwner();
    final ownerUpgrades = DriftOwnerUpgradeRepository(
      database,
      nowUtc: () => DateTime.now().toUtc(),
      generateConflictId: idGenerator.v4,
      generateOwnerId: idGenerator.v4,
    );
    final upgradeGuestOwner = UpgradeGuestOwner(ownerUpgrades);
    var firebase = await _availability(initializeFirebase);
    final createAccountGateway = accountGatewayFactory;
    AccountUseCases? account;
    if (firebase == RuntimeAvailability.ready && createAccountGateway != null) {
      try {
        final candidate = AccountUseCases(
          gateway: createAccountGateway(),
          owners: localOwners,
          upgradeGuestOwner: upgradeGuestOwner,
        );
        await candidate.reconcileLocalOwner();
        account = candidate;
      } catch (_) {
        firebase = RuntimeAvailability.unavailable;
      }
    }
    final supabase = await _availability(initializeSupabase);
    final config = _loadConfig();
    final syncStore = DriftSyncStore(database);
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
        store: syncStore,
        gateway: gateway,
        policyProvider: policy.call,
        mutex: SyncMutex(),
        backoff: const SyncBackoff(),
        nowUtc: () => DateTime.now().toUtc(),
        generateLeaseToken: idGenerator.v4,
      );
      syncTrigger = SyncTrigger(syncEngine.run);
    }
    void notifyLocalMutation() {
      final trigger = syncTrigger;
      if (trigger != null) {
        unawaited(trigger.request(SyncTriggerReason.localMutation));
      }
    }

    final exposedGuestSession = bindGuestOwnership
        ? OwnerBindingGuestSessionService(
            delegate: guestSessionService,
            localOwners: localOwners,
            upgradeGuestOwner: upgradeGuestOwner,
            onOwnerBound: () {
              final trigger = syncTrigger;
              if (trigger != null) {
                unawaited(trigger.request(SyncTriggerReason.accountBinding));
              }
            },
          )
        : guestSessionService;
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
    final learning = LearningUseCases(
      owners: localOwners,
      repository: DriftLearningRepository(database),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      buildInfo: const AppBuildInfo.fromEnvironment(),
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
    final rewards = RewardUseCases(
      owners: localOwners,
      repository: DriftRewardRepository(database),
      generateId: idGenerator.v4,
      nowUtc: () => DateTime.now().toUtc(),
      onLocalMutation: notifyLocalMutation,
    );
    final exports = ExportUseCases(
      owners: localOwners,
      reader: DriftExportReader(database),
      store: const FileSelectorExportStore(),
      nowUtc: () => DateTime.now().toUtc(),
      loadThaiFont: () =>
          rootBundle.load('assets/fonts/NotoSansThai-Variable.ttf'),
      researchConsent: researchConsent,
      researchAuthorizer: researchAuthorizer,
    );
    final modelRepository = DriftModelDownloadRepository(database);
    final modelByteSource = HttpModelByteSource(http.Client());
    final modelDownloadManager = ModelDownloadManager(
      repository: modelRepository,
      source: modelByteSource,
      verifier: const LiteRtModelFileVerifier(),
      modelDirectory: () async {
        final support = await getApplicationSupportDirectory();
        return Directory('${support.path}${Platform.pathSeparator}models');
      },
      nowUtc: () => DateTime.now().toUtc(),
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
    final objectScanner = ObjectScannerUseCases(
      camera: PluginCameraGateway(),
      deviceModels: deviceModels,
      vocabulary: vocabulary,
      preprocessor: const DartImagePreprocessor(),
    );
    final speechPractice = SpeechPracticeUseCases(
      PluginSpeechRecognitionGateway(),
    );
    final geminiHttpClient = http.Client();
    final geminiOwnerQuery = database.select(database.localOwners)
      ..where((row) => row.isActive.equals(true));
    LocalOwner? geminiOwner = await geminiOwnerQuery.getSingleOrNull();
    final readSession = readGeminiSession ?? () => account?.currentSession;
    var geminiAuthTrusted = true;
    GeminiScope? scopeFor(LocalOwner? owner) {
      if (owner == null ||
          !geminiAuthTrusted ||
          firebase != RuntimeAvailability.ready) {
        return null;
      }
      try {
        final session = readSession();
        if (owner.firebaseUid != session?.uid) return null;
        return GeminiScope(
          ownerId: owner.id,
          firebaseUid: session?.uid,
          isAnonymous: session?.isAnonymous ?? true,
        );
      } on Object {
        return null;
      }
    }

    final geminiTutor = GeminiTutorUseCases(
      store:
          geminiSettingsStoreFactory?.call() ??
          SecureGeminiSettingsStore.production(),
      gateway:
          geminiGatewayFactory?.call() ??
          GeminiRestGateway(client: geminiHttpClient),
      loadProgress: progress.load,
      nowUtc: () => DateTime.now().toUtc(),
      readScope: () => scopeFor(geminiOwner),
      verifyScope: () async =>
          scopeFor(await geminiOwnerQuery.getSingleOrNull()),
    );
    final geminiOwnerSubscription = geminiOwnerQuery.watchSingleOrNull().listen(
      (owner) {
        final changed =
            owner?.id != geminiOwner?.id ||
            owner?.firebaseUid != geminiOwner?.firebaseUid;
        geminiOwner = owner;
        if (changed) geminiTutor.invalidateScope();
      },
      onError: (Object _) {
        geminiOwner = null;
        geminiTutor.invalidateScope();
      },
    );
    // Query snapshots can coalesce ABA transitions; every owner-table commit fences AI.
    final geminiOwnerUpdatesSubscription = database
        .tableUpdates(TableUpdateQuery.onTable(database.localOwners))
        .listen(
          (_) => geminiTutor.invalidateScope(),
          onError: (Object _) {
            geminiOwner = null;
            geminiTutor.invalidateScope();
          },
        );
    StreamSubscription<AccountSession?>? geminiAuthSubscription;
    final watchSessions = watchGeminiSessions;
    if (firebase == RuntimeAvailability.ready && watchSessions != null) {
      AccountSession? observedSession;
      try {
        observedSession = readSession();
      } on Object {
        geminiAuthTrusted = false;
      }
      try {
        geminiAuthSubscription = watchSessions().listen(
          (session) {
            final changed =
                !geminiAuthTrusted ||
                session?.uid != observedSession?.uid ||
                session?.isAnonymous != observedSession?.isAnonymous;
            geminiAuthTrusted = true;
            observedSession = session;
            if (changed) geminiTutor.invalidateScope();
          },
          onError: (Object _) {
            geminiAuthTrusted = false;
            geminiTutor.invalidateScope();
          },
        );
      } on Object {
        geminiAuthTrusted = false;
        geminiTutor.invalidateScope();
      }
    }

    return AppDependencies(
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
      buildInfo: const AppBuildInfo.fromEnvironment(),
      database: database,
      localOwners: localOwners,
      upgradeGuestOwner: upgradeGuestOwner,
      syncEngine: syncEngine,
      syncTrigger: syncTrigger,
      syncStatus: syncStore,
      learning: learning,
      associativeLearning: DriftAssociativeLearningAdapter(database),
      progress: progress,
      rewards: rewards,
      exports: exports,
      vocabulary: vocabulary,
      vocabularyImporter: vocabularyImporter,
      vocabularyImportFilePicker: FileSelectorVocabularyImportFilePicker().pick,
      sourcePracticeFilePicker: FileSelectorSourcePracticeFilePicker().pick,
      deviceModels: deviceModels,
      account: account,
      researchConsent: researchConsent,
      geminiTutor: geminiTutor,
      objectScanner: objectScanner,
      devicePermissions: const PluginDevicePermissionAccess(),
      speechPractice: speechPractice,
      disposeResources: () async {
        await geminiAuthSubscription?.cancel();
        await geminiOwnerUpdatesSubscription.cancel();
        await geminiOwnerSubscription.cancel();
        await geminiTutor.dispose();
        geminiHttpClient.close();
        await objectScanner.dispose();
        await speechPractice.dispose();
        await deviceModels.dispose();
        modelByteSource.close();
        await database.close();
      },
    );
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

AccountSession? _geminiAuthSession(User? user) => user == null
    ? null
    : AccountSession(
        uid: user.uid,
        email: null,
        isAnonymous: user.isAnonymous,
        emailVerified: false,
      );
