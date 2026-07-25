import 'package:flutter/foundation.dart';

const _invalidVoiceApiUrl = 'Voice API URL is not configured.';

/// Immutable application configuration containing only a sanitized voice API
/// and AI API origin. No credential or API key is shipped in the Flutter
/// application.
final class AppConfig {
  const AppConfig._({
    required this.voiceApiBaseUri,
    required this.aiApiBaseUri,
  });

  final Uri voiceApiBaseUri;
  final Uri aiApiBaseUri;

  factory AppConfig.fromValues({
    required String voiceApiUrl,
    String? aiApiUrl,
    required bool isDebug,
  }) {
    // When AI URL is omitted, default it to the voice URL so a single-host
    // deployment (both services behind one origin) needs only one URL.
    final resolvedAiUrl = aiApiUrl ?? voiceApiUrl;
    return AppConfig._(
      voiceApiBaseUri: _parse(voiceApiUrl, isDebug: isDebug, label: 'Voice API'),
      aiApiBaseUri: _parse(resolvedAiUrl, isDebug: isDebug, label: 'AI API'),
    );
  }

  /// Reads the endpoints supplied with:
  ///   --dart-define=LEXIQUEST_VOICE_API_URL=https://...
  ///   --dart-define=LEXIQUEST_AI_API_URL=https://...
  /// When the AI URL is omitted it defaults to the voice URL so a single-host
  /// deployment (both services behind one origin) needs only one define.
  factory AppConfig.fromEnvironment({bool? isDebug}) {
    const voiceUrl = String.fromEnvironment('LEXIQUEST_VOICE_API_URL');
    const aiUrl = String.fromEnvironment(
      'LEXIQUEST_AI_API_URL',
      defaultValue: voiceUrl,
    );
    return AppConfig.fromValues(
      voiceApiUrl: voiceUrl,
      aiApiUrl: aiUrl,
      isDebug: isDebug ?? kDebugMode,
    );
  }

  @override
  String toString() => 'AppConfig';

  static Uri _parse(
    String apiBaseUrl, {
    required bool isDebug,
    String label = 'Voice API',
  }) {
    try {
      final uri = Uri.parse(apiBaseUrl);
      final scheme = uri.scheme;
      if (scheme != 'http' && scheme != 'https') {
        throw AppConfigException('$label URL is invalid.');
      }
      if (!uri.hasAuthority || uri.host.isEmpty) {
        throw AppConfigException('$label URL is invalid.');
      }
      if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
        throw AppConfigException('$label URL is invalid.');
      }
      if (uri.path.isNotEmpty && uri.path != '/') {
        throw AppConfigException('$label URL is invalid.');
      }

      if (scheme == 'http') {
        if (!isDebug) {
          throw AppConfigException('$label URL must use HTTPS in release.');
        }
        final host = uri.host.toLowerCase();
        if (host != '127.0.0.1' && host != '10.0.2.2') {
          throw AppConfigException(
            '$label URL must use HTTPS except for 127.0.0.1 / 10.0.2.2.',
          );
        }
      }

      final port = uri.hasPort ? uri.port : null;
      return Uri(scheme: scheme, host: uri.host, port: port, path: '/');
    } on FormatException {
      throw AppConfigException('$label URL is invalid.');
    }
  }
}

/// Fixed, privacy-safe failure for every invalid configuration input.
final class AppConfigException implements Exception {
  const AppConfigException([this._message]);

  final String? _message;

  @override
  String toString() => 'AppConfigException: ${_message ?? _invalidVoiceApiUrl}';
}
