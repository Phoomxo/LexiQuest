import 'package:flutter_test/flutter_test.dart';
import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider_registry.dart';

void main() {
  test('registry resolves providers and exposes immutable engines', () {
    final registry = VoiceProviderRegistry<String>(const [
      MapEntry(VoiceEngine.nativeTts, 'native'),
      MapEntry(VoiceEngine.omniVoice, 'omni'),
    ]);

    expect(registry.providerFor(VoiceEngine.nativeTts), 'native');
    expect(registry.providerFor(VoiceEngine.omniVoice), 'omni');
    expect(registry.providerFor(VoiceEngine.voxCpmStandard), isNull);
    expect(registry.engines, const <VoiceEngine>{
      VoiceEngine.nativeTts,
      VoiceEngine.omniVoice,
    });
    expect(
      () => registry.engines.add(VoiceEngine.voxCpmStandard),
      throwsUnsupportedError,
    );
  });

  test('registry rejects duplicate engine registration', () {
    expect(
      () => VoiceProviderRegistry<String>(const [
        MapEntry(VoiceEngine.nativeTts, 'first'),
        MapEntry(VoiceEngine.nativeTts, 'second'),
      ]),
      throwsArgumentError,
    );
  });

  test('registry rejects an empty provider set', () {
    expect(
      () => VoiceProviderRegistry<String>(
        const <MapEntry<VoiceEngine, String>>[],
      ),
      throwsArgumentError,
    );
  });
}
