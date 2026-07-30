import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';

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

void main() {
  group('AppBootstrap.initialize', () {
    test('marks all components ready and retains the exact config', () async {
      final expectedConfig = _validConfig();
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
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
        );

        final dependencies = await bootstrap.initialize();
        final result = await dependencies.guestSessionService.start();
        final owner = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();

        expect(result, isA<GuestSessionStarted>());
        expect(owner.firebaseUid, 'anonymous-bootstrap-user');
        expect(owner.accountState, 'firebaseBound');
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
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.vocabulary!.createCategory('Travel');
      await Future<void>.delayed(Duration.zero);

      expect(dependencies.syncTrigger, isNotNull);
      expect(gateway.policyFetches, 1);
    });
  });
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
