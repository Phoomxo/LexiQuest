import 'dart:async';

import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_policy.dart';
import 'voice_provider.dart';
import 'voice_provider_registry.dart';
import 'voice_route_handler.dart';
import 'voice_telemetry.dart';

const _cancelledFailure = VoiceFailure(
  category: VoiceFailureCategory.cancelled,
  message: 'The voice request was cancelled.',
);

const _missingHandlerFailure = VoiceFailure(
  category: VoiceFailureCategory.configuration,
  message: 'The selected voice provider is not registered.',
);

const _unsupportedRouteFailure = VoiceFailure(
  category: VoiceFailureCategory.unsupportedCapability,
  message: 'The selected voice provider cannot handle this route.',
);

/// Resolves policy once and executes one provider-neutral voice route plan.
final class VoiceOrchestrator implements VoiceProvider {
  VoiceOrchestrator({
    required VoicePolicySource policySource,
    required VoicePolicyResolver policyResolver,
    required VoiceProviderRegistry<VoiceRouteHandler> handlerRegistry,
    VoiceTelemetrySink telemetrySink = const NoopVoiceTelemetrySink(),
  }) : this._(policySource, policyResolver, handlerRegistry, telemetrySink);

  VoiceOrchestrator._(
    this._policySource,
    this._policyResolver,
    this._handlerRegistry,
    this._telemetrySink,
  );

  final VoicePolicySource _policySource;
  final VoicePolicyResolver _policyResolver;
  final VoiceProviderRegistry<VoiceRouteHandler> _handlerRegistry;
  final VoiceTelemetrySink _telemetrySink;

  int _generation = 0;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async {
    final stopwatch = Stopwatch()..start();
    final generation = ++_generation;
    final cancellation = _GenerationCancellationToken(
      generation: generation,
      currentGeneration: () => _generation,
    );
    var requestedEngine = _defaultRequestedEngine(request);

    try {
      await _stopHandlers(cancellation);
      final context = await _policySource.load();
      cancellation.throwIfCancelled();
      final plan = _policyResolver.resolve(
        request: request,
        context: context,
        registeredEngines: _handlerRegistry.engines,
      );
      requestedEngine = plan.steps.first.engine;

      VoiceFailureCategory? fallbackReason;
      for (var index = 0; index < plan.steps.length; index++) {
        final step = plan.steps[index];
        try {
          final handler = _handlerRegistry.providerFor(step.engine);
          if (handler == null) {
            throw _missingHandlerFailure;
          }
          _validateHandler(handler, step);
          final routedRequest = _copyForStep(request, step);
          final handlerResult = await handler.speak(
            routedRequest,
            cancellation,
          );
          cancellation.throwIfCancelled();
          final result = VoicePlaybackResult(
            requestedEngine: requestedEngine,
            actualEngine: handlerResult.actualEngine,
            usedFallback: index > 0,
            cacheHit: handlerResult.cacheHit,
            requestId: handlerResult.requestId,
            modelVersion: handlerResult.modelVersion,
          );
          final event = VoiceTelemetryEvent.succeeded(
            request: request,
            result: result,
            fallbackReason: result.usedFallback ? fallbackReason : null,
            latency: stopwatch.elapsed,
            occurredAtUtc: DateTime.now().toUtc(),
          );
          unawaited(_recordTelemetry(event));
          return result;
        } on VoiceFailure catch (failure, stackTrace) {
          cancellation.throwIfCancelled();
          final isLast = index == plan.steps.length - 1;
          if (request.mode == VoiceMode.researchEvaluation ||
              isLast ||
              !_allowsFallback(failure.category)) {
            Error.throwWithStackTrace(failure, stackTrace);
          }
          fallbackReason = failure.category;
        }
      }
      throw _missingHandlerFailure;
    } on VoiceFailure catch (failure, stackTrace) {
      final event = VoiceTelemetryEvent.failed(
        request: request,
        requestedEngine: requestedEngine,
        failure: failure,
        latency: stopwatch.elapsed,
        occurredAtUtc: DateTime.now().toUtc(),
      );
      unawaited(_recordTelemetry(event));
      Error.throwWithStackTrace(failure, stackTrace);
    }
  }

  void _validateHandler(VoiceRouteHandler handler, VoiceRouteStep step) {
    final descriptor = handler.descriptor;
    if (descriptor.engine != step.engine) {
      throw _missingHandlerFailure;
    }
    if (!descriptor.supports(step.capability) ||
        descriptor.privacyScope != step.privacyScope) {
      throw _unsupportedRouteFailure;
    }
  }

  VoiceRequest _copyForStep(VoiceRequest request, VoiceRouteStep step) {
    return VoiceRequest.create(
      text: request.text,
      language: request.language,
      voiceId: request.voiceId,
      speed: request.speed,
      contentId: request.contentId,
      contentType: request.contentType,
      mode: request.mode,
      assignedEngine: step.engine,
      capability: step.capability,
      privacyScope: step.privacyScope,
    );
  }

  bool _allowsFallback(VoiceFailureCategory category) {
    return switch (category) {
      VoiceFailureCategory.authentication ||
      VoiceFailureCategory.network ||
      VoiceFailureCategory.timeout ||
      VoiceFailureCategory.rateLimited ||
      VoiceFailureCategory.modelUnavailable ||
      VoiceFailureCategory.insufficientStorage ||
      VoiceFailureCategory.checksumMismatch ||
      VoiceFailureCategory.synthesis ||
      VoiceFailureCategory.playback ||
      VoiceFailureCategory.configuration ||
      VoiceFailureCategory.unknown => true,
      VoiceFailureCategory.validation ||
      VoiceFailureCategory.consentMissing ||
      VoiceFailureCategory.providerDisabled ||
      VoiceFailureCategory.unsupportedCapability ||
      VoiceFailureCategory.sessionExpired ||
      VoiceFailureCategory.cleanupIncomplete ||
      VoiceFailureCategory.cancelled => false,
    };
  }

  VoiceEngine _defaultRequestedEngine(VoiceRequest request) {
    final assignedEngine = request.assignedEngine;
    if (assignedEngine != null) {
      return assignedEngine;
    }
    return request.capability == VoiceCapability.sessionVoiceMirror
        ? VoiceEngine.voxCpmMirror
        : VoiceEngine.omniVoice;
  }

  Future<void> _stopHandlers(VoiceCancellationToken cancellation) async {
    await _stopAllHandlers(cancellation: cancellation);
  }

  Future<void> _stopAllHandlers({VoiceCancellationToken? cancellation}) async {
    Object? firstFailure;
    StackTrace? firstStackTrace;

    for (final engine in _handlerRegistry.engines) {
      try {
        await _handlerRegistry.providerFor(engine)!.stop();
      } on Object catch (error, stackTrace) {
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
      try {
        cancellation?.throwIfCancelled();
      } on Object catch (error, stackTrace) {
        firstFailure ??= error;
        firstStackTrace ??= stackTrace;
      }
    }

    if (firstFailure case final failure?) {
      Error.throwWithStackTrace(failure, firstStackTrace!);
    }
  }

  Future<void> _recordTelemetry(VoiceTelemetryEvent event) async {
    try {
      await _telemetrySink.record(event);
    } on Object {
      // Telemetry is best-effort and must never alter playback.
    }
  }

  @override
  Future<void> stop() async {
    _generation++;
    await _stopAllHandlers();
  }
}

final class _GenerationCancellationToken implements VoiceCancellationToken {
  const _GenerationCancellationToken({
    required this.generation,
    required this.currentGeneration,
  });

  final int generation;
  final int Function() currentGeneration;

  @override
  bool get isCancelled => generation != currentGeneration();

  @override
  void throwIfCancelled() {
    if (isCancelled) {
      throw _cancelledFailure;
    }
  }
}
