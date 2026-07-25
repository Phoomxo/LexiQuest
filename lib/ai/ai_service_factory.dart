import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/config/app_config.dart';

import '../voice/voice_auth_token_provider.dart';
import 'ai_models.dart';
import 'content_provider.dart';

const _disposedFailure = AiFailure(
  category: AiFailureCategory.configuration,
  message: 'The AI service has been disposed.',
);

/// Production composition root for the AI content pipeline.
///
/// Mirrors [VoiceServiceFactory] in shape so call sites read identically:
/// resolve config + injectables with sensible production defaults, return a
/// lifecycle-managed service that owns the HTTP client and disposes it once.
final class AiServiceFactory {
  const AiServiceFactory._();

  /// Creates a service that owns the resolved HTTP client, including injected
  /// instances supplied for tests or host integration.
  static ManagedAiService create({
    AppConfig? config,
    http.Client? client,
    FirebaseTokenReader? firebaseTokenReader,
    Duration timeout = const Duration(seconds: 20),
  }) {
    final resolvedConfig = config ?? AppConfig.fromEnvironment();
    final resolvedClient = client ?? http.Client();
    final authTokenProvider = FirebaseVoiceAuthTokenProvider(
      firebaseTokenReader ?? FirebaseAuthTokenReader(),
    );
    final provider = HttpContentProvider(
      client: resolvedClient,
      authTokenProvider: authTokenProvider,
      baseUri: resolvedConfig.aiApiBaseUri,
      timeout: timeout,
    );

    return ManagedAiService._(provider: provider, client: resolvedClient);
  }
}

/// Lifecycle-managed [ContentProvider] returned by [AiServiceFactory].
final class ManagedAiService implements ContentProvider {
  ManagedAiService._({
    required this._provider,
    required this._client,
  });

  final HttpContentProvider _provider;
  final http.Client _client;
  bool _disposed = false;

  @override
  Future<ContentResponse> generate(ContentRequest request) {
    if (_disposed) {
      return Future<ContentResponse>.error(_disposedFailure);
    }
    return _provider.generate(request);
  }

  /// Closes the HTTP client exactly once and preserves any error.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _client.close();
  }
}
