import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';

void main() {
  late SecureAiTutorSettingsStore store;
  late _FakeGateway gateway;
  late _MemoryUsageRepository usage;
  late String activeOwner;

  setUp(() async {
    activeOwner = 'owner-a';
    store = SecureAiTutorSettingsStore(
      _MemorySecureStore(),
      activeOwnerId: () async => activeOwner,
    );
    await store.writeCredential(
      const AiTutorCredential(
        key: 'secret-key-sentinel',
        providerId: AiProviderId.openrouter,
        model: 'provider/model',
        providerConsent: true,
        shareLearningSummary: false,
      ),
    );
    gateway = _FakeGateway();
    usage = _MemoryUsageRepository();
  });

  AiTutorUseCases createTutor({AiUsageRepository? usageRepository}) =>
      AiTutorUseCases(
        store: store,
        gatewayResolver:
            ({required providerId, required model, customBaseUrl}) {
              gateway.providerIdValue = providerId;
              gateway.modelValue = model;
              return gateway;
            },
        nowUtc: () => DateTime.utc(2026, 8, 9),
        usageRepository: usageRepository ?? usage,
        usageEventId: () => 'usage-event',
      );

  test(
    'records only metadata and provider-reported usage after success',
    () async {
      gateway.reply = const AiGatewayReply(
        text: 'provider-response-sentinel',
        usage: AiTokenUsage(inputTokens: 8, outputTokens: 3, totalTokens: 11),
      );

      await createTutor().reply(
        scenario: 'scenario-sentinel',
        learnerMessage: 'learner-message-sentinel',
      );

      expect(usage.events, hasLength(1));
      final event = usage.events.single;
      expect(event.providerId, AiProviderId.openrouter);
      expect(event.model, 'provider/model');
      expect(event.requestType, 'tutorReply');
      expect(event.outcome, 'success');
      expect(event.totalTokens, 11);
      final metadata = jsonEncode({
        'provider': event.providerId.name,
        'model': event.model,
        'type': event.requestType,
        'outcome': event.outcome,
        'error': event.errorCategory,
        'tokens': event.totalTokens,
      });
      expect(metadata, isNot(contains('secret-key-sentinel')));
      expect(metadata, isNot(contains('learner-message-sentinel')));
      expect(metadata, isNot(contains('provider-response-sentinel')));
    },
  );

  test('records provider quota failure without swallowing it', () async {
    gateway.failure = const AiTutorException(AiFailureCode.quota);

    await expectLater(
      createTutor().reply(scenario: 'scenario', learnerMessage: 'message'),
      throwsA(
        isA<AiTutorException>().having(
          (error) => error.code,
          'code',
          AiFailureCode.quota,
        ),
      ),
    );

    expect(usage.events.single.outcome, 'failure');
    expect(usage.events.single.errorCategory, 'quota');
  });

  test('local accounting failure never replaces a provider success', () async {
    final reply = await createTutor(
      usageRepository: _FailingUsageRepository(),
    ).reply(scenario: 'scenario', learnerMessage: 'message');

    expect(reply.text, 'live reply');
  });

  test(
    'pins usage to the credential owner across an in-flight switch',
    () async {
      final providerStarted = Completer<void>();
      final releaseProvider = Completer<void>();
      gateway.onGenerate = () async {
        providerStarted.complete();
        await releaseProvider.future;
      };

      final reply = createTutor().reply(
        scenario: 'scenario',
        learnerMessage: 'message',
      );
      await providerStarted.future;
      activeOwner = 'owner-b';
      releaseProvider.complete();
      await reply;

      expect(usage.ownerIds, ['owner-a']);
    },
  );
}

final class _MemorySecureStore implements SecureValueStore {
  final Map<String, String> values = {};

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

final class _FakeGateway implements AiTutorGateway {
  AiProviderId providerIdValue = AiProviderId.openrouter;
  String modelValue = 'provider/model';
  AiTutorException? failure;
  AiGatewayReply reply = const AiGatewayReply(text: 'live reply');
  Future<void> Function()? onGenerate;

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
    await onGenerate?.call();
    if (failure case final error?) throw error;
    return reply;
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async => [AiModel(id: model)];

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {}
}

class _MemoryUsageRepository implements AiUsageRepository {
  final List<AiUsageEvent> events = [];
  final List<String> ownerIds = [];

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
  Future<void> recordForOwner(String ownerId, AiUsageEvent event) async {
    ownerIds.add(ownerId);
    events.add(event);
  }

  @override
  Future<List<AiUsageSummary>> summarize() async => const [];
}

final class _FailingUsageRepository extends _MemoryUsageRepository {
  @override
  Future<void> record(AiUsageEvent event) => throw StateError('disk-full');

  @override
  Future<void> recordForOwner(String ownerId, AiUsageEvent event) =>
      throw StateError('disk-full');
}
