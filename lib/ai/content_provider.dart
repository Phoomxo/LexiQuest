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

const _cancelledFailure = AiFailure(
  category: AiFailureCategory.cancelled,
  message: 'The content request is no longer current.',
);
const _paymentRequiredFailure = AiFailure(
  category: AiFailureCategory.paymentRequired,
  message: 'Verify or restore your membership before using managed AI.',
);
const _quotaExhaustedFailure = AiFailure(
  category: AiFailureCategory.quotaExhausted,
  message: 'The managed AI quota for this period has been used.',
);
const _operationUncertainFailure = AiFailure(
  category: AiFailureCategory.operationUncertain,
  message:
      'The previous managed AI request has an uncertain outcome. Do not automatically start another request.',
);

typedef AiAuthBindingReader = Object? Function();

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
    AiAuthBindingReader? readAuthBinding,
  }) {
    return HttpContentProvider._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/content'),
      timeout,
      readAuthBinding,
    );
  }

  HttpContentProvider._(
    this._client,
    this._authTokenProvider,
    this._contentUri,
    this._timeout,
    this._readAuthBinding,
  );

  final http.Client _client;
  final AiAuthTokenProvider _authTokenProvider;
  final Uri _contentUri;
  final Duration _timeout;
  final AiAuthBindingReader? _readAuthBinding;

  @override
  Future<ContentResponse> generate(ContentRequest request) async {
    Object? binding;
    try {
      if (!request.isCurrent) throw _cancelledFailure;
      binding = _readAuthBinding?.call();
    } on AiFailure {
      rethrow;
    } on Object {
      throw _authenticationFailure;
    }
    if (_readAuthBinding != null && binding == null) {
      throw _authenticationFailure;
    }
    void requireCurrent() {
      try {
        if (!request.isCurrent ||
            (_readAuthBinding != null && _readAuthBinding() != binding)) {
          throw _cancelledFailure;
        }
      } on AiFailure {
        rethrow;
      } on Object {
        throw _cancelledFailure;
      }
    }

    final body = <String, Object>{
      'text': request.text,
      'kind': request.kind.wire,
      'cefr': request.cefr.wire,
      'language': request.language,
    };

    requireCurrent();
    final token = await _token(forceRefresh: false);
    requireCurrent();
    var response = await _post(
      token,
      body,
      request.operationId,
      requireCurrent,
    );
    requireCurrent();

    if (response.statusCode == 401) {
      final refreshedToken = await _token(forceRefresh: true);
      requireCurrent();
      response = await _post(
        refreshedToken,
        body,
        request.operationId,
        requireCurrent,
      );
      requireCurrent();
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }

    if (response.statusCode != 200) {
      throw _failureFor(response);
    }

    return _contentFrom(response);
  }

  Future<String> _token({required bool forceRefresh}) async {
    try {
      return await _authTokenProvider
          .getIdToken(forceRefresh: forceRefresh)
          .timeout(_timeout);
    } on TimeoutException {
      throw _timeoutFailure;
    } on Object {
      throw _authenticationFailure;
    }
  }

  Future<http.Response> _post(
    String token,
    Map<String, Object> body,
    String operationId,
    void Function() requireCurrent,
  ) async {
    requireCurrent();
    final request = http.Request('POST', _contentUri)
      ..followRedirects = false
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json'
      ..headers['idempotency-key'] = operationId
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
    } on Exception {
      throw _networkFailure;
    }
  }

  AiFailure _failureFor(http.Response response) {
    final code = _detailCode(response);
    switch (response.statusCode) {
      case 402:
      case 403:
        if (code == 'BILLING_ENTITLEMENT_REQUIRED') {
          return _paymentRequiredFailure;
        }
        if (code == 'BILLING_ACCOUNT_REQUIRED') return _authenticationFailure;
        return _unknownFailure;
      case 400:
      case 422:
        return _validationFailure;
      case 429:
        if (code == 'BILLING_QUOTA_EXHAUSTED') return _quotaExhaustedFailure;
        return _rateLimitedFailure;
      case 409:
        if (code == 'BILLING_OPERATION_UNCERTAIN') {
          return _operationUncertainFailure;
        }
        if (code == 'BILLING_REQUEST_CONFLICT') return _validationFailure;
        return _unknownFailure;
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
