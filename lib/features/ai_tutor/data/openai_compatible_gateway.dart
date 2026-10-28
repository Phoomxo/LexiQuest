import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../gemini/domain/gemini_contracts.dart';
import '../domain/ai_tutor_contracts.dart';

typedef OpenAiOfflineCheck = Future<bool> Function();

/// OpenAI-compatible gateway adapter. Speaks the `/chat/completions` contract
/// used by OpenAI, OpenRouter, and most Thai/alternative providers. The
/// participant supplies their own base URL, model, and key.
final class OpenAiCompatibleGateway implements AiTutorGateway {
  factory OpenAiCompatibleGateway({
    required http.Client client,
    required Uri baseUri,
    required String model,
    OpenAiOfflineCheck? isOffline,
    Duration requestTimeout = const Duration(seconds: 20),
    AiProvider providerId = AiProvider.openai,
  }) {
    return OpenAiCompatibleGateway._(
      client: client,
      baseUri: baseUri,
      model: model,
      isOffline: isOffline ?? _assumeOnline,
      requestTimeout: requestTimeout,
      providerId: providerId,
    );
  }

  OpenAiCompatibleGateway._({
    required this._client,
    required this._baseUri,
    required this.model,
    required this._isOffline,
    required this.requestTimeout,
    required this.providerId,
  });

  final http.Client _client;
  final Uri _baseUri;
  final OpenAiOfflineCheck _isOffline;
  final Duration requestTimeout;

  @override
  final AiProvider providerId;

  @override
  final String model;

  static Future<bool> _assumeOnline() async => false;

  static const _systemPrompt =
      'You are a concise English tutor. Stay in the requested scenario, use '
      'CEFR B1-B2 English, correct only material errors kindly, never claim to '
      'have heard audio, and reply in no more than two short sentences.';

  @override
  Future<void> validateKey(
    String key, {
    AiCancellation? cancellation,
  }) async {
    await listModels(key, cancellation: cancellation);
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async {
    final normalized = _normalizedKey(key);
    final response = await _sendRequest(
      http.Request('GET', _baseUri.resolve('models'))
        ..headers['authorization'] = 'Bearer $normalized'
        ..headers['content-type'] = 'application/json',
      cancellation: cancellation,
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final ids =
          (decoded['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map((item) => item['id'])
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty && id.length <= 200)
              .toSet()
              .toList()
            ..sort();
      return ids.map((id) => AiModel(id: id)).toList(growable: false);
    } on FormatException {
      throw const GeminiException(GeminiFailureCode.malformedResponse);
    }
  }

  @override
  Future<AiGatewayReply> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    AiCancellation? cancellation,
  }) async {
    final normalized = _normalizedKey(key);
    final normalizedScenario = _normalizedText(scenario, maximumLength: 80);
    final normalizedMessage = _normalizedText(
      learnerMessage,
      maximumLength: 500,
    );
    final summary = learningSummary == null
        ? null
        : _normalizedText(learningSummary, maximumLength: 600);
    final userContent = StringBuffer()
      ..writeln('Scenario: $normalizedScenario');
    if (summary != null) {
      userContent.writeln('Consented learning summary: $summary');
    }
    userContent
      ..writeln()
      ..write('Learner message: $normalizedMessage');
    final response = await _send(normalized, {
      'model': model,
      'messages': [
        {'role': 'system', 'content': _systemPrompt},
        {'role': 'user', 'content': userContent.toString()},
      ],
      'max_tokens': 120,
      'temperature': 0.7,
    }, cancellation: cancellation);
    return _parseReply(response.body);
  }

  Future<http.Response> _send(
    String key,
    Map<String, Object> body, {
    AiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    if (await _isOffline()) {
      throw const GeminiException(GeminiFailureCode.offline);
    }
    final request = http.Request('POST', _baseUri.resolve('chat/completions'))
      ..headers['authorization'] = 'Bearer $key'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    return _sendRequest(request, cancellation: cancellation);
  }

  Future<http.Response> _sendRequest(
    http.Request request, {
    AiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    if (await _isOffline()) {
      throw const GeminiException(GeminiFailureCode.offline);
    }
    try {
      final streamed = await _sendWithCancellation(request, cancellation);
      final response = await http.Response.fromStream(
        streamed,
      ).timeout(requestTimeout);
      if (response.statusCode != 200) {
        throw _failureFor(response.statusCode);
      }
      if (cancellation?.isCancelled ?? false) {
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      return response;
    } on GeminiException {
      rethrow;
    } on TimeoutException {
      throw const GeminiException(GeminiFailureCode.timeout);
    } on http.ClientException {
      throw const GeminiException(GeminiFailureCode.offline);
    } on Object {
      throw const GeminiException(GeminiFailureCode.offline);
    }
  }

  Future<http.StreamedResponse> _sendWithCancellation(
    http.Request request,
    AiCancellation? cancellation,
  ) {
    final operation = _client.send(request).timeout(requestTimeout);
    if (cancellation == null) return operation;
    return Future.any([
      operation,
      cancellation.whenCancelled.then<http.StreamedResponse>(
        (_) => throw const GeminiException(GeminiFailureCode.cancelled),
      ),
    ]);
  }

  GeminiException _failureFor(int statusCode) => switch (statusCode) {
    400 || 401 || 403 => const GeminiException(GeminiFailureCode.invalidKey),
    402 => const GeminiException(GeminiFailureCode.quota),
    408 => const GeminiException(GeminiFailureCode.timeout),
    429 => const GeminiException(GeminiFailureCode.rateLimited),
    500 ||
    502 ||
    503 ||
    504 => const GeminiException(GeminiFailureCode.providerUnavailable),
    _ => const GeminiException(GeminiFailureCode.providerUnavailable),
  };

  AiGatewayReply _parseReply(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final choices = decoded['choices'];
      if (choices is! List || choices.isEmpty) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final first = choices.first;
      if (first is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final message = first['message'];
      if (message is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final content = message['content'];
      if (content is! String || content.isEmpty || content.length > 4000) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      return AiGatewayReply(
        text: content.trim(),
        usage: _parseUsage(decoded['usage']),
      );
    } on FormatException {
      throw const GeminiException(GeminiFailureCode.malformedResponse);
    }
  }

  AiTokenUsage? _parseUsage(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? read(String key) => switch (raw[key]) {
      final int value when value >= 0 => value,
      _ => null,
    };
    final input = read('prompt_tokens') ?? read('input_tokens');
    final output = read('completion_tokens') ?? read('output_tokens');
    final total = read('total_tokens');
    final cached = switch (raw['prompt_tokens_details']) {
      final Map<String, dynamic> details => switch (details['cached_tokens']) {
        final int value when value >= 0 => value,
        _ => null,
      },
      _ => null,
    };
    final costMicros = switch (raw['cost']) {
      final num value when value >= 0 => (value * 1000000).round(),
      _ => null,
    };
    if (input == null &&
        output == null &&
        total == null &&
        cached == null &&
        costMicros == null) {
      return null;
    }
    return AiTokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total,
      cachedTokens: cached,
      providerReportedCostMicrosUsd: costMicros,
    );
  }

  String _normalizedKey(String value) {
    final normalized = value.trim();
    if (normalized.isEmpty || normalized.length > 512) {
      throw const GeminiException(GeminiFailureCode.invalidKey);
    }
    return normalized;
  }

  String _normalizedText(String value, {required int maximumLength}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > maximumLength) {
      throw const GeminiException(GeminiFailureCode.validation);
    }
    return normalized;
  }
}
