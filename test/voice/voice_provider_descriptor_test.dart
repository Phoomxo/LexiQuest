import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_capability.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider_descriptor.dart';

void main() {
  test('descriptor exposes immutable provider capabilities', () {
    final source = <VoiceCapability>{VoiceCapability.standardTargetSpeech};
    final descriptor = VoiceProviderDescriptor(
      engine: VoiceEngine.omniVoice,
      capabilities: source,
      privacyScope: VoicePrivacyScope.standardContent,
      allowsStandardCache: true,
    );

    source.add(VoiceCapability.dynamicTargetSpeech);

    expect(descriptor.capabilities, const <VoiceCapability>{
      VoiceCapability.standardTargetSpeech,
    });
    expect(
      () => descriptor.capabilities.add(VoiceCapability.dynamicTargetSpeech),
      throwsUnsupportedError,
    );
    expect(descriptor.supports(VoiceCapability.standardTargetSpeech), isTrue);
    expect(descriptor.supports(VoiceCapability.dynamicTargetSpeech), isFalse);
  });

  test('descriptor rejects an empty capability set', () {
    expect(
      () => VoiceProviderDescriptor(
        engine: VoiceEngine.nativeTts,
        capabilities: const <VoiceCapability>{},
        privacyScope: VoicePrivacyScope.standardContent,
        allowsStandardCache: false,
      ),
      throwsArgumentError,
    );
  });

  test('participant transient descriptor cannot use standard caching', () {
    expect(
      () => VoiceProviderDescriptor(
        engine: VoiceEngine.voxCpmMirror,
        capabilities: const <VoiceCapability>{
          VoiceCapability.sessionVoiceMirror,
        },
        privacyScope: VoicePrivacyScope.participantTransient,
        allowsStandardCache: true,
      ),
      throwsArgumentError,
    );
  });
}
