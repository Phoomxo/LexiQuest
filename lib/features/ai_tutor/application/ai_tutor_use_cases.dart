import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../progress/domain/progress_models.dart';
import '../data/ai_tutor_gateway_factory.dart';
import '../domain/ai_tutor_contracts.dart';

typedef LoadAiTutorProgress = Future<ProgressSnapshot> Function();
typedef AiGatewayResolver =
    AiTutorGateway Function({
      required AiProviderId providerId,
      required String model,
      Uri? customBaseUrl,
    });

final class AiTutorUseCases implements AiTutorController {
  AiTutorUseCases({
    required this.store,
    required this.nowUtc,
    http.Client? httpClient,
    AiGatewayResolver? gatewayResolver,
    Duration requestTimeout = const Duration(seconds: 20),
    this.loadProgress,
    this.usageRepository,
    String Function()? usageEventId,
  }) : _usageEventId = usageEventId ?? const Uuid().v4,
       _gatewayResolver =
           gatewayResolver ??
           _defaultResolver(
             httpClient ?? http.Client(),
             requestTimeout: requestTimeout,
           );

  final AiTutorSettingsStore store;
  final AiGatewayResolver _gatewayResolver;
  final DateTime Function() nowUtc;
  final LoadAiTutorProgress? loadProgress;
  final AiUsageRepository? usageRepository;
  final String Function() _usageEventId;
  final Set<AiCancellation> _activeCancellations = {};
  final Set<Future<Object?>> _activeOperations = {};
  final _transitionGate = _AsyncSerialGate();
  bool _disposed = false;

  static AiGatewayResolver _defaultResolver(
    http.Client client, {
    required Duration requestTimeout,
  }) {
    final factory = AiTutorGatewayFactory(
      client: client,
      requestTimeout: requestTimeout,
    );
    return ({required providerId, required model, customBaseUrl}) =>
        factory.create(
          providerId: providerId,
          model: model,
          customBaseUrl: customBaseUrl,
        );
  }

  List<AiProviderConfig> get availableProviders => AiProviderConfig.all;

  @override
  Future<AiTutorSettingsStatus> loadSettings() {
    _checkNotDisposed();
    return _transitionGate.run(_loadSettingsUnlocked);
  }

  Future<AiTutorSettingsStatus> _loadSettingsUnlocked() async {
    final ownerId = await store.resolveActiveOwnerId();
    final credential = await store.readCredentialForOwner(ownerId);
    if (credential == null) {
      return const AiTutorSettingsStatus(
        hasKey: false,
        providerConsent: false,
        shareLearningSummary: false,
        providerId: AiProviderId.gemini,
        model: null,
      );
    }
    return AiTutorSettingsStatus(
      hasKey: credential.key.trim().isNotEmpty,
      providerConsent: credential.providerConsent,
      shareLearningSummary:
          credential.providerConsent && credential.shareLearningSummary,
      providerId: credential.providerId,
      model: credential.model.trim().isEmpty ? null : credential.model,
      customBaseUrl: credential.customBaseUrl,
    );
  }

  @override
  Future<List<AiModel>> listModels({
    required AiProviderId providerId,
    required String key,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    final effectiveCancellation = cancellation ?? AiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(() async {
        final customUri = _customUri(providerId, customBaseUrl);
        final gateway = _gatewayResolver(
          providerId: providerId,
          model: '_model_discovery_',
          customBaseUrl: customUri,
        );
        return gateway.listModels(
          key.trim(),
          cancellation: effectiveCancellation,
        );
      }),
    );
  }

  @override
  Future<void> configure({
    required String key,
    required bool providerConsent,
    required bool shareLearningSummary,
    required AiProviderId providerId,
    required String model,
    String? customBaseUrl,
    AiCancellation? cancellation,
  }) async {
    _checkNotDisposed();
    if (!providerConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
    }
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty || normalizedModel.length > 200) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    final effectiveCancellation = cancellation ?? AiCancellation();
    await _track(
      effectiveCancellation,
      _transitionGate.run(() async {
        final ownerId = await store.resolveActiveOwnerId();
        final customUri = _customUri(providerId, customBaseUrl);
        final gateway = _gatewayResolver(
          providerId: providerId,
          model: normalizedModel,
          customBaseUrl: customUri,
        );
        final models = await gateway.listModels(
          key.trim(),
          cancellation: effectiveCancellation,
        );
        final modelIsListed = models.any(
          (candidate) => candidate.id == normalizedModel,
        );
        if (!modelIsListed &&
            (providerId != AiProviderId.customOpenAi || models.isNotEmpty)) {
          throw const AiTutorException(AiFailureCode.missingModel);
        }
        await _runConfigurationProbe(
          ownerId: ownerId,
          gateway: gateway,
          key: key.trim(),
          cancellation: effectiveCancellation,
        );
        await store.writeCredentialForOwner(
          ownerId,
          AiTutorCredential(
            key: key.trim(),
            providerId: providerId,
            model: normalizedModel,
            providerConsent: true,
            shareLearningSummary: shareLearningSummary,
            customBaseUrl: customUri?.toString(),
          ),
        );
      }),
    );
  }

  @override
  Future<List<AiModel>> listModelsForActiveCredential({
    AiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    final effectiveCancellation = cancellation ?? AiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(() async {
        final ownerId = await store.resolveActiveOwnerId();
        final credential = await store.readCredentialForOwner(ownerId);
        if (credential == null || credential.key.trim().isEmpty) {
          throw const AiTutorException(AiFailureCode.missingKey);
        }
        if (!credential.providerConsent) {
          throw const AiTutorException(AiFailureCode.consentRequired);
        }
        final customUri = _customUri(
          credential.providerId,
          credential.customBaseUrl,
        );
        final gateway = _gatewayResolver(
          providerId: credential.providerId,
          model: '_model_discovery_',
          customBaseUrl: customUri,
        );
        return gateway.listModels(
          credential.key.trim(),
          cancellation: effectiveCancellation,
        );
      }),
    );
  }

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) async {
    _checkNotDisposed();
    final normalizedModel = model.trim();
    if (normalizedModel.isEmpty || normalizedModel.length > 200) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    final effectiveCancellation = cancellation ?? AiCancellation();
    await _track(
      effectiveCancellation,
      _transitionGate.run(() async {
        final ownerId = await store.resolveActiveOwnerId();
        final previous = await store.readCredentialForOwner(ownerId);
        if (previous == null || previous.key.trim().isEmpty) {
          throw const AiTutorException(AiFailureCode.missingKey);
        }
        if (!previous.providerConsent) {
          throw const AiTutorException(AiFailureCode.consentRequired);
        }
        final customUri = _customUri(
          previous.providerId,
          previous.customBaseUrl,
        );
        final gateway = _gatewayResolver(
          providerId: previous.providerId,
          model: normalizedModel,
          customBaseUrl: customUri,
        );
        final models = await gateway.listModels(
          previous.key.trim(),
          cancellation: effectiveCancellation,
        );
        final modelIsListed = models.any((c) => c.id == normalizedModel);
        if (!modelIsListed &&
            (previous.providerId != AiProviderId.customOpenAi ||
                models.isNotEmpty)) {
          throw const AiTutorException(AiFailureCode.missingModel);
        }
        await _runConfigurationProbe(
          ownerId: ownerId,
          gateway: gateway,
          key: previous.key.trim(),
          cancellation: effectiveCancellation,
        );
        await store.writeCredentialForOwner(
          ownerId,
          previous.copyWith(
            model: normalizedModel,
            shareLearningSummary: shareLearningSummary,
          ),
        );
      }),
    );
  }

  Future<void> _runConfigurationProbe({
    required String ownerId,
    required AiTutorGateway gateway,
    required String key,
    required AiCancellation cancellation,
  }) async {
    final stopwatch = Stopwatch()..start();
    try {
      final reply = await gateway.generateTutorReply(
        key: key,
        scenario: 'Configuration validation',
        learnerMessage: 'Reply with OK.',
        learningSummary: null,
        cancellation: cancellation,
      );
      stopwatch.stop();
      final completedAt = nowUtc();
      if (!completedAt.isUtc) {
        throw ArgumentError.value(completedAt, 'nowUtc', 'must return UTC');
      }
      await _recordUsage(
        ownerId: ownerId,
        occurredAtUtc: completedAt,
        providerId: gateway.providerId,
        model: gateway.model,
        requestType: 'configurationValidation',
        outcome: 'success',
        latencyMs: stopwatch.elapsedMilliseconds,
        usage: reply.usage,
      );
    } on AiTutorException catch (error) {
      stopwatch.stop();
      final failedAt = nowUtc();
      if (failedAt.isUtc) {
        await _recordUsage(
          ownerId: ownerId,
          occurredAtUtc: failedAt,
          providerId: gateway.providerId,
          model: gateway.model,
          requestType: 'configurationValidation',
          outcome: 'failure',
          errorCategory: error.code.name,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      rethrow;
    }
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    _checkNotDisposed();
    final transition = _transitionGate.run(() async {
      final ownerId = await store.resolveActiveOwnerId();
      final current = await store.readCredentialForOwner(ownerId);
      if (current == null) {
        throw const AiTutorException(AiFailureCode.missingKey);
      }
      await store.writeCredentialForOwner(
        ownerId,
        current.copyWith(
          providerConsent: providerConsent,
          shareLearningSummary: providerConsent && shareLearningSummary,
        ),
      );
    });
    if (!providerConsent) await _cancelActiveOperations();
    await transition;
  }

  @override
  Future<void> removeKey() async {
    _checkNotDisposed();
    final transition = _transitionGate.run(() async {
      final ownerId = await store.resolveActiveOwnerId();
      await store.deleteCredentialForOwner(ownerId);
    });
    await _cancelActiveOperations();
    await transition;
  }

  @override
  Future<AiTutorReply> reply({
    required String scenario,
    required String learnerMessage,
    AiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    final effectiveCancellation = cancellation ?? AiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(
        () => _reply(
          scenario: scenario,
          learnerMessage: learnerMessage,
          cancellation: effectiveCancellation,
        ),
      ),
    );
  }

  Future<AiTutorReply> _reply({
    required String scenario,
    required String learnerMessage,
    required AiCancellation cancellation,
  }) async {
    final ownerId = await store.resolveActiveOwnerId();
    final credential = await store.readCredentialForOwner(ownerId);
    if (credential == null || credential.key.trim().isEmpty) {
      throw const AiTutorException(AiFailureCode.missingKey);
    }
    if (!credential.providerConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
    }
    if (credential.model.trim().isEmpty) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    String? summary;
    if (credential.shareLearningSummary && loadProgress != null) {
      summary = _progressSummary(await loadProgress!());
    }
    final gateway = _gatewayResolver(
      providerId: credential.providerId,
      model: credential.model,
      customBaseUrl: _customUri(
        credential.providerId,
        credential.customBaseUrl,
      ),
    );
    final stopwatch = Stopwatch()..start();
    try {
      final providerReply = await gateway.generateTutorReply(
        key: credential.key,
        scenario: scenario,
        learnerMessage: learnerMessage,
        learningSummary: summary,
        cancellation: cancellation,
      );
      stopwatch.stop();
      final generatedAtUtc = nowUtc();
      if (!generatedAtUtc.isUtc) {
        throw ArgumentError.value(generatedAtUtc, 'nowUtc', 'must return UTC');
      }
      await _recordUsage(
        ownerId: ownerId,
        occurredAtUtc: generatedAtUtc,
        providerId: gateway.providerId,
        model: gateway.model,
        requestType: 'tutorReply',
        outcome: 'success',
        latencyMs: stopwatch.elapsedMilliseconds,
        usage: providerReply.usage,
      );
      return AiTutorReply(
        text: providerReply.text,
        providerId: gateway.providerId,
        model: gateway.model,
        generatedAtUtc: generatedAtUtc,
        usage: providerReply.usage,
      );
    } on AiTutorException catch (error) {
      stopwatch.stop();
      final failedAt = nowUtc();
      if (failedAt.isUtc) {
        await _recordUsage(
          ownerId: ownerId,
          occurredAtUtc: failedAt,
          providerId: gateway.providerId,
          model: gateway.model,
          requestType: 'tutorReply',
          outcome: 'failure',
          errorCategory: error.code.name,
          latencyMs: stopwatch.elapsedMilliseconds,
        );
      }
      rethrow;
    }
  }

  Future<void> _recordUsage({
    required String ownerId,
    required DateTime occurredAtUtc,
    required AiProviderId providerId,
    required String model,
    required String requestType,
    required String outcome,
    required int latencyMs,
    String? errorCategory,
    AiTokenUsage? usage,
  }) async {
    final repository = usageRepository;
    if (repository == null) return;
    try {
      await repository.recordForOwner(
        ownerId,
        AiUsageEvent(
          eventId: _usageEventId(),
          occurredAtUtc: occurredAtUtc,
          providerId: providerId,
          model: model,
          requestType: requestType,
          outcome: outcome,
          errorCategory: errorCategory,
          latencyMs: latencyMs,
          inputTokens: usage?.inputTokens,
          outputTokens: usage?.outputTokens,
          totalTokens: usage?.totalTokens,
          cachedTokens: usage?.cachedTokens,
          providerReportedCostMicrosUsd: usage?.providerReportedCostMicrosUsd,
        ),
      );
    } on Object {
      // Local usage telemetry must never break the learner's provider request.
    }
  }

  Uri? _customUri(AiProviderId providerId, String? raw) {
    if (providerId != AiProviderId.customOpenAi) return null;
    if (raw == null || raw.trim().isEmpty) {
      throw const AiTutorException(AiFailureCode.unsafeEndpoint);
    }
    return validateCustomAiBaseUri(Uri.parse(raw.trim()));
  }

  String _progressSummary(ProgressSnapshot progress) {
    final accuracy = progress.accuracy == null
        ? 'none'
        : '${(progress.accuracy! * 100).round()}%';
    final weaknesses = progress.weaknesses
        .take(3)
        .map(
          (item) =>
              '${item.spelling}:${(item.errorRate * 100).round()}%'
              '(n=${item.sampleSize})',
        )
        .join(',');
    return 'answers=${progress.sampleSize};accuracy=$accuracy;'
        'due=${progress.dueReviewCount};mastered=${progress.masteredWordCount};'
        'weaknesses=${weaknesses.isEmpty ? 'none' : weaknesses}';
  }

  Future<T> _track<T>(AiCancellation cancellation, Future<T> operation) {
    _activeCancellations.add(cancellation);
    late Future<T> tracked;
    tracked = operation.whenComplete(() {
      _activeCancellations.remove(cancellation);
      _activeOperations.remove(tracked);
    });
    _activeOperations.add(tracked);
    return tracked;
  }

  @override
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    await _cancelActiveOperations();
  }

  Future<void> _cancelActiveOperations() async {
    for (final cancellation in _activeCancellations.toList()) {
      cancellation.cancel();
    }
    final active = _activeOperations.toList(growable: false);
    if (active.isNotEmpty) {
      await Future.wait(
        active.map(
          (operation) => operation.then<void>((_) {}, onError: (_) {}),
        ),
      );
    }
  }

  void _checkNotDisposed() {
    if (_disposed) throw const AiTutorException(AiFailureCode.cancelled);
  }
}

final class _AsyncSerialGate {
  Future<void> _tail = Future<void>.value();

  Future<T> run<T>(Future<T> Function() action) {
    final previous = _tail;
    final release = Completer<void>();
    _tail = release.future;
    return () async {
      await previous;
      try {
        return await action();
      } finally {
        release.complete();
      }
    }();
  }
}
