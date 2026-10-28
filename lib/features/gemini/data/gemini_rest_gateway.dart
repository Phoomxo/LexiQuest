import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../domain/gemini_contracts.dart';

typedef OfflineCheck = Future<bool> Function();

final class GeminiRestGateway implements GeminiGateway {
  factory GeminiRestGateway({
    required http.Client client,
    OfflineCheck? isOffline,
    Uri? baseUri,
    Duration requestTimeout = const Duration(seconds: 20),
    String model = 'gemini-2.5-flash-lite',
  }) {
    return GeminiRestGateway._(
      client: client,
      isOffline: isOffline ?? _assumeOnline,
      baseUri: baseUri ?? Uri.https('generativelanguage.googleapis.com', '/'),
      requestTimeout: requestTimeout,
      model: model,
    );
  }

  GeminiRestGateway._({
    required this._client,
    required this._isOffline,
    required this._baseUri,
    required this.requestTimeout,
    required this.model,
  });

  static const _maximumResponseBytes = 256 * 1024;

  final http.Client _client;
  final OfflineCheck _isOffline;
  final Uri _baseUri;
  final Duration requestTimeout;

  @override
  final String model;

  static Future<bool> _assumeOnline() async => false;

  @override
  Future<void> validateKey(
    String key, {
    GeminiCancellation? cancellation,
  }) async {
    final normalized = _normalizedKey(key);
    final abort = _abortFor(cancellation);
    final request = http.AbortableRequest(
      'GET',
      _baseUri.resolve('/v1beta/models/$model'),
      abortTrigger: abort.future,
    )..headers['x-goog-api-key'] = normalized;
    final response = await _send(
      request,
      abort: abort,
      cancellation: cancellation,
    );
    if (response.statusCode != 200) {
      throw _failureFor(response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic> ||
          decoded['name'] is! String ||
          !(decoded['name'] as String).endsWith(model)) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
    } on FormatException {
      throw const GeminiException(GeminiFailureCode.malformedResponse);
    }
  }

  @override
  Future<String> generateTutorReply({
    required String key,
    required String scenario,
    required String learnerMessage,
    String? learningSummary,
    GeminiCancellation? cancellation,
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
    final abort = _abortFor(cancellation);
    final request =
        http.AbortableRequest(
            'POST',
            _baseUri.resolve('/v1beta/models/$model:generateContent'),
            abortTrigger: abort.future,
          )
          ..headers['x-goog-api-key'] = normalized
          ..headers['content-type'] = 'application/json'
          ..body = jsonEncode({
            'systemInstruction': {
              'parts': [
                {
                  'text':
                      'You are a concise English tutor. Stay in the requested '
                      'scenario, use CEFR B1-B2 English, correct only material '
                      'errors kindly, never claim to have heard audio, and reply '
                      'in no more than two short sentences.',
                },
              ],
            },
            'contents': [
              {
                'role': 'user',
                'parts': [
                  {
                    'text':
                        'Scenario: $normalizedScenario\n'
                        '${summary == null ? '' : 'Consented learning summary: $summary\n'}'
                        'Learner message: $normalizedMessage',
                  },
                ],
              },
            ],
            'generationConfig': {'candidateCount': 1, 'maxOutputTokens': 120},
          });
    final response = await _send(
      request,
      abort: abort,
      cancellation: cancellation,
    );
    if (response.statusCode != 200) {
      throw _failureFor(response.statusCode);
    }
    return _parseText(response.body);
  }

  @override
  Future<List<String>> listModels(
    String key, {
    GeminiCancellation? cancellation,
  }) async {
    final normalized = _normalizedKey(key);
    final abort = _abortFor(cancellation);
    final request = http.AbortableRequest(
      'GET',
      _baseUri.resolve('/v1beta/models'),
      abortTrigger: abort.future,
    )..headers['x-goog-api-key'] = normalized;
    final response = await _send(
      request,
      abort: abort,
      cancellation: cancellation,
    );
    if (response.statusCode != 200) {
      throw _failureFor(response.statusCode);
    }
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final models = decoded['models'];
      if (models is! List) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      return models
          .whereType<Map<String, dynamic>>()
          .map((m) => m['name'])
          .whereType<String>()
          .map((name) => name.startsWith('models/') ? name.substring(7) : name)
          .where((name) => name.contains('gemini'))
          .toList(growable: false);
    } on FormatException {
      throw const GeminiException(GeminiFailureCode.malformedResponse);
    }
  }

  Future<http.Response> _send(
    http.AbortableRequest request, {
    required Completer<void> abort,
    GeminiCancellation? cancellation,
  }) async {
    if (cancellation?.isCancelled ?? false) {
      throw const GeminiException(GeminiFailureCode.cancelled);
    }
    if (await _isOffline()) {
      throw const GeminiException(GeminiFailureCode.offline);
    }
    var timedOut = false;
    try {
      final operation = () async {
        final streamed = await _client.send(request);
        final bytes = BytesBuilder(copy: false);
        await for (final chunk in streamed.stream) {
          if (bytes.length + chunk.length > _maximumResponseBytes) {
            throw const GeminiException(GeminiFailureCode.malformedResponse);
          }
          bytes.add(chunk);
        }
        return http.Response.bytes(
          Uint8List.fromList(bytes.takeBytes()),
          streamed.statusCode,
          headers: streamed.headers,
          request: streamed.request,
          reasonPhrase: streamed.reasonPhrase,
        );
      }();
      final response = await operation.timeout(
        requestTimeout,
        onTimeout: () {
          timedOut = true;
          if (!abort.isCompleted) abort.complete();
          throw const GeminiException(GeminiFailureCode.timeout);
        },
      );
      if (cancellation?.isCancelled ?? false) {
        throw const GeminiException(GeminiFailureCode.cancelled);
      }
      return response;
    } on http.RequestAbortedException {
      if (timedOut) {
        throw const GeminiException(GeminiFailureCode.timeout);
      }
      throw GeminiException(
        cancellation?.isCancelled ?? false
            ? GeminiFailureCode.cancelled
            : GeminiFailureCode.offline,
      );
    } on TimeoutException {
      throw const GeminiException(GeminiFailureCode.timeout);
    } on http.ClientException {
      throw const GeminiException(GeminiFailureCode.offline);
    } on GeminiException {
      rethrow;
    } on Object {
      throw const GeminiException(GeminiFailureCode.offline);
    }
  }

  Completer<void> _abortFor(GeminiCancellation? cancellation) {
    final abort = Completer<void>();
    if (cancellation != null) {
      unawaited(
        cancellation.whenCancelled.then((_) {
          if (!abort.isCompleted) abort.complete();
        }),
      );
    }
    return abort;
  }

  GeminiException _failureFor(int statusCode) => switch (statusCode) {
    400 || 401 || 403 => const GeminiException(GeminiFailureCode.invalidKey),
    408 => const GeminiException(GeminiFailureCode.timeout),
    429 => const GeminiException(GeminiFailureCode.quota),
    500 ||
    502 ||
    503 ||
    504 => const GeminiException(GeminiFailureCode.providerUnavailable),
    _ => const GeminiException(GeminiFailureCode.providerUnavailable),
  };

  String _parseText(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final promptFeedback = decoded['promptFeedback'];
      if (promptFeedback is Map<String, dynamic> &&
          promptFeedback['blockReason'] != null) {
        throw const GeminiException(GeminiFailureCode.blocked);
      }
      final candidates = decoded['candidates'];
      if (candidates is! List || candidates.isEmpty) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final first = candidates.first;
      if (first is! Map<String, dynamic>) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final content = first['content'];
      if (content is! Map<String, dynamic>) {
        final finishReason = first['finishReason'];
        throw GeminiException(
          finishReason == 'SAFETY' || finishReason == 'PROHIBITED_CONTENT'
              ? GeminiFailureCode.blocked
              : GeminiFailureCode.malformedResponse,
        );
      }
      final parts = content['parts'];
      if (parts is! List) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      final text = parts
          .whereType<Map<String, dynamic>>()
          .map((part) => part['text'])
          .whereType<String>()
          .join()
          .trim();
      if (text.isEmpty || text.length > 4000) {
        throw const GeminiException(GeminiFailureCode.malformedResponse);
      }
      return text;
    } on FormatException {
      throw const GeminiException(GeminiFailureCode.malformedResponse);
    }
  }

  String _normalizedKey(String value) {
    final normalized = value.trim();
    if (normalized.length < 20 ||
        normalized.length > 256 ||
        normalized.contains(RegExp(r'\s'))) {
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
