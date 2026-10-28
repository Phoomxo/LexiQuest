import 'dart:convert';

import 'package:http/http.dart' as http;

import '../domain/ai_tutor_contracts.dart';
import 'abortable_ai_http.dart';

typedef OpenAiResponsesOfflineCheck = Future<bool> Function();

final class OpenAiResponsesGateway implements AiTutorGateway {
  OpenAiResponsesGateway({
    required this.client,
    required Uri baseUri,
    required this.model,
    OpenAiResponsesOfflineCheck? isOffline,
    this.requestTimeout = const Duration(seconds: 20),
  }) : baseUri = normalizeAiApiBaseUri(baseUri),
       _isOffline = isOffline ?? _assumeOnline;

  final http.Client client;
  final Uri baseUri;
  final OpenAiResponsesOfflineCheck _isOffline;
  final Duration requestTimeout;

  @override
  AiProviderId get providerId => AiProviderId.openai;

  @override
  final String model;

  static Future<bool> _assumeOnline() async => false;

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
    final response = await _send(
      http.Request('GET', baseUri.resolve('models'))
        ..headers['authorization'] = 'Bearer $normalized'
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
              .map((item) => item['id'])
              .whereType<String>()
              .map((id) => id.trim())
              .where((id) => id.isNotEmpty && id.length <= 200)
              .toSet()
              .map((id) => AiModel(id: id))
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
    final normalizedScenario = _normalizedText(scenario, maximumLength: 80);
    final normalizedMessage = _normalizedText(
      learnerMessage,
      maximumLength: 500,
    );
    final summary = learningSummary == null
        ? null
        : _normalizedText(learningSummary, maximumLength: 600);
    final input = StringBuffer('Scenario: $normalizedScenario\n');
    if (summary != null) {
      input.writeln('Consented learning summary: $summary');
    }
    input.write('Learner message: $normalizedMessage');
    final request = http.Request('POST', baseUri.resolve('responses'))
      ..headers['authorization'] = 'Bearer ${_normalizedKey(key)}'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode({
        'model': model,
        'instructions':
            'You are a concise English tutor. Stay in the requested scenario, '
            'use CEFR B1-B2 English, correct only material errors kindly, '
            'never claim to have heard audio, and reply in no more than two '
            'short sentences.',
        'input': input.toString(),
        'max_output_tokens': 120,
      });
    final response = await _send(request, cancellation: cancellation);
    return _parseReply(response.body);
  }

  Future<http.Response> _send(
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
      client: client,
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
      final direct = decoded['output_text'];
      final text = direct is String
          ? direct.trim()
          : _readOutputBlocks(decoded);
      if (text.isEmpty || text.length > 4000) {
        throw const AiTutorException(AiFailureCode.malformedResponse);
      }
      return AiGatewayReply(text: text, usage: _parseUsage(decoded['usage']));
    } on FormatException {
      throw const AiTutorException(AiFailureCode.malformedResponse);
    }
  }

  bool _isBlockedResponse(Map<String, dynamic> decoded) {
    final details = decoded['incomplete_details'];
    final reason = details is Map<String, dynamic> ? details['reason'] : null;
    if (reason == 'content_filter' ||
        reason == 'safety' ||
        reason == 'refusal') {
      return true;
    }
    final output = decoded['output'];
    if (output is! List) return false;
    return output.whereType<Map<String, dynamic>>().any((item) {
      final content = item['content'];
      return content is List &&
          content.whereType<Map<String, dynamic>>().any(
            (block) => block['type'] == 'refusal',
          );
    });
  }

  String _readOutputBlocks(Map<String, dynamic> decoded) {
    final output = decoded['output'];
    if (output is! List) return '';
    return output
        .whereType<Map<String, dynamic>>()
        .expand(
          (item) => item['content'] is List ? item['content'] as List : [],
        )
        .whereType<Map<String, dynamic>>()
        .where((item) => item['type'] == 'output_text')
        .map((item) => item['text'])
        .whereType<String>()
        .join()
        .trim();
  }

  AiTokenUsage? _parseUsage(Object? raw) {
    if (raw is! Map<String, dynamic>) return null;
    int? read(String key) => switch (raw[key]) {
      final int value when value >= 0 => value,
      _ => null,
    };
    final input = read('input_tokens');
    final output = read('output_tokens');
    final total = read('total_tokens');
    final cached = switch (raw['input_tokens_details']) {
      final Map<String, dynamic> details => switch (details['cached_tokens']) {
        final int value when value >= 0 => value,
        _ => null,
      },
      _ => null,
    };
    if (input == null && output == null && total == null && cached == null) {
      return null;
    }
    return AiTokenUsage(
      inputTokens: input,
      outputTokens: output,
      totalTokens: total,
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
