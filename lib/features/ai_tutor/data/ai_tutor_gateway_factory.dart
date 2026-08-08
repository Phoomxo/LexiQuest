import 'package:http/http.dart' as http;

import '../../../runtime/circuit_breaker.dart';
import '../../gemini/data/gemini_rest_gateway.dart';
import '../../gemini/data/retry_gemini_gateway.dart';
import '../../gemini/domain/gemini_contracts.dart';
import '../domain/ai_tutor_contracts.dart';
import 'anthropic_gateway.dart';
import 'openai_compatible_gateway.dart';
import 'openai_responses_gateway.dart';

/// Resolves the correct [AiTutorGateway] adapter for a given provider. The
/// factory reads the participant's chosen provider, model, and (for custom
/// OpenAI-compatible providers) base URL from the settings store.
final class AiTutorGatewayFactory {
  AiTutorGatewayFactory({
    required this._client,
    this._requestTimeout = const Duration(seconds: 20),
    CircuitBreaker? geminiBreaker,
  }) : _geminiBreaker =
           geminiBreaker ??
           CircuitBreaker(
             shouldCountFailure: RetryGeminiGateway.isTransientFailure,
           );

  final http.Client _client;
  final Duration _requestTimeout;
  final CircuitBreaker _geminiBreaker;

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
            breaker: _geminiBreaker,
          ),
        );
      case AiProvider.openai:
        return OpenAiResponsesGateway(
          client: _client,
          baseUri: config.baseUri,
          model: effectiveModel,
          requestTimeout: _requestTimeout,
        );
      case AiProvider.openrouter:
      case AiProvider.maxPlus:
      case AiProvider.customOpenAi:
        final baseUri = providerId == AiProvider.customOpenAi
            ? _validatedCustomBaseUri(customBaseUrl)
            : config.baseUri;
        return OpenAiCompatibleGateway(
          client: _client,
          baseUri: baseUri,
          model: effectiveModel,
          requestTimeout: _requestTimeout,
          providerId: providerId,
        );
      case AiProvider.claude:
        return AnthropicGateway(
          client: _client,
          baseUri: config.baseUri,
          model: effectiveModel,
          requestTimeout: _requestTimeout,
        );
    }
  }

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
        customBaseUrl = Uri.parse(raw);
      }
    }
    return create(
      providerId: providerId,
      model: model,
      customBaseUrl: customBaseUrl,
    );
  }
}

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
      _inner.validateKey(key, cancellation: _bridge(cancellation));

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async => (await _inner.listModels(
    key,
    cancellation: _bridge(cancellation),
  )).map((id) => AiModel(id: id)).toList(growable: false);

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    final text = await _inner.generateTutorReply(
      key: key,
      scenario: scenario,
      learnerMessage: learnerMessage,
      learningSummary: learningSummary,
      cancellation: _bridge(cancellation),
    );
    return AiGatewayReply(text: text);
  }
}
