import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';
import '../learning/association_prompt.dart';
import '../learning/associative_memory.dart';
import '../learning/associative_reading_coordinator.dart';
import '../learning/reading_content_source.dart';
import '../learning/secure_id_generator.dart';
import '../learning/storage/drift_learning_repository.dart';
import '../learning/storage/learning_database_factory.dart';
import '../learning/vocabulary_mixer.dart';
import '../progress/local_progress_repository.dart';
import '../progress/progress_repository.dart';
import '../services/guest_session_service.dart';
import 'app_build_info.dart';
import 'app_dependencies.dart';
import 'app_runtime_status.dart';
import 'learning_dependencies.dart';
import 'learning_feature_flags.dart';
import 'supabase_client_config.dart';

typedef RuntimeInitializer = Future<void> Function();
typedef AppConfigLoader = AppConfig Function();
typedef ProgressRepositoryLoader = Future<ProgressRepository> Function();

// Public client identifiers, not server credentials. The Supabase URL keeps a
// public default, but the publishable key must be supplied per build.
const _productionSupabaseUrl = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_URL',
  defaultValue: 'https://jkiyfnlegmhodyxpfwpc.supabase.co',
);
const _productionSupabasePublishableKey = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_PUBLISHABLE_KEY',
);

bool _productionSupabaseInitialized = false;

Future<void> _initializeFirebaseProduction() async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
  }
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

Future<ProgressRepository> _loadProgressRepositoryProduction() async {
  return LocalProgressRepository(await SharedPreferences.getInstance());
}

Future<LearningDependencies> _loadLearningDependenciesProduction() async {
  final database = await LearningDatabaseFactory().open();
  final repository = DriftLearningRepository(database);
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
      contentSource: OfflineCuratedReadingContentSource(),
      mixer: const VersionedVocabularyMixer(),
      idGenerator: CryptographicIdGenerator(),
      clock: DateTime.now,
    ),
    close: database.close,
  );
}

final class AppBootstrap {
  const AppBootstrap({
    required this.initializeFirebase,
    required this.initializeSupabase,
    required this.loadConfig,
    required this.guestSessionService,
    this.loadProgressRepository = _loadProgressRepositoryProduction,
    this.featureFlags = const LearningFeatureFlags.fromEnvironment(),
    this.loadLearningDependencies = _loadLearningDependenciesProduction,
  });

  factory AppBootstrap.production() {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      initializeSupabase: _initializeSupabaseProduction,
      loadConfig: AppConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
      loadProgressRepository: _loadProgressRepositoryProduction,
    );
  }

  final RuntimeInitializer initializeFirebase;
  final RuntimeInitializer initializeSupabase;
  final AppConfigLoader loadConfig;
  final GuestSessionService guestSessionService;
  final ProgressRepositoryLoader loadProgressRepository;
  final LearningFeatureFlags featureFlags;
  final LearningDependenciesLoader loadLearningDependencies;

  Future<AppDependencies> initialize() async {
    final firebase = await _availability(initializeFirebase);
    final supabase = await _availability(initializeSupabase);
    final config = _loadConfig();
    final progressRepository = await _loadProgressRepository();
    final learningDependencies = featureFlags.associativeReadingEnabled
        ? await _loadLearningDependencies()
        : null;

    return AppDependencies(
      runtimeStatus: AppRuntimeStatus(
        firebase: firebase,
        supabase: supabase,
        backends: config == null
            ? RuntimeAvailability.unavailable
            : RuntimeAvailability.ready,
      ),
      config: config,
      guestSessionService: guestSessionService,
      buildInfo: const AppBuildInfo.fromEnvironment(),
      progressRepository: progressRepository,
      learningDependencies: learningDependencies,
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

  Future<LearningDependencies?> _loadLearningDependencies() async {
    try {
      return await loadLearningDependencies();
    } catch (_) {
      return null;
    }
  }
}
