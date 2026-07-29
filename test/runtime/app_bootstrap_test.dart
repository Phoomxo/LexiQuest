import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/progress/progress_remote_writer.dart';
import 'package:vocab_learning_app/progress/progress_repository.dart';
import 'package:vocab_learning_app/progress/purchase_remote_writer.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

class _StubGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionFailed(GuestSessionFailure.unknown);
  }
}

class _StubProgressRepository implements ProgressRepository {
  @override
  Future<void> acknowledgeSession(String sessionId) async {}

  @override
  Future<List<ProgressSession>> pendingSessions() async => const [];

  @override
  Future<ProgressSnapshot> readSnapshot() async => const ProgressSnapshot(
    totalPoints: 0,
    totalCorrectAnswers: 0,
    totalWrongAnswers: 0,
    gamesPlayed: 0,
  );

  @override
  Future<void> recordSession(ProgressSession session) async {}
}

class _StubProgressRemoteWriter implements ProgressRemoteWriter {
  @override
  Future<ProgressRemoteResult> recordProgressSession(
    ProgressSession session,
  ) async {
    return const ProgressRemoteAccepted(duplicate: false);
  }
}

class _StubPurchaseRemoteWriter implements PurchaseRemoteWriter {
  @override
  Future<PurchaseRemoteResult> purchaseItem(String productId) async {
    return const PurchaseRemoteAccepted(
      alreadyOwned: false,
      remainingPoints: 0,
    );
  }
}

AppConfig _validConfig() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  aiApiUrl: 'https://ai.example.com',
  isDebug: false,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AppBootstrap.initialize', () {
    test('retains the repository returned by the injected loader', () async {
      final expectedRepository = _StubProgressRepository();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        loadProgressRepository: () async => expectedRepository,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.progressRepository, expectedRepository),
        isTrue,
      );
    });

    test(
      'composes one-shot progress synchronization when both ports exist',
      () async {
        final repository = _StubProgressRepository();
        final remoteWriter = _StubProgressRemoteWriter();
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          loadProgressRepository: () async => repository,
          progressRemoteWriter: remoteWriter,
        );

        final dependencies = await bootstrap.initialize();

        expect(dependencies.progressSyncService, isNotNull);
        expect(
          identical(dependencies.progressSyncService!.repository, repository),
          isTrue,
        );
        expect(
          identical(
            dependencies.progressSyncService!.remoteWriter,
            remoteWriter,
          ),
          isTrue,
        );
      },
    );

    test('retains the trusted purchase writer without enabling the shop', () async {
      final purchaseWriter = _StubPurchaseRemoteWriter();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        purchaseRemoteWriter: purchaseWriter,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.purchaseRemoteWriter, purchaseWriter),
        isTrue,
      );
      expect(
        dependencies.remoteEconomyPolicy.shopAndPurchasesEnabled,
        isFalse,
      );
    });

    test(
      'repository loader failure returns null without leaking details',
      () async {
        const sentinel = 'LOCAL-STORAGE-CREDENTIAL-7c9f3a';
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          loadProgressRepository: () async => throw StateError(sentinel),
        );

        final dependencies = await bootstrap.initialize();

        expect(dependencies.progressRepository, isNull);
        expect(dependencies.toString(), isNot(contains(sentinel)));
      },
    );

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
