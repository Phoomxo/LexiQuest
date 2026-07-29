import '../learning/reading_content_source.dart';
import 'voice_models.dart';
import 'voice_provider.dart';

sealed class ReadingVoiceResult {
  const ReadingVoiceResult();
}

final class ReadingVoicePlayed extends ReadingVoiceResult {
  const ReadingVoicePlayed(this.playback);

  final VoicePlaybackResult playback;
}

enum ReadingVoiceFailure { disabled, providerFailure }

final class ReadingVoiceUnavailable extends ReadingVoiceResult {
  const ReadingVoiceUnavailable(this.failure);

  final ReadingVoiceFailure failure;
}

/// Optional voice adapter for reading sessions. Playback never changes learning
/// state, and all provider failures reduce to a typed unavailable result.
final class ReadingVoiceEnrichment {
  const ReadingVoiceEnrichment({required VoiceProvider provider})
    : _provider = provider,
      _enabled = true;

  const ReadingVoiceEnrichment.disabled() : _provider = null, _enabled = false;

  final VoiceProvider? _provider;
  final bool _enabled;

  Future<ReadingVoiceResult> speak(
    ReadingContent content, {
    String voiceId = 'default-en',
    double speed = 1,
  }) async {
    if (!_enabled) {
      return const ReadingVoiceUnavailable(ReadingVoiceFailure.disabled);
    }

    try {
      final playback = await _provider!.speak(
        VoiceRequest.create(
          text: content.passage,
          language: 'en',
          voiceId: voiceId,
          speed: speed,
          contentId: content.contentId,
          contentType: 'associative-reading',
          mode: VoiceMode.practice,
        ),
      );
      return ReadingVoicePlayed(playback);
    } on Object {
      return const ReadingVoiceUnavailable(ReadingVoiceFailure.providerFailure);
    }
  }

  Future<void> stop() async {
    if (_enabled) {
      try {
        await _provider!.stop();
      } on Object {
        // Playback is optional and must never affect the learning session.
      }
    }
  }
}
