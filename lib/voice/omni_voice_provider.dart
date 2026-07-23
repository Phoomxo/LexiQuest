import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'voice_auth_token_provider.dart';
import 'voice_models.dart';

const _authenticationFailure = VoiceFailure(
  category: VoiceFailureCategory.authentication,
  message: 'Voice authentication is unavailable.',
);

const _synthesisFailure = VoiceFailure(
  category: VoiceFailureCategory.synthesis,
  message: 'Voice synthesis could not be completed.',
);

const _unknownFailure = VoiceFailure(
  category: VoiceFailureCategory.unknown,
  message: 'Voice synthesis is unavailable.',
);

/// Immutable WAV payload plus the OmniVoice provenance headers.
final class OmniVoiceAudio {
  OmniVoiceAudio({
    required Uint8List bytes,
    required this.requestId,
    required this.engine,
    required this.modelVersion,
    required this.sampleRate,
  }) : _bytes = Uint8List.fromList(bytes);

  final Uint8List _bytes;
  final String requestId;
  final String engine;
  final String modelVersion;
  final int sampleRate;

  Uint8List get bytes => Uint8List.fromList(_bytes);
}

/// Sends authenticated speech requests to the OmniVoice WAV API.
final class OmniVoiceProvider {
  factory OmniVoiceProvider({
    required http.Client client,
    required VoiceAuthTokenProvider authTokenProvider,
    required Uri baseUri,
    Duration timeout = const Duration(seconds: 30),
  }) {
    return OmniVoiceProvider._(
      client,
      authTokenProvider,
      baseUri.resolve('/v1/speech'),
      timeout,
    );
  }

  OmniVoiceProvider._(
    this._client,
    this._authTokenProvider,
    this._speechUri,
    this._timeout,
  );

  final http.Client _client;
  final VoiceAuthTokenProvider _authTokenProvider;
  final Uri _speechUri;
  final Duration _timeout;

  Future<OmniVoiceAudio> synthesize(VoiceRequest request) async {
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
      throw _unknownFailure;
    }

    return _audioFrom(response);
  }

  Future<http.Response> _post(String token, Map<String, Object> body) async {
    final request = http.Request('POST', _speechUri)
      ..headers['authorization'] = 'Bearer $token'
      ..headers['content-type'] = 'application/json'
      ..body = jsonEncode(body);
    final streamedResponse = await _client.send(request).timeout(_timeout);
    return http.Response.fromStream(streamedResponse);
  }

  OmniVoiceAudio _audioFrom(http.Response response) {
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

    return OmniVoiceAudio(
      bytes: response.bodyBytes,
      requestId: requestId.trim(),
      engine: engine.trim(),
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
}
