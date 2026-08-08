import 'voice_capability.dart';
import 'voice_models.dart';

final class VoiceProviderDescriptor {
  VoiceProviderDescriptor({
    required this.engine,
    required Set<VoiceCapability> capabilities,
    required this.privacyScope,
    required this.allowsStandardCache,
  }) : capabilities = Set<VoiceCapability>.unmodifiable(capabilities) {
    if (capabilities.isEmpty) {
      throw ArgumentError.value(
        capabilities,
        'capabilities',
        'must not be empty',
      );
    }
    if (privacyScope == VoicePrivacyScope.participantTransient &&
        allowsStandardCache) {
      throw ArgumentError(
        'Participant-transient providers cannot use standard caching.',
      );
    }
  }

  final VoiceEngine engine;
  final Set<VoiceCapability> capabilities;
  final VoicePrivacyScope privacyScope;
  final bool allowsStandardCache;

  bool supports(VoiceCapability capability) =>
      capabilities.contains(capability);
}
