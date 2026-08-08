import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import '../runtime/circuit_breaker.dart';
import 'voice_auth_token_provider.dart';
import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_provider_descriptor.dart';
import 'voice_request_quota.dart';
import 'voice_synthesis_provider.dart';

const _validationFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'The voice request could not be processed.',
);

const _authenticationFailure = VoiceFailure(
  category: VoiceFailureCategory.authentication,
  message: 'Voice authentication is unavailable.',
);

const _networkFailure = VoiceFailure(
  category: VoiceFailureCategory.network,
  message: 'The voice service could not be reached.',
);

const _timeoutFailure = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'The voice service took too long to respond.',
);

const _rateLimitedFailure = VoiceFailure(
  category: VoiceFailureCategory.rateLimited,
  message: 'Voice synthesis is busy. Please try again shortly.',
);

const _modelUnavailableFailure = VoiceFailure(
  category: VoiceFailureCategory.modelUnavailable,
  message: 'The voice model is currently unavailable.',
);

const _unsupportedCapabilityFailure = VoiceFailure(
  category: VoiceFailureCategory.unsupportedCapability,
  message: 'OmniVoice does not support this request.',
);

const _synthesisFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'Voice synthesis could not be completed.',
);

const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice synthesis is unavailable.',
);

/// Sends authenticated speech requests to the OmniVoice WAV API.
final class OmniVoiceProvider implements VoiceSynthesisProvider {
  factory OmniVoiceProvider({
    required http.Client client,
    required VoiceAuthTokenProvider authTokenProvider,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 30),
    CircuitBreaker? circuitBreaker,
    VoiceRequestQuota? quota,
  }) {
    return OmniVoiceProvider._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/speech'),
      timeout,
      quota,
      circuitBreaker ?? CircuitBreaker(shouldCountFailure: _shouldTrip),
    );
  }

  OmniVoiceProvider._(
    this._client,
    this._authTokenProvider,
    this._speechUri,
    this._timeout,
    this._quota,
    this._circuitBreaker,
  );

  final http.Client _client;
  final VoiceAuthTokenProvider _authTokenProvider;
  final Uri _speechUri;
  final Duration _timeout;
  final VoiceRequestQuota? _quota;
  final CircuitBreaker _circuitBreaker;

  CircuitState get circuitState => _circuitBreaker.state;

  static final VoiceProviderDescriptor _descriptor = VoiceProviderDescriptor(
    engine: VoiceEngine.omniVoice,
    capabilities: const <VoiceCapability>{
      VoiceCapability.standardTargetSpeech,
      VoiceCapability.dynamicTargetSpeech,
    },
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: true,
  );

  @override
  VoiceProviderDescriptor get descriptor => _descriptor;

  @override
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    if (!descriptor.supports(request.capability) ||
        request.privacyScope != descriptor.privacyScope) {
      throw _unsupportedCapabilityFailure;
    }

    final quota = _quota;
    if (request.capability == VoiceCapability.dynamicTargetSpeech &&
        quota != null) {
      return quota.run(request, () => _synthesizeProtected(request));
    }
    return _synthesizeProtected(request);
  }

  Future<VoiceAudio> _synthesizeProtected(VoiceRequest request) async {
    try {
      return await _circuitBreaker.call(() => _synthesizeRemote(request));
    } on CircuitBreakerOpenException {
      throw _rateLimitedFailure;
    }
  }

  Future<VoiceAudio> _synthesizeRemote(VoiceRequest request) async {
    final body = <String, Object>{
      'text': request.text,
      'language': request.language,
      'voice': request.voiceId,
      'speed': request.speed,
      'format': 'wav',
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

    return _audioFrom(response);
  }

  Future<http.Response> _post(String token, Map<String, Object> body) async {
    final request = http.Request('POST', _speechUri)
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

  VoiceFailure _failureFor(http.Response response) {
    final code = _detailCode(response);
    switch (response.statusCode) {
      case 400:
      case 422:
        return _validationFailure;
      case 429:
        return _rateLimitedFailure;
      case 503:
        switch (code) {
          case 'MODEL_UNAVAILABLE':
            return _modelUnavailableFailure;
          case 'SYNTHESIS_FAILED':
            return _synthesisFailure;
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

  VoiceAudio _audioFrom(http.Response response) {
    final contentType = _header(response.headers, 'content-type');
    final requestId = _header(response.headers, 'x-request-id') ?? '';
    final engine = _header(response.headers, 'x-voice-engine') ?? '';
    final modelVersion = _header(response.headers, 'x-model-version') ?? '';
    final sampleRateHeader = _header(response.headers, 'x-audio-sample-rate');

    if (!_isAudioWav(contentType) ||
        response.bodyBytes.isEmpty ||
        requestId.trim().isEmpty ||
        engine.trim().isEmpty ||
        modelVersion.trim().isEmpty) {
      throw _synthesisFailure;
    }

    final sampleRate = int.tryParse((sampleRateHeader ?? '').trim());
    if (sampleRate == null || sampleRate <= 0) {
      throw _synthesisFailure;
    }

    return VoiceAudio(
      bytes: response.bodyBytes,
      requestId: requestId.trim(),
      engine: VoiceEngine.omniVoice,
      modelVersion: modelVersion.trim(),
      sampleRate: sampleRate,
    );
  }

  bool _isAudioWav(String? contentType) {
    if (contentType == null) return false;
    final mime = contentType.split(';').first.trim().toLowerCase();
    return mime == 'audio/wav';
  }

  String? _header(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) {
        return entry.value;
      }
    }
    return null;
  }

  static bool _shouldTrip(Object error) {
    if (error is! VoiceFailure) return false;
    return <VoiceFailureCategory>{
      VoiceFailureCategory.network,
      VoiceFailureCategory.timeout,
      VoiceFailureCategory.modelUnavailable,
      VoiceFailureCategory.synthesis,
      VoiceFailureCategory.unknown,
    }.contains(error.category);
  }
}
