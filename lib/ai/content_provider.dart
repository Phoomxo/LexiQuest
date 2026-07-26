import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../voice/voice_auth_token_provider.dart';
import 'ai_models.dart';

const _validationFailure = AiFailure(
  category: AiFailureCategory.validation,
  message: 'The content request could not be processed.',
);

const _authenticationFailure = AiFailure(
  category: AiFailureCategory.authentication,
  message: 'AI authentication is unavailable.',
);

const _networkFailure = AiFailure(
  category: AiFailureCategory.network,
  message: 'The AI service could not be reached.',
);

const _timeoutFailure = AiFailure(
  category: AiFailureCategory.timeout,
  message: 'The AI service took too long to respond.',
);

const _rateLimitedFailure = AiFailure(
  category: AiFailureCategory.rateLimited,
  message: 'AI generation is busy. Please try again shortly.',
);

const _providerUnavailableFailure = AiFailure(
  category: AiFailureCategory.providerUnavailable,
  message: 'The AI provider is currently unavailable.',
);

const _generationFailure = AiFailure(
  category: AiFailureCategory.generation,
  message: 'Content generation could not be completed.',
);

const _unknownFailure = AiFailure(
  category: AiFailureCategory.unknown,
  message: 'Content generation is unavailable.',
);

/// Boundary for acquiring a Firebase ID token for AI requests.
///
/// Re-uses [VoiceAuthTokenProvider] verbatim because the token is identical
/// (it is the same Firebase ID token for the same signed-in user). Aliased
/// here so call sites read naturally as "AI auth" rather than "voice auth",
/// and so a future split (if AI ever needs a different scope) has a clear
/// seam.
typedef AiAuthTokenProvider = VoiceAuthTokenProvider;

/// Provider-neutral boundary for generating teaching content.
abstract interface class ContentProvider {
  Future<ContentResponse> generate(ContentRequest request);
}

/// Sends authenticated content requests to the LexiQuest-LM (or any
/// OpenAI-compatible) AI endpoint.
///
/// Mirrors [OmniVoiceProvider] in shape: an injected [http.Client], an
/// injected [AiAuthTokenProvider], a base [Uri], and a timeout. A 401 forces
/// a single token refresh and retry; every other non-200 maps to a typed
/// [AiFailure] via the backend's stable `detail.code` contract.
final class HttpContentProvider implements ContentProvider {
  factory HttpContentProvider({
    required http.Client client,
    required AiAuthTokenProvider authTokenProvider,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 20),
  }) {
    return HttpContentProvider._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/content'),
      timeout,
    );
  }

  HttpContentProvider._(
    this._client,
    this._authTokenProvider,
    this._contentUri,
    this._timeout,
  );

  final http.Client _client;
  final AiAuthTokenProvider _authTokenProvider;
  final Uri _contentUri;
  final Duration _timeout;

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    final body = <String, Object>{
      'text': request.text,
      'kind': request.kind.wire,
      'cefr': request.cefr.wire,
      'language': request.language,
    };

    final token = await _authTokenProvider.getIdToken(forceRefresh: false);
    var response = await _post(token, body);

    if (response.statusCode == 401) {
      final refreshedToken = await _authTokenProvider.getIdToken(
        forceRefresh: true,
      );
      response = await _post(refreshedToken, body);
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }

    if (response.statusCode != 200) {
      throw _failureFor(response);
    }

    return _contentFrom(response);
  }

  Future<http.Response> _post(String token, Map<String, Object> body) async {
    final request = http.Request('POST', _contentUri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    try {
      final response = () async {
        final streamedResponse = await _client.send(request);
        return http.Response.fromStream(streamedResponse);
      }();
      return await response.timeout(_timeout);
    } on TimeoutException {
      throw _timeoutFailure;
    } on http.ClientException {
      throw _networkFailure;
    }
  }

  AiFailure _failureFor(http.Response response) {
    final code = _detailCode(response);
    switch (response.statusCode) {
      case 400:
      case 422:
        return _validationFailure;
      case 429:
        return _rateLimitedFailure;
      case 503:
        switch (code) {
          case 'PROVIDER_UNAVAILABLE':
            return _providerUnavailableFailure;
          case 'CONTENT_GENERATION_FAILED':
            return _generationFailure;
          case 'PROVIDER_UNAUTHORIZED':
            return _providerUnavailableFailure;
          case 'AUTH_UNAVAILABLE':
            return _authenticationFailure;
          default:
            return _unknownFailure;
        }
      default:
        return code == 'RATE_LIMITED' ? _rateLimitedFailure : _unknownFailure;
    }
  }

  String? _detailCode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          final code = detail['code'];
          if (code is String) {
            return code;
          }
        }
      }
    } on FormatException {
      // Invalid JSON is intentionally reduced to an unknown fixed failure.
    }
    return null;
  }

  ContentResponse _contentFrom(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is! Map<String, dynamic>) {
        throw _generationFailure;
      }
      final text = decoded['text'];
      final kind = ContentKind.fromWire(decoded['kind'] as String?);
      final modelVersion = decoded['model_version'] as String?;
      final cached = decoded['cached'];

      if (text is! String ||
          text.trim().isEmpty ||
          kind == null ||
          modelVersion == null ||
          modelVersion.trim().isEmpty ||
          cached is! bool) {
        throw _generationFailure;
      }

      return ContentResponse(
        text: text.trim(),
        kind: kind,
        cefr: CefrLevel.fromWire(decoded['cefr'] as String?),
        language:
            (decoded['language'] as String?)?.trim().toLowerCase() ?? 'en',
        modelVersion: modelVersion.trim(),
        cached: cached,
      );
    } on AiFailure {
      rethrow;
    } on FormatException {
      throw _generationFailure;
    }
  }
}
