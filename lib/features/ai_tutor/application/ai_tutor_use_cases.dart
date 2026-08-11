import 'dart:async';

import 'package:uuid/uuid.dart';

import '../../progress/domain/progress_models.dart';
import '../domain/ai_tutor_contracts.dart';
import 'owner_operation_coordinator.dart';

typedef LoadAiTutorProgress = Future<ProgressSnapshot> Function();
typedef AiGatewayResolver =
    AiTutorGateway Function({
      required AiProviderId providerId,
      required String model,
      Uri? customBaseUrl,
    });

AiGatewayResolver _retainGatewayResolver(AiGatewayResolver value) => value;

final class AiTutorUseCases implements AiTutorController {
  AiTutorUseCases({
    required this.store,
    required this.nowUtc,
    required AiGatewayResolver gatewayResolver,
    required this.usageRepository,
    required this.ownerCoordinator,
    this.loadProgress,
    String Function()? usageEventId,
  }) : _usageEventId = usageEventId ?? const Uuid().v4,
       _gatewayResolver = _retainGatewayResolver(gatewayResolver);

  final AiTutorSettingsStore store;
  final AiGatewayResolver _gatewayResolver;
  final DateTime Function() nowUtc;
  final LoadAiTutorProgress? loadProgress;
  final AiUsageRepository usageRepository;
  final OwnerOperationCoordinator ownerCoordinator;
  final String Function() _usageEventId;
  final Set<AiCancellation> _activeCancellations = <AiCancellation>{};
  final Set<Future<Object?>> _activeOperations = <Future<Object?>>{};
  final _AsyncSerialGate _transitionGate = _AsyncSerialGate();
  bool _disposed = false;
  Future<void>? _disposeFuture;

  List<AiProviderConfig> get availableProviders => AiProviderConfig.all;

  @override
  Future<AiTutorSettingsStatus> loadSettings() {
    _checkNotDisposed();
    final cancellation = AiCancellation();
    return _track(
      cancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(cancellation, (ownerId) async {
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
        }),
      ),
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
      _transitionGate.run(
        () => ownerCoordinator.run(effectiveCancellation, (ownerId) async {
          final gateway = _resolveGateway(
            providerId: providerId,
            model: '_model_discovery_',
            customBaseUrl: _customUri(providerId, customBaseUrl),
          );
          return _accounted<List<AiModel>>(
            ownerId: ownerId,
            gateway: gateway,
            requestType: 'modelDiscovery',
            cancellation: effectiveCancellation,
            operation: () => gateway.listModels(
              key.trim(),
              cancellation: effectiveCancellation,
            ),
          );
        }),
      ),
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
  }) {
    _checkNotDisposed();
    if (!providerConsent) {
      throw const AiTutorException(AiFailureCode.consentRequired);
    }
    final normalizedModel = _requiredModel(model);
    final effectiveCancellation = cancellation ?? AiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(effectiveCancellation, (ownerId) async {
          final customUri = _customUri(providerId, customBaseUrl);
          final gateway = _resolveGateway(
            providerId: providerId,
            model: normalizedModel,
            customBaseUrl: customUri,
          );
          final models = await _accounted<List<AiModel>>(
            ownerId: ownerId,
            gateway: gateway,
            requestType: 'modelDiscovery',
            cancellation: effectiveCancellation,
            operation: () => gateway.listModels(
              key.trim(),
              cancellation: effectiveCancellation,
            ),
          );
          _requireListedModel(providerId, normalizedModel, models);
          await _configurationProbe(
            ownerId: ownerId,
            gateway: gateway,
            key: key.trim(),
            cancellation: effectiveCancellation,
          );
          await _replaceCredential(
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
      ),
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
      _transitionGate.run(
        () => ownerCoordinator.run(effectiveCancellation, (ownerId) async {
          final credential = await _requiredCredential(ownerId);
          final gateway = _resolveGateway(
            providerId: credential.providerId,
            model: '_model_discovery_',
            customBaseUrl: _customUri(
              credential.providerId,
              credential.customBaseUrl,
            ),
          );
          return _accounted<List<AiModel>>(
            ownerId: ownerId,
            gateway: gateway,
            requestType: 'modelDiscovery',
            cancellation: effectiveCancellation,
            operation: () => gateway.listModels(
              credential.key.trim(),
              cancellation: effectiveCancellation,
            ),
          );
        }),
      ),
    );
  }

  @override
  Future<void> configureActiveModel({
    required String model,
    required bool shareLearningSummary,
    AiCancellation? cancellation,
  }) {
    _checkNotDisposed();
    final normalizedModel = _requiredModel(model);
    final effectiveCancellation = cancellation ?? AiCancellation();
    return _track(
      effectiveCancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(effectiveCancellation, (ownerId) async {
          final previous = await _requiredCredential(ownerId);
          final gateway = _resolveGateway(
            providerId: previous.providerId,
            model: normalizedModel,
            customBaseUrl: _customUri(
              previous.providerId,
              previous.customBaseUrl,
            ),
          );
          final models = await _accounted<List<AiModel>>(
            ownerId: ownerId,
            gateway: gateway,
            requestType: 'modelDiscovery',
            cancellation: effectiveCancellation,
            operation: () => gateway.listModels(
              previous.key.trim(),
              cancellation: effectiveCancellation,
            ),
          );
          _requireListedModel(previous.providerId, normalizedModel, models);
          await _configurationProbe(
            ownerId: ownerId,
            gateway: gateway,
            key: previous.key.trim(),
            cancellation: effectiveCancellation,
          );
          await _replaceCredential(
            ownerId,
            previous.copyWith(
              model: normalizedModel,
              shareLearningSummary: shareLearningSummary,
            ),
          );
        }),
      ),
    );
  }

  Future<void> _configurationProbe({
    required String ownerId,
    required AiTutorGateway gateway,
    required String key,
    required AiCancellation cancellation,
  }) async {
    await _accounted<AiGatewayReply>(
      ownerId: ownerId,
      gateway: gateway,
      requestType: 'configurationValidation',
      cancellation: cancellation,
      operation: () => gateway.generateTutorReply(
        key: key,
        scenario: 'Configuration validation',
        learnerMessage: 'Reply with OK.',
        learningSummary: null,
        cancellation: cancellation,
      ),
      usageOf: (reply) => reply.usage,
    );
  }

  @override
  Future<void> updateConsents({
    required bool providerConsent,
    required bool shareLearningSummary,
  }) async {
    _checkNotDisposed();
    if (!providerConsent) await _cancelActiveOperations();
    final cancellation = AiCancellation();
    await _track(
      cancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(cancellation, (ownerId) async {
          final current = await store.readCredentialForOwner(ownerId);
          if (current == null) {
            throw const AiTutorException(AiFailureCode.missingKey);
          }
          await _replaceCredential(
            ownerId,
            current.copyWith(
              providerConsent: providerConsent,
              shareLearningSummary: providerConsent && shareLearningSummary,
            ),
          );
        }),
      ),
    );
  }

  @override
  Future<void> removeKey() async {
    _checkNotDisposed();
    await _cancelActiveOperations();
    final cancellation = AiCancellation();
    await _track(
      cancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(cancellation, (ownerId) async {
          await _replaceCredential(ownerId, null);
        }),
      ),
    );
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
        () => ownerCoordinator.run(effectiveCancellation, (ownerId) async {
          final credential = await _requiredCredential(ownerId);
          String? summary;
          if (credential.shareLearningSummary && loadProgress != null) {
            try {
              summary = _progressSummary(await loadProgress!());
            } on Object {
              throw const AiTutorException(AiFailureCode.localPersistence);
            }
          }
          final gateway = _resolveGateway(
            providerId: credential.providerId,
            model: credential.model,
            customBaseUrl: _customUri(
              credential.providerId,
              credential.customBaseUrl,
            ),
          );
          final providerReply = await _accounted<AiGatewayReply>(
            ownerId: ownerId,
            gateway: gateway,
            requestType: 'tutorReply',
            cancellation: effectiveCancellation,
            operation: () => gateway.generateTutorReply(
              key: credential.key,
              scenario: scenario,
              learnerMessage: learnerMessage,
              learningSummary: summary,
              cancellation: effectiveCancellation,
            ),
            usageOf: (reply) => reply.usage,
          );
          return AiTutorReply(
            text: providerReply.text,
            providerId: gateway.providerId,
            model: gateway.model,
            generatedAtUtc: _utcNow(),
            usage: providerReply.usage,
          );
        }),
      ),
    );
  }

  @override
  Future<List<AiUsageSummary>> loadUsage() {
    _checkNotDisposed();
    final cancellation = AiCancellation();
    return _track(
      cancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(cancellation, (ownerId) async {
          try {
            return await usageRepository.summarizeForOwner(ownerId);
          } on Object {
            throw const AiTutorException(AiFailureCode.localPersistence);
          }
        }),
      ),
    );
  }

  @override
  Future<void> clearUsage() {
    _checkNotDisposed();
    final cancellation = AiCancellation();
    return _track(
      cancellation,
      _transitionGate.run(
        () => ownerCoordinator.run(cancellation, (ownerId) async {
          try {
            await usageRepository.clearForOwner(ownerId);
          } on Object {
            throw const AiTutorException(AiFailureCode.localPersistence);
          }
        }),
      ),
    );
  }

  Future<T> _accounted<T>({
    required String ownerId,
    required AiTutorGateway gateway,
    required String requestType,
    required AiCancellation cancellation,
    required Future<T> Function() operation,
    AiTokenUsage? Function(T value)? usageOf,
  }) async {
    if (cancellation.isCancelled) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    final eventId = _usageEventId().trim();
    final startedAtUtc = _utcNow();
    try {
      await usageRepository.beginForOwner(
        ownerId,
        AiUsageAttempt(
          eventId: eventId,
          occurredAtUtc: startedAtUtc,
          providerId: gateway.providerId,
          model: gateway.model,
          requestType: requestType,
        ),
      );
    } on Object {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }

    final stopwatch = Stopwatch()..start();
    late T value;
    try {
      if (cancellation.isCancelled) {
        throw const AiTutorException(AiFailureCode.cancelled);
      }
      value = await Future<T>.sync(operation);
      ownerCoordinator.markCurrentOperationResultCommitted();
    } on Object catch (error, stackTrace) {
      stopwatch.stop();
      final failure = _normalizeProviderFailure(error);
      if (!await ownerCoordinator.canFinalizeCurrentOperation()) {
        cancellation.cancel();
        Error.throwWithStackTrace(
          const AiTutorException(AiFailureCode.cancelled),
          stackTrace,
        );
      }
      try {
        await usageRepository.finalizeForOwner(
          ownerId,
          AiUsageCompletion(
            eventId: eventId,
            outcome: 'failure',
            errorCategory: failure.code.name,
            latencyMs: stopwatch.elapsedMilliseconds,
          ),
        );
      } on Object {
        // Preserve the original provider-neutral failure. The pending row is
        // intentionally recovered as indeterminate on a later gated run.
      }
      ownerCoordinator.markCurrentOperationResultCommitted();
      Error.throwWithStackTrace(failure, stackTrace);
    }

    stopwatch.stop();
    if (!await ownerCoordinator.canFinalizeCurrentOperation()) {
      cancellation.cancel();
      return value;
    }
    AiTokenUsage? usage;
    try {
      usage = _sanitizedUsage(usageOf?.call(value));
    } on Object {
      // Provider-reported counters are advisory. A malformed counter getter
      // cannot discard a paid response or corrupt the durable pending row.
      usage = null;
    }
    final completion = AiUsageCompletion(
      eventId: eventId,
      outcome: 'success',
      latencyMs: stopwatch.elapsedMilliseconds,
      inputTokens: usage?.inputTokens,
      outputTokens: usage?.outputTokens,
      totalTokens: usage?.totalTokens,
      cachedTokens: usage?.cachedTokens,
      providerReportedCostMicrosUsd: usage?.providerReportedCostMicrosUsd,
    );
    for (var attempt = 0; attempt < 2; attempt++) {
      try {
        await usageRepository.finalizeForOwner(ownerId, completion);
        break;
      } on Object {
        // Leave durable pending evidence for gated recovery.
      }
    }
    // The paid provider result must not be discarded or retried by the UI.
    // A still-pending row is durable evidence and is recovered to
    // indeterminate on the next successfully gated operation.
    return value;
  }

  AiTokenUsage? _sanitizedUsage(AiTokenUsage? usage) {
    if (usage == null) return null;
    final values = <int?>[
      usage.inputTokens,
      usage.outputTokens,
      usage.totalTokens,
      usage.cachedTokens,
      usage.providerReportedCostMicrosUsd,
    ];
    if (values.any((value) => value != null && value < 0) ||
        (usage.cachedTokens != null &&
            usage.totalTokens != null &&
            usage.cachedTokens! > usage.totalTokens!) ||
        (usage.inputTokens != null &&
            usage.outputTokens != null &&
            usage.totalTokens != null &&
            usage.totalTokens! < usage.inputTokens! + usage.outputTokens!)) {
      return null;
    }
    return usage;
  }

  Future<void> _replaceCredential(
    String ownerId,
    AiTutorCredential? credential,
  ) async {
    await ownerCoordinator.requireCurrentLease();
    await store.replaceCredentialForOwnerFenced(
      ownerId,
      credential,
      operationVersion: ownerCoordinator.currentOperationVersion,
      leaseIsOwned: ownerCoordinator.canFinalizeCurrentOperation,
      nowUtc: _utcNow,
    );
    ownerCoordinator.markCurrentOperationResultCommitted();
  }

  Future<AiTutorCredential> _requiredCredential(String ownerId) async {
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
    return credential;
  }

  AiTutorGateway _resolveGateway({
    required AiProviderId providerId,
    required String model,
    Uri? customBaseUrl,
  }) {
    try {
      return _gatewayResolver(
        providerId: providerId,
        model: model,
        customBaseUrl: customBaseUrl,
      );
    } on AiTutorException {
      rethrow;
    } on Object {
      throw const AiTutorException(AiFailureCode.providerUnavailable);
    }
  }

  AiTutorException _normalizeProviderFailure(Object error) {
    if (error is AiTutorException) return error;
    if (error is TimeoutException) {
      return const AiTutorException(AiFailureCode.timeout);
    }
    return const AiTutorException(AiFailureCode.providerUnavailable);
  }

  void _requireListedModel(
    AiProviderId providerId,
    String model,
    List<AiModel> models,
  ) {
    final listed = models.any((candidate) => candidate.id == model);
    if (!listed &&
        (providerId != AiProviderId.customOpenAi || models.isNotEmpty)) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
  }

  String _requiredModel(String value) {
    final model = value.trim();
    if (model.isEmpty || model.length > 200) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    return model;
  }

  Uri? _customUri(AiProviderId providerId, String? raw) {
    if (providerId != AiProviderId.customOpenAi) return null;
    if (raw == null || raw.trim().isEmpty) {
      throw const AiTutorException(AiFailureCode.unsafeEndpoint);
    }
    return parseAndValidateCustomAiBaseUri(raw);
  }

  DateTime _utcNow() {
    final value = nowUtc();
    if (!value.isUtc) {
      throw const AiTutorException(AiFailureCode.localPersistence);
    }
    return value;
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
  Future<void> dispose() => _disposeFuture ??= _disposeOnce();

  Future<void> _disposeOnce() async {
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
