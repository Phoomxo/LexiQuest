import 'package:http/http.dart' as http;

import '../../../runtime/circuit_breaker.dart';
import '../../gemini/data/gemini_rest_gateway.dart';
import '../../gemini/data/retry_gemini_gateway.dart';
import '../../gemini/domain/gemini_contracts.dart';
import '../domain/ai_tutor_contracts.dart';
import 'anthropic_gateway.dart';
import 'openai_compatible_gateway.dart';
import 'openai_responses_gateway.dart';

http.Client _retainAiHttpClient(http.Client value) => value;

/// Resolves the correct [AiTutorGateway] adapter for a given provider. The
/// factory reads the participant's chosen provider, model, and (for custom
/// OpenAI-compatible providers) base URL from the settings store.
final class AiTutorGatewayFactory {
  AiTutorGatewayFactory({
    required http.Client client,
    Duration requestTimeout = const Duration(seconds: 20),
    CircuitBreaker? geminiBreaker,
    Map<AiProviderId, CircuitBreaker>? providerBreakers,
  }) : _client = _retainAiHttpClient(client),
       _requestTimeout = requestTimeout,
       _providerBreakers =
           providerBreakers ??
           <AiProviderId, CircuitBreaker>{
             for (final provider in AiProviderId.values)
               provider: provider == AiProviderId.gemini
                   ? geminiBreaker ??
                         CircuitBreaker(
                           shouldCountFailure:
                               RetryGeminiGateway.isTransientFailure,
                           shouldKeepHalfOpen: _isGeminiCancellation,
                         )
                   : CircuitBreaker(
                       shouldCountFailure: _isTransientAiFailure,
                       shouldKeepHalfOpen: _isAiCancellation,
                     ),
           } {
    if (requestTimeout <= Duration.zero) {
      throw ArgumentError.value(requestTimeout, 'requestTimeout');
    }
  }

  final http.Client _client;
  final Duration _requestTimeout;
  final Map<AiProviderId, CircuitBreaker> _providerBreakers;

  /// Creates a gateway for [providerId]. When [model] is null the provider's
  /// default model is used. [customBaseUrl] is required for
  /// [AiProvider.customOpenAi].
  AiTutorGateway create({
    required AiProvider providerId,
    String? model,
    Uri? customBaseUrl,
  }) {
    final config = AiProviderConfig.forId(providerId);
    final effectiveModel = (model == null || model.trim().isEmpty)
        ? config.defaultModel
        : model.trim();
    if (effectiveModel == null || effectiveModel.isEmpty) {
      throw const AiTutorException(AiFailureCode.missingModel);
    }
    switch (providerId) {
      case AiProvider.gemini:
        return GeminiRestGatewayAdapter(
          RetryGeminiGateway(
            GeminiRestGateway(
              client: _client,
              baseUri: config.baseUri,
              model: effectiveModel,
              requestTimeout: _requestTimeout,
            ),
            totalTimeout: _requestTimeout,
            breaker: _providerBreakers[AiProviderId.gemini],
          ),
        );
      case AiProvider.openai:
        return _withBreaker(
          OpenAiResponsesGateway(
            client: _client,
            baseUri: config.baseUri,
            model: effectiveModel,
            requestTimeout: _requestTimeout,
          ),
        );
      case AiProvider.openrouter:
      case AiProvider.customOpenAi:
        final baseUri = providerId == AiProvider.customOpenAi
            ? _validatedCustomBaseUri(customBaseUrl)
            : config.baseUri;
        return _withBreaker(
          OpenAiCompatibleGateway(
            client: _client,
            baseUri: baseUri,
            model: effectiveModel,
            requestTimeout: _requestTimeout,
            providerId: providerId,
          ),
        );
      case AiProvider.maxPlus:
        return _DisabledAiTutorGateway(providerId, effectiveModel);
      case AiProvider.claude:
        return _withBreaker(
          AnthropicGateway(
            client: _client,
            baseUri: config.baseUri,
            model: effectiveModel,
            requestTimeout: _requestTimeout,
          ),
        );
    }
  }

  AiTutorGateway _withBreaker(AiTutorGateway inner) =>
      _CircuitBreakingAiTutorGateway(
        inner,
        _providerBreakers[inner.providerId]!,
      );

  Uri _validatedCustomBaseUri(Uri? baseUri) {
    if (baseUri == null) {
      throw const AiTutorException(AiFailureCode.unsafeEndpoint);
    }
    validateCustomAiBaseUri(baseUri);
    return baseUri;
  }

  /// Resolves the gateway from the participant's stored provider and model.
  Future<AiTutorGateway> createForStore(AiTutorSettingsStore store) async {
    final providerId = await store.readProviderId();
    final model = await store.readModel();
    Uri? customBaseUrl;
    if (providerId == AiProvider.customOpenAi) {
      final raw = await store.readCustomBaseUrl();
      if (raw != null && raw.isNotEmpty) {
        customBaseUrl = parseAndValidateCustomAiBaseUri(raw);
      }
    }
    return create(
      providerId: providerId,
      model: model,
      customBaseUrl: customBaseUrl,
    );
  }
}

final class _CircuitBreakingAiTutorGateway implements AiTutorGateway {
  const _CircuitBreakingAiTutorGateway(this._inner, this._breaker);

  final AiTutorGateway _inner;
  final CircuitBreaker _breaker;

  @override
  AiProviderId get providerId => _inner.providerId;

  @override
  String get model => _inner.model;

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) => _call(
    cancellation,
    () => _inner.validateKey(key, cancellation: cancellation),
  );

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) => _call(
    cancellation,
    () => _inner.listModels(key, cancellation: cancellation),
  );

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) => _call(
    cancellation,
    () => _inner.generateTutorReply(
      key: key,
      scenario: scenario,
      learnerMessage: learnerMessage,
      learningSummary: learningSummary,
      cancellation: cancellation,
    ),
  );

  Future<T> _call<T>(
    AiCancellation? cancellation,
    Future<T> Function() operation,
  ) async {
    if (cancellation?.isCancelled ?? false) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    try {
      return await _breaker.call(operation);
    } on CircuitBreakerOpenException {
      throw const AiTutorException(AiFailureCode.circuitOpen);
    }
  }
}

final class _DisabledAiTutorGateway implements AiTutorGateway {
  const _DisabledAiTutorGateway(this.providerId, this.model);

  @override
  final AiProviderId providerId;

  @override
  final String model;

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) =>
      Future<void>.error(_disabledAiFailure);

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) => Future<List<AiModel>>.error(_disabledAiFailure);

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) => Future<AiGatewayReply>.error(_disabledAiFailure);
}

const _disabledAiFailure = AiTutorException(AiFailureCode.providerDisabled);

bool _isTransientAiFailure(Object error) =>
    error is AiTutorException &&
    (error.code == AiFailureCode.offline ||
        error.code == AiFailureCode.timeout ||
        error.code == AiFailureCode.rateLimited ||
        error.code == AiFailureCode.providerUnavailable);

bool _isAiCancellation(Object error) =>
    error is AiTutorException && error.code == AiFailureCode.cancelled;

bool _isGeminiCancellation(Object error) =>
    error is GeminiException && error.code == GeminiFailureCode.cancelled;

/// Adapts a [GeminiGateway] to the provider-neutral tutor boundary.
final class GeminiRestGatewayAdapter implements AiTutorGateway {
  GeminiRestGatewayAdapter(this._inner);

  final GeminiGateway _inner;

  @override
  AiProvider get providerId => AiProvider.gemini;

  @override
  String get model => _inner.model;

  /// Bridges [AiCancellation] → [GeminiCancellation] so the tutor
  /// cancellation API works with the existing Gemini gateway.
  GeminiCancellation? _bridge(AiCancellation? cancellation) {
    if (cancellation == null) return null;
    final gemini = GeminiCancellation();
    cancellation.whenCancelled.then((_) => gemini.cancel());
    return gemini;
  }

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) =>
      _providerNeutral(
        () => _inner.validateKey(key, cancellation: _bridge(cancellation)),
      );

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) => _providerNeutral(() async {
    final models = await _inner.listModels(
      key,
      cancellation: _bridge(cancellation),
    );
    return models.map((id) => AiModel(id: id)).toList(growable: false);
  });

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    return _providerNeutral(() async {
      final text = await _inner.generateTutorReply(
        key: key,
        scenario: scenario,
        learnerMessage: learnerMessage,
        learningSummary: learningSummary,
        cancellation: _bridge(cancellation),
      );
      return AiGatewayReply(text: text);
    });
  }

  Future<T> _providerNeutral<T>(Future<T> Function() operation) async {
    try {
      return await operation();
    } on GeminiException catch (error, stackTrace) {
      Error.throwWithStackTrace(
        AiTutorException(_translateGeminiFailure(error.code)),
        stackTrace,
      );
    } on Object catch (_, stackTrace) {
      Error.throwWithStackTrace(
        const AiTutorException(AiFailureCode.providerUnavailable),
        stackTrace,
      );
    }
  }

  AiFailureCode _translateGeminiFailure(GeminiFailureCode code) =>
      switch (code) {
        GeminiFailureCode.missingKey => AiFailureCode.missingKey,
        GeminiFailureCode.consentRequired => AiFailureCode.consentRequired,
        GeminiFailureCode.invalidKey => AiFailureCode.invalidKey,
        GeminiFailureCode.quota => AiFailureCode.quota,
        GeminiFailureCode.rateLimited => AiFailureCode.rateLimited,
        GeminiFailureCode.offline => AiFailureCode.offline,
        GeminiFailureCode.timeout => AiFailureCode.timeout,
        GeminiFailureCode.providerUnavailable =>
          AiFailureCode.providerUnavailable,
        GeminiFailureCode.providerDisabled => AiFailureCode.providerDisabled,
        GeminiFailureCode.circuitOpen => AiFailureCode.circuitOpen,
        GeminiFailureCode.requestRejected => AiFailureCode.requestRejected,
        GeminiFailureCode.malformedResponse => AiFailureCode.malformedResponse,
        GeminiFailureCode.blocked => AiFailureCode.blocked,
        GeminiFailureCode.cancelled => AiFailureCode.cancelled,
        GeminiFailureCode.validation => AiFailureCode.validation,
        GeminiFailureCode.secureStorage => AiFailureCode.secureStorage,
      };
}
