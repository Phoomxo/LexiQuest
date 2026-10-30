import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_dependencies.dart';
import 'package:vocab_learning_app/features/research/application/study_runtime.dart';
import 'package:vocab_learning_app/features/learning/application/learning_use_cases.dart';
import 'package:vocab_learning_app/features/learning/data/learning_session_lifecycle_observer.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/features/vocabulary/data/drift_saved_words_repository.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/registries/consent_registry.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/account_deletion/application/account_deletion_use_cases.dart';
import 'package:vocab_learning_app/features/account_deletion/data/drift_local_account_deletion_gateway.dart';
import 'package:vocab_learning_app/features/account_deletion/domain/account_deletion_contracts.dart';
import 'package:vocab_learning_app/features/identity/domain/local_owner_repository.dart';
import 'package:vocab_learning_app/features/identity/data/drift_owner_write_coordinator.dart';
import 'package:vocab_learning_app/features/gemini/domain/gemini_contracts.dart';
import 'package:vocab_learning_app/features/research/domain/research_operation_authorizer.dart';
import 'package:vocab_learning_app/features/research/domain/research_runtime_availability.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';

import '../support/fake_owner_write_coordinator.dart';

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
  test(
    'saved words compose on the real local database without backend or sync work',
    () async {
      final database = _testDatabase();
      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async =>
            throw StateError('synthetic offline Firebase'),
        initializeSupabase: () async =>
            throw StateError('synthetic offline Supabase'),
        loadConfig: () =>
            throw const AppConfigException('synthetic unavailable config'),
        guestSessionService: _StubGuestSessionService(),
        cloudSyncEnabled: false,
      ).initialize();
      addTearDown(dependencies.dispose);
      expect(dependencies.savedWords, isNotNull);
      expect(
        dependencies.savedWords!.repository,
        isA<DriftSavedWordsRepository>(),
      );
      expect(
        (dependencies.savedWords!.repository as DriftSavedWordsRepository)
            .database,
        same(database),
      );
      final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
      final category = await dependencies.vocabulary!.createCategory(
        'Synthetic saved category',
      );
      final word = await dependencies.vocabulary!.createWord(
        CreateWordCommand(
          categoryId: category.id,
          spelling: 'station',
          meaning: 'synthetic station',
          partOfSpeech: 'noun',
        ),
      );
      Future<Map<String, List<String>>> effects() async => {
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'srs_states',
          'points_ledger_entries',
          'reward_transactions',
          'achievement_unlocks',
          'quest_instances',
          'quest_objective_progress',
          'streak_states',
          'research_consents',
          'experiment_assignments',
          'research_participation_permits',
          'motivation_measurement_runs',
          'motivation_responses',
          'measurement_opportunities',
          'assessment_runs',
          'events_v2',
          'outbox_operations',
        ])
          table: [
            for (final row
                in await database
                    .customSelect('SELECT * FROM $table ORDER BY 1')
                    .get())
              jsonEncode(row.data),
          ],
      };
      final before = await effects();
      final snapshot = await dependencies.savedWords!
          .watchOwner(owner.id)
          .first;
      final command = dependencies.savedWords!.prepareSet(
        state: snapshot.stateFor(word.id),
        desiredIsSaved: true,
      );
      final result = await dependencies.savedWords!.apply(command);
      expect(result.state.isSaved, isTrue);
      expect(result.state.localRevision, 1);
      expect(await effects(), before);
      final saved = await dependencies.savedWords!.watchOwner(owner.id).first;
      expect(saved.savedItems.single.word!.spelling, 'station');
    },
  );

  test(
    'composes account deletion only behind its explicit production flag',
    () async {
      var calls = 0;
      final newRequestFlags = <bool>[];
      Future<AccountDeletionComposition> compose({
        required AppDatabase database,
        required LocalOwnerRepository owners,
        required AppConfig config,
        required AccountDeletionSessionReader currentSession,
        required Future<void> Function() signOut,
        required bool newRequestsEnabled,
      }) async {
        calls++;
        newRequestFlags.add(newRequestsEnabled);
        return AccountDeletionComposition(
          useCases: _deletionUseCases(owners, enabled: newRequestsEnabled),
          dispose: () async {},
        );
      }

      final disabled = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => _StartupGateway(
          const AccountSession(
            uid: 'firebase-user',
            email: 'learner@example.test',
            isAnonymous: false,
            emailVerified: true,
          ),
        ),
        accountDeletionFactory: compose,
      ).initialize();
      addTearDown(disabled.dispose);
      expect(disabled.accountDeletion?.enabled, isFalse);
      expect(calls, 1);

      final capabilityMissing = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => _StartupGateway(
          const AccountSession(
            uid: 'firebase-user',
            email: 'learner@example.test',
            isAnonymous: false,
            emailVerified: true,
          ),
        ),
        accountDeletionEnabled: true,
        accountDeletionFactory: compose,
      ).initialize();
      addTearDown(capabilityMissing.dispose);
      expect(capabilityMissing.accountDeletion?.enabled, isFalse);
      expect(calls, 2);

      final enabled = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => _StartupGateway(
          const AccountSession(
            uid: 'firebase-user',
            email: 'learner@example.test',
            isAnonymous: false,
            emailVerified: true,
          ),
        ),
        accountDeletionEnabled: true,
        accountDeletionServerExportAuthorityConfigured: true,
        accountDeletionRecoveryRetention: const Duration(days: 7),
        accountDeletionFactory: compose,
      ).initialize();
      addTearDown(enabled.dispose);
      expect(enabled.accountDeletion, isNotNull);
      expect(enabled.accountDeletion?.enabled, isTrue);
      expect(calls, 3);
      expect(newRequestFlags, [false, false, true]);
    },
  );

  test(
    'recovers an Auth-deleted account before startup reconciliation',
    () async {
      final database = _testDatabase();
      await database.customStatement(
        "INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) VALUES ('owner-a', 'firebase-user', 1, 1)",
      );
      final events = <String>[];
      final gateway = _StartupGateway(null)
        ..onRead = () => events.add('reconcile');
      final journal = _BootstrapDeletionJournal(_pendingDeletionEntry());
      final cloud = _BootstrapDeletionCloud()
        ..onCall = () => events.add('recover');

      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => gateway,
        accountDeletionFactory:
            ({
              required database,
              required owners,
              required config,
              required currentSession,
              required signOut,
              required newRequestsEnabled,
            }) async => _bootstrapDeletionComposition(
              database: database,
              owners: owners,
              currentSession: currentSession,
              signOut: signOut,
              journal: journal,
              cloud: cloud,
              newRequestsEnabled: newRequestsEnabled,
              onLocalPurge: () => events.add('local-purge'),
            ),
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(events.take(2), ['recover', 'local-purge']);
      expect(
        events.indexOf('reconcile'),
        greaterThan(events.indexOf('local-purge')),
      );
      final active = await dependencies.localOwners!.getOrCreateActiveOwner();
      expect(active.firebaseUid, isNull);
      expect(active.id, isNot('owner-a'));
      expect(dependencies.accountDeletion?.enabled, isFalse);
    },
  );

  test(
    'failed startup recovery preserves the bound owner and remains retryable',
    () async {
      final database = _testDatabase();
      await database.customStatement(
        "INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) VALUES ('owner-a', 'firebase-user', 1, 1)",
      );
      final events = <String>[];
      final gateway = _StartupGateway(null)
        ..onRead = () => events.add('reconcile');
      final journal = _BootstrapDeletionJournal(_pendingDeletionEntry());
      final cloud = _BootstrapDeletionCloud()
        ..failure = StateError('synthetic recovery outage')
        ..onCall = () => events.add('recover');

      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => gateway,
        accountDeletionEnabled: true,
        accountDeletionServerExportAuthorityConfigured: true,
        accountDeletionRecoveryRetention: const Duration(days: 7),
        accountDeletionFactory:
            ({
              required database,
              required owners,
              required config,
              required currentSession,
              required signOut,
              required newRequestsEnabled,
            }) async => _bootstrapDeletionComposition(
              database: database,
              owners: owners,
              currentSession: currentSession,
              signOut: signOut,
              journal: journal,
              cloud: cloud,
              newRequestsEnabled: newRequestsEnabled,
              onLocalPurge: () => events.add('local-purge'),
            ),
      ).initialize();
      addTearDown(dependencies.dispose);

      var active = await dependencies.localOwners!.getOrCreateActiveOwner();
      expect(active.id, 'owner-a');
      expect(active.firebaseUid, 'firebase-user');
      expect(events.first, 'recover');
      expect(events, isNot(contains('local-purge')));
      expect(dependencies.accountDeletion, isNotNull);

      cloud.failure = null;
      await dependencies.accountDeletion!.resumePendingDeletion();
      active = await dependencies.localOwners!.getOrCreateActiveOwner();
      expect(active.firebaseUid, isNull);
      expect(events.where((event) => event == 'recover'), hasLength(2));
      expect(events.where((event) => event == 'local-purge'), hasLength(1));
    },
  );

  test(
    'committed deletion finishes local purge when Firebase is unavailable',
    () async {
      final database = _testDatabase();
      await database.customStatement(
        "INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) VALUES ('owner-a', 'firebase-user', 1, 1)",
      );
      final events = <String>[];
      final journal = _BootstrapDeletionJournal(_committedDeletionEntry());
      final cloud = _BootstrapDeletionCloud()
        ..onCall = () => events.add('cloud');

      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async =>
            throw StateError('synthetic Firebase outage'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => throw StateError('must not be called'),
        accountDeletionEnabled: true,
        accountDeletionServerExportAuthorityConfigured: true,
        accountDeletionRecoveryRetention: const Duration(days: 7),
        accountDeletionFactory:
            ({
              required database,
              required owners,
              required config,
              required currentSession,
              required signOut,
              required newRequestsEnabled,
            }) async => _bootstrapDeletionComposition(
              database: database,
              owners: owners,
              currentSession: currentSession,
              signOut: signOut,
              journal: journal,
              cloud: cloud,
              newRequestsEnabled: newRequestsEnabled,
              onLocalPurge: () => events.add('local-purge'),
            ),
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(events, ['local-purge']);
      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.account, isNull);
      expect(dependencies.syncEngine, isNull);
      expect(dependencies.accountDeletion?.enabled, isFalse);
      final active = await dependencies.localOwners!.getOrCreateActiveOwner();
      expect(active.firebaseUid, isNull);
      expect(active.id, isNot('owner-a'));
      expect(
        (await dependencies.vocabulary!.createCategory('Offline')).name,
        'Offline',
      );
    },
  );

  test(
    'two committed Drift owner transitions A B A cancel delayed validation without reactivating A',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final gateway = _GeminiGateway();
      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        geminiSettingsStoreFactory: _ScopedGeminiStore.new,
        geminiGatewayFactory: () => gateway,
      ).initialize();
      addTearDown(dependencies.dispose);
      final tutor = dependencies.geminiTutor!;
      final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
      final inserted = tutor.invalidations.first;
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'synthetic-B',
              createdAtUtcMs: 1,
              isActive: const Value(false),
            ),
          );
      await inserted;
      await tutor.configure(
        key: 'synthetic-A',
        providerConsent: true,
        shareLearningSummary: true,
      );
      gateway.validationGate = Completer<void>();
      gateway.validationStarted = Completer<void>();
      final pending = expectLater(
        tutor.configure(
          key: 'synthetic-pending-A',
          providerConsent: true,
          shareLearningSummary: true,
        ),
        throwsA(isA<GeminiException>()),
      );
      await gateway.validationStarted!.future;
      final before = tutor.epoch;
      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(owner.id)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('synthetic-B')))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
      });
      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals('synthetic-B')))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(owner.id)))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
      });
      final finalOwner = await (database.select(
        database.localOwners,
      )..where((row) => row.isActive.equals(true))).getSingle();
      expect(finalOwner.id, owner.id);
      expect(tutor.epoch, greaterThan(before));
      expect(gateway.validationCancellation!.isCancelled, isTrue);
      gateway.validationGate!.complete();
      await pending;
      expect((await tutor.loadSettings()).hasKey, isTrue);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      expect((await tutor.loadSettings()).shareLearningSummary, isFalse);
      expect(gateway.generated, 0);
    },
  );
  test(
    'real Drift owner ABA updates invalidate pending Gemini work even at the same final snapshot',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final gateway = _GeminiGateway()..gate = Completer<String>();
      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        geminiSettingsStoreFactory: _ScopedGeminiStore.new,
        geminiGatewayFactory: () => gateway,
      ).initialize();
      addTearDown(dependencies.dispose);
      final tutor = dependencies.geminiTutor!;
      final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
      await tutor.configure(
        key: 'synthetic-ABA-key',
        providerConsent: true,
        shareLearningSummary: true,
      );
      final pending = expectLater(
        tutor.reply(scenario: 'Cafe Ordering', learnerMessage: 'Synthetic ABA'),
        throwsA(isA<GeminiException>()),
      );
      await gateway.started.future;
      final before = tutor.epoch;
      // One commit has an unchanged final row, while the owner table was touched.
      await database.transaction(() async {
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(owner.id)))
            .write(const LocalOwnersCompanion(isActive: Value(false)));
        await (database.update(database.localOwners)
              ..where((row) => row.id.equals(owner.id)))
            .write(const LocalOwnersCompanion(isActive: Value(true)));
      });
      await Future<void>.delayed(const Duration(milliseconds: 20));
      gateway.gate!.complete('Late synthetic ABA reply');
      await pending;
      expect(tutor.epoch, greaterThan(before));
      expect((await tutor.loadSettings()).hasKey, isTrue);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      expect((await tutor.loadSettings()).shareLearningSummary, isFalse);
    },
  );
  test(
    'optional Gemini auth watcher construction failure does not break local learning',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      addTearDown(database.close);
      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        readGeminiSession: () => null,
        watchGeminiSessions: () =>
            throw StateError('synthetic-watch-unavailable'),
        geminiSettingsStoreFactory: _ScopedGeminiStore.new,
        geminiGatewayFactory: _GeminiGateway.new,
      ).initialize();
      addTearDown(dependencies.dispose);
      expect(
        (await dependencies.learning!.startQuiz(limit: 1)).isEmpty,
        isTrue,
      );
      await expectLater(
        dependencies.geminiTutor!.loadSettings(),
        throwsA(isA<GeminiException>()),
      );
    },
  );
  test(
    'Gemini composition observes owner/auth/anonymous transitions and disposes watches',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final authEvents = StreamController<AccountSession?>.broadcast(
        sync: true,
      );
      AccountSession? session;
      final store = _ScopedGeminiStore();
      final gateway = _GeminiGateway();
      final dependencies = await AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        readGeminiSession: () => session,
        watchGeminiSessions: () => authEvents.stream,
        geminiSettingsStoreFactory: () => store,
        geminiGatewayFactory: () => gateway,
      ).initialize();
      addTearDown(dependencies.dispose);
      addTearDown(authEvents.close);
      final tutor = dependencies.geminiTutor!;
      final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
      await tutor.configure(
        key: 'synthetic-local-guest-key',
        providerConsent: true,
        shareLearningSummary: true,
      );
      expect((await tutor.loadSettings()).hasKey, isTrue);
      final epochs = <int>[];
      final subscription = tutor.invalidations.listen(epochs.add);
      session = const AccountSession(
        uid: 'synthetic-uid',
        email: null,
        isAnonymous: true,
        emailVerified: false,
      );
      authEvents.add(session);
      await expectLater(tutor.loadSettings(), throwsA(isA<GeminiException>()));
      final ownerBound = tutor.invalidations.firstWhere(
        (_) => tutor.scope?.firebaseUid == 'synthetic-uid',
      );
      await dependencies.localOwners!.bindFirebaseUid(
        owner.id,
        'synthetic-uid',
      );
      await ownerBound;
      expect((await tutor.loadSettings()).hasKey, isFalse);
      await tutor.configure(
        key: 'synthetic-anon-key',
        providerConsent: true,
        shareLearningSummary: true,
      );
      final beforeUpgrade = tutor.epoch;
      session = const AccountSession(
        uid: 'synthetic-uid',
        email: null,
        isAnonymous: false,
        emailVerified: false,
      );
      authEvents.add(session);
      expect(tutor.epoch, greaterThan(beforeUpgrade));
      expect((await tutor.loadSettings()).hasKey, isFalse);
      await tutor.configure(
        key: 'synthetic-registered-key',
        providerConsent: true,
        shareLearningSummary: false,
      );
      final beforeABA = tutor.epoch;
      session = null;
      authEvents.add(session);
      session = const AccountSession(
        uid: 'synthetic-uid',
        email: null,
        isAnonymous: false,
        emailVerified: false,
      );
      authEvents.add(session);
      expect(tutor.epoch, greaterThanOrEqualTo(beforeABA + 2));
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      await tutor.updateConsents(
        providerConsent: true,
        shareLearningSummary: false,
      );
      gateway.gate = Completer<String>();
      final pending = expectLater(
        tutor.reply(
          scenario: 'Cafe Ordering',
          learnerMessage: 'Synthetic pending',
        ),
        throwsA(isA<GeminiException>()),
      );
      await gateway.started.future;
      authEvents.addError(StateError('synthetic-auth-unavailable'));
      expect(gateway.cancellation!.isCancelled, isTrue);
      gateway.gate!.complete('Late synthetic reply');
      await pending;
      await expectLater(tutor.loadSettings(), throwsA(isA<GeminiException>()));
      expect(
        (await dependencies.learning!.startQuiz(limit: 1)).isEmpty,
        isTrue,
      );
      authEvents.add(session);
      expect((await tutor.loadSettings()).providerConsent, isFalse);
      final beforeOwner = tutor.epoch;
      await (database.update(database.localOwners)
            ..where((row) => row.id.equals(owner.id)))
          .write(const LocalOwnersCompanion(isActive: Value(false)));
      await database
          .into(database.localOwners)
          .insert(
            LocalOwnersCompanion.insert(
              id: 'synthetic-new-owner',
              createdAtUtcMs: 1,
            ),
          );
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(tutor.epoch, greaterThan(beforeOwner));
      await expectLater(tutor.loadSettings(), throwsA(isA<GeminiException>()));
      expect(dependencies.learning, isNotNull);
      expect(dependencies.vocabularyImportFilePicker, isNotNull);
      expect(dependencies.sourcePracticeFilePicker, isNotNull);
      expect(gateway.generated, 1);
      expect(epochs, isNotEmpty);
      await subscription.cancel();
      await dependencies.dispose();
      expect(authEvents.hasListener, isFalse);
      await authEvents.close();
    },
  );
  group('AppBootstrap.initialize', () {
    test('production hides research UI until every rollout gate is ready', () {
      expect(AppBootstrap.production().researchAvailability.isEnabled, isFalse);
      expect(AppBootstrap.production().studyRuntimeFactory, isNull);
      expect(
        const ResearchRuntimeAvailability(
          ethicsApproved: true,
          protocolApproved: true,
          instrumentApproved: true,
          trustedIssuerConfigured: true,
          trustedTimeConfigured: false,
          rolloutApproved: true,
        ).isEnabled,
        isFalse,
      );
      expect(
        AppBootstrap.production(
          researchAvailability: ResearchRuntimeAvailability.syntheticComplete,
        ).researchAvailability.isEnabled,
        isTrue,
      );
    });

    test('default composition does not expose research consent UI', () async {
      final dependencies = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(dependencies.researchAvailability.isEnabled, isFalse);
      expect(dependencies.researchConsent, isNull);
      expect(dependencies.studyRuntime, isNull);
      for (final table in [
        'research_consents',
        'experiment_assignments',
        'research_participation_permits',
        'motivation_measurement_runs',
        'motivation_responses',
        'measurement_opportunities',
        'events_v2',
        'outbox_operations',
      ]) {
        final rows = await dependencies.database!
            .customSelect('SELECT COUNT(*) AS n FROM $table')
            .getSingle();
        expect(rows.read<int>('n'), 0, reason: table);
      }
    });

    test('production defaults research authority to deny-all', () {
      expect(
        AppBootstrap.production().researchAuthorizer,
        isA<DenyAllResearchOperationAuthorizer>(),
      );
    });

    test('disabled rollout never invokes the optional study factory', () async {
      var calls = 0;
      final dependencies = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        studyRuntimeFactory: (_) {
          calls++;
          throw StateError('disabled factory must not run');
        },
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(calls, 0);
      expect(dependencies.studyRuntime, isNull);
      expect(await dependencies.learning!.prepareReading(), isEmpty);
    });

    for (final earlyLearningRead in [false, true]) {
      test(
        'optional study factory failure preserves learning ($earlyLearningRead)',
        () async {
          var calls = 0;
          final dependencies = await AppBootstrap(
            createDatabase: _testDatabase,
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            researchAvailability: ResearchRuntimeAvailability.syntheticComplete,
            studyRuntimeFactory: (context) {
              calls++;
              if (earlyLearningRead) context.getLearning();
              throw StateError('synthetic optional factory failure');
            },
          ).initialize();
          addTearDown(dependencies.dispose);

          expect(calls, 1);
          expect(dependencies.studyRuntime, isNull);
          expect(await dependencies.learning!.prepareReading(), isEmpty);
          final rows = await dependencies.database!
              .customSelect('SELECT COUNT(*) AS n FROM learning_sessions')
              .getSingle();
          expect(rows.read<int>('n'), 0);
        },
      );
    }

    for (final brokenObserver in ['throws', 'foreign database']) {
      test(
        'a $brokenObserver study observer preserves real learning',
        () async {
          final foreign = _testDatabase();
          final dependencies = await AppBootstrap(
            createDatabase: _testDatabase,
            initializeFirebase: () async {},
            initializeSupabase: () async {},
            loadConfig: _validConfig,
            guestSessionService: _StubGuestSessionService(),
            researchAvailability: ResearchRuntimeAvailability.syntheticComplete,
            studyRuntimeFactory: (context) => _BootstrapStudyRuntime(
              context,
              _BootstrapStudyObserver(foreign),
              throwObserver: brokenObserver == 'throws',
            ),
          ).initialize();
          addTearDown(dependencies.dispose);

          expect(dependencies.studyRuntime, isNull);
          await _completeBootstrapQuiz(dependencies);
          final answers = await dependencies.database!
              .customSelect('SELECT COUNT(*) AS n FROM answer_attempts')
              .getSingle();
          expect(answers.read<int>('n'), 1);
        },
      );
    }

    test(
      'study composition observes the one canonical learning writer',
      () async {
        late StudyRuntimeContext composition;
        late _BootstrapStudyObserver observer;
        final dependencies = await AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          researchAvailability: ResearchRuntimeAvailability.syntheticComplete,
          studyRuntimeFactory: (context) {
            composition = context;
            observer = _BootstrapStudyObserver(context.database);
            return _BootstrapStudyRuntime(context, observer);
          },
        ).initialize();
        addTearDown(dependencies.dispose);

        expect(composition.database, same(dependencies.database));
        expect(composition.owners, same(dependencies.localOwners));
        expect(composition.ownerWrites.database, same(dependencies.database));
        expect(
          composition.consentRepository,
          same(dependencies.researchConsent!.repository),
        );
        expect(composition.getLearning(), same(dependencies.learning));
        expect(
          dependencies.studyRuntime!.learning,
          same(dependencies.learning),
        );
        expect(observer.acceptedFacts, isEmpty);
        expect(observer.completedFacts, isEmpty);

        final sessionId = await _completeBootstrapQuiz(dependencies);
        expect(observer.acceptedFacts.single.id, sessionId);
        expect(observer.completedFacts.single.id, sessionId);
        expect(observer.completedFacts.single.state, 'completed');
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        final restored = await dependencies.learning!.resumeQuiz(
          sessionId: sessionId,
          expectedOwnerId: owner.id,
        );
        expect(restored.state, 'completed');
        expect(observer.acceptedFacts, hasLength(1));
        expect(observer.completedFacts, hasLength(1));
        for (final table in [
          'learning_sessions',
          'answer_attempts',
          'srs_states',
        ]) {
          final row = await dependencies.database!
              .customSelect('SELECT COUNT(*) AS n FROM $table')
              .getSingle();
          expect(row.read<int>('n'), 1, reason: table);
        }
        final points = await dependencies.database!
            .customSelect('SELECT COUNT(*) AS n FROM points_ledger_entries')
            .getSingle();
        expect(points.read<int>('n'), greaterThan(0));
      },
    );

    test('production accepts an explicitly configured research authority', () {
      const authorizer = _AllowResearchOperationAuthorizer();

      expect(
        identical(
          AppBootstrap.production(
            researchAuthorizer: authorizer,
          ).researchAuthorizer,
          authorizer,
        ),
        isTrue,
      );
    });

    test(
      'production composition keeps research export fail closed after consent',
      () async {
        final database = _testDatabase();
        final dependencies = await AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          researchAvailability: ResearchRuntimeAvailability.syntheticComplete,
        ).initialize();
        addTearDown(dependencies.dispose);
        final owner = await dependencies.localOwners!.getOrCreateActiveOwner();
        await dependencies.researchConsent!.accept();
        final consent = await dependencies.consents.snapshot(
          purpose: ConsentPurpose.researchDataUpload,
          ownerId: owner.id,
          consentVersion: 1,
        );
        expect(consent.state, ConsentState.granted);
        expect(consent.ownerId, owner.id);

        Object? failure;
        try {
          await dependencies.exports!.prepare(
            format: ExportFormat.researchJson,
            selection: const ExportSelection(
              includeVocabulary: true,
              includeAttempts: false,
              includeReading: false,
            ),
            cancellation: ExportCancellation(),
          );
        } catch (error) {
          failure = error;
        }

        expect(
          failure,
          isA<ExportException>().having(
            (error) => error.code,
            'code',
            ExportFailureCode.unavailable,
          ),
        );
        expect(failure.toString(), isNot(contains(owner.id)));
        expect(await database.select(database.eventsV2).get(), isEmpty);
        expect(await database.select(database.outboxOperations).get(), isEmpty);
      },
    );

    test(
      'account factory failure still exposes local learning and Guest',
      () async {
        final database = _testDatabase();
        final dependencies = await _accountBootstrap(
          database,
          () => throw StateError('synthetic factory failure'),
        ).initialize();
        addTearDown(dependencies.dispose);

        expect(
          dependencies.runtimeStatus.firebase,
          RuntimeAvailability.unavailable,
        );
        expect(dependencies.runtimeStatus.localData, RuntimeAvailability.ready);
        expect(dependencies.account, isNull);
        expect(dependencies.syncEngine, isNull);
        expect(
          await dependencies.guestSessionService.start(),
          isA<GuestSessionStarted>(),
        );
        final category = await dependencies.vocabulary!.createCategory(
          'Offline',
        );
        expect(category.name, 'Offline');
      },
    );

    test('unavailable Firebase never creates cloud gateways', () async {
      var factoryCalls = 0;
      var syncFactoryCalls = 0;
      final dependencies = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async =>
            throw StateError('synthetic offline Firebase'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _OfflineGuest(),
        bindGuestOwnership: true,
        accountGatewayFactory: () {
          factoryCalls++;
          return _StartupGateway(null);
        },
        syncGatewayFactory: () {
          syncFactoryCalls++;
          return _BootstrapSyncGateway();
        },
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(factoryCalls, 0);
      expect(syncFactoryCalls, 0);
      expect(dependencies.account, isNull);
      expect(dependencies.syncEngine, isNull);
      expect(dependencies.syncTrigger, isNull);
      expect(dependencies.runtimeStatus.localData, RuntimeAvailability.ready);
      expect(
        await dependencies.guestSessionService.start(),
        isA<GuestSessionStarted>(),
      );
    });

    test('failed restored-session read falls back to local learning', () async {
      final gateway = _StartupGateway(null)
        ..readFailure = StateError('synthetic session failure');
      final dependencies = await _accountBootstrap(
        _testDatabase(),
        () => gateway,
      ).initialize();
      addTearDown(dependencies.dispose);

      expect(
        dependencies.runtimeStatus.firebase,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.account, isNull);
      expect(dependencies.syncEngine, isNull);
      expect(
        (await dependencies.vocabulary!.createCategory('Offline')).name,
        'Offline',
      );
    });

    for (final anonymous in [false, true]) {
      test(
        'bootstrap reconciles restored ${anonymous ? 'anonymous' : 'registered'} session once',
        () async {
          final database = _testDatabase();
          final gateway = _StartupGateway(
            AccountSession(
              uid: 'synthetic-restored',
              email: anonymous ? null : 'learner@example.test',
              isAnonymous: anonymous,
              emailVerified: !anonymous,
            ),
          );
          final dependencies = await _accountBootstrap(
            database,
            () => gateway,
          ).initialize();
          addTearDown(dependencies.dispose);
          final owner = await dependencies.localOwners!
              .getOrCreateActiveOwner();

          expect(dependencies.account, isNotNull);
          expect(dependencies.account!.googleSignInAvailable, isFalse);
          expect(owner.firebaseUid, 'synthetic-restored');
          await dependencies.account!.reconcileLocalOwner();
          expect(
            await database.select(database.localOwners).get(),
            hasLength(1),
          );
          expect(gateway.signOutCalls, 0);
        },
      );
    }

    for (final existingB in [false, true]) {
      test(
        'bootstrap preserves A when restoring ${existingB ? 'existing' : 'new'} B',
        () async {
          final database = _testDatabase();
          await database.customStatement(
            "INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) VALUES ('owner-a', 'uid-a', 1, 1)",
          );
          await database.customStatement(
            "INSERT INTO vocabulary_categories (id, owner_id, name, normalized_name, created_at_utc_ms, updated_at_utc_ms, cloud_revision) VALUES ('category-a', 'owner-a', 'Travel', 'travel', 1, 1, 4)",
          );
          if (existingB) {
            await database.customStatement(
              "INSERT INTO local_owners (id, firebase_uid, created_at_utc_ms, is_active) VALUES ('owner-b', 'uid-b', 2, 0)",
            );
          }
          final gateway = _StartupGateway(
            const AccountSession(
              uid: 'uid-b',
              email: 'b@example.test',
              isAnonymous: false,
              emailVerified: true,
            ),
          );
          final dependencies = await _accountBootstrap(
            database,
            () => gateway,
          ).initialize();
          addTearDown(dependencies.dispose);

          expect(
            dependencies.runtimeStatus.firebase,
            RuntimeAvailability.ready,
          );
          final active = await dependencies.localOwners!
              .getOrCreateActiveOwner();
          expect(active.firebaseUid, 'uid-b');
          if (existingB) expect(active.id, 'owner-b');
          final category = await database
              .select(database.vocabularyCategories)
              .getSingle();
          expect(category.ownerId, 'owner-a');
          expect(category.cloudRevision, 4);
          final ownerCount =
              (await database.select(database.localOwners).get()).length;
          await dependencies.account!.reconcileLocalOwner();
          expect(
            (await database.select(database.localOwners).get()).length,
            ownerCount,
          );
          expect(
            await (database.select(
              database.localOwners,
            )..where((row) => row.isActive.equals(true))).get(),
            hasLength(1),
          );
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
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
      expect(dependencies.deviceModels, isNotNull);
      expect(dependencies.objectScanner, isNotNull);
      expect(dependencies.devicePermissions, isNotNull);
      expect(dependencies.speechPractice, isNotNull);
      expect(dependencies.geminiTutor, isNotNull);
      expect(dependencies.associativeLearning, isNotNull);
      expect(dependencies.vocabularyImportFilePicker, isNotNull);
      expect(dependencies.sourcePracticeFilePicker, isNotNull);
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

    test('wires local sync status without a Cloud gateway', () async {
      final dependencies = await AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async =>
            throw StateError('synthetic offline Firebase'),
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
      ).initialize();

      final status = await dependencies.syncStatus!
          .watchCurrentOwnerSyncStatus()
          .firstWhere((snapshot) => snapshot != null);

      expect(dependencies.syncEngine, isNull);
      expect(status?.ownerId, isNotEmpty);
      expect(status?.pending, 0);
      expect(status?.handledConflicts, 0);
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
        accountGatewayFactory: () => _StartupGateway(
          const AccountSession(
            uid: 'firebase-user',
            email: 'learner@example.test',
            isAnonymous: false,
            emailVerified: true,
          ),
        ),
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.vocabulary!.createCategory('Travel');
      await Future<void>.delayed(Duration.zero);

      expect(dependencies.syncTrigger, isNotNull);
      expect(gateway.policyFetches, 1);
    });
  });

  group('resolveAndroidAppCheckProvider', () {
    test('returns the debug provider when debugMode is true', () {
      final provider = resolveAndroidAppCheckProvider(debugMode: true);
      expect(provider, isA<AndroidDebugProvider>());
      expect(provider.type, 'debug');
    });

    test('returns the Play Integrity provider when debugMode is false', () {
      final provider = resolveAndroidAppCheckProvider(debugMode: false);
      expect(provider, isA<AndroidPlayIntegrityProvider>());
      expect(provider.type, 'playIntegrity');
    });

    test(
      'selects debug only for the exact debug flag, not a truthy default',
      () {
        // Regression guard: the production default is `!kReleaseMode`, so a
        // release build (kReleaseMode == true) must resolve to Play Integrity
        // and never fall back to the debug provider.
        expect(
          resolveAndroidAppCheckProvider(debugMode: false).runtimeType,
          AndroidPlayIntegrityProvider,
        );
      },
    );
  });

  group('requireFirebaseAppCheckToken', () {
    test('accepts a structurally valid App Check JWT', () async {
      await requireFirebaseAppCheckToken(
        () async =>
            'eyJhbGciOiJSUzI1NiJ9.eyJleHAiOjQxMDI0NDQ4MDB9.c2lnbmF0dXJl',
      );
    });

    for (final token in <String?>[
      null,
      '',
      '   ',
      'synthetic-token',
      'eyJlcnJvciI6IlVOS05PV05fRVJST1IifQ==',
    ]) {
      test('rejects unavailable token ${token ?? 'null'}', () async {
        await expectLater(
          requireFirebaseAppCheckToken(() async => token),
          throwsStateError,
        );
      });
    }

    test('preserves the first App Check exchange failure', () async {
      final failure = StateError('synthetic exchange rejection');

      await expectLater(
        requireFirebaseAppCheckToken(() async => throw failure),
        throwsA(same(failure)),
      );
    });

    test('times out a token exchange that never completes', () async {
      final never = Completer<String?>();

      await expectLater(
        requireFirebaseAppCheckToken(
          () => never.future,
          timeout: const Duration(milliseconds: 1),
        ),
        throwsA(isA<TimeoutException>()),
      );
    });
  });
}

AppBootstrap _accountBootstrap(
  AppDatabase database,
  AccountGatewayFactory factory,
) => AppBootstrap(
  createDatabase: () => database,
  initializeFirebase: () async {},
  initializeSupabase: () async {},
  loadConfig: _validConfig,
  guestSessionService: _OfflineGuest(),
  bindGuestOwnership: true,
  accountGatewayFactory: factory,
);

final class _OfflineGuest implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

final class _AllowResearchOperationAuthorizer
    implements ResearchOperationAuthorizer {
  const _AllowResearchOperationAuthorizer();

  @override
  Future<bool> authorize({
    required String ownerId,
    required ResearchOperation operation,
  }) async => true;
}

final class _StartupGateway implements AccountGateway {
  _StartupGateway(this.session);
  AccountSession? session;
  Object? readFailure;
  void Function()? onRead;
  int signOutCalls = 0;
  @override
  AccountSession? get currentSession {
    onRead?.call();
    if (readFailure case final error?) throw error;
    return session;
  }

  @override
  Future<void> signOut() async {
    signOutCalls++;
    session = null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

final class _ScopedGeminiStore implements GeminiSettingsStore {
  final values = <GeminiScope, GeminiConfiguration>{};
  @override
  Future<GeminiConfiguration> read(GeminiScope scope) async =>
      values[scope] ?? const GeminiConfiguration();
  @override
  Future<void> write(
    GeminiScope scope,
    GeminiConfiguration configuration,
  ) async {
    values[scope] = configuration;
  }
}

final class _GeminiGateway implements GeminiGateway {
  int generated = 0;
  Completer<String>? gate;
  final started = Completer<void>();
  GeminiCancellation? cancellation;
  Completer<void>? validationGate;
  Completer<void>? validationStarted;
  GeminiCancellation? validationCancellation;
  @override
  String get model => 'synthetic';
  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {
    validationCancellation = cancellation;
    validationStarted?.complete();
    await validationGate?.future;
  }

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    GeminiTutorMode mode = GeminiTutorMode.guided,
    String? learningSummary,
    GeminiCancellation? cancellation,
  }) async {
    generated += 1;
    this.cancellation = cancellation;
    if (!started.isCompleted) started.complete();
    return gate?.future ?? 'synthetic';
  }
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
  Future<PushResult> push(PushMutation mutation) async => PushAcknowledged(
    operationId: mutation.operationId,
    resultingRevision: mutation.localRevision,
    acknowledgedAtUtc: DateTime.now().toUtc(),
  );
}

AccountDeletionUseCases _deletionUseCases(
  LocalOwnerRepository owners, {
  bool enabled = false,
}) {
  final unused = _UnusedDeletionDependency();
  return AccountDeletionUseCases(
    enabled: enabled,
    owners: owners,
    ownerWrites: FakeOwnerWriteCoordinator(),
    currentSession: () => null,
    exporter: unused,
    reauthenticator: unused,
    cloud: unused,
    local: unused,
    journal: unused,
    nowUtc: () => DateTime.now().toUtc(),
  );
}

final class _UnusedDeletionDependency
    implements
        FullAccountExporter,
        AccountDeletionReauthenticator,
        PrivilegedAccountDeletionGateway,
        LocalAccountDeletionGateway,
        AccountDeletionJournal {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError();
}

AccountDeletionJournalEntry _pendingDeletionEntry() {
  final now = DateTime.now().toUtc();
  const key = 'delete:00000000-0000-4000-8000-000000000001';
  return AccountDeletionJournalEntry(
    ownerId: 'owner-a',
    firebaseUid: 'firebase-user',
    idempotencyKey: key,
    exportReceipt: FullAccountExportReceipt(
      ownerId: 'owner-a',
      artifactId: 'complete-export.json',
      artifactSha256: 'a' * 64,
      bytesWritten: 128,
      schemaVersion: 10,
      coveredScopes: requiredFullAccountExportScopes,
      completedAtUtc: now.subtract(const Duration(minutes: 10)),
    ),
    authenticationReceipt: RecentAuthenticationReceipt(
      firebaseUid: 'firebase-user',
      authenticatedAtUtc: now.subtract(const Duration(minutes: 10)),
    ),
  );
}

AccountDeletionJournalEntry _committedDeletionEntry() {
  final now = DateTime.now().toUtc();
  return AccountDeletionJournalEntry(
    cloudReceipt: CloudDeletionReceipt(
      receiptId: 'cloud-receipt-bootstrap',
      ownerId: 'owner-a',
      firebaseUid: 'firebase-user',
      idempotencyKey: durableAccountDeletionBinding(
        'delete:00000000-0000-4000-8000-000000000001',
      ),
      completedAtUtc: now.subtract(const Duration(minutes: 1)),
    ),
  );
}

AccountDeletionComposition _bootstrapDeletionComposition({
  required AppDatabase database,
  required LocalOwnerRepository owners,
  required AccountDeletionSessionReader currentSession,
  required Future<void> Function() signOut,
  required _BootstrapDeletionJournal journal,
  required _BootstrapDeletionCloud cloud,
  required bool newRequestsEnabled,
  required void Function() onLocalPurge,
}) {
  final unused = _UnusedDeletionDependency();
  return AccountDeletionComposition(
    useCases: AccountDeletionUseCases(
      enabled: newRequestsEnabled,
      owners: owners,
      ownerWrites: DriftOwnerWriteCoordinator(
        database,
        nowUtc: () => DateTime.now().toUtc(),
      ),
      currentSession: currentSession,
      exporter: unused,
      reauthenticator: unused,
      cloud: cloud,
      local: DriftLocalAccountDeletionGateway(
        database,
        nowUtc: () => DateTime.now().toUtc(),
        purgeOwnerSecret: ({required ownerId, required firebaseUid}) async {
          onLocalPurge();
          await signOut();
        },
      ),
      journal: journal,
      nowUtc: () => DateTime.now().toUtc(),
    ),
    dispose: () async {},
  );
}

final class _BootstrapStudyRuntime extends Fake implements StudyRuntime {
  _BootstrapStudyRuntime(
    this.context,
    this.observer, {
    this.throwObserver = false,
  });

  final StudyRuntimeContext context;
  final LearningSessionLifecycleObserver observer;
  final bool throwObserver;

  @override
  LearningSessionLifecycleObserver get lifecycleObserver {
    if (throwObserver) throw StateError('synthetic observer failure');
    return observer;
  }

  @override
  LearningUseCases get learning => context.getLearning();
}

final class _BootstrapStudyObserver
    implements LearningSessionLifecycleObserver {
  _BootstrapStudyObserver(this.database);
  @override
  final AppDatabase database;
  final acceptedFacts = <LearningSessionLifecycleFact>[];
  final completedFacts = <LearningSessionLifecycleFact>[];

  @override
  Future<void> accepted(LearningSessionLifecycleFact fact) async {
    acceptedFacts.add(fact);
  }

  @override
  Future<void> completed(LearningSessionLifecycleFact fact) async {
    completedFacts.add(fact);
  }
}

Future<String> _completeBootstrapQuiz(AppDependencies dependencies) async {
  final category = await dependencies.vocabulary!.createCategory('Synthetic');
  await dependencies.vocabulary!.createWord(
    CreateWordCommand(
      categoryId: category.id,
      spelling: 'river',
      meaning: 'แม่น้ำ',
      partOfSpeech: 'noun',
    ),
  );
  final learning = dependencies.learning!;
  final session = await learning.startQuiz(categoryId: category.id, limit: 1);
  final initial = session.configured!;
  final question = initial.plan.questions.single;
  final pending = await learning.prepareQuizAnswer(
    sessionId: session.id,
    expectedOwnerId: initial.ownerId,
    expectedRevision: initial.checkpointRevision,
    selectedOptionOrdinal: question.options.indexOf(question.word.meaning),
  );
  final answer = await learning.commitQuizAnswer(
    sessionId: session.id,
    expectedOwnerId: initial.ownerId,
    expectedRevision: pending.checkpointRevision,
  );
  final closing = await learning.prepareQuizFinish(
    sessionId: session.id,
    expectedOwnerId: initial.ownerId,
    expectedRevision: answer.state.checkpointRevision,
  );
  final finished = await learning.finishConfiguredQuiz(
    sessionId: session.id,
    expectedOwnerId: initial.ownerId,
    expectedRevision: closing.checkpointRevision,
  );
  expect(finished.summary.correctCount, 1);
  expect(finished.summary.state, 'completed');
  return session.id;
}

final class _BootstrapDeletionCloud
    implements PrivilegedAccountDeletionGateway {
  Object? failure;
  void Function()? onCall;

  @override
  Future<CloudDeletionReceipt> deleteRecursively({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async {
    onCall?.call();
    if (failure case final error?) throw error;
    return CloudDeletionReceipt(
      receiptId: 'cloud-receipt-bootstrap',
      ownerId: ownerId,
      firebaseUid: firebaseUid,
      idempotencyKey: idempotencyKey,
      completedAtUtc: DateTime.now().toUtc(),
    );
  }
}

final class _BootstrapDeletionJournal implements AccountDeletionJournal {
  _BootstrapDeletionJournal(this.entry);

  AccountDeletionJournalEntry? entry;

  @override
  Future<AccountDeletionJournalEntry?> load() async => entry;

  @override
  Future<void> saveCloudReceipt(CloudDeletionReceipt receipt) async {
    final durableReceipt = receipt.durableMarker();
    entry = AccountDeletionJournalEntry(
      ownerId: durableReceipt.ownerId,
      firebaseUid: durableReceipt.firebaseUid,
      idempotencyKey: durableReceipt.idempotencyKey,
      cloudReceipt: durableReceipt,
    );
  }

  @override
  Future<void> saveLocalReceipt({
    required CloudDeletionReceipt cloudReceipt,
    required LocalDeletionReceipt localReceipt,
  }) async {
    final current = entry!;
    entry = AccountDeletionJournalEntry(
      ownerId: current.ownerId,
      firebaseUid: current.firebaseUid,
      idempotencyKey: current.idempotencyKey,
      cloudReceipt: cloudReceipt,
      localReceipt: localReceipt,
    );
  }

  @override
  Future<void> savePendingOperation({
    required String ownerId,
    required String firebaseUid,
    required String idempotencyKey,
    required FullAccountExportReceipt exportReceipt,
    required RecentAuthenticationReceipt authenticationReceipt,
  }) async => throw UnimplementedError();
}
