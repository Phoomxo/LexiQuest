import 'voice_capability.dart';
import 'voice_models.dart';
import 'voice_provider.dart';
import 'voice_provider_descriptor.dart';
import 'voice_route_handler.dart';

/// Routes speech requests through the on-device native TTS provider.
final class NativeVoiceRouteHandler implements VoiceRouteHandler {
  NativeVoiceRouteHandler(this._provider);

  final VoiceProvider _provider;

  static final VoiceProviderDescriptor _descriptor = VoiceProviderDescriptor(
    engine: VoiceEngine.nativeTts,
    capabilities: const <VoiceCapability>{
      VoiceCapability.standardTargetSpeech,
      VoiceCapability.dynamicTargetSpeech,
    },
    privacyScope: VoicePrivacyScope.standardContent,
    allowsStandardCache: false,
  );

  @override
  VoiceProviderDescriptor get descriptor => _descriptor;

  @override
  Future<VoicePlaybackResult> speak(
    VoiceRequest request,
    VoiceCancellationToken cancellation,
  ) async {
    cancellation.throwIfCancelled();
    final result = await _provider.speak(request);
    cancellation.throwIfCancelled();
    return result;
  }

  @override
  Future<void> stop() => _provider.stop();
}
