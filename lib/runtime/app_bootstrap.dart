import 'package:firebase_core/firebase_core.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../config/app_config.dart';
import '../firebase_options.dart';
import '../services/guest_session_service.dart';
import 'app_dependencies.dart';
import 'app_runtime_status.dart';

typedef RuntimeInitializer = Future<void> Function();
typedef AppConfigLoader = AppConfig Function();

// Public client identifiers, not server credentials. They remain overrideable
// so research, staging, and production builds can target separate projects.
const _productionSupabaseUrl = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_URL',
  defaultValue: 'https://anyiuoqnuimtjlbjhwuf.supabase.co',
);
const _productionSupabasePublishableKey = String.fromEnvironment(
  'LEXIQUEST_SUPABASE_PUBLISHABLE_KEY',
  defaultValue:
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFueWl1b3FudWltdGpsYmpod3VmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3MzY1ODMyMzIsImV4cCI6MjA1MjE1OTIzMn0.sHp532XD1L_Xr5X9eiRMCZqpgV2LA5RwQoOw3df6gDg',
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
  await Supabase.initialize(
    url: _productionSupabaseUrl,
    publishableKey: _productionSupabasePublishableKey,
  );
  _productionSupabaseInitialized = true;
}

final class AppBootstrap {
  const AppBootstrap({
    required this.initializeFirebase,
    required this.initializeSupabase,
    required this.loadConfig,
    required this.guestSessionService,
  });

  factory AppBootstrap.production() {
    return AppBootstrap(
      initializeFirebase: _initializeFirebaseProduction,
      initializeSupabase: _initializeSupabaseProduction,
      loadConfig: AppConfig.fromEnvironment,
      guestSessionService: FirebaseGuestSessionService.production(),
    );
  }

  final RuntimeInitializer initializeFirebase;
  final RuntimeInitializer initializeSupabase;
  final AppConfigLoader loadConfig;
  final GuestSessionService guestSessionService;

  Future<AppDependencies> initialize() async {
    final firebase = await _availability(initializeFirebase);
    final supabase = await _availability(initializeSupabase);
    final config = _loadConfig();

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
