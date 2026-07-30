import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/config/app_config.dart';

import 'hybrid_voice_service.dart';
import 'native_tts_provider.dart';
import 'omni_voice_provider.dart';
import 'voice_audio_cache.dart';
import 'voice_audio_player.dart';
import 'voice_auth_token_provider.dart';
import 'voice_models.dart';
import 'voice_provider.dart';
import 'voice_telemetry.dart';

const _disposedFailure = VoiceFailure(
  category: VoiceFailureCategory.configuration,
  message: 'The voice service has been disposed.',
);

/// Production composition root for the hybrid native/OmniVoice pipeline.
final class VoiceServiceFactory {
  const VoiceServiceFactory._();

  /// Creates a service that owns the resolved HTTP client and audio player,
  /// including injected instances supplied for tests or host integration.
  static ManagedVoiceService create({
    AppConfig? config,
    http.Client? client,
    FirebaseTokenReader? firebaseTokenReader,
    NativeTtsAdapter? nativeTtsAdapter,
    AudioPlayerAdapter? audioPlayerAdapter,
    VoiceTelemetrySink telemetrySink = const NoopVoiceTelemetrySink(),
    Duration timeout = const Duration(seconds: 30),
    int cacheMaxEntries = 64,
    int cacheMaxBytes = 16 * 1024 * 1024,
    String omniVoiceModelVersion = 'unresolved',
  }) {
    final nativeProvider = NativeTtsProvider(
      nativeTtsAdapter ?? FlutterTtsAdapter(),
    );
    final resolvedConfig = config ?? _environmentConfigOrNull();
    final resolvedClient = resolvedConfig == null
        ? client
        : client ?? http.Client();
    final audioPlayer = audioPlayerAdapter == null
        ? resolvedConfig == null
              ? const _NoopVoiceAudioPlayer()
              : PluginVoiceAudioPlayer(AudioplayersAdapter())
        : PluginVoiceAudioPlayer(audioPlayerAdapter);
    final omniVoiceProvider = resolvedConfig == null
        ? const _UnavailableOmniVoiceSynthesizer()
        : OmniVoiceProvider(
            client: resolvedClient!,
            authTokenProvider: FirebaseVoiceAuthTokenProvider(
              firebaseTokenReader ?? FirebaseAuthTokenReader(),
            ),
            baseUri: resolvedConfig.voiceApiBaseUri,
            timeout: timeout,
          );
    final hybrid = HybridVoiceService(
      nativeProvider: nativeProvider,
      omniVoiceProvider: omniVoiceProvider,
      audioPlayer: audioPlayer,
      audioCache: MemoryVoiceAudioCache(
        maxEntries: cacheMaxEntries,
        maxBytes: cacheMaxBytes,
      ),
      omniVoiceModelVersion: omniVoiceModelVersion,
      telemetrySink: telemetrySink,
    );

    return ManagedVoiceService._(
      hybrid: hybrid,
      audioPlayer: audioPlayer,
      client: resolvedClient,
    );
  }
}

/// Lifecycle-managed [VoiceProvider] returned by [VoiceServiceFactory].
final class ManagedVoiceService implements VoiceProvider {
  ManagedVoiceService._({
    required this._hybrid,
    required this._audioPlayer,
    required this._client,
  });

  final HybridVoiceService _hybrid;
  final VoiceAudioPlayer _audioPlayer;
  final http.Client? _client;
  bool _disposed = false;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    if (_disposed) {
      return Future<VoicePlaybackResult>.error(_disposedFailure);
    }
    return _hybrid.speak(request);
  }

  @override
  Future<void> stop() async {
    if (!_disposed) {
      await _hybrid.stop();
    }
  }

  /// Attempts every cleanup step exactly once and preserves the first failure
  /// with its original stack trace after the remaining resources are closed.
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _hybrid.stop();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    try {
      await _audioPlayer.dispose();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    try {
      _client?.close();
    } on Object catch (error, stackTrace) {
      firstError ??= error;
      firstStackTrace ??= stackTrace;
    }

    final error = firstError;
    if (error != null) {
      Error.throwWithStackTrace(error, firstStackTrace!);
    }
  }
}

AppConfig? _environmentConfigOrNull() {
  try {
    return AppConfig.fromEnvironment();
  } on AppConfigException {
    return null;
  }
}

const _remoteVoiceUnavailable = VoiceFailure(
  category: VoiceFailureCategory.configuration,
  message: 'Remote voice synthesis is not configured.',
);

final class _UnavailableOmniVoiceSynthesizer implements OmniVoiceSynthesizer {
  const _UnavailableOmniVoiceSynthesizer();

  @override
  Future<OmniVoiceAudio> synthesize(VoiceRequest request) async {
    throw _remoteVoiceUnavailable;
  }
}

final class _NoopVoiceAudioPlayer implements VoiceAudioPlayer {
  const _NoopVoiceAudioPlayer();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> stop() async {}
}
