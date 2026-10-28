import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_auth_token_provider.dart';
import 'voice_models.dart';
import 'voice_synthesis_provider.dart';

const _validationFailure = VoiceFailure(
  category: VoiceFailureCategory.validation,
  message: 'The voice mirror request could not be processed.',
);
const _authenticationFailure = VoiceFailure(
  category: VoiceFailureCategory.authentication,
  message: 'Voice authentication is unavailable.',
);
const _networkFailure = VoiceFailure(
  category: VoiceFailureCategory.network,
  message: 'The voice mirror service could not be reached.',
);
const _timeoutFailure = VoiceFailure(
  category: VoiceFailureCategory.timeout,
  message: 'The voice mirror service took too long to respond.',
);
const _rateLimitedFailure = VoiceFailure(
  category: VoiceFailureCategory.rateLimited,
  message: 'Voice mirroring is busy. Please try again shortly.',
);
const _providerDisabledFailure = VoiceFailure(
  category: VoiceFailureCategory.providerDisabled,
  message: 'The voice mirror provider is disabled.',
);
const _consentMissingFailure = VoiceFailure(
  category: VoiceFailureCategory.consentMissing,
  message: 'Voice mirror consent is missing.',
);
const _sessionExpiredFailure = VoiceFailure(
  category: VoiceFailureCategory.sessionExpired,
  message: 'The voice mirror session has expired.',
);
const _synthesisFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'Voice mirror synthesis could not be completed.',
);
const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice mirroring is unavailable.',
);

/// Server lease for a temporary voice-mirror session.
final class VoiceMirrorLease {
  const VoiceMirrorLease({
    required this.sessionId,
    required this.leaseExpiresAtEpochMs,
    required this.absoluteExpiresAtEpochMs,
  });

  final String sessionId;
  final int leaseExpiresAtEpochMs;
  final int absoluteExpiresAtEpochMs;
}

/// Boundary implemented by the temporary voice-mirror HTTP client. The
/// session controller depends on this interface so it can be tested without a
/// live network.
abstract interface class VoiceMirrorClient {
  Future<VoiceMirrorLease> enroll({required Uint8List wavBytes});

  Future<VoiceMirrorLease> heartbeat({required String sessionId});

  Future<VoiceAudio> synthesize({
    required String sessionId,
    required String contentId,
    required String text,
    required String language,
  });

  Future<void> delete({required String sessionId});
}

/// Authenticated HTTP boundary for the temporary participant voice mirror.
///
/// All requests carry a refreshed-once Firebase bearer token, honour
/// `Cache-Control: no-store`, and reduce provider detail to the fixed
/// [VoiceFailureCategory] taxonomy. Raw enrollment audio and synthesized
/// output never leave this boundary into a cache.
final class VoiceMirrorGateway implements VoiceMirrorClient {
  factory VoiceMirrorGateway({
    required http.Client client,
    required VoiceAuthTokenProvider authTokenProvider,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 30),
    String consentVersion = _defaultConsentVersion,
  }) {
    return VoiceMirrorGateway._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/voice-mirror/sessions'),
      timeout,
      consentVersion,
    );
  }

  VoiceMirrorGateway._(
    this._client,
    this._authTokenProvider,
    this._sessionsUri,
    this._timeout,
    this._consentVersion,
  );

  static const String _defaultConsentVersion = 'voice-mirror-v1';

  final http.Client _client;
  final VoiceAuthTokenProvider _authTokenProvider;
  final Uri _sessionsUri;
  final Duration _timeout;
  final String _consentVersion;

  /// Enrolls the participant voice from bounded WAV bytes and returns the
  /// temporary session lease.
  @override
  Future<VoiceMirrorLease> enroll({required Uint8List wavBytes}) async {
    final token = await _authTokenProvider.getIdToken(forceRefresh: false);
    var response = await _sendEnroll(token, wavBytes);
    if (response.statusCode == 401) {
      final refreshed = await _authTokenProvider.getIdToken(forceRefresh: true);
      response = await _sendEnroll(refreshed, wavBytes);
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }
    if (response.statusCode != 201) {
      throw _failureFor(response);
    }
    return _leaseFrom(response);
  }

  /// Renews the renewable lease without extending the absolute lifetime.
  @override
  Future<VoiceMirrorLease> heartbeat({required String sessionId}) async {
    final token = await _authTokenProvider.getIdToken(forceRefresh: false);
    var response = await _sendHeartbeat(token, sessionId);
    if (response.statusCode == 401) {
      final refreshed = await _authTokenProvider.getIdToken(forceRefresh: true);
      response = await _sendHeartbeat(refreshed, sessionId);
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }
    if (response.statusCode != 200) {
      throw _failureFor(response);
    }
    return _leaseFrom(response);
  }

  /// Synthesizes the approved target phrase in the mirrored voice.
  @override
  Future<VoiceAudio> synthesize({
    required String sessionId,
    required String contentId,
    required String text,
    required String language,
  }) async {
    final body = jsonEncode({
      'contentId': contentId,
      'text': text,
      'language': language,
    });
    final token = await _authTokenProvider.getIdToken(forceRefresh: false);
    var response = await _sendSpeech(token, sessionId, body);
    if (response.statusCode == 401) {
      final refreshed = await _authTokenProvider.getIdToken(forceRefresh: true);
      response = await _sendSpeech(refreshed, sessionId, body);
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }
    if (response.statusCode != 200) {
      throw _failureFor(response);
    }
    return _audioFrom(response);
  }

  /// Deletes the session. A session-not-found for the owner is treated as a
  /// successful idempotent delete.
  @override
  Future<void> delete({required String sessionId}) async {
    final token = await _authTokenProvider.getIdToken(forceRefresh: false);
    var response = await _sendDelete(token, sessionId);
    if (response.statusCode == 401) {
      final refreshed = await _authTokenProvider.getIdToken(forceRefresh: true);
      response = await _sendDelete(refreshed, sessionId);
      if (response.statusCode == 401) {
        throw _authenticationFailure;
      }
    }
    final status = response.statusCode;
    if (status == 204 || status == 404) {
      return;
    }
    throw _failureFor(response);
  }

  Future<http.Response> _sendEnroll(String token, Uint8List wavBytes) async {
    final request = http.Request('POST', _sessionsUri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'audio/wav'
      ..headers['x-voice-mirror-consent'] = _consentVersion
      ..bodyBytes = wavBytes;
    return _execute(request);
  }

  Uri _join(List<String> segments) {
    final builder = StringBuffer(_sessionsUri.path);
    for (final segment in segments) {
      if (builder.isNotEmpty && !builder.toString().endsWith('/')) {
        builder.write('/');
      }
      builder.write(Uri.encodeQueryComponent(segment));
    }
    return _sessionsUri.replace(path: builder.toString());
  }

  Future<http.Response> _sendHeartbeat(String token, String sessionId) async {
    final request = http.Request('POST', _join([sessionId, 'heartbeat']))
      ..headers['authorization'] = 'Bearer $token';
    return _execute(request);
  }

  Future<http.Response> _sendSpeech(
    String token,
    String sessionId,
    String body,
  ) async {
    final request = http.Request('POST', _join([sessionId, 'speech']))
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json'
      ..body = body;
    return _execute(request);
  }

  Future<http.Response> _sendDelete(String token, String sessionId) async {
    final request = http.Request('DELETE', _join([sessionId]))
      ..headers['authorization'] = 'Bearer $token';
    return _execute(request);
  }

  Future<http.Response> _execute(http.Request request) async {
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
      403 =>
        code == 'CONSENT_MISSING' ? _consentMissingFailure : _unknownFailure,
      409 => code == 'SESSION_BUSY' ? _rateLimitedFailure : _unknownFailure,
      410 =>
        code == 'SESSION_EXPIRED' ? _sessionExpiredFailure : _unknownFailure,
      413 || 415 || 422 => _validationFailure,
      429 => _rateLimitedFailure,
      503 => switch (code) {
        'PROVIDER_DISABLED' => _providerDisabledFailure,
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

  VoiceMirrorLease _leaseFrom(http.Response response) {
    try {
      final decoded = jsonDecode(response.body);
      if (decoded is Map<String, dynamic>) {
        final sessionId = decoded['sessionId'];
        final lease = decoded['leaseExpiresAtEpochMs'];
        final absolute = decoded['absoluteExpiresAtEpochMs'];
        if (sessionId is String &&
            sessionId.isNotEmpty &&
            lease is int &&
            absolute is int) {
          return VoiceMirrorLease(
            sessionId: sessionId,
            leaseExpiresAtEpochMs: lease,
            absoluteExpiresAtEpochMs: absolute,
          );
        }
      }
    } on FormatException {
      // Fall through to a typed synthesis failure.
    }
    throw _synthesisFailure;
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
      engine: VoiceEngine.voxCpmMirror,
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
}
