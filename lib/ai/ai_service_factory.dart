import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
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
    AiAuthBindingReader? readAuthBinding,
  }) {
    final resolvedConfig = config ?? AppConfig.fromEnvironment();
    final resolvedClient = client ?? http.Client();
    _FirebaseAiAuthBinding? authBinding;
    try {
      if (firebaseTokenReader == null && readAuthBinding == null) {
        authBinding = _FirebaseAiAuthBinding(FirebaseAuth.instance);
      }
      final authTokenProvider = FirebaseVoiceAuthTokenProvider(
        firebaseTokenReader ?? FirebaseAuthTokenReader(),
      );
      final provider = HttpContentProvider(
        client: resolvedClient,
        authTokenProvider: authTokenProvider,
        baseUri: resolvedConfig.aiApiBaseUri,
        timeout: timeout,
        readAuthBinding: readAuthBinding ?? authBinding?.read,
      );
      return ManagedAiService._(
        provider: provider,
        client: resolvedClient,
        authBinding: authBinding,
      );
    } on Object {
      unawaited(authBinding?.dispose());
      resolvedClient.close();
      rethrow;
    }
  }
}

/// Lifecycle-managed [ContentProvider] returned by [AiServiceFactory].
final class ManagedAiService implements ContentProvider {
  ManagedAiService._({
    required this._provider,
    required this._client,
    required this._authBinding,
  });

  final HttpContentProvider _provider;
  final http.Client _client;
  final _FirebaseAiAuthBinding? _authBinding;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  @override
  Future<ContentResponse> generate(ContentRequest request) {
    if (_disposed) {
      return Future<ContentResponse>.error(_disposedFailure);
    }
    return _provider.generate(request);
  }

  /// Closes the HTTP client exactly once and preserves any error.
  Future<void> dispose() => _disposeFuture ??= _dispose();

  Future<void> _dispose() async {
    _disposed = true;
    try {
      _client.close();
    } finally {
      await _authBinding?.dispose();
    }
  }
}

final class _FirebaseAiAuthBinding {
  _FirebaseAiAuthBinding(this.auth) {
    _identity = _key(auth.currentUser);
    _changes = auth.authStateChanges().listen(
      (user) {
        final next = _key(user);
        if (next != _identity || !_available) _epoch++;
        _identity = next;
        _available = true;
      },
      onError: (Object _) {
        _epoch++;
        _available = false;
      },
      onDone: () {
        _epoch++;
        _available = false;
      },
    );
  }
  final FirebaseAuth auth;
  late final StreamSubscription<User?> _changes;
  var _epoch = 0;
  var _available = true;
  var _disposed = false;
  (String, bool)? _identity;

  (String, bool)? _key(User? user) =>
      user == null ? null : (user.uid, user.isAnonymous);

  Object? read() {
    final user = auth.currentUser;
    return !_disposed && _available && user != null && _key(user) == _identity
        ? (user.uid, user.isAnonymous, _epoch)
        : null;
  }

  Future<void> dispose() {
    _disposed = true;
    _epoch++;
    return _changes.cancel();
  }
}
