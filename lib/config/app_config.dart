import 'package:flutter/foundation.dart';

const _invalidVoiceApiUrl = 'Voice API URL is not configured.';

/// Immutable application configuration containing only a sanitized voice API
/// origin. No credential or API key is shipped in the Flutter application.
final class AppConfig {
  const AppConfig._({required this.voiceApiBaseUri});

  final Uri voiceApiBaseUri;

  factory AppConfig.fromValues({
    required String voiceApiUrl,
    required bool isDebug,
  }) {
    return AppConfig._(voiceApiBaseUri: _parse(voiceApiUrl, isDebug: isDebug));
  }

  /// Reads the endpoint supplied with:
  /// `--dart-define=LEXIQUEST_VOICE_API_URL=https://...`.
  factory AppConfig.fromEnvironment({bool? isDebug}) {
    const url = String.fromEnvironment('LEXIQUEST_VOICE_API_URL');
    return AppConfig.fromValues(
      voiceApiUrl: url,
      isDebug: isDebug ?? kDebugMode,
    );
  }

  @override
  String toString() => 'AppConfig';

  static Uri _parse(String voiceApiUrl, {required bool isDebug}) {
    try {
      final uri = Uri.parse(voiceApiUrl);
      final scheme = uri.scheme;
      if (scheme != 'http' && scheme != 'https') {
        throw const AppConfigException();
      }
      if (!uri.hasAuthority || uri.host.isEmpty) {
        throw const AppConfigException();
      }
      if (uri.userInfo.isNotEmpty || uri.hasQuery || uri.hasFragment) {
        throw const AppConfigException();
      }
      if (uri.path.isNotEmpty && uri.path != '/') {
        throw const AppConfigException();
      }

      if (scheme == 'http') {
        if (!isDebug) {
          throw const AppConfigException();
        }
        final host = uri.host.toLowerCase();
        if (host != '127.0.0.1' && host != '10.0.2.2') {
          throw const AppConfigException();
        }
      }

      final port = uri.hasPort ? uri.port : null;
      return Uri(scheme: scheme, host: uri.host, port: port, path: '/');
    } on FormatException {
      throw const AppConfigException();
    }
  }
}

/// Fixed, privacy-safe failure for every invalid configuration input.
final class AppConfigException implements Exception {
  const AppConfigException();

  @override
  String toString() => 'AppConfigException: $_invalidVoiceApiUrl';
}
