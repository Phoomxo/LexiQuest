import 'voice_capability.dart';
import 'voice_mirror_session_controller.dart';
import 'voice_models.dart';
import 'voice_provider_descriptor.dart';
import 'voice_synthesis_provider.dart';

const _unsupportedCapabilityFailure = VoiceFailure(
  category: VoiceFailureCategory.unsupportedCapability,
  message: 'This provider only supports participant-transient mirror speech.',
);

/// Wraps the mirror [VoiceMirrorSessionControllerView] as a
/// [VoiceSynthesisProvider] so the participant-transient mirror can be routed
/// through the same provider-neutral pipeline as standard speech.
///
/// The provider accepts only [VoiceCapability.sessionVoiceMirror] requests.
/// Mirror output is participant-transient and never cached: the descriptor
/// declares [VoicePrivacyScope.participantTransient] with
/// `allowsStandardCache: false`.
final class VoxCpmMirrorProvider implements VoiceSynthesisProvider {
  VoxCpmMirrorProvider({required this._controller});

  final VoiceMirrorSessionControllerView _controller;

  static final VoiceProviderDescriptor _descriptor = VoiceProviderDescriptor(
    engine: VoiceEngine.voxCpmMirror,
    capabilities: const {VoiceCapability.sessionVoiceMirror},
    privacyScope: VoicePrivacyScope.participantTransient,
    allowsStandardCache: false,
  );

  @override
  VoiceProviderDescriptor get descriptor => _descriptor;

  @override
  Future<VoiceAudio> synthesize(VoiceRequest request) async {
    if (!descriptor.supports(request.capability) ||
        request.privacyScope != descriptor.privacyScope) {
      throw _unsupportedCapabilityFailure;
    }
    return _controller.synthesize(
      contentId: request.contentId,
      text: request.text,
      language: request.language,
    );
  }
}
