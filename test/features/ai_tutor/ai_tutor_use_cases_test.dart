import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';

void main() {
  late SecureAiTutorSettingsStore store;
  late _FakeGateway gateway;

  setUp(() {
    store = SecureAiTutorSettingsStore(_MemoryValueStore());
    gateway = _FakeGateway();
  });

  AiTutorUseCases createTutor({
    DateTime Function()? nowUtc,
    Future<ProgressSnapshot> Function()? loadProgress,
    AiUsageRepository? usageRepository,
  }) => AiTutorUseCases(
    store: store,
    gatewayResolver: ({required providerId, required model, customBaseUrl}) {
      gateway.providerIdValue = providerId;
      gateway.modelValue = model;
      return gateway;
    },
    nowUtc: nowUtc ?? () => DateTime.utc(2026, 8, 1),
    loadProgress: loadProgress,
    usageRepository: usageRepository,
    usageEventId: () => 'usage-event',
  );

  test('requires explicit model selection', () async {
    final tutor = createTutor();

    await expectLater(
      tutor.configure(
        key: 'sk-test-key',
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openai,
        model: '',
      ),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.missingModel,
        ),
      ),
    );
  });

  test('validates replacement before atomically replacing profile', () async {
    await store.writeCredential(
      const AiTutorCredential(
        key: 'existing-key',
        providerId: AiProviderId.gemini,
        model: 'gemini-existing',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    gateway.validationFailure = const AiTutorException(
      AiFailureCode.invalidKey,
    );
    final tutor = createTutor();

    await expectLater(
      tutor.configure(
        key: 'invalid-replacement',
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openai,
        model: 'gpt-test',
      ),
      throwsA(isA<AiTutorException>()),
    );

    final active = await store.readCredential();
    expect(active?.key, 'existing-key');
    expect(active?.providerId, AiProviderId.gemini);
  });

  test(
    'configuration probe records metadata before atomic activation',
    () async {
      final usage = _MemoryUsageRepository();
      gateway.reply = const AiGatewayReply(
        text: 'OK',
        usage: AiTokenUsage(inputTokens: 4, outputTokens: 1, totalTokens: 5),
      );
      final tutor = createTutor(usageRepository: usage);

      await tutor.configure(
        key: 'sk-test-key',
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
      );

      final active = await store.readCredential();
      expect(active?.model, 'provider/model');
      expect(gateway.generateCalls, 1);
      expect(gateway.lastScenario, 'Configuration validation');
      expect(gateway.lastLearnerMessage, 'Reply with OK.');
      expect(gateway.lastSummary, isNull);
      expect(usage.events, hasLength(1));
      expect(usage.events.single.requestType, 'configurationValidation');
      expect(usage.events.single.outcome, 'success');
      expect(usage.events.single.totalTokens, 5);
    },
  );

  test(
    'failed configuration probe preserves the previous credential',
    () async {
      await store.writeCredential(
        const AiTutorCredential(
          key: 'existing-key',
          providerId: AiProviderId.gemini,
          model: 'gemini-existing',
          providerConsent: true,
          shareLearningSummary: false,
        ),
      );
      final usage = _MemoryUsageRepository();
      gateway.generationFailure = const AiTutorException(
        AiFailureCode.requestRejected,
      );
      final tutor = createTutor(usageRepository: usage);

      await expectLater(
        tutor.configure(
          key: 'replacement-key',
          providerConsent: true,
          shareLearningSummary: false,
          providerId: AiProviderId.openrouter,
          model: 'provider/model',
        ),
        throwsA(
          isA<AiTutorException>().having(
            (error) => error.code,
            'code',
            AiFailureCode.requestRejected,
          ),
        ),
      );

      final active = await store.readCredential();
      expect(active?.key, 'existing-key');
      expect(active?.providerId, AiProviderId.gemini);
      expect(gateway.generateCalls, 1);
      expect(usage.events, hasLength(1));
      expect(usage.events.single.requestType, 'configurationValidation');
      expect(usage.events.single.outcome, 'failure');
      expect(usage.events.single.errorCategory, 'requestRejected');
    },
  );

  test(
    'cancelled configuration probe writes no replacement and does not retry',
    () async {
      await store.writeCredential(
        const AiTutorCredential(
          key: 'existing-key',
          providerId: AiProviderId.gemini,
          model: 'gemini-existing',
          providerConsent: true,
          shareLearningSummary: false,
        ),
      );
      final cancellation = AiCancellation();
      gateway.waitForCancellation = true;
      final tutor = createTutor();

      final configuring = tutor.configure(
        key: 'replacement-key',
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        cancellation: cancellation,
      );
      await gateway.generationStarted.future;
      cancellation.cancel();

      await expectLater(
        configuring,
        throwsA(
          isA<AiTutorException>().having(
            (error) => error.code,
            'code',
            AiFailureCode.cancelled,
          ),
        ),
      );
      expect((await store.readCredential())?.key, 'existing-key');
      expect(gateway.generateCalls, 1);
    },
  );

  test('does not save a model absent from the provider model list', () async {
    gateway.models = const [AiModel(id: 'available-model')];
    final tutor = createTutor();

    await expectLater(
      tutor.configure(
        key: 'sk-test-key',
        providerConsent: true,
        shareLearningSummary: false,
        providerId: AiProviderId.openrouter,
        model: 'missing-model',
      ),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.missingModel,
        ),
      ),
    );
    expect(await store.readCredential(), isNull);
  });

  test('loads provider models without a generation request', () async {
    gateway.models = const [AiModel(id: 'model-a')];
    final tutor = createTutor();

    final models = await tutor.listModels(
      providerId: AiProviderId.openrouter,
      key: 'sk-test-key',
    );

    expect(models.single.id, 'model-a');
    expect(gateway.generateCalls, 0);
  });

  test('sends bounded aggregate progress only after consent', () async {
    await store.writeCredential(
      const AiTutorCredential(
        key: 'configured-key',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: true,
      ),
    );
    final tutor = createTutor(loadProgress: () async => _progress());

    final reply = await tutor.reply(
      scenario: 'Job Interview',
      learnerMessage: 'I learn quickly.',
    );

    expect(reply.text, 'Live provider reply');
    expect(reply.providerId, AiProviderId.openrouter);
    expect(gateway.lastSummary, contains('answers=10'));
    expect(gateway.lastSummary, contains('apple:50%(n=4)'));
    expect(gateway.lastSummary, isNot(contains('owner')));
  });

  test('does not load progress without summary consent', () async {
    var progressCalls = 0;
    await store.writeCredential(
      const AiTutorCredential(
        key: 'configured-key',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final tutor = createTutor(
      loadProgress: () async {
        progressCalls += 1;
        return _progress();
      },
    );

    await tutor.reply(scenario: 'Interview', learnerMessage: 'Hello');

    expect(progressCalls, 0);
    expect(gateway.lastSummary, isNull);
  });

  test('removing key cancels and awaits active provider work', () async {
    final pending = _PendingGateway();
    await store.writeCredential(
      const AiTutorCredential(
        key: 'configured-key',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final tutor = AiTutorUseCases(
      store: store,
      gatewayResolver: ({required providerId, required model, customBaseUrl}) =>
          pending,
      nowUtc: () => DateTime.utc(2026, 8, 1),
    );
    final reply = tutor.reply(scenario: 'Interview', learnerMessage: 'Hello');
    final expected = expectLater(
      reply,
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.cancelled,
        ),
      ),
    );
    await pending.started.future;

    await tutor.removeKey();
    await expected;

    expect(await store.readCredential(), isNull);
    expect(pending.cancelled, isTrue);
  });

  test('rejects a non-UTC clock result', () async {
    await store.writeCredential(
      const AiTutorCredential(
        key: 'configured-key',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final tutor = createTutor(nowUtc: () => DateTime(2026, 8, 1));

    await expectLater(
      tutor.reply(scenario: 'Interview', learnerMessage: 'Hello'),
      throwsArgumentError,
    );
  });

  test('records metadata and provider-reported usage after a reply', () async {
    final usage = _MemoryUsageRepository();
    gateway.reply = const AiGatewayReply(
      text: 'Live provider reply',
      usage: AiTokenUsage(inputTokens: 8, outputTokens: 3, totalTokens: 11),
    );
    await store.writeCredential(
      const AiTutorCredential(
        key: 'configured-key',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final tutor = createTutor(usageRepository: usage);

    await tutor.reply(scenario: 'Interview', learnerMessage: 'private text');

    expect(usage.events, hasLength(1));
    expect(usage.events.single.providerId, AiProviderId.openrouter);
    expect(usage.events.single.totalTokens, 11);
    expect(usage.events.single.outcome, 'success');
  });

  // ── listModelsForActiveCredential ─────────────────────────────────────────

  test(
    'listModelsForActiveCredential uses stored key without exposing it',
    () async {
      gateway.models = const [AiModel(id: 'gemini-2.5-flash')];
      await store.writeCredential(
        const AiTutorCredential(
          key: 'stored-key-test-key-0000',
          providerId: AiProviderId.gemini,
          model: 'gemini-existing',
          providerConsent: true,
          shareLearningSummary: false,
        ),
      );
      final tutor = createTutor();

      final models = await tutor.listModelsForActiveCredential();

      expect(models.map((m) => m.id), contains('gemini-2.5-flash'));
      expect(gateway.generateCalls, 0);
    },
  );

  test(
    'listModelsForActiveCredential throws missingKey when no credential',
    () async {
      final tutor = createTutor();

      await expectLater(
        tutor.listModelsForActiveCredential(),
        throwsA(
          isA<AiTutorException>().having(
            (e) => e.code,
            'code',
            AiFailureCode.missingKey,
          ),
        ),
      );
    },
  );

  test(
    'listModelsForActiveCredential throws consentRequired when consent revoked',
    () async {
      await store.writeCredential(
        const AiTutorCredential(
          key: 'stored-key',
          providerId: AiProviderId.gemini,
          model: 'gemini-existing',
          providerConsent: false,
          shareLearningSummary: false,
        ),
      );
      final tutor = createTutor();

      await expectLater(
        tutor.listModelsForActiveCredential(),
        throwsA(
          isA<AiTutorException>().having(
            (e) => e.code,
            'code',
            AiFailureCode.consentRequired,
          ),
        ),
      );
    },
  );

  // ── configureActiveModel ──────────────────────────────────────────────────

  test('configureActiveModel replaces model using stored key', () async {
    final usage = _MemoryUsageRepository();
    gateway.reply = const AiGatewayReply(text: 'OK');
    await store.writeCredential(
      const AiTutorCredential(
        key: 'stored-key-test-key-0000',
        providerId: AiProviderId.gemini,
        model: 'gemini-old',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    final tutor = createTutor(usageRepository: usage);

    await tutor.configureActiveModel(
      model: 'gemini-new',
      shareLearningSummary: true,
    );

    final active = await store.readCredential();
    expect(active?.model, 'gemini-new');
    expect(active?.key, 'stored-key-test-key-0000');
    expect(active?.shareLearningSummary, isTrue);
    expect(gateway.generateCalls, 1);
    expect(gateway.lastScenario, 'Configuration validation');
    expect(usage.events.single.requestType, 'configurationValidation');
    expect(usage.events.single.outcome, 'success');
  });

  test(
    'configureActiveModel preserves existing credential on probe failure',
    () async {
      gateway.generationFailure = const AiTutorException(
        AiFailureCode.requestRejected,
      );
      await store.writeCredential(
        const AiTutorCredential(
          key: 'stored-key-test-key-0000',
          providerId: AiProviderId.gemini,
          model: 'gemini-old',
          providerConsent: true,
          shareLearningSummary: false,
        ),
      );
      final tutor = createTutor();

      await expectLater(
        tutor.configureActiveModel(
          model: 'gemini-new',
          shareLearningSummary: false,
        ),
        throwsA(
          isA<AiTutorException>().having(
            (e) => e.code,
            'code',
            AiFailureCode.requestRejected,
          ),
        ),
      );

      final active = await store.readCredential();
      expect(active?.model, 'gemini-old');
      expect(active?.key, 'stored-key-test-key-0000');
    },
  );

  test('configureActiveModel throws missingKey when no credential', () async {
    final tutor = createTutor();

    await expectLater(
      tutor.configureActiveModel(
        model: 'gemini-2.5-flash',
        shareLearningSummary: false,
      ),
      throwsA(
        isA<AiTutorException>().having(
          (e) => e.code,
          'code',
          AiFailureCode.missingKey,
        ),
      ),
    );
  });
}

final class _MemoryValueStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async => values[key] = value;
}

final class _FakeGateway implements AiTutorGateway {
  AiProviderId providerIdValue = AiProviderId.openrouter;
  String modelValue = 'provider/model';
  AiTutorException? validationFailure;
  AiTutorException? generationFailure;
  List<AiModel> models = const [];
  int generateCalls = 0;
  String? lastScenario;
  String? lastLearnerMessage;
  String? lastSummary;
  bool waitForCancellation = false;
  final Completer<void> generationStarted = Completer<void>();
  AiGatewayReply reply = const AiGatewayReply(text: 'Live provider reply');

  @override
  AiProviderId get providerId => providerIdValue;

  @override
  String get model => modelValue;

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    generateCalls += 1;
    lastScenario = scenario;
    lastLearnerMessage = learnerMessage;
    lastSummary = learningSummary;
    if (!generationStarted.isCompleted) generationStarted.complete();
    if (waitForCancellation) {
      await cancellation!.whenCancelled;
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    if (generationFailure case final failure?) throw failure;
    return reply;
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async {
    if (validationFailure case final failure?) throw failure;
    return models.isEmpty ? [AiModel(id: model)] : models;
  }

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {
    if (validationFailure case final failure?) throw failure;
  }
}

final class _MemoryUsageRepository implements AiUsageRepository {
  final List<AiUsageEvent> events = [];

  @override
  Future<void> clear() async => events.clear();

  @override
  Future<String> exportAggregateJson({required bool researchConsent}) async =>
      '{}';

  @override
  Future<int> purgeExpired(DateTime nowUtc) async => 0;

  @override
  Future<void> record(AiUsageEvent event) async => events.add(event);

  @override
  Future<List<AiUsageSummary>> summarize() async => const [];
}

final class _PendingGateway implements AiTutorGateway {
  final Completer<void> started = Completer<void>();
  bool cancelled = false;

  @override
  AiProviderId get providerId => AiProviderId.openrouter;

  @override
  String get model => 'provider/model';

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    started.complete();
    await cancellation!.whenCancelled;
    cancelled = true;
    throw const AiTutorException(AiFailureCode.cancelled);
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async => const [];

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {}
}

ProgressSnapshot _progress() => ProgressSnapshot(
  sampleSize: 10,
  correctCount: 7,
  wrongCount: 3,
  accuracy: 0.7,
  points: 70,
  completedSessions: 2,
  streakDays: 1,
  dueReviewCount: 3,
  masteredWordCount: 2,
  achievementCount: 1,
  gameLevel: 1,
  skills: const [],
  weaknesses: [
    WeaknessEvidence(
      wordId: 'word-1',
      spelling: 'apple',
      meaning: 'fruit',
      sampleSize: 4,
      incorrectCount: 2,
      errorRate: 0.5,
      dueAtUtc: DateTime.utc(2026, 8, 2),
    ),
  ],
  recommendations: const [],
);
