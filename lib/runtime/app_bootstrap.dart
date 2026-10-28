import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../account/account_gateway.dart';
import '../account/account_models.dart';
import '../account/account_profile_provisioner.dart';
import '../account/firebase_account_gateway.dart';
import '../ai/ai_service_factory.dart';
import '../ai/generated_reading_content_source.dart';
import '../config/app_config.dart';
import '../device/device_capability_models.dart';
import '../device/device_capability_probe.dart';
import '../firebase_options.dart';
import '../learning/adaptive_associative_scheduler.dart';
import '../learning/association_prompt.dart';
import '../learning/associative_memory.dart';
import '../learning/associative_reading_coordinator.dart';
import '../learning/reading_content_source.dart';
import '../learning/secure_id_generator.dart';
import '../learning/storage/drift_learning_repository.dart';
import '../learning/storage/learning_database_factory.dart';
import '../learning/vocabulary_mixer.dart';
import '../progress/local_progress_repository.dart';
import '../progress/firebase_progress_remote_writer.dart';
import '../progress/firebase_purchase_remote_writer.dart';
import '../progress/progress_remote_writer.dart';
import '../progress/progress_repository.dart';
import '../progress/progress_sync_service.dart';
import '../progress/purchase_remote_writer.dart';
import '../services/guest_session_service.dart';
import '../voice/reading_voice_enrichment.dart';
import '../voice/voice_service_factory.dart';
import 'app_build_info.dart';
import 'app_dependencies.dart';
import 'app_runtime_status.dart';
import 'learning_dependencies.dart';
import 'learning_feature_flags.dart';

typedef RuntimeInitializer = Future<void> Function();
typedef AppConfigLoader = AppConfig Function();
typedef ProgressRepositoryLoader = Future<ProgressRepository> Function();
typedef AccountGatewayFactory = AccountGateway Function();
typedef AccountProfileProvisioningFactory =
    AccountProfileProvisioning Function();

Future<void> _initializeFirebaseProduction() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
    await FirebaseAppCheck.instance.activate(
      providerAndroid: kDebugMode
          ? const AndroidDebugProvider()
          : const AndroidPlayIntegrityProvider(),
    );
  } else if (!kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS)) {
    await FirebaseAppCheck.instance.activate(
      providerApple: kDebugMode
          ? const AppleDebugProvider()
          : const AppleAppAttestWithDeviceCheckFallbackProvider(),
    );
  }
}

Future<ProgressRepository> _loadProgressRepositoryProduction() async {
  return LocalProgressRepository(await SharedPreferences.getInstance());
}

Future<LearningDependencies> _loadLearningDependenciesProduction(
  AppConfig? config,
  LearningFeatureFlags flags,
) async {
  final database = await LearningDatabaseFactory().open();
  const buildInfo = AppBuildInfo.fromEnvironment();
  ManagedAiService? generatedService;
  ManagedVoiceService? voiceService;
  try {
    final repository = DriftLearningRepository(database);
    final curatedSource = OfflineCuratedReadingContentSource();
    ReadingContentSource contentSource = curatedSource;
    if (flags.generatedContentEnabled && config != null) {
      generatedService = AiServiceFactory.create(config: config);
      contentSource = GeneratedReadingContentSource(
        provider: generatedService,
        curatedFallback: curatedSource,
      );
    }

    var readingVoice = const ReadingVoiceEnrichment.disabled();
    if (flags.voiceEnrichmentEnabled && config != null) {
      voiceService = VoiceServiceFactory.create(config: config);
      readingVoice = ReadingVoiceEnrichment(provider: voiceService);
    }

    return LearningDependencies(
      repository: repository,
      reader: repository,
      associativeMemory: AssociativeMemory(
        repository: repository,
        reader: repository,
        promptCatalog: CuratedAssociationPromptCatalog.offlineDefaults(),
        idGenerator: CryptographicIdGenerator(),
        clock: DateTime.now,
      ),
      readingCoordinator: AssociativeReadingCoordinator(
        repository: repository,
        reader: repository,
        contentSource: contentSource,
        mixer: const VersionedVocabularyMixer(),
        scheduler: const AdaptiveAssociativeScheduler(),
        idGenerator: CryptographicIdGenerator(),
        clock: DateTime.now,
        appVersion: buildInfo.version,
        buildId: buildInfo.buildId,
      ),
      readingVoice: readingVoice,
      close: () => _closeLearningResources(
        database.close,
        generatedService?.dispose,
        voiceService?.dispose,
      ),
    );
  } on Object {
    await _closeLearningResources(
      database.close,
      generatedService?.dispose,
      voiceService?.dispose,
    );
    rethrow;
  }
}

Future<void> _closeLearningResources(
  Future<void> Function() closeDatabase,
  Future<void> Function()? closeGeneratedService,
  Future<void> Function()? closeVoiceService,
) async {
  Object? firstError;
  StackTrace? firstStackTrace;
  for (final closer in <Future<void> Function()?>[
    closeVoiceService,
    closeGeneratedService,
    closeDatabase,
  ]) {
    if (closer == null) continue;
    try {
      await closer();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }
  }
  if (firstError != null) {
    Error.throwWithStackTrace(firstError, firstStackTrace!);
  }
}

final class AppBootstrap {
  const AppBootstrap({
    required this.initializeFirebase,
    required this.loadConfig,
    required this.guestSessionService,
    this.createAccountGateway = _unavailableAccountGateway,
    this.createAccountProfileProvisioning =
        _unavailableAccountProfileProvisioning,
    this.loadProgressRepository = _loadProgressRepositoryProduction,
    this.progressRemoteWriter,
    this.purchaseRemoteWriter,
    this.featureFlags = const LearningFeatureFlags.fromEnvironment(),
    this.loadLearningDependencies = _loadLearningDependenciesProduction,
    this.deviceCapabilityProbe = const MethodChannelDeviceCapabilityProbe(),
  });

  factory AppBootstrap.production() {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      loadConfig: AppConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
      createAccountGateway: FirebaseAccountGateway.new,
      createAccountProfileProvisioning: AccountProfileProvisioner.new,
      loadProgressRepository: _loadProgressRepositoryProduction,
      progressRemoteWriter: FirebaseProgressRemoteWriter(),
      purchaseRemoteWriter: FirebasePurchaseRemoteWriter(),
    );
  }

  final RuntimeInitializer initializeFirebase;
  final AppConfigLoader loadConfig;
  final GuestSessionService guestSessionService;
  final AccountGatewayFactory createAccountGateway;
  final AccountProfileProvisioningFactory createAccountProfileProvisioning;
  final ProgressRepositoryLoader loadProgressRepository;
  final ProgressRemoteWriter? progressRemoteWriter;
  final PurchaseRemoteWriter? purchaseRemoteWriter;
  final LearningFeatureFlags featureFlags;
  final LearningDependenciesLoader loadLearningDependencies;
  final DeviceCapabilityProbe deviceCapabilityProbe;

  Future<AppDependencies> initialize() async {
    final firebase = await _availability(initializeFirebase);
    final accountGateway = firebase == RuntimeAvailability.ready
        ? createAccountGateway()
        : _unavailableAccountGateway();
    final accountProfileProvisioning = firebase == RuntimeAvailability.ready
        ? createAccountProfileProvisioning()
        : _unavailableAccountProfileProvisioning();
    final config = _loadConfig();
    final progressRepository = await _loadProgressRepository();
    final progressSyncService =
        progressRepository == null || progressRemoteWriter == null
        ? null
        : ProgressSyncService(
            repository: progressRepository,
            remoteWriter: progressRemoteWriter!,
          );
    final learningDependencies = featureFlags.associativeReadingEnabled
        ? await _loadLearningDependencies(config)
        : null;
    final deviceCapabilitySnapshot = await _loadDeviceCapabilitySnapshot();

    return AppDependencies(
      runtimeStatus: AppRuntimeStatus(
        firebase: firebase,
        backends: config == null
            ? RuntimeAvailability.unavailable
            : RuntimeAvailability.ready,
        deviceCapabilities: deviceCapabilitySnapshot == null
            ? RuntimeAvailability.unavailable
            : deviceCapabilitySnapshot.hasRequiredPolicyEvidence
            ? RuntimeAvailability.ready
            : RuntimeAvailability.degraded,
        onDeviceInference: RuntimeAvailability.unavailable,
      ),
      config: config,
      accountGateway: accountGateway,
      accountProfileProvisioning: accountProfileProvisioning,
      guestSessionService: guestSessionService,
      guestUpgradeHandoff: noOpGuestUpgradeHandoff,
      buildInfo: const AppBuildInfo.fromEnvironment(),
      progressRepository: progressRepository,
      progressSyncService: progressSyncService,
      purchaseRemoteWriter: purchaseRemoteWriter,
      learningDependencies: learningDependencies,
      deviceCapabilitySnapshot: deviceCapabilitySnapshot,
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

  Future<ProgressRepository?> _loadProgressRepository() async {
    try {
      return await loadProgressRepository();
    } catch (_) {
      return null;
    }
  }

  Future<LearningDependencies?> _loadLearningDependencies(
    AppConfig? config,
  ) async {
    try {
      return await loadLearningDependencies(config, featureFlags);
    } catch (_) {
      return null;
    }
  }

  Future<DeviceCapabilitySnapshot?> _loadDeviceCapabilitySnapshot() async {
    try {
      return await deviceCapabilityProbe.snapshot();
    } catch (_) {
      return null;
    }
  }
}

AccountGateway _unavailableAccountGateway() =>
    const _UnavailableAccountGateway();

AccountProfileProvisioning _unavailableAccountProfileProvisioning() =>
    const UnavailableAccountProfileProvisioner();

final class _UnavailableAccountGateway implements AccountGateway {
  const _UnavailableAccountGateway();

  @override
  AccountSession? get currentSession => null;

  @override
  Stream<AccountSession?> authStateChanges() =>
      Stream<AccountSession?>.value(null);

  @override
  Future<void> applyVerificationCode(String code) => _unavailable();

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) => _unavailable();

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) => _unavailable();

  @override
  Future<AccountSession> createAccount({
    required String email,
    required String password,
  }) => _unavailable();

  @override
  Future<void> requestPasswordReset(String email) => _unavailable();

  @override
  Future<AccountSession?> reloadSession() => _unavailable();

  @override
  Future<void> sendVerificationEmail() => _unavailable();

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => _unavailable();

  @override
  Future<void> signOut() => _unavailable();

  @override
  Future<GuestUpgradeResult> upgradeAnonymous({
    required String email,
    required String password,
  }) => _unavailable();

  @override
  Future<String> verifyPasswordResetCode(String code) => _unavailable();

  Future<T> _unavailable<T>() =>
      Future<T>.error(const AccountOperationException('account-unavailable'));
}
