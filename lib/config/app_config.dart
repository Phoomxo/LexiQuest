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
      voiceApiBaseUri: _parse(
        voiceApiUrl,
        isDebug: isDebug,
        label: 'Voice API',
      ),
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
        if (!_isDebugHttpHostAllowed(uri.host)) {
          throw AppConfigException(
            '$label URL must use HTTPS except for local debug addresses.',
          );
        }
      }

      final port = uri.hasPort ? uri.port : null;
      return Uri(scheme: scheme, host: uri.host, port: port, path: '/');
    } on FormatException {
      throw AppConfigException('$label URL is invalid.');
    }
  }

  /// Allows cleartext only for loopback, the Android emulator host alias, or a
  /// numerically valid RFC 1918 IPv4 address in debug builds.
  static bool _isDebugHttpHostAllowed(String host) {
    final normalized = host.toLowerCase();
    if (normalized == '127.0.0.1' || normalized == '10.0.2.2') {
      return true;
    }

    final octets = normalized.split('.');
    if (octets.length != 4) {
      return false;
    }

    final values = <int>[];
    for (final octet in octets) {
      final value = int.tryParse(octet);
      if (value == null || value < 0 || value > 255) {
        return false;
      }
      if (octet != value.toString()) {
        return false;
      }
      values.add(value);
    }

    final first = values[0];
    final second = values[1];
    if (first == 10) return true;
    if (first == 172 && second >= 16 && second <= 31) return true;
    if (first == 192 && second == 168) return true;
    return false;
  }
}

/// Fixed, privacy-safe failure for every invalid configuration input.
final class AppConfigException implements Exception {
  const AppConfigException([this._message]);

  final String? _message;

  @override
  String toString() => 'AppConfigException: ${_message ?? _invalidVoiceApiUrl}';
}
