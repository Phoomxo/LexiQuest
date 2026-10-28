import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai_tutor_contracts.dart';
import 'abortable_ai_http.dart';

typedef AnthropicOfflineCheck = Future<bool> Function();

/// Anthropic Claude gateway adapter. Speaks the `/v1/messages` contract with
/// `x-api-key` and `anthropic-version` headers.
final class AnthropicGateway implements AiTutorGateway {
  factory AnthropicGateway({
    required http.Client client,
    required Uri baseUri,
    required String model,
    AnthropicOfflineCheck? isOffline,
    Duration requestTimeout = const Duration(seconds: 20),
  }) {
    return AnthropicGateway._(
      client: client,
      baseUri: normalizeAiApiBaseUri(baseUri),
      model: model,
      isOffline: isOffline ?? _assumeOnline,
      requestTimeout: requestTimeout,
    );
  }

  AnthropicGateway._({
    required this._client,
    required this._baseUri,
    required this.model,
    required this._isOffline,
    required this.requestTimeout,
  });

  final http.Client _client;
  final Uri _baseUri;
  final AnthropicOfflineCheck _isOffline;
  final Duration requestTimeout;

  @override
  final AiProvider providerId = AiProvider.claude;

  @override
  final String model;

  static Future<bool> _assumeOnline() async => false;

  static const _anthropicVersion = '2023-06-01';
  static const _systemPrompt =
      'You are a concise English tutor. Stay in the requested scenario, use '
      'CEFR B1-B2 English, correct only material errors kindly, never claim to '
      'have heard audio, and reply in no more than two short sentences.';

  @override
  Future<void> validateKey(String key, {AiCancellation? cancellation}) async {
    await listModels(key, cancellation: cancellation);
  }

  @override
  Future<List<AiModel>> listModels(
    String key, {
    AiCancellation? cancellation,
  }) async {
    final normalized = _normalizedKey(key);
    final response = await _sendRequest(
      http.Request('GET', _baseUri.resolve('v1/models'))
        ..headers['x-api-key'] = normalized
        ..headers['anthropic-version'] = _anthropicVersion
        ..headers['content-type'] = 'application/json',
      cancellation: cancellation,
    );
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> || decoded['data'] is! List) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      final models =
          (decoded['data'] as List)
              .whereType<Map<String, dynamic>>()
              .map(
                (item) => switch (item['id']) {
                  final String id
                      when id.trim().isNotEmpty && id.length <= 200 =>
                    AiModel(
                      id: id.trim(),
                      displayName: item['display_name'] is String
                          ? item['display_name'] as String
                          : null,
                    ),
                  _ => null,
                },
              )
              .whereType<AiModel>()
              .toList()
            ..sort((left, right) => left.id.compareTo(right.id));
      return models;
    } on FormatException {
      throw const AiTutorException(AiFailureCode.malformedResponse);
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
      'system': _systemPrompt,
      'max_tokens': 120,
      'messages': [
        {'role': 'user', 'content': userContent.toString()},
      ],
    }, cancellation: cancellation);
    return _parseReply(response.body);
  }

  Future<http.Response> _send(
    String key,
    Map<String, Object> body, {
    AiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    if (await _isOffline()) {
      throw const AiTutorException(AiFailureCode.offline);
    }
    final request = http.Request('POST', _baseUri.resolve('v1/messages'))
      ..headers['x-api-key'] = key
      ..headers['anthropic-version'] = _anthropicVersion
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    return _sendRequest(request, cancellation: cancellation);
  }

  Future<http.Response> _sendRequest(
    http.Request request, {
    AiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const AiTutorException(AiFailureCode.cancelled);
    }
    if (await _isOffline()) {
      throw const AiTutorException(AiFailureCode.offline);
    }
    final response = await sendAbortableAiRequest(
      client: _client,
      request: request,
      timeout: requestTimeout,
      cancellation: cancellation,
    );
    if (response.statusCode != 200) {
      throw aiFailureForHttpStatus(response.statusCode);
    }
    return response;
  }

  AiGatewayReply _parseReply(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      if (_isBlockedResponse(decoded)) {
        throw const AiTutorException(AiFailureCode.blocked);
      }
      final content = decoded['content'];
      if (content is! List || content.isEmpty) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      final text = content
          .whereType<Map<String, dynamic>>()
          .where((block) => block['type'] == 'text')
          .map((block) => block['text'])
          .whereType<String>()
          .join()
          .trim();
      if (text.isEmpty || text.length > 4000) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      return AiGatewayReply(text: text, usage: _parseUsage(decoded['usage']));
    } on FormatException {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
  }

  bool _isBlockedResponse(Map<String, dynamic> decoded) {
    final reason = decoded['stop_reason'];
    if (reason == 'refusal' ||
        reason == 'content_filter' ||
        reason == 'safety') {
      return true;
    }
    final content = decoded['content'];
    return content is List &&
        content.whereType<Map<String, dynamic>>().any(
          (block) => block['type'] == 'refusal',
        );
  }

  AiTokenUsage? _parseUsage(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? read(String key) => switch (raw[key]) {
      final int value when value >= 0 => value,
      _ => null,
    };
    final input = read('input_tokens');
    final output = read('output_tokens');
    final cached = read('cache_read_input_tokens');
    if (input == null && output == null && cached == null) return null;
    return AiTokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: input != null && output != null ? input + output : null,
      cachedTokens: cached,
    );
  }

  String _normalizedKey(String value) {
    return normalizeAiApiKey(value);
  }

  String _normalizedText(String value, {required int maximumLength}) {
    final normalized = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (normalized.isEmpty || normalized.length > maximumLength) {
      throw const AiTutorException(AiFailureCode.validation);
    }
    return normalized;
  }
}
