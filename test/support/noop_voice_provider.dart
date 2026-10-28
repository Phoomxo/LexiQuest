import 'package:vocab_learning_app/voice/voice_models.dart';
import 'package:vocab_learning_app/voice/voice_provider.dart';

/// Minimal, deterministic [VoiceProvider] for tests.
final class NoopVoiceProvider implements VoiceProvider {
  const NoopVoiceProvider();

  @override
  Future<VoicePlaybackResult> speak(VoiceRequest request) async =>
      const VoicePlaybackResult(
        requestedEngine: VoiceEngine.nativeTts,
        actualEngine: VoiceEngine.nativeTts,
        usedFallback: false,
        cacheHit: false,
      );

  @override
  Future<void> stop() async {}
}
