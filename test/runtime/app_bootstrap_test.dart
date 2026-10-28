import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/account/account_models.dart';
import 'package:vocab_learning_app/device/device_capability_models.dart';
import 'package:vocab_learning_app/device/device_capability_probe.dart';
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

class _StubDeviceCapabilityProbe implements DeviceCapabilityProbe {
  _StubDeviceCapabilityProbe(this.result);

  final Future<DeviceCapabilitySnapshot> Function() result;
  int invocationCount = 0;

  @override
  Future<DeviceCapabilitySnapshot> snapshot() {
    invocationCount++;
    return result();
  }
}

DeviceCapabilitySnapshot _validDeviceSnapshot() => DeviceCapabilitySnapshot(
  sdkInt: 35,
  primaryAbi: 'arm64-v8a',
  memoryClassMb: 512,
  availableMemoryMb: 3072,
  freeStorageBytes: 4294967296,
  lowMemory: false,
  batterySaverEnabled: false,
  thermalState: DeviceThermalState.nominal,
  gpuApiCandidate: true,
);

DeviceCapabilitySnapshot _partialDeviceSnapshot() => DeviceCapabilitySnapshot(
  sdkInt: 35,
  primaryAbi: 'arm64-v8a',
  memoryClassMb: 512,
  availableMemoryMb: null,
  freeStorageBytes: 4294967296,
  lowMemory: false,
  batterySaverEnabled: null,
  thermalState: DeviceThermalState.nominal,
  gpuApiCandidate: true,
);

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
    test(
      'production composition does not access Firebase before initialization',
      () {
        expect(AppBootstrap.production, returnsNormally);
      },
    );

    test('retains the repository returned by the injected loader', () async {
      final expectedRepository = _StubProgressRepository();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
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

    test(
      'retains the trusted purchase writer without enabling the shop',
      () async {
        final purchaseWriter = _StubPurchaseRemoteWriter();
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
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
      },
    );

    test(
      'repository loader failure returns null without leaking details',
      () async {
        const sentinel = 'LOCAL-STORAGE-CREDENTIAL-7c9f3a';
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
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
        loadConfig: () => expectedConfig,
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
    });

    test(
      'marks a complete capability profile ready but inference unavailable',
      () async {
        final expectedSnapshot = _validDeviceSnapshot();
        final probe = _StubDeviceCapabilityProbe(() async => expectedSnapshot);
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          deviceCapabilityProbe: probe,
        );

        final dependencies = await bootstrap.initialize();

        expect(probe.invocationCount, 1);
        expect(
          identical(dependencies.deviceCapabilitySnapshot, expectedSnapshot),
          isTrue,
        );
        expect(
          dependencies.runtimeStatus.deviceCapabilities,
          RuntimeAvailability.ready,
        );
        expect(
          dependencies.runtimeStatus.onDeviceInference,
          RuntimeAvailability.unavailable,
        );
        expect(dependencies.runtimeStatus.isFullyReady, isFalse);
      },
    );

    test('marks a partial capability profile degraded', () async {
      final expectedSnapshot = _partialDeviceSnapshot();
      final probe = _StubDeviceCapabilityProbe(() async => expectedSnapshot);
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        deviceCapabilityProbe: probe,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.deviceCapabilitySnapshot, expectedSnapshot),
        isTrue,
      );
      expect(
        dependencies.runtimeStatus.deviceCapabilities,
        RuntimeAvailability.degraded,
      );
      expect(
        dependencies.runtimeStatus.onDeviceInference,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.isFullyReady, isFalse);
      expect(dependencies.runtimeStatus.isCoreLearningAvailable, isTrue);
    });

    test(
      'device capability unavailability does not block other startup paths',
      () async {
        final expectedRepository = _StubProgressRepository();
        final probe = _StubDeviceCapabilityProbe(
          () async =>
              throw const DeviceCapabilityUnavailable.channelUnavailable(),
        );
        final bootstrap = AppBootstrap(
          initializeFirebase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          loadProgressRepository: () async => expectedRepository,
          deviceCapabilityProbe: probe,
        );

        final dependencies = await bootstrap.initialize();

        expect(probe.invocationCount, 1);
        expect(dependencies.deviceCapabilitySnapshot, isNull);
        expect(
          dependencies.runtimeStatus.deviceCapabilities,
          RuntimeAvailability.unavailable,
        );
        expect(
          dependencies.runtimeStatus.onDeviceInference,
          RuntimeAvailability.unavailable,
        );
        expect(dependencies.runtimeStatus.isFullyReady, isFalse);
        expect(dependencies.runtimeStatus.isCoreLearningAvailable, isTrue);
        expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
        expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
        expect(
          identical(dependencies.progressRepository, expectedRepository),
          isTrue,
        );
        expect(dependencies.config, isNotNull);
      },
    );

    test('redacts unexpected device probe exception details', () async {
      const sentinel = 'NATIVE-DEVICE-PROBE-SECRET-7c9f3a';
      final probe = _StubDeviceCapabilityProbe(
        () async => throw StateError(sentinel),
      );
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        deviceCapabilityProbe: probe,
      );

      final dependencies = await bootstrap.initialize();
      final rendered = <String>[
        dependencies.toString(),
        dependencies.runtimeStatus.toString(),
        dependencies.runtimeStatus.deviceCapabilities.name,
        dependencies.runtimeStatus.onDeviceInference.name,
        '${dependencies.deviceCapabilitySnapshot}',
      ];

      expect(probe.invocationCount, 1);
      expect(dependencies.deviceCapabilitySnapshot, isNull);
      expect(
        dependencies.runtimeStatus.deviceCapabilities,
        RuntimeAvailability.unavailable,
      );
      expect(
        dependencies.runtimeStatus.onDeviceInference,
        RuntimeAvailability.unavailable,
      );
      for (final value in rendered) {
        expect(value, isNot(contains(sentinel)));
      }
    });

    test('records Firebase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError('firebase-down'),
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(dependencies.config, isNotNull);
    });

    test('records config failure with null config', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
    });

    test('represents multiple failures independently', () async {
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError('firebase-down'),
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
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
      const configSentinel = 'CONFIG-SECRET-7c9f3a';
      final bootstrap = AppBootstrap(
        initializeFirebase: () async => throw StateError(firebaseSentinel),
        loadConfig: () => throw const AppConfigException(configSentinel),
        guestSessionService: _StubGuestSessionService(),
      );

      final dependencies = await bootstrap.initialize();
      final rendered = <String>[
        dependencies.toString(),
        dependencies.runtimeStatus.toString(),
        dependencies.runtimeStatus.firebase.name,
        dependencies.runtimeStatus.backends.name,
        '${dependencies.config}',
        dependencies.guestSessionService.toString(),
      ];

      for (final value in rendered) {
        for (final sentinel in <String>[firebaseSentinel, configSentinel]) {
          expect(value, isNot(contains(sentinel)));
        }
      }
    });

    test('retains exact injected GuestSessionService identity', () async {
      final guestSessionService = _StubGuestSessionService();
      final bootstrap = AppBootstrap(
        initializeFirebase: () async {},
        loadConfig: _validConfig,
        guestSessionService: guestSessionService,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.guestSessionService, guestSessionService),
        isTrue,
      );
    });

    test('explicitly composes the Plan 2 no-op guest handoff', () async {
      final dependencies = await AppBootstrap(
        initializeFirebase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      ).initialize();

      expect(
        identical(dependencies.guestUpgradeHandoff, noOpGuestUpgradeHandoff),
        isTrue,
      );
    });
  });
}
