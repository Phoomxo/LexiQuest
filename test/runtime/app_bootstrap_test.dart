import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _StubGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionFailed(GuestSessionFailure.unknown);
  }
}

AppConfig _validConfig() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  aiApiUrl: 'https://ai.example.com',
  isDebug: false,
);

void main() {
  group('AppBootstrap.initialize', () {
    test('marks all components ready and retains the exact config', () async {
      final expectedConfig = _validConfig();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => expectedConfig,
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
    });

    test('records Firebase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(dependencies.config, isNotNull);
    });

    test('records Supabase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.supabase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
    });

    test('records config failure with null config', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
    });

    test('represents multiple failures independently', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(
        dependencies.runtimeStatus.supabase,
        RuntimeAvailability.unavailable,
      );
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
    });

    test('never leaks exception credential sentinels', () async {
      const firebaseSentinel = 'FIREBASE-SECRET-7c9f3a';
      const supabaseSentinel = 'SUPABASE-SECRET-7c9f3a';
      const configSentinel = 'CONFIG-SECRET-7c9f3a';
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError(firebaseSentinel),
        initializeSupabase: () async => throw StateError(supabaseSentinel),
        loadConfig: () => throw const AppConfigException(configSentinel),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();
      final rendered = <String>[
        dependencies.toString(),
        dependencies.runtimeStatus.toString(),
        dependencies.runtimeStatus.firebase.name,
        dependencies.runtimeStatus.supabase.name,
        dependencies.runtimeStatus.backends.name,
        '${dependencies.config}',
        dependencies.guestSessionService.toString(),
      ];

      for (final value in rendered) {
        for (final sentinel in <String>[
          firebaseSentinel,
          supabaseSentinel,
          configSentinel,
        ]) {
          expect(value, isNot(contains(sentinel)));
        }
      }
    });

    test('retains exact injected GuestSessionService identity', () async {
      final guestSessionService = _StubGuestSessionService();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: guestSessionService,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.guestSessionService, guestSessionService),
        isTrue,
      );
    });
  });
}
