import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_download_manager.dart';
import 'package:vocab_learning_app/voice/standard_voice_pack_manifest.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';
import 'package:vocab_learning_app/voice/voice_service_factory.dart';

class _StubGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async {
    return const GuestSessionFailed(GuestSessionFailure.unknown);
  }
}

final class _SuccessfulGuestSessionService implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionStarted(uid: 'anonymous-bootstrap-user');
}

AppConfig _validConfig() => AppConfig.fromValues(
  voiceApiUrl: 'https://voice.example.com',
  aiApiUrl: 'https://ai.example.com',
  isDebug: false,
);

AppDatabase _testDatabase() {
  final database = AppDatabase(NativeDatabase.memory());
  addTearDown(database.close);
  return database;
}

ManagedVoiceProvider _testVoiceFactory({
  AppConfig? config,
  InstalledStandardVoicePack? installedVoicePack,
}) => _RecordingManagedVoiceProvider(config);

void main() {
  group('AppBootstrap.initialize', () {
    for (final testCase in <(AppEntryMode, AppRoute)>[
      (AppEntryMode.signedOut, AppRoute.login),
      (AppEntryMode.guest, AppRoute.home),
    ]) {
      test(
        'resolves ${testCase.$1.name} entry to ${testCase.$2.name}',
        () async {
          final bootstrap = AppBootstrap(
            createDatabase: _testDatabase,
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            voiceFactory: _testVoiceFactory,
            entryStateStoreFactory: () async =>
                _BootstrapEntryStateStore(testCase.$1),
          );

          final dependencies = await bootstrap.initialize();

          expect(dependencies.initialRoute, testCase.$2);
        },
      );
    }

    test('marks all components ready and retains the exact config', () async {
      final expectedConfig = _validConfig();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => expectedConfig,
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
      expect(dependencies.deviceModels, isNotNull);
      expect(dependencies.objectScanner, isNotNull);
      expect(dependencies.speechPractice, isNotNull);
      expect(dependencies.aiTutor, isNotNull);
      expect(dependencies.aiUsage, isNotNull);
    });

    test(
      'creates the active local owner before exposing dependencies',
      () async {
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          voiceFactory: _testVoiceFactory,
        );

        final dependencies = await bootstrap.initialize();
        final owners = await database.select(database.localOwners).get();

        expect(dependencies.localOwners, isNotNull);
        expect(owners, hasLength(1));
        expect(owners.single.isActive, isTrue);
      },
    );

    test('records Firebase failure and still returns', () async {
      final database = _testDatabase();
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.localData, RuntimeAvailability.ready);
      expect(identical(dependencies.database, database), isTrue);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(dependencies.config, isNotNull);
    });

    test('records Supabase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
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
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
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
        createDatabase: _testDatabase,
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
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
        createDatabase: _testDatabase,
        initializeFirebase: () async => throw StateError(firebaseSentinel),
        initializeSupabase: () async => throw StateError(supabaseSentinel),
        loadConfig: () => throw const AppConfigException(configSentinel),
        guestSessionService: _StubGuestSessionService(),
        voiceFactory: _testVoiceFactory,
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
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: guestSessionService,
        voiceFactory: _testVoiceFactory,
      );

      final dependencies = await bootstrap.initialize();

      expect(
        identical(dependencies.guestSessionService, guestSessionService),
        isTrue,
      );
    });

    test(
      'production composition binds anonymous auth to local ownership',
      () async {
        final database = _testDatabase();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _SuccessfulGuestSessionService(),
          bindGuestOwnership: true,
          voiceFactory: _testVoiceFactory,
          entryStateStoreFactory: () async =>
              _BootstrapEntryStateStore(AppEntryMode.signedOut),
        );

        final dependencies = await bootstrap.initialize();
        final result = await dependencies.guestSessionService.start();
        LocalOwner? owner;
        for (var attempt = 0; attempt < 20; attempt++) {
          owner = await (database.select(
            database.localOwners,
          )..where((row) => row.isActive.equals(true))).getSingle();
          if (owner.firebaseUid == 'anonymous-bootstrap-user') {
            break;
          }
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }

        expect(result, isA<GuestSessionStarted>());
        expect(owner?.firebaseUid, 'anonymous-bootstrap-user');
        expect(owner?.accountState, 'firebaseBound');
      },
    );

    test('composes local mutations into the shared sync trigger', () async {
      final gateway = _BootstrapSyncGateway();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        syncGatewayFactory: () => gateway,
        voiceFactory: _testVoiceFactory,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.vocabulary!.createCategory('Travel');
      await Future<void>.delayed(Duration.zero);

      expect(dependencies.syncTrigger, isNotNull);
      expect(gateway.policyFetches, 1);
    });

    test(
      'shares one managed voice service built from the injected factory',
      () async {
        final expectedConfig = _validConfig();
        final installedPack = InstalledStandardVoicePack(
          rootPath: 'test-pack',
          manifest: StandardVoicePackManifest.fromJson({
            'schemaVersion': 1,
            'packId': 'core-en',
            'version': '1.0.0',
            'locale': 'en',
            'voiceId': 'teacher_female',
            'engine': 'voxcpm2',
            'modelVersion': '2.0.3',
            'license': 'Apache-2.0',
            'licenseUri': 'https://github.com/OpenBMB/VoxCPM/blob/main/LICENSE',
            'minimumAppVersion': '1.0.0+1',
            'baseUri': 'https://assets.example.com/',
            'generatedAtUtc': '2026-07-31T00:00:00Z',
            'totalBytes': 1,
            'files': [
              {
                'contentId': 'word-cat',
                'normalizedTextSha256':
                    '48735c4fae42d1501164976afec76730b9e5fe467f680bdd8daff4bb77674045',
                'relativePath': 'cat.wav',
                'byteSize': 1,
                'sha256':
                    'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa',
              },
            ],
          }),
          activeMarkerPath: 'test-pack.active',
        );
        final voiceFactory = _RecordingVoiceFactory(expectedConfig);
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: () => expectedConfig,
          guestSessionService: _StubGuestSessionService(),
          voiceFactory: voiceFactory.call,
          installedVoicePackLoader: () async => installedPack,
        );

        final dependencies = await bootstrap.initialize();

        expect(voiceFactory.created, hasLength(1));
        expect(
          identical(voiceFactory.created.single.config, expectedConfig),
          isTrue,
        );
        expect(
          identical(dependencies.voice, voiceFactory.created.single.voice),
          isTrue,
        );
        expect(
          identical(voiceFactory.created.single.installedPack, installedPack),
          isTrue,
        );

        await dependencies.dispose();
        await dependencies.dispose();

        expect(voiceFactory.created.single.voice.disposeCalls, 1);
      },
    );

    test(
      'centralized dispose still closes the database when voice dispose throws '
      'and rethrows the original voice error',
      () async {
        final database = _testDatabase();
        // The injected provider fails to dispose. Because AppBootstrap builds a
        // single centralized disposeResources closure, this regression test
        // guards the teardown ordering contract: the database must still be
        // closed and the original voice error must propagate.
        final voiceError = StateError('voice-dispose-failed');
        final voiceFactory = _RecordingVoiceFactory(
          _validConfig(),
          disposeError: voiceError,
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          voiceFactory: voiceFactory.call,
        );

        final dependencies = await bootstrap.initialize();

        // dispose must rethrow the original voice error, not swallow it.
        await expectLater(dependencies.dispose(), throwsA(same(voiceError)));
        expect(voiceFactory.created.single.voice.disposeCalls, 1);

        // Prove the AppDatabase connection is closed: a bounded read against a
        // real table must now fail because drift rejects queries once the
        // underlying connection has been closed.
        await expectLater(
          database.select(database.localOwners).get(),
          throwsA(isA<StateError>()),
        );
      },
    );
  });
}

final class _BootstrapEntryStateStore implements AppEntryStateStore {
  _BootstrapEntryStateStore(this.mode);

  AppEntryMode mode;

  @override
  Future<AppEntryMode> read() async => mode;

  @override
  Future<void> markGuest() async => mode = AppEntryMode.guest;

  @override
  Future<void> clear() async => mode = AppEntryMode.signedOut;
}

final class _BootstrapSyncGateway implements SyncGateway {
  int policyFetches = 0;

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
    policyFetches += 1;
    final now = DateTime.now().toUtc();
    return CloudSyncPolicy(
      enabled: true,
      source: CloudSyncPolicySource.remote,
      fetchedAtUtc: now,
      expiresAtUtc: now.add(const Duration(minutes: 15)),
    );
  }

  @override
  Future<PullPage> pull({
    required String firebaseUid,
    required SyncCollection collection,
    required SyncCursor? after,
    required int limit,
  }) async => PullPage(changes: const [], nextCursor: after, hasMore: false);

  @override
  Future<PushResult> push(PushMutation mutation) {
    throw UnimplementedError();
  }
}

/// Compact fake for the planned [ManagedVoiceProvider] interface. Implements the
/// real [VoiceProvider] methods with native no-op results and records every
/// [dispose] invocation so lifecycle tests can assert idempotent teardown.
///
/// Holds a nullable [AppConfig] because [AppBootstrap] may resolve `null`
/// (for example, when [loadConfig] fails), and the no-op factory must still
/// build a provider without touching Firebase or audio plugins.
final class _RecordingManagedVoiceProvider implements ManagedVoiceProvider {
  _RecordingManagedVoiceProvider(this.config, {this.disposeError});

  final AppConfig? config;
  int disposeCalls = 0;

  /// Optional error thrown by [dispose] after recording the call, so teardown
  /// regression tests can assert centralized dispose ordering under failure.
  final Object? disposeError;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    final error = disposeError;
    if (error != null) {
      throw error;
    }
  }
}

class _RecordingVoiceFactory {
  _RecordingVoiceFactory(this._expectedConfig, {this.disposeError});

  final AppConfig _expectedConfig;
  final Object? disposeError;
  final List<
    ({
      AppConfig config,
      InstalledStandardVoicePack? installedPack,
      _RecordingManagedVoiceProvider voice,
    })
  >
  created = [];

  _RecordingManagedVoiceProvider call({
    AppConfig? config,
    InstalledStandardVoicePack? installedVoicePack,
  }) {
    final resolvedConfig = config ?? _expectedConfig;
    final voice = _RecordingManagedVoiceProvider(
      resolvedConfig,
      disposeError: disposeError,
    );
    created.add((
      config: resolvedConfig,
      installedPack: installedVoicePack,
      voice: voice,
    ));
    return voice;
  }
}
