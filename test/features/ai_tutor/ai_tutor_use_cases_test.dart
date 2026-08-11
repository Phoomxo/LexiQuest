import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/ai_tutor_use_cases.dart';
import 'package:vocab_learning_app/features/ai_tutor/application/owner_operation_coordinator.dart';
import 'package:vocab_learning_app/features/ai_tutor/data/ai_tutor_settings_store.dart';
import 'package:vocab_learning_app/features/ai_tutor/domain/ai_tutor_contracts.dart';
import 'package:vocab_learning_app/features/gemini/data/secure_gemini_settings_store.dart';
import 'package:vocab_learning_app/features/progress/domain/progress_models.dart';
import 'package:vocab_learning_app/features/sync/domain/owner_operation_gate.dart';

void main() {
  late SecureAiTutorSettingsStore store;
  late _MemorySecureStore secureStorage;
  late _FakeGateway gateway;
  late _MemoryUsageRepository usage;
  late String activeOwner;

  setUp(() async {
    activeOwner = 'owner-a';
    secureStorage = _MemorySecureStore();
    store = SecureAiTutorSettingsStore(
      secureStorage,
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

  AiTutorUseCases createTutor({
    String Function()? eventId,
    _OpenOwnerGate? gate,
    Future<ProgressSnapshot> Function()? loadProgress,
  }) {
    final operationGate = gate ?? _OpenOwnerGate();
    return AiTutorUseCases(
      store: store,
      gatewayResolver: ({required providerId, required model, customBaseUrl}) {
        gateway.providerIdValue = providerId;
        gateway.modelValue = model;
        return gateway;
      },
      nowUtc: () => DateTime.utc(2026, 8, 9),
      usageRepository: usage,
      usageEventId: eventId ?? () => 'usage-event',
      loadProgress: loadProgress,
      ownerCoordinator: OwnerOperationCoordinator(
        gate: operationGate,
        activeOwnerId: () async => activeOwner,
        generateToken: () => 'lease-token',
      ),
    );
  }

  test('durable pending insert completes before the provider starts', () async {
    final allowBegin = Completer<void>();
    usage.beforeBegin = () => allowBegin.future;
    final tutor = createTutor();

    final replying = tutor.reply(
      scenario: 'scenario',
      learnerMessage: 'message',
    );
    await Future<void>.delayed(Duration.zero);
    expect(gateway.generateCalls, 0);
    allowBegin.complete();

    final reply = await replying;
    expect(reply.text, 'live reply');
    expect(gateway.generateCalls, 1);
    expect(usage.timeline, <String>[
      'begin:usage-event',
      'success:usage-event',
    ]);
    expect(usage.pending, isEmpty);
  });

  test(
    'begin failure is local-persistence and makes zero provider calls',
    () async {
      usage.failBegin = true;

      await expectLater(
        createTutor().reply(scenario: 'scenario', learnerMessage: 'message'),
        throwsA(_aiFailure(AiFailureCode.localPersistence)),
      );

      expect(gateway.generateCalls, 0);
    },
  );

  test(
    'loadUsage normalizes repository failure to local-persistence',
    () async {
      usage.failSummarize = true;

      await expectLater(
        createTutor().loadUsage(),
        throwsA(_aiFailure(AiFailureCode.localPersistence)),
      );
    },
  );

  test('loadUsage preserves typed repository failure identity', () async {
    final sentinel = AiTutorException(AiFailureCode.timeout);
    usage.summarizeFailure = sentinel;

    await expectLater(
      createTutor().loadUsage(),
      throwsA(
        allOf(
          same(sentinel),
          isA<AiTutorException>().having(
            (error) => error.code,
            'code',
            AiFailureCode.timeout,
          ),
        ),
      ),
    );
  });

  test(
    'clearUsage normalizes repository failure to local-persistence',
    () async {
      usage.failClear = true;

      await expectLater(
        createTutor().clearUsage(),
        throwsA(_aiFailure(AiFailureCode.localPersistence)),
      );
    },
  );

  test('clearUsage preserves typed repository failure identity', () async {
    final sentinel = AiTutorException(AiFailureCode.cancelled);
    usage.clearFailure = sentinel;

    await expectLater(
      createTutor().clearUsage(),
      throwsA(
        allOf(
          same(sentinel),
          isA<AiTutorException>().having(
            (error) => error.code,
            'code',
            AiFailureCode.cancelled,
          ),
        ),
      ),
    );
  });

  test(
    'opted-in learning-summary load failure is local-persistence with zero provider calls',
    () async {
      await store.writeCredential(
        const AiTutorCredential(
          key: 'secret-key-sentinel',
          providerId: AiProviderId.openrouter,
          model: 'provider/model',
          providerConsent: true,
          shareLearningSummary: true,
        ),
      );

      await expectLater(
        createTutor(
          loadProgress: () async => throw StateError('progress read failed'),
        ).reply(scenario: 'scenario', learnerMessage: 'message'),
        throwsA(_aiFailure(AiFailureCode.localPersistence)),
      );

      expect(gateway.generateCalls, 0);
    },
  );

  test(
    'opted-in learning-summary preserves typed failure identity with zero provider calls',
    () async {
      final sentinel = AiTutorException(AiFailureCode.circuitOpen);
      await store.writeCredential(
        const AiTutorCredential(
          key: 'secret-key-sentinel',
          providerId: AiProviderId.openrouter,
          model: 'provider/model',
          providerConsent: true,
          shareLearningSummary: true,
        ),
      );

      await expectLater(
        createTutor(
          loadProgress: () async => throw sentinel,
        ).reply(scenario: 'scenario', learnerMessage: 'message'),
        throwsA(
          allOf(
            same(sentinel),
            isA<AiTutorException>().having(
              (error) => error.code,
              'code',
              AiFailureCode.circuitOpen,
            ),
          ),
        ),
      );

      expect(gateway.generateCalls, 0);
    },
  );

  test(
    'cancellation during begin makes zero provider calls and terminates row',
    () async {
      final allowBegin = Completer<void>();
      usage.beforeBegin = () => allowBegin.future;
      final cancellation = AiCancellation();
      final replying = createTutor().reply(
        scenario: 'scenario',
        learnerMessage: 'message',
        cancellation: cancellation,
      );
      final expectation = expectLater(
        replying,
        throwsA(_aiFailure(AiFailureCode.cancelled)),
      );
      await Future<void>.delayed(Duration.zero);
      cancellation.cancel();
      allowBegin.complete();

      await expectation;
      expect(gateway.generateCalls, 0);
      expect(usage.completed.single.$2.errorCategory, 'cancelled');
    },
  );

  test(
    'paid success is returned while durable pending awaits recovery',
    () async {
      usage.failFinalize = true;

      final reply = await createTutor().reply(
        scenario: 'scenario',
        learnerMessage: 'message',
      );

      expect(reply.text, 'live reply');
      expect(gateway.generateCalls, 1);
      expect(usage.finalizeCalls, 2);
      expect(usage.pending.keys, <String>['owner-a/usage-event']);
    },
  );

  test(
    'terminally accounted paid success survives a late lease loss',
    () async {
      final gate = _OpenOwnerGate();
      usage.afterFinalize = () => gate.token = null;

      final reply = await createTutor(
        gate: gate,
      ).reply(scenario: 'scenario', learnerMessage: 'message');

      expect(reply.text, 'live reply');
      expect(gateway.generateCalls, 1);
      expect(usage.completed.single.$2.outcome, 'success');
    },
  );

  test(
    'lease loss before terminal accounting returns paid success pending',
    () async {
      final gate = _OpenOwnerGate(renewResult: false);
      final ownershipCheckStarted = Completer<void>();
      final allowOwnershipCheck = Completer<void>();
      gate.beforeIsOwned = () async {
        if (!ownershipCheckStarted.isCompleted) {
          ownershipCheckStarted.complete();
        }
        await allowOwnershipCheck.future;
      };
      final tutor = AiTutorUseCases(
        store: store,
        gatewayResolver:
            ({required providerId, required model, customBaseUrl}) => gateway,
        nowUtc: () => DateTime.now().toUtc(),
        usageRepository: usage,
        usageEventId: () => 'usage-event',
        ownerCoordinator: OwnerOperationCoordinator(
          gate: gate,
          activeOwnerId: () async => activeOwner,
          generateToken: () => 'lease-token',
          leaseDuration: const Duration(milliseconds: 100),
          heartbeatInterval: const Duration(milliseconds: 5),
        ),
      );

      final replying = tutor.reply(
        scenario: 'scenario',
        learnerMessage: 'message',
      );
      await ownershipCheckStarted.future;
      await gate.leaseLost.future.timeout(const Duration(seconds: 1));
      allowOwnershipCheck.complete();
      final reply = await replying;

      expect(reply.text, 'live reply');
      expect(gateway.generateCalls, 1);
      expect(usage.finalizeCalls, 0);
      expect(usage.pending.keys, <String>['owner-a/usage-event']);
    },
  );

  test(
    'provider failure remains primary when terminal persistence fails',
    () async {
      gateway.failure = const AiTutorException(AiFailureCode.quota);
      usage.failFinalize = true;

      await expectLater(
        createTutor().reply(scenario: 'scenario', learnerMessage: 'message'),
        throwsA(_aiFailure(AiFailureCode.quota)),
      );

      expect(usage.finalizeCalls, 1);
      expect(usage.pending.keys, <String>['owner-a/usage-event']);
    },
  );

  test('success and provider failure finalize the same pending row', () async {
    final tutor = createTutor();
    await tutor.reply(scenario: 'scenario', learnerMessage: 'message');
    final success = usage.completed.single;
    expect(success.$1, 'owner-a');
    expect(success.$2.outcome, 'success');

    usage.reset();
    gateway.failure = const AiTutorException(AiFailureCode.timeout);
    await expectLater(
      tutor.reply(scenario: 'scenario', learnerMessage: 'message'),
      throwsA(_aiFailure(AiFailureCode.timeout)),
    );
    final failure = usage.completed.single.$2;
    expect(failure.outcome, 'failure');
    expect(failure.errorCategory, 'timeout');
  });

  test(
    'owner is pinned before external work despite an in-flight switch',
    () async {
      final providerStarted = Completer<void>();
      final releaseProvider = Completer<void>();
      gateway.onGenerate = () async {
        providerStarted.complete();
        await releaseProvider.future;
      };
      final replying = createTutor().reply(
        scenario: 'scenario',
        learnerMessage: 'message',
      );
      await providerStarted.future;
      activeOwner = 'owner-b';
      releaseProvider.complete();

      await replying;
      expect(usage.ownerIds, everyElement('owner-a'));
    },
  );

  test('duplicate event id aborts before a second provider call', () async {
    final tutor = createTutor(eventId: () => 'duplicate');
    await tutor.reply(scenario: 'one', learnerMessage: 'one');

    await expectLater(
      tutor.reply(scenario: 'two', learnerMessage: 'two'),
      throwsA(_aiFailure(AiFailureCode.localPersistence)),
    );

    expect(gateway.generateCalls, 1);
  });

  test(
    'malformed custom endpoint is a typed unsafe-endpoint failure',
    () async {
      await expectLater(
        createTutor().listModels(
          providerId: AiProviderId.customOpenAi,
          key: 'secret-key-sentinel',
          customBaseUrl: 'https://provider.example/%ZZ',
        ),
        throwsA(_aiFailure(AiFailureCode.unsafeEndpoint)),
      );

      expect(gateway.generateCalls, 0);
    },
  );

  test(
    'lease loss during credential read performs no secure mutation',
    () async {
      final gate = _OpenOwnerGate(renewResult: false);
      final readStarted = Completer<void>();
      final allowRead = Completer<void>();
      secureStorage.beforeRead = () async {
        if (!readStarted.isCompleted) readStarted.complete();
        await allowRead.future;
      };
      final writesBefore = secureStorage.writeCalls;
      final tutor = AiTutorUseCases(
        store: store,
        gatewayResolver:
            ({required providerId, required model, customBaseUrl}) => gateway,
        nowUtc: () => DateTime.now().toUtc(),
        usageRepository: usage,
        usageEventId: () => 'usage-event',
        ownerCoordinator: OwnerOperationCoordinator(
          gate: gate,
          activeOwnerId: () async => activeOwner,
          generateToken: () => 'lease-token',
          leaseDuration: const Duration(milliseconds: 100),
          heartbeatInterval: const Duration(milliseconds: 5),
        ),
      );

      final updating = tutor.updateConsents(
        providerConsent: false,
        shareLearningSummary: false,
      );
      final expectation = expectLater(
        updating,
        throwsA(_aiFailure(AiFailureCode.cancelled)),
      );
      await readStarted.future;
      await gate.firstRenew.future.timeout(const Duration(seconds: 1));
      try {
        await gate.leaseLost.future.timeout(const Duration(seconds: 1));
      } finally {
        if (!allowRead.isCompleted) allowRead.complete();
      }
      await expectation;

      expect(secureStorage.writeCalls, writesBefore);
      secureStorage.beforeRead = null;
      expect(
        (await store.readCredentialForOwner('owner-a'))!.providerConsent,
        isTrue,
      );
      expect(gate.releaseCalls, 1);
    },
  );

  test(
    'lease loss during secure write restores the previous credential',
    () async {
      final gate = _OpenOwnerGate(renewResult: false);
      final writeStarted = Completer<void>();
      final allowWrite = Completer<void>();
      var blockNextWrite = true;
      secureStorage.beforeWrite = () async {
        if (!blockNextWrite) return;
        blockNextWrite = false;
        writeStarted.complete();
        await allowWrite.future;
      };
      final tutor = AiTutorUseCases(
        store: store,
        gatewayResolver:
            ({required providerId, required model, customBaseUrl}) => gateway,
        nowUtc: () => DateTime.now().toUtc(),
        usageRepository: usage,
        usageEventId: () => 'usage-event',
        ownerCoordinator: OwnerOperationCoordinator(
          gate: gate,
          activeOwnerId: () async => activeOwner,
          generateToken: () => 'lease-token',
          leaseDuration: const Duration(milliseconds: 100),
          heartbeatInterval: const Duration(milliseconds: 5),
        ),
      );

      final updating = tutor.updateConsents(
        providerConsent: false,
        shareLearningSummary: false,
      );
      final expectation = expectLater(
        updating,
        throwsA(_aiFailure(AiFailureCode.cancelled)),
      );
      await writeStarted.future;
      await gate.leaseLost.future.timeout(const Duration(seconds: 1));
      allowWrite.complete();
      await expectation;

      secureStorage.beforeWrite = null;
      expect(
        (await store.readCredentialForOwner('owner-a'))!.providerConsent,
        isTrue,
      );
      expect(gate.releaseCalls, 1);
    },
  );
}

Matcher _aiFailure(AiFailureCode code) =>
    isA<AiTutorException>().having((error) => error.code, 'code', code);

final class _MemorySecureStore implements SecureValueStore {
  final Map<String, String> values = <String, String>{};
  Future<void> Function()? beforeRead;
  Future<void> Function()? beforeWrite;
  int writeCalls = 0;

  @override
  Future<void> delete(String key) async => values.remove(key);

  @override
  Future<String?> read(String key) async {
    await beforeRead?.call();
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writeCalls += 1;
    await beforeWrite?.call();
    values[key] = value;
  }
}

final class _FakeGateway implements AiTutorGateway {
  AiProviderId providerIdValue = AiProviderId.openrouter;
  String modelValue = 'provider/model';
  AiTutorException? failure;
  Future<void> Function()? onGenerate;
  int generateCalls = 0;

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
    generateCalls++;
    await onGenerate?.call();
    if (failure case final error?) throw error;
    return const AiGatewayReply(
      text: 'live reply',
      usage: AiTokenUsage(inputTokens: 2, outputTokens: 3, totalTokens: 5),
    );
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async => <AiModel>[AiModel(id: model)];

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {}
}

final class _MemoryUsageRepository implements AiUsageRepository {
  final Map<String, AiUsageAttempt> pending = <String, AiUsageAttempt>{};
  final List<(String, AiUsageCompletion)> completed =
      <(String, AiUsageCompletion)>[];
  final List<String> timeline = <String>[];
  final List<String> ownerIds = <String>[];
  Future<void> Function()? beforeBegin;
  bool failBegin = false;
  bool failFinalize = false;
  bool failSummarize = false;
  bool failClear = false;
  AiTutorException? summarizeFailure;
  AiTutorException? clearFailure;
  int finalizeCalls = 0;
  void Function()? afterFinalize;

  @override
  Future<void> beginForOwner(String ownerId, AiUsageAttempt attempt) async {
    await beforeBegin?.call();
    if (failBegin) throw StateError('begin failed');
    final key = '$ownerId/${attempt.eventId}';
    if (pending.containsKey(key) ||
        completed.any((item) => '${item.$1}/${item.$2.eventId}' == key)) {
      throw StateError('duplicate');
    }
    pending[key] = attempt;
    ownerIds.add(ownerId);
    timeline.add('begin:${attempt.eventId}');
  }

  @override
  Future<AiUsageFinalizeResult> finalizeForOwner(
    String ownerId,
    AiUsageCompletion completion,
  ) async {
    finalizeCalls++;
    if (failFinalize) throw StateError('finalize failed');
    final key = '$ownerId/${completion.eventId}';
    if (pending.remove(key) == null) throw StateError('missing pending');
    completed.add((ownerId, completion));
    ownerIds.add(ownerId);
    timeline.add('${completion.outcome}:${completion.eventId}');
    afterFinalize?.call();
    return AiUsageFinalizeResult.finalized;
  }

  void reset() {
    pending.clear();
    completed.clear();
    timeline.clear();
    ownerIds.clear();
    finalizeCalls = 0;
  }

  @override
  Future<int> recoverPendingStartedBefore(
    DateTime cutoffUtc, {
    required DateTime recoveredAtUtc,
  }) async => 0;

  @override
  Future<void> clear() async {}

  @override
  Future<void> clearForOwner(String ownerId) async {
    final failure = clearFailure;
    if (failure != null) throw failure;
    if (failClear) throw StateError('clear failed');
  }

  @override
  Future<String> exportAggregateJson({required bool researchConsent}) async =>
      '{}';

  @override
  Future<int> purgeExpired(DateTime nowUtc) async => 0;

  @override
  Future<int> purgeExpiredForOwner(String ownerId, DateTime nowUtc) async => 0;

  @override
  Future<List<AiUsageSummary>> summarize() async => const <AiUsageSummary>[];

  @override
  Future<List<AiUsageSummary>> summarizeForOwner(String ownerId) async {
    final failure = summarizeFailure;
    if (failure != null) throw failure;
    if (failSummarize) throw StateError('summarize failed');
    return const <AiUsageSummary>[];
  }
}

final class _OpenOwnerGate implements OwnerOperationGate {
  _OpenOwnerGate({this.renewResult = true});

  final bool renewResult;
  String? token;
  int releaseCalls = 0;
  final Completer<void> firstRenew = Completer<void>();
  final Completer<void> leaseLost = Completer<void>();
  Future<void> Function()? beforeIsOwned;

  @override
  Future<bool> tryAcquire({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    this.token = token;
    return true;
  }

  @override
  Future<bool> renew({
    required String token,
    required DateTime nowUtc,
    required Duration leaseDuration,
  }) async {
    if (!firstRenew.isCompleted) firstRenew.complete();
    if (!renewResult) {
      this.token = null;
      if (!leaseLost.isCompleted) leaseLost.complete();
      return false;
    }
    return this.token == token;
  }

  @override
  Future<bool> isOwned({
    required String token,
    required DateTime nowUtc,
  }) async {
    await beforeIsOwned?.call();
    return this.token == token;
  }

  @override
  Future<void> release({required String token}) async {
    releaseCalls += 1;
    if (this.token == token) this.token = null;
  }
}
