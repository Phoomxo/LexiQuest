import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:vocab_learning_app/config/app_config.dart';

import 'native_voice_route_handler.dart';
import 'native_tts_provider.dart';
import 'omni_voice_provider.dart';
import 'installed_voice_pack_provider.dart';
import 'standard_voice_pack_download_manager.dart';
import 'synthesized_voice_route_handler.dart';
import 'voice_audio_cache.dart';
import 'voice_audio_player.dart';
import 'voice_auth_token_provider.dart';
import 'voice_mirror_gateway.dart';
import 'voice_mirror_session_controller.dart';
import 'voice_models.dart';
import 'voice_orchestrator.dart';
import 'voice_policy.dart';
import 'voice_provider.dart';
import 'voice_provider_registry.dart';
import 'voice_route_handler.dart';
import 'voice_telemetry.dart';
import 'voice_request_quota.dart';
import 'vox_cpm_mirror_provider.dart';
import 'vox_cpm_standard_provider.dart';

const _disposedFailure = VoiceFailure(
  category: VoiceFailureCategory.configuration,
  message: 'The voice service has been disposed.',
);

/// Production composition root for the provider-neutral voice pipeline.
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
    String voxCpmModelVersion = 'unresolved',
    String voxCpmMirrorModelVersion = 'unresolved',
    bool useOmniVoiceRollback = false,
    int dynamicMaxRequests = 20,
    int dynamicMaxCharacters = 4000,
    int dynamicMaxConcurrent = 1,
    InstalledStandardVoicePack? installedVoicePack,
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
    final handlers = <MapEntry<VoiceEngine, VoiceRouteHandler>>[
      MapEntry<VoiceEngine, VoiceRouteHandler>(
        VoiceEngine.nativeTts,
        NativeVoiceRouteHandler(nativeProvider),
      ),
    ];
    if (installedVoicePack != null) {
      handlers.add(
        MapEntry(
          VoiceEngine.offlinePack,
          SynthesizedVoiceRouteHandler(
            provider: InstalledVoicePackProvider(installedVoicePack),
            audioPlayer: audioPlayer,
            audioCache: MemoryVoiceAudioCache(
              maxEntries: cacheMaxEntries,
              maxBytes: cacheMaxBytes,
            ),
            modelVersion: installedVoicePack.manifest.modelVersion,
          ),
        ),
      );
    }
    VoiceMirrorSessionController? activeMirrorController;
    if (resolvedConfig != null) {
      final authTokenProvider = FirebaseVoiceAuthTokenProvider(
        firebaseTokenReader ?? FirebaseAuthTokenReader(),
      );
      final remoteEngine = useOmniVoiceRollback
          ? VoiceEngine.omniVoice
          : VoiceEngine.voxCpmStandard;
      final dynamicQuota = VoiceRequestQuota(
        maxRequests: dynamicMaxRequests,
        maxCharacters: dynamicMaxCharacters,
        maxConcurrent: dynamicMaxConcurrent,
      );
      final remoteProvider = useOmniVoiceRollback
          ? OmniVoiceProvider(
              client: resolvedClient!,
              authTokenProvider: authTokenProvider,
              baseUri: resolvedConfig.voiceApiBaseUri,
              timeout: timeout,
              quota: dynamicQuota,
            )
          : VoxCpmStandardProvider(
              client: resolvedClient!,
              authTokenProvider: authTokenProvider,
              baseUri: resolvedConfig.voiceApiBaseUri,
              timeout: timeout,
              quota: dynamicQuota,
            );
      handlers.add(
        MapEntry<VoiceEngine, VoiceRouteHandler>(
          remoteEngine,
          SynthesizedVoiceRouteHandler(
            provider: remoteProvider,
            audioPlayer: audioPlayer,
            audioCache: MemoryVoiceAudioCache(
              maxEntries: cacheMaxEntries,
              maxBytes: cacheMaxBytes,
            ),
            modelVersion: useOmniVoiceRollback
                ? omniVoiceModelVersion
                : voxCpmModelVersion,
          ),
        ),
      );

      // Register the participant-transient mirror only when the Cloud voice
      // configuration and a shared HTTP client are available. The provider is
      // never cached and routes only through the live session controller.
      final mirrorGateway = VoiceMirrorGateway(
        client: resolvedClient,
        authTokenProvider: authTokenProvider,
        baseUri: resolvedConfig.voiceApiBaseUri,
        timeout: timeout,
      );
      final mirrorController = VoiceMirrorSessionController(
        gateway: mirrorGateway,
        now: DateTime.now,
      );
      activeMirrorController = mirrorController;
      final mirrorProvider = VoxCpmMirrorProvider(controller: mirrorController);
      handlers.add(
        MapEntry<VoiceEngine, VoiceRouteHandler>(
          VoiceEngine.voxCpmMirror,
          SynthesizedVoiceRouteHandler(
            provider: mirrorProvider,
            audioPlayer: audioPlayer,
            // Mirror output is participant-transient and never cached; the
            // cache instance is supplied for symmetry but the descriptor
            // forbids writes.
            audioCache: MemoryVoiceAudioCache(
              maxEntries: cacheMaxEntries,
              maxBytes: cacheMaxBytes,
            ),
            modelVersion: voxCpmMirrorModelVersion,
          ),
        ),
      );
    }
    final hasRemoteConfig = resolvedConfig != null;
    final baseContext = VoiceRouteContext(
      isOnline: hasRemoteConfig,
      remoteStandardEnabled: hasRemoteConfig,
      offlinePackAvailable: installedVoicePack != null,
      voiceMirrorEnabled: hasRemoteConfig && activeMirrorController != null,
      hasVoiceMirrorConsent: false,
      hasActiveVoiceMirrorSession: false,
    );
    final policySource = activeMirrorController == null
        ? StaticVoicePolicySource(baseContext)
        : MirrorAwareVoicePolicySource(
            baseContext: baseContext,
            readMirrorState: () {
              final controller = activeMirrorController;
              return MirrorPolicyState(
                capabilityEnabled: hasRemoteConfig,
                hasConsent: controller?.hasConsent ?? false,
                hasActiveSession: controller?.isActive ?? false,
              );
            },
          );
    final service = VoiceOrchestrator(
      policySource: policySource,
      policyResolver: const VoicePolicyResolver(),
      handlerRegistry: VoiceProviderRegistry<VoiceRouteHandler>(handlers),
      telemetrySink: telemetrySink,
    );

    return ManagedVoiceService._(
      service: service,
      audioPlayer: audioPlayer,
      client: resolvedClient,
      voiceMirrorController: activeMirrorController,
    );
  }
}

/// A [VoiceProvider] whose lifecycle is owned by the factory caller.
///
/// Exposing [dispose] as part of the interface lets integration tests inject
/// a fake managed voice service without subclassing the final concrete class.
abstract interface class ManagedVoiceProvider implements VoiceProvider {
  /// Releases the resources held by this provider.
  Future<void> dispose();
}

/// Lifecycle-managed [VoiceProvider] returned by [VoiceServiceFactory].
final class ManagedVoiceService implements ManagedVoiceProvider {
  ManagedVoiceService._({
    required this._service,
    required this._audioPlayer,
    required this._client,
    required this._voiceMirrorController,
  });

  final VoiceProvider _service;
  final VoiceAudioPlayer _audioPlayer;
  final http.Client? _client;
  final VoiceMirrorSessionController? _voiceMirrorController;
  bool _disposed = false;

  /// The participant-transient mirror controller, if the mirror capability is
  /// registered. The host forwards app lifecycle and account changes here so
  /// the temporary session is ended deterministically.
  VoiceMirrorSessionController? get voiceMirrorController =>
      _voiceMirrorController;

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) {
    if (_disposed) {
      return Future<VoicePlaybackResult>.error(_disposedFailure);
    }
    return _service.speak(request);
  }

  @override
  Future<void> stop() async {
    if (!_disposed) {
      await _service.stop();
    }
  }

  /// Attempts every cleanup step exactly once and preserves the first failure
  /// with its original stack trace after the remaining resources are closed.
  @override
  Future<void> dispose() async {
    if (_disposed) {
      return;
    }
    _disposed = true;

    Object? firstError;
    StackTrace? firstStackTrace;

    try {
      await _service.stop();
    } on Object catch (error, stackTrace) {
      firstError = error;
      firstStackTrace = stackTrace;
    }

    // End any active mirror session before releasing shared audio resources.
    // The controller's cleanup is idempotent.
    final mirrorController = _voiceMirrorController;
    if (mirrorController != null) {
      try {
        await mirrorController.dispose();
      } on Object catch (error, stackTrace) {
        firstError ??= error;
        firstStackTrace ??= stackTrace;
      }
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

final class _NoopVoiceAudioPlayer implements VoiceAudioPlayer {
  const _NoopVoiceAudioPlayer();

  @override
  Future<void> dispose() async {}

  @override
  Future<void> play(Uint8List bytes) async {}

  @override
  Future<void> stop() async {}
}
