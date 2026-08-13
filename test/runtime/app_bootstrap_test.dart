import 'dart:async';
import 'dart:convert';

import 'package:drift/drift.dart' hide isNotNull, isNull;
import 'package:drift/native.dart';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/account/domain/account_contracts.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/export/domain/export_contracts.dart';
import 'package:vocab_learning_app/features/quest/domain/quest_models.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/sync/application/sync_trigger.dart';
import 'package:vocab_learning_app/features/sync/domain/cloud_sync_policy.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_entity.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_gateway.dart';
import 'package:vocab_learning_app/features/sync/domain/sync_result.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/navigation/app_routes.dart';
import 'package:vocab_learning_app/runtime/registries/feature_registry.dart';
import 'package:vocab_learning_app/runtime/runtime_feature_override_store.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

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

final class _ControllableBootstrapGuestSessionService
    implements GuestSessionService {
  final Completer<GuestSessionResult> _result = Completer<GuestSessionResult>();
  int startCalls = 0;

  @override
  Future<GuestSessionResult> start() {
    startCalls += 1;
    return _result.future;
  }

  void complete(GuestSessionResult result) => _result.complete(result);
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

Future<AppEntryStateStore> _createSignedOutEntryState() async =>
    _MemoryAppEntryStateStore();

void main() {
  group('AppBootstrap.initialize', () {
    test('marks all components ready and retains the exact config', () async {
      final expectedConfig = _validConfig();
      final ai = _BootstrapAiTutorController();
      final voice = _BootstrapManagedVoiceProvider();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: () => expectedConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          return ManagedAiTutor(controller: ai, disposeController: ai.dispose);
        },
        buildVoice: (config) {
          voiceBuilds += 1;
          expect(identical(config, expectedConfig), isTrue);
          return voice;
        },
      );

      final dependencies = await bootstrap.initialize();
      final repeated = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.backends, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.voice, RuntimeAvailability.ready);
      expect(identical(dependencies.config, expectedConfig), isTrue);
      expect(dependencies.deviceModels, isNotNull);
      expect(dependencies.objectScanner, isNotNull);
      expect(dependencies.speechPractice, isNotNull);
      expect(identical(dependencies, repeated), isTrue);
      expect(identical(dependencies.aiTutor, ai), isTrue);
      expect(dependencies.voice, isNotNull);
      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(dependencies.localDataEraser, isNotNull);
      expect(dependencies.featureControls, isNotNull);
      final ownerArchive = await dependencies.exports!.prepare(
        format: ExportFormat.ownerArchiveJson,
        selection: const ExportSelection(
          includeVocabulary: false,
          includeAttempts: false,
          includeReading: false,
        ),
        cancellation: ExportCancellation(),
      );
      final archiveEnvelope =
          jsonDecode(utf8.decode(ownerArchive.bytes)) as Map<String, dynamic>;
      expect(
        (archiveEnvelope['content'] as Map<String, dynamic>)['tables'],
        hasLength(31),
      );
    });

    test(
      'awaits and memoizes managed AI and voice disposal exactly once',
      () async {
        final aiDisposal = Completer<void>();
        final voiceDisposal = Completer<void>();
        final ai = _BootstrapAiTutorController(disposal: aiDisposal.future);
        final voice = _BootstrapManagedVoiceProvider(
          disposal: voiceDisposal.future,
        );
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          buildAiTutor: (_) =>
              ManagedAiTutor(controller: ai, disposeController: ai.dispose),
          buildVoice: (_) => voice,
        );
        final dependencies = await bootstrap.initialize();

        var completed = false;
        final first = dependencies.dispose().whenComplete(
          () => completed = true,
        );
        final second = dependencies.dispose();
        await Future<void>.delayed(Duration.zero);

        expect(completed, isFalse);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 0);

        voiceDisposal.complete();
        await Future<void>.delayed(Duration.zero);
        expect(completed, isFalse);
        expect(ai.disposeCalls, 1);

        aiDisposal.complete();
        await Future.wait(<Future<void>>[first, second]);

        expect(completed, isTrue);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
      },
    );

    test('AI builder failure preserves voice and local learning', () async {
      final voice = _BootstrapManagedVoiceProvider();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          throw StateError('AI builder unavailable');
        },
        buildVoice: (_) {
          voiceBuilds += 1;
          return voice;
        },
      );

      final dependencies = await bootstrap.initialize();

      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(dependencies.aiTutor, isNull);
      expect(dependencies.voice, isNotNull);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.quest, isNotNull);
    });

    test('voice builder failure preserves AI and local learning', () async {
      final ai = _BootstrapAiTutorController();
      var aiBuilds = 0;
      var voiceBuilds = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        buildAiTutor: (_) {
          aiBuilds += 1;
          return ManagedAiTutor(controller: ai, disposeController: ai.dispose);
        },
        buildVoice: (_) {
          voiceBuilds += 1;
          throw StateError('voice builder unavailable');
        },
      );

      final dependencies = await bootstrap.initialize();

      expect(aiBuilds, 1);
      expect(voiceBuilds, 1);
      expect(identical(dependencies.aiTutor, ai), isTrue);
      expect(dependencies.voice, isNull);
      expect(dependencies.vocabulary, isNotNull);
      expect(dependencies.quest, isNotNull);
    });

    test(
      'cleanup errors do not prevent the remaining managed stack from draining',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final ai = _BootstrapAiTutorController();
        final voice = _BootstrapManagedVoiceProvider(
          disposalError: StateError('voice cleanup failed'),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          buildAiTutor: (_) =>
              ManagedAiTutor(controller: ai, disposeController: ai.dispose),
          buildVoice: (_) => voice,
        );
        final dependencies = await bootstrap.initialize();

        final cleanupFailure = throwsA(
          isA<VoiceFailure>().having(
            (failure) => failure.category,
            'category',
            VoiceFailureCategory.cleanupIncomplete,
          ),
        );
        await expectLater(dependencies.dispose(), cleanupFailure);

        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
        await expectLater(
          database.customSelect('SELECT 1').getSingle(),
          throwsA(anything),
        );
        await expectLater(dependencies.dispose(), cleanupFailure);
        expect(voice.disposeCalls, 1);
        expect(ai.disposeCalls, 1);
      },
    );

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
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        final owners = await database.select(database.localOwners).get();

        expect(dependencies.localOwners, isNotNull);
        expect(owners, hasLength(1));
        expect(owners.single.isActive, isTrue);
      },
    );

    test(
      'seeds quest before replay and skips pre-assignment learning',
      () async {
        final database = _testDatabase();
        const ownerId = 'bootstrap-history-owner';
        final historicalAt = DateTime.utc(2000, 1, 1);
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: ownerId,
                createdAtUtcMs: historicalAt.millisecondsSinceEpoch,
              ),
            );
        await database
            .into(database.eventsV2)
            .insert(
              EventsV2Companion.insert(
                eventId: 'learning-event:bootstrap-history',
                eventType: 'QuizCompleted',
                eventVersion: 1,
                occurredAtUtc: historicalAt,
                recordedAtUtc: historicalAt,
                actorIdentity: ownerId,
                ownerId: ownerId,
                aggregateType: 'LearningSession',
                aggregateId: 'session-history',
                idempotencyKey: 'learning-attempt:bootstrap-history:v1',
                consentContextJson: '{}',
                appVersion: '1.0.0',
                buildId: 'bootstrap-test',
                privacyClassification: 'anonymized',
                payloadJson: '{"correct":true}',
              ),
            );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.learningReconciliation!.drain();

        final active = await dependencies.quest.getActiveInstances();
        expect(active, hasLength(1));
        expect(active.single.assignedAtUtc.isAfter(historicalAt), isTrue);
        expect(active.single.progress.single.currentCount, 0);
        final questResult =
            await (database.select(database.eventsV2)..where(
                  (row) =>
                      row.aggregateId.equals(
                        'learning-event:bootstrap-history',
                      ) &
                      row.aggregateType.equals('LearningProjection') &
                      row.eventType.equals('LearningProjectionSkipped') &
                      row.idempotencyKey.equals(
                        'learning-projection:quest:'
                        'learning-event:bootstrap-history:v1',
                      ),
                ))
                .getSingleOrNull();
        expect(questResult, isNotNull);
      },
    );

    test(
      'loads persisted emergency feature controls into navigation',
      () async {
        final database = _testDatabase();
        await RuntimeFeatureOverrideStore(database).setEmergencyOff(
          Feature.aiTutor,
          updatedAtUtc: DateTime.utc(2026, 8, 9, 12),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();

        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(dependencies.features.isVisible(Feature.aiTutor), isFalse);
      },
    );

    test(
      'restored TTL controls schedule live expiry during bootstrap',
      () async {
        final database = _testDatabase();
        var now = DateTime.utc(2026, 8, 9, 12);
        final seedRegistry = RuntimeFeatureRegistry(
          const BuildFeatureRegistry.fieldDefaults(),
        );
        final seedControls = RuntimeFeatureControls(
          store: RuntimeFeatureOverrideStore(database),
          registry: seedRegistry,
          nowUtc: () => now,
          scheduleExpiry: (_, _) => () {},
        );
        await seedControls.emergencyOff(
          Feature.aiTutor,
          expiresAtUtc: now.add(const Duration(hours: 1)),
        );
        seedControls.dispose();
        seedRegistry.dispose();

        void Function()? expiryCallback;
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          runtimeFeatureNowUtc: () => now,
          scheduleRuntimeFeatureExpiry: (_, callback) {
            expiryCallback = callback;
            return () {};
          },
        );

        final dependencies = await bootstrap.initialize();
        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.emergencyOff,
        );
        expect(expiryCallback, isNotNull);

        now = now.add(const Duration(hours: 1));
        expiryCallback!();
        await Future<void>.delayed(Duration.zero);
        await Future<void>.delayed(Duration.zero);

        expect(
          dependencies.features.stateOf(Feature.aiTutor),
          FeatureState.limited,
        );
      },
    );

    test(
      'gated AI recovery purges only expired active-owner terminal usage',
      () async {
        final database = _testDatabase();
        final now = DateTime.utc(2026, 8, 11, 12);
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(id: 'owner-a', createdAtUtcMs: 1),
            );
        await database
            .into(database.localOwners)
            .insert(
              LocalOwnersCompanion.insert(
                id: 'owner-b',
                createdAtUtcMs: 2,
                isActive: const Value(false),
              ),
            );
        Future<void> seedUsage({
          required String eventId,
          required String ownerId,
          required DateTime occurredAt,
          required String outcome,
        }) => database
            .into(database.aiUsageEvents)
            .insert(
              AiUsageEventsCompanion.insert(
                eventId: eventId,
                ownerId: ownerId,
                occurredAtUtcMs: occurredAt.millisecondsSinceEpoch,
                providerId: 'gemini',
                model: 'typed-model',
                requestType: 'tutorReply',
                outcome: outcome,
                latencyMs: 1,
              ),
            );
        await seedUsage(
          eventId: 'expired-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'success',
        );
        await seedUsage(
          eventId: 'recent-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 1)),
          outcome: 'failure',
        );
        await seedUsage(
          eventId: 'pending-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(minutes: 1)),
          outcome: 'pending',
        );
        await seedUsage(
          eventId: 'expired-pending-a',
          ownerId: 'owner-a',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'pending',
        );
        await seedUsage(
          eventId: 'expired-b',
          ownerId: 'owner-b',
          occurredAt: now.subtract(const Duration(days: 91)),
          outcome: 'success',
        );
        final ai = _BootstrapAiTutorController();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
          aiNowUtc: () => now,
          buildAiTutor: (context) async {
            await context.ownerCoordinator.run(AiCancellation(), (_) async {});
            return ManagedAiTutor(
              controller: ai,
              disposeController: ai.dispose,
            );
          },
        );

        await bootstrap.initialize();

        final rows = await database.select(database.aiUsageEvents).get();
        final byId = {for (final row in rows) row.eventId: row};
        expect(byId, isNot(contains('expired-a')));
        expect(byId['recent-a']?.outcome, 'failure');
        expect(byId['pending-a']?.outcome, 'pending');
        expect(byId, isNot(contains('expired-pending-a')));
        expect(byId['expired-b']?.outcome, 'success');
      },
    );

    test(
      'quest projection and reward reconciliation survive quest emergency-off',
      () async {
        final database = _testDatabase();
        await RuntimeFeatureOverrideStore(database).setEmergencyOff(
          Feature.questV2,
          updatedAtUtc: DateTime.utc(2026, 8, 11, 12),
        );
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          createEntryStateStore: _createSignedOutEntryState,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.learningReconciliation!.drain();
        final quest = dependencies.quest;
        final active = await quest.getActiveInstances();
        expect(
          dependencies.features.stateOf(Feature.questV2),
          FeatureState.emergencyOff,
        );
        expect(active, hasLength(1));

        final ownerId = active.single.ownerId;
        // events_v2 uses Drift's DateTime precision while quest assignment is
        // stored as explicit epoch milliseconds. Keep test evidence safely
        // beyond the assignment boundary instead of relying on subsecond
        // rounding in the in-memory SQLite adapter.
        final base = active.single.assignedAtUtc.add(
          const Duration(minutes: 1),
        );
        for (var index = 1; index <= 5; index++) {
          final occurredAt = base.add(Duration(milliseconds: index));
          await database
              .into(database.eventsV2)
              .insert(
                EventsV2Companion.insert(
                  eventId: 'learning-event:quest-off-$index',
                  eventType: 'QuizCompleted',
                  eventVersion: 1,
                  occurredAtUtc: occurredAt,
                  recordedAtUtc: occurredAt,
                  actorIdentity: ownerId,
                  ownerId: ownerId,
                  aggregateType: 'LearningSession',
                  aggregateId: 'session-quest-off',
                  idempotencyKey: 'learning-attempt:quest-off-$index:v1',
                  consentContextJson: '{}',
                  appVersion: '1.0.0',
                  buildId: 'bootstrap-test',
                  privacyClassification: 'anonymized',
                  payloadJson: '{"correct":true}',
                ),
              );
        }

        dependencies.learningReconciliation!.request(ownerId);
        await dependencies.learningReconciliation!.drain();

        final firstQuestReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:quest:'
                    'learning-event:quest-off-1:v1',
                  ),
                ))
                .getSingleOrNull();
        expect(firstQuestReceipt, isNotNull);
        expect(firstQuestReceipt?.eventType, 'LearningProjectionApplied');
        final instances = await quest.getAllInstancesForCurrentOwner();
        expect(instances, hasLength(1));
        expect(instances.single.progress.single.currentCount, 5);
        expect(instances.single.state, QuestInstanceState.completed);
        final rewards =
            await (database.select(database.pointsLedgerEntries)..where(
                  (row) =>
                      row.ownerId.equals(ownerId) &
                      row.entryType.equals('questCompletion'),
                ))
                .get();
        expect(rewards, hasLength(1));
        expect(rewards.single.amount, 50);
        final rewardReceipt =
            await (database.select(database.eventsV2)..where(
                  (row) => row.eventId.equals(
                    'learning-projection:reward:'
                    'learning-event:quest-off-5:v1',
                  ),
                ))
                .getSingleOrNull();
        expect(rewardReceipt?.eventType, 'LearningProjectionApplied');
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
        createEntryStateStore: _createSignedOutEntryState,
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
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.runtimeStatus.voice, RuntimeAvailability.ready);
      expect(dependencies.config, isNotNull);
    });

    test('records Supabase failure and still returns', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
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
        createEntryStateStore: _createSignedOutEntryState,
      );

      final dependencies = await bootstrap.initialize();

      expect(dependencies.runtimeStatus.firebase, RuntimeAvailability.ready);
      expect(dependencies.runtimeStatus.supabase, RuntimeAvailability.ready);
      expect(
        dependencies.runtimeStatus.backends,
        RuntimeAvailability.unavailable,
      );
      expect(dependencies.config, isNull);
      expect(dependencies.aiTutor, isNotNull);
      expect(dependencies.voice, isNotNull);
      expect(dependencies.vocabulary, isNotNull);
    });

    test('represents multiple failures independently', () async {
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async => throw StateError('firebase-down'),
        initializeSupabase: () async => throw StateError('supabase-down'),
        loadConfig: () => throw const AppConfigException('invalid config'),
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
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
        createEntryStateStore: _createSignedOutEntryState,
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
        createEntryStateStore: _createSignedOutEntryState,
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
          createEntryStateStore: _createSignedOutEntryState,
          bindGuestOwnership: true,
        );

        final dependencies = await bootstrap.initialize();
        final originalOwner = await (database.select(
          database.localOwners,
        )..where((row) => row.isActive.equals(true))).getSingle();
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
        expect(owner?.id, originalOwner.id);
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
        createEntryStateStore: _createSignedOutEntryState,
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.vocabulary!.createCategory('Travel');
      await Future<void>.delayed(Duration.zero);

      expect(dependencies.syncTrigger, isNotNull);
      expect(gateway.policyFetches, 1);
    });

    test(
      'resolves launch route from the single persisted entry store',
      () async {
        final entryState = _MemoryAppEntryStateStore(AppEntryMode.guest);
        var factoryCalls = 0;
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          bindGuestOwnership: true,
          createEntryStateStore: () async {
            factoryCalls += 1;
            return entryState;
          },
        );

        final dependencies = await bootstrap.initialize();

        expect(factoryCalls, 1);
        expect(dependencies.initialRoute, AppRoute.home);
        await entryState.clear();

        final guestResult = await dependencies.guestSessionService.start();

        expect(guestResult, isA<GuestSessionStarted>());
        expect(entryState.mode, AppEntryMode.guest);
      },
    );

    test('memoizes one dependency graph per bootstrap instance', () async {
      var databaseCalls = 0;
      var entryStateCalls = 0;
      final bootstrap = AppBootstrap(
        createDatabase: () {
          databaseCalls += 1;
          return _testDatabase();
        },
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: () async {
          entryStateCalls += 1;
          return _MemoryAppEntryStateStore();
        },
      );

      final first = await bootstrap.initialize();
      final second = await bootstrap.initialize();

      expect(identical(first, second), isTrue);
      expect(databaseCalls, 1);
      expect(entryStateCalls, 1);
    });

    test('closes the database when later composition fails', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        syncGatewayFactory: () => throw StateError('gateway unavailable'),
      );

      await expectLater(bootstrap.initialize(), throwsStateError);
      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
    });

    test(
      'entry-store creation failure falls back to signed-out volatile guest state',
      () async {
        final bootstrap = AppBootstrap(
          createDatabase: _testDatabase,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: _StubGuestSessionService(),
          bindGuestOwnership: true,
          createEntryStateStore: () async {
            throw StateError('preferences unavailable');
          },
        );

        final dependencies = await bootstrap.initialize();
        final guest = await dependencies.guestSessionService.start();

        expect(dependencies.initialRoute, AppRoute.login);
        expect(guest, isA<GuestSessionStarted>());
      },
    );

    test('shares the bootstrap entry store with account transitions', () async {
      final entryState = _MemoryAppEntryStateStore(AppEntryMode.guest);
      final gateway = _BootstrapAccountGateway(
        currentSession: const AccountSession(
          uid: 'account-user',
          email: 'student@example.com',
          isAnonymous: false,
          emailVerified: true,
        ),
      );
      var factoryCalls = 0;
      final bootstrap = AppBootstrap(
        createDatabase: _testDatabase,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _StubGuestSessionService(),
        accountGatewayFactory: () => gateway,
        createEntryStateStore: () async {
          factoryCalls += 1;
          return entryState;
        },
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.account!.signOutToLocalGuest();

      expect(factoryCalls, 1);
      expect(dependencies.initialRoute, AppRoute.home);
      expect(entryState.clearCalls, 1);
      expect(entryState.mode, AppEntryMode.signedOut);
    });

    test(
      'disposal cancels owner binding before closing the database',
      () async {
        final database = AppDatabase(NativeDatabase.memory());
        final delegate = _ControllableBootstrapGuestSessionService();
        final bootstrap = AppBootstrap(
          createDatabase: () => database,
          initializeFirebase: () async {},
          initializeSupabase: () async {},
          loadConfig: _validConfig,
          guestSessionService: delegate,
          createEntryStateStore: _createSignedOutEntryState,
          bindGuestOwnership: true,
        );

        final dependencies = await bootstrap.initialize();
        await dependencies.guestSessionService.start();
        await dependencies.dispose().timeout(const Duration(milliseconds: 250));
        delegate.complete(
          const GuestSessionStarted(uid: 'late-bootstrap-provider'),
        );
        await Future<void>.delayed(Duration.zero);

        expect(delegate.startCalls, 1);
        await expectLater(
          database.customSelect('SELECT 1').getSingle(),
          throwsA(anything),
        );
      },
    );

    test('disposal drains blocked sync before closing the database', () async {
      final database = AppDatabase(NativeDatabase.memory());
      final gateway = _BlockingBootstrapSyncGateway();
      final bootstrap = AppBootstrap(
        createDatabase: () => database,
        initializeFirebase: () async {},
        initializeSupabase: () async {},
        loadConfig: _validConfig,
        guestSessionService: _SuccessfulGuestSessionService(),
        createEntryStateStore: _createSignedOutEntryState,
        bindGuestOwnership: true,
        syncGatewayFactory: () => gateway,
      );

      final dependencies = await bootstrap.initialize();
      await dependencies.guestSessionService.start();
      await dependencies.syncTrigger!.request(SyncTriggerReason.manualRetry);
      await dependencies.vocabulary!.createCategory('Blocked sync');
      await gateway.pushEntered.future;

      var disposeCompleted = false;
      final disposing = dependencies.dispose().whenComplete(
        () => disposeCompleted = true,
      );
      await Future<void>.delayed(Duration.zero);
      final completedBeforeProvider = disposeCompleted;
      Object? databaseErrorBeforeProvider;
      QueryRow? databaseOpenBeforeProvider;
      try {
        databaseOpenBeforeProvider = await database
            .customSelect('SELECT 1')
            .getSingle();
      } catch (error) {
        databaseErrorBeforeProvider = error;
      }

      gateway.releasePush.complete();
      await disposing;

      expect(completedBeforeProvider, isFalse);
      expect(databaseErrorBeforeProvider, isNull);
      expect(databaseOpenBeforeProvider!.read<int>('1'), 1);
      await expectLater(
        database.customSelect('SELECT 1').getSingle(),
        throwsA(anything),
      );
      await expectLater(
        dependencies.syncTrigger!.request(SyncTriggerReason.manualRetry),
        throwsA(isA<StateError>()),
      );
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
}

final class _BootstrapAiTutorController implements AiTutorController {
  _BootstrapAiTutorController({Future<void>? disposal})
    : _disposal = disposal ?? Future<void>.value();

  final Future<void> _disposal;
  int disposeCalls = 0;

  @override
  Future<void> dispose() {
    disposeCalls += 1;
    return _disposal;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _BootstrapManagedVoiceProvider implements ManagedVoiceProvider {
  _BootstrapManagedVoiceProvider({Future<void>? disposal, this.disposalError})
    : _disposal = disposal ?? Future<void>.value();

  final Future<void> _disposal;
  final Object? disposalError;
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
    await _disposal;
    final error = disposalError;
    if (error != null) throw error;
  }

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    return VoicePlaybackResult(
      requestedEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      actualEngine: request.assignedEngine ?? VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}
}

final class _MemoryAppEntryStateStore implements AppEntryStateStore {
  _MemoryAppEntryStateStore([this.mode = AppEntryMode.signedOut]);

  AppEntryMode mode;
  int clearCalls = 0;
  int markGuestCalls = 0;

  @override
  Future<void> clear() async {
    clearCalls += 1;
    mode = AppEntryMode.signedOut;
  }

  @override
  Future<void> markGuest() async {
    markGuestCalls += 1;
    mode = AppEntryMode.guest;
  }

  @override
  Future<AppEntryMode> read() async => mode;
}

final class _BootstrapAccountGateway implements AccountGateway {
  _BootstrapAccountGateway({this.currentSession});

  @override
  AccountSession? currentSession;

  @override
  Future<AccountSession> register({
    required String email,
    required String password,
  }) async => currentSession = AccountSession(
    uid: 'account-user',
    email: email,
    isAnonymous: false,
    emailVerified: false,
  );

  @override
  Future<AccountSession> signIn({
    required String email,
    required String password,
  }) => register(email: email, password: password);

  @override
  Future<void> signOut() async {
    currentSession = null;
  }

  @override
  Future<void> applyEmailVerificationCode(String code) async {}

  @override
  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {}

  @override
  Future<void> confirmPasswordReset({
    required String code,
    required String newPassword,
  }) async {}

  @override
  Future<AccountSession> reload() async => currentSession!;

  @override
  Future<void> sendPasswordReset(String email) async {}

  @override
  Future<void> sendVerification() async {}
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

final class _BlockingBootstrapSyncGateway implements SyncGateway {
  final Completer<void> pushEntered = Completer<void>();
  final Completer<void> releasePush = Completer<void>();

  @override
  Future<CloudSyncPolicy> fetchPolicy() async {
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
  }) async => PullPage(
    changes: const <SyncEntity>[],
    nextCursor: after,
    hasMore: false,
  );

  @override
  Future<PushResult> push(PushMutation mutation) async {
    if (!pushEntered.isCompleted) pushEntered.complete();
    await releasePush.future;
    return PushAcknowledged(
      operationId: mutation.operationId,
      resultingRevision: mutation.localRevision,
      acknowledgedAtUtc: DateTime.now().toUtc(),
    );
  }
}
