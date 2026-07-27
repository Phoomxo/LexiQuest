enum SpeechSynthesisEngine { omniVoice, nativeTts }

class SpeechPlaybackResult {
  final SpeechSynthesisEngine engine;
  final bool success;
  final String? errorReason;

  SpeechPlaybackResult({
    required this.engine,
    required this.success,
    this.errorReason,
  });
}

class VoiceReadingAdapter {
  Future<SpeechPlaybackResult> speakText({
    required String text,
    bool preferOmniVoice = true,
    bool isNetworkAvailable = true,
  }) async {
    if (preferOmniVoice && isNetworkAvailable) {
      // Primary OmniVoice engine
      return SpeechPlaybackResult(
        engine: SpeechSynthesisEngine.omniVoice,
        success: true,
      );
    }

    // Fallback to Native TTS
    return SpeechPlaybackResult(
      engine: SpeechSynthesisEngine.nativeTts,
      success: true,
      errorReason: 'OmniVoice unavailable or offline; used native TTS fallback',
    );
  }
}
