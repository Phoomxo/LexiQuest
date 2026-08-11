import 'dart:async';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vocab_learning_app/config/app_config.dart';
import 'package:vocab_learning_app/data/local/app_database.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_gateway_factory.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/drift_ai_usage_repository.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/identity/data/drift_local_owner_repository.dart';
import 'package:vocab_learning_app/features/session/domain/app_entry_state.dart';
import 'package:vocab_learning_app/features/sync/data/drift_owner_operation_gate.dart';
import 'package:vocab_learning_app/features/vocabulary/application/vocabulary_use_cases.dart';
import 'package:vocab_learning_app/runtime/app_bootstrap.dart';
import 'package:vocab_learning_app/runtime/app_runtime_status.dart';
import 'package:vocab_learning_app/runtime/circuit_breaker.dart';
import 'package:vocab_learning_app/services/guest_session_service.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

void main() {
  test(
    'local learning survives isolated AI and voice composition failures',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final bootstrap = _bootstrap(
        database,
        buildAiTutor: (_) => throw StateError('AI unavailable'),
        buildVoice: (_) => throw StateError('voice unavailable'),
      );

      final dependencies = await bootstrap.initialize();
      try {
        final category = await dependencies.vocabulary!.createCategory(
          'Offline travel',
        );
        await dependencies.vocabulary!.createWord(
          CreateWordCommand(
            categoryId: category.id,
            spelling: 'station',
            meaning: 'transport stop',
            partOfSpeech: 'noun',
          ),
        );
        final localQuiz = await dependencies.learning!.startQuiz();

        expect(localQuiz.isEmpty, isFalse);
        expect(localQuiz.questions.single.word.spelling, 'station');
        expect(dependencies.quest, isNotNull);
        expect(dependencies.aiTutor, isNull);
        expect(dependencies.voice, isNull);
        expect(
          dependencies.runtimeStatus.aiTutor,
          RuntimeAvailability.unavailable,
        );
        expect(
          dependencies.runtimeStatus.voice,
          RuntimeAvailability.unavailable,
        );
      } finally {
        await dependencies.dispose();
      }
    },
  );

  test(
    'missing cloud config keeps BYOK AI and native voice available',
    () async {
      final database = AppDatabase(NativeDatabase.memory());
      final controller = _ScenarioAiController();
      final nativeVoice = _ScenarioManagedVoice();
      final bootstrap = _bootstrap(
        database,
        loadConfig: () => throw const AppConfigException('missing endpoints'),
        buildAiTutor: (_) => ManagedAiTutor(
          controller: controller,
          disposeController: controller.dispose,
        ),
        buildVoice: (config) {
          expect(config, isNull);
          return nativeVoice;
        },
      );

      final dependencies = await bootstrap.initialize();
      try {
        final session = dependencies.voice!.acquireSession();
        final result = await session.speak(_voiceRequest('offline voice'));
        await session.release();

        expect(dependencies.config, isNull);
        expect(dependencies.aiTutor, same(controller));
        expect(result.actualEngine, VoiceEngine.nativeTts);
        expect(
          dependencies.runtimeStatus.backends,
          RuntimeAvailability.unavailable,
        );
        expect(dependencies.runtimeStatus.aiTutor, RuntimeAvailability.ready);
        expect(dependencies.runtimeStatus.voice, RuntimeAvailability.ready);
        expect(nativeVoice.speakCalls, 1);
      } finally {
        await dependencies.dispose();
      }
    },
  );

  test(
    'one AI request is terminally accounted only to the active owner',
    () async {
      final harness = await _AiJourneyHarness.open();
      try {
        final reply = await harness.tutor.reply(
          scenario: 'travel',
          learnerMessage: 'Help me ask for directions.',
        );
        final rows = await harness.database
            .select(harness.database.aiUsageEvents)
            .get();

        expect(reply.text, 'bounded reply');
        expect(harness.gateway.generateCalls, 1);
        expect(rows, hasLength(1));
        expect(rows.single.ownerId, harness.ownerId);
        expect(
          rows.where((row) => row.ownerId == harness.inactiveOwnerId),
          isEmpty,
        );
        expect(rows.single.outcome, 'success');
        expect(rows.single.totalTokens, 7);
      } finally {
        await harness.dispose();
      }
    },
  );

  test(
    'real factory bounds disabled, circuit-open, and timeout failures',
    () async {
      var sends = 0;
      final outageClient = MockClient((_) async {
        sends += 1;
        return http.Response('{}', 503);
      });
      final factory = AiTutorGatewayFactory(
        client: outageClient,
        requestTimeout: const Duration(milliseconds: 100),
        providerBreakers: <AiProviderId, CircuitBreaker>{
          AiProviderId.openai: CircuitBreaker(threshold: 1),
        },
      );

      final maxPlus = factory.create(
        providerId: AiProviderId.maxPlus,
        model: 'disabled-model',
      );
      await expectLater(
        _gatewayReply(maxPlus),
        throwsA(_aiFailure(AiFailureCode.providerDisabled)),
      );
      expect(sends, 0);

      final openAi = factory.create(
        providerId: AiProviderId.openai,
        model: 'outage-model',
      );
      await expectLater(
        _gatewayReply(openAi),
        throwsA(_aiFailure(AiFailureCode.providerUnavailable)),
      );
      expect(sends, 1);
      await expectLater(
        _gatewayReply(openAi),
        throwsA(_aiFailure(AiFailureCode.circuitOpen)),
      );
      expect(sends, 1);

      var stalledSends = 0;
      final stalledClient = MockClient((_) {
        stalledSends += 1;
        return Completer<http.Response>().future;
      });
      final timed = AiTutorGatewayFactory(
        client: stalledClient,
        requestTimeout: const Duration(milliseconds: 20),
      ).create(providerId: AiProviderId.openai, model: 'timeout-model');
      await expectLater(
        _gatewayReply(timed).timeout(const Duration(seconds: 1)),
        throwsA(_aiFailure(AiFailureCode.timeout)),
      );
      expect(stalledSends, 1);
    },
  );
}

AppBootstrap _bootstrap(
  AppDatabase database, {
  AppConfig Function()? loadConfig,
  ManagedAiTutorBuilder? buildAiTutor,
  ManagedVoiceBuilder? buildVoice,
}) => AppBootstrap(
  initializeFirebase: () async {},
  initializeSupabase: () async {},
  loadConfig:
      loadConfig ??
      () => AppConfig.fromValues(
        voiceApiUrl: 'https://voice.example.com',
        aiApiUrl: 'https://ai.example.com',
        isDebug: false,
      ),
  guestSessionService: _ScenarioGuestSession(),
  createDatabase: () => database,
  createEntryStateStore: () async => _ScenarioEntryStateStore(),
  buildAiTutor: buildAiTutor,
  buildVoice: buildVoice,
);

final class _AiJourneyHarness {
  _AiJourneyHarness._({
    required this.database,
    required this.ownerId,
    required this.inactiveOwnerId,
    required this.tutor,
    required this.gateway,
    required this.resolvedProviders,
  });

  final AppDatabase database;
  final String ownerId;
  final String inactiveOwnerId;
  final AiTutorUseCases tutor;
  final _ScenarioGateway gateway;
  final List<AiProviderId> resolvedProviders;

  static Future<_AiJourneyHarness> open() async {
    final database = AppDatabase(NativeDatabase.memory());
    final now = DateTime.utc(2026, 8, 11, 8);
    final owners = DriftLocalOwnerRepository(
      database,
      generateId: () => 'active-owner',
      nowUtc: () => now,
    );
    final owner = await owners.getOrCreateActiveOwner();
    const inactiveOwnerId = 'local:inactive-owner';
    await database
        .into(database.localOwners)
        .insert(
          LocalOwnersCompanion.insert(
            id: inactiveOwnerId,
            createdAtUtcMs: now.millisecondsSinceEpoch,
            isActive: const Value(false),
          ),
        );
    final gate = DriftOwnerOperationGate(database);
    final usage = DriftAiUsageRepository(
      database,
      activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
      activeOwnerLeaseToken: () => OwnerOperationCoordinator.currentLeaseToken,
      nowUtc: () => now,
    );
    var event = 0;
    final gateway = _ScenarioGateway();
    final resolvedProviders = <AiProviderId>[];
    final tutor = AiTutorUseCases(
      store: _ScenarioCredentialStore(owner.id),
      gatewayResolver: ({required providerId, required model, customBaseUrl}) {
        resolvedProviders.add(providerId);
        return gateway;
      },
      nowUtc: () => now.add(Duration(milliseconds: event)),
      usageRepository: usage,
      usageEventId: () => 'journey-event-${++event}',
      ownerCoordinator: OwnerOperationCoordinator(
        gate: gate,
        activeOwnerId: () async => (await owners.getOrCreateActiveOwner()).id,
        nowUtc: () => now,
        generateToken: () => 'journey-lease-${event + 1}',
      ),
    );
    return _AiJourneyHarness._(
      database: database,
      ownerId: owner.id,
      inactiveOwnerId: inactiveOwnerId,
      tutor: tutor,
      gateway: gateway,
      resolvedProviders: resolvedProviders,
    );
  }

  Future<void> dispose() async {
    await tutor.dispose();
    await database.close();
  }
}

final class _ScenarioCredentialStore implements AiTutorSettingsStore {
  _ScenarioCredentialStore(this.ownerId);

  final String ownerId;

  @override
  Future<AiTutorCredential?> readCredentialForOwner(String requestedOwnerId) {
    if (requestedOwnerId != ownerId) return Future.value();
    return Future.value(
      const AiTutorCredential(
        key: 'scenario-key',
        providerId: AiProviderId.openai,
        model: 'scenario-model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScenarioGateway implements AiTutorGateway {
  int generateCalls = 0;

  @override
  AiProviderId get providerId => AiProviderId.openai;

  @override
  String get model => 'scenario-model';

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    return const AiGatewayReply(
      text: 'bounded reply',
      usage: AiTokenUsage(inputTokens: 3, outputTokens: 4, totalTokens: 7),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScenarioAiController implements AiTutorController {
  int disposeCalls = 0;

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final class _ScenarioManagedVoice implements ManagedVoiceProvider {
  int speakCalls = 0;
  int disposeCalls = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    speakCalls += 1;
    return const VoicePlaybackResult(
      requestedEngine: VoiceEngine.nativeTts,
      actualEngine: VoiceEngine.nativeTts,
      usedFallback: false,
      cacheHit: false,
    );
  }

  @override
  Future<void> stop() async {}

  @override
  Future<void> dispose() async {
    disposeCalls += 1;
  }
}

final class _ScenarioGuestSession implements GuestSessionService {
  @override
  Future<GuestSessionResult> start() async =>
      const GuestSessionFailed(GuestSessionFailure.firebaseUnavailable);
}

final class _ScenarioEntryStateStore implements AppEntryStateStore {
  AppEntryMode mode = AppEntryMode.signedOut;

  @override
  Future<void> clear() async => mode = AppEntryMode.signedOut;

  @override
  Future<void> markGuest() async => mode = AppEntryMode.guest;

  @override
  Future<AppEntryMode> read() async => mode;
}

VoiceRequest _voiceRequest(String text) => VoiceRequest.create(
  text: text,
  language: 'en',
  voiceId: 'device-default',
  speed: 1,
  mode: VoiceMode.practice,
  contentId: text,
  contentType: 'fallback-journey',
);

Future<AiGatewayReply> _gatewayReply(AiTutorGateway gateway) =>
    gateway.generateTutorReply(
      key: 'scenario-key',
      scenario: 'travel',
      learnerMessage: 'bounded request',
    );

Matcher _aiFailure(AiFailureCode code) =>
    isA<AiTutorException>().having((error) => error.code, 'code', code);
