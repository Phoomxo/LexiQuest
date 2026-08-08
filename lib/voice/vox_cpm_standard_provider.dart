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
const _providerDisabledFailure = VoiceFailure(
  category: VoiceFailureCategory.providerDisabled,
  message: 'The voice provider is disabled.',
);
const _modelUnavailableFailure = VoiceFailure(
  category: VoiceFailureCategory.modelUnavailable,
  message: 'The voice model is currently unavailable.',
);
const _unsupportedCapabilityFailure = VoiceFailure(
  category: VoiceFailureCategory.unsupportedCapability,
  message: 'This provider does not support the requested capability.',
);
const _synthesisFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'Voice synthesis could not be completed.',
);
const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice synthesis is unavailable.',
);

/// Authenticated client for standard-content VoxCPM2 speech.
final class VoxCpmStandardProvider implements VoiceSynthesisProvider {
  factory VoxCpmStandardProvider({
    required http.Client client,
    required VoiceAuthTokenProvider authTokenProvider,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 30),
    VoiceRequestQuota? quota,
    CircuitBreaker? circuitBreaker,
  }) {
    return VoxCpmStandardProvider._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/speech'),
      timeout,
      quota,
      circuitBreaker ?? CircuitBreaker(shouldCountFailure: _shouldTrip),
    );
  }

  VoxCpmStandardProvider._(
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
    engine: VoiceEngine.voxCpmStandard,
    capabilities: const {
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
      final refreshed = await _authTokenProvider.getIdToken(forceRefresh: true);
      response = await _post(refreshed, body);
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
      final streamed = await _client.send(request).timeout(_timeout);
      return await http.Response.fromStream(streamed).timeout(_timeout);
    } on TimeoutException {
      throw _timeoutFailure;
    } on http.ClientException {
      throw _networkFailure;
    }
  }

  VoiceFailure _failureFor(http.Response response) {
    final code = _detailCode(response);
    return switch (response.statusCode) {
      400 || 422 => _validationFailure,
      429 => _rateLimitedFailure,
      503 => switch (code) {
        'PROVIDER_DISABLED' => _providerDisabledFailure,
        'MODEL_UNAVAILABLE' => _modelUnavailableFailure,
        'SYNTHESIS_FAILED' => _synthesisFailure,
        'AUTH_UNAVAILABLE' => _authenticationFailure,
        _ => _unknownFailure,
      },
      _ => code == 'RATE_LIMITED' ? _rateLimitedFailure : _unknownFailure,
    };
  }

  String? _detailCode(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final detail = decoded['detail'];
        if (detail is Map<String, dynamic>) {
          final code = detail['code'];
          return code is String ? code : null;
        }
      }
    } on FormatException {
      // Provider details are intentionally reduced to the fixed taxonomy.
    }
    return null;
  }

  VoiceAudio _audioFrom(http.Response response) {
    final contentType = _header(response.headers, 'content-type');
    final requestId = _header(response.headers, 'x-request-id')?.trim() ?? '';
    final engine = _header(response.headers, 'x-voice-engine')?.trim() ?? '';
    final modelVersion =
        _header(response.headers, 'x-model-version')?.trim() ?? '';
    final sampleRate = int.tryParse(
      _header(response.headers, 'x-audio-sample-rate')?.trim() ?? '',
    );
    final mime = contentType?.split(';').first.trim().toLowerCase();
    if (mime != 'audio/wav' ||
        response.bodyBytes.isEmpty ||
        requestId.isEmpty ||
        engine.isEmpty ||
        modelVersion.isEmpty ||
        sampleRate == null ||
        sampleRate <= 0) {
      throw _synthesisFailure;
    }
    return VoiceAudio(
      bytes: response.bodyBytes,
      requestId: requestId,
      engine: VoiceEngine.voxCpmStandard,
      modelVersion: modelVersion,
      sampleRate: sampleRate,
    );
  }

  String? _header(Map<String, String> headers, String name) {
    final target = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == target) return entry.value;
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
